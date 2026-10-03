import Foundation

// MARK: - Westwood Studios Animation (.WSA), Tiberian Dawn flavour
//
// Mirrors Open_Animation / Animate_Frame / Apply_Delta (WIN32LIB wsa.cpp;
// Vanilla-Conquer common/wsa.cpp). Layout (little-endian):
//   +0  u16 total_frames   +2 u16 x   +4 u16 y   +6 u16 width   +8 u16 height
//  +10  u16 largest_frame_size (delta-buffer size)   +12 u16 flags
//  +14  u32 offsets[total_frames + 2]
//       [768-byte 6-bit palette if flags & 1]
//       frame data
// offsets[i] is the file offset of frame i's data *not counting* the
// palette (add 768 when present); frame i spans offsets[i]..<offsets[i+1].
// offsets[total_frames] is the loop-back delta (last frame → frame 0); if
// offsets[total_frames + 1] == 0 there is no loop delta (WSA_LINEAR_ONLY).
// offsets[0] == 0 means frame 0 has no data (WSA_FRAME_0_ON_PAGE): frame 0
// is whatever is already on the page.
// Each frame = LCW (format80) → XOR delta (format40) applied to the previous
// frame. flags & 2 (WSA_FRAME_0_IS_DELTA) means frame 0 is itself an XOR
// against a picture already on the page rather than drawn over black.

package struct WSAFile {
    package let frameCount: Int
    package let x: Int
    package let y: Int
    package let width: Int
    package let height: Int
    package let largestFrameSize: Int
    package let flags: Int
    /// Embedded palette (flags & 1).
    package let palette: VGAPalette?
    /// WSA_FRAME_0_IS_DELTA: frame 0 is XORed onto the page, not copied.
    package var frame0IsDelta: Bool { flags & 2 != 0 }
    /// WSA_FRAME_0_ON_PAGE: the file has no frame-0 data at all.
    package let frame0OnPage: Bool
    /// The file carries a loop-back delta (last frame → frame 0).
    package var hasLoopFrame: Bool { deltas.count > frameCount }
    /// LCW-decompressed XOR deltas: [0, frameCount) plus the loop delta at
    /// index frameCount when present. Frame 0's is empty if `frame0OnPage`.
    package let deltas: [[UInt8]]

    package var pixelCount: Int { width * height }

    package init(data: Data) throws {
        try self.init(bytes: [UInt8](data))
    }

    package init(bytes: [UInt8]) throws {
        guard bytes.count >= 14 else { throw WestwoodImageError.truncated("WSA header") }
        let n = wwReadLE16(bytes, 0)
        x = wwReadLE16(bytes, 2)
        y = wwReadLE16(bytes, 4)
        width = wwReadLE16(bytes, 6)
        height = wwReadLE16(bytes, 8)
        largestFrameSize = wwReadLE16(bytes, 10)
        flags = wwReadLE16(bytes, 12)
        guard n > 0, n < 0x8000 else {
            // High bit set = Amiga animation (wsa.cpp header comment).
            throw WestwoodImageError.badHeader("WSA frame count \(n)")
        }
        guard width > 0, height > 0, width <= 640, height <= 400 else {
            throw WestwoodImageError.badHeader("WSA size \(width)x\(height)")
        }
        frameCount = n

        let tableEnd = 14 + (n + 2) * 4
        guard bytes.count >= tableEnd else { throw WestwoodImageError.truncated("WSA offset table") }
        let offsets = (0..<(n + 2)).map { Int(wwReadLE32(bytes, 14 + $0 * 4)) }

        let paletteAdjust: Int
        if flags & 1 != 0 {
            guard bytes.count >= tableEnd + VGAPalette.byteCount else {
                throw WestwoodImageError.truncated("WSA palette")
            }
            palette = try VGAPalette(vga6: Array(bytes[tableEnd..<(tableEnd + VGAPalette.byteCount)]))
            paletteAdjust = VGAPalette.byteCount
        } else {
            palette = nil
            paletteAdjust = 0
        }
        frame0OnPage = offsets[0] == 0

        // Decompress with generous headroom; each delta is trimmed to what
        // the LCW stream actually wrote.
        let scratch = max(largestFrameSize, width * height * 2 + 64)
        let lastIndex = offsets[n + 1] != 0 ? n : n - 1  // include loop delta?
        var out: [[UInt8]] = []
        out.reserveCapacity(lastIndex + 1)
        for i in 0...lastIndex {
            if i == 0 && frame0OnPage { out.append([]); continue }
            let start = offsets[i] + paletteAdjust
            // The final frame of a linear-only file ends at offsets[n] (the
            // file end); otherwise at the next offset.
            let end = offsets[i + 1] + paletteAdjust
            guard start <= end, end <= bytes.count else {
                throw WestwoodImageError.truncated("WSA frame \(i) data \(start)..<\(end) of \(bytes.count)")
            }
            let (buf, written) = WestwoodCodec.lcwDecompressCounted(Array(bytes[start..<end]), outputSize: scratch)
            out.append(Array(buf.prefix(written)))
        }
        deltas = out
    }

    /// Applies frame `index`'s delta (index == frameCount = the loop delta).
    /// `copy` selects Copy_Delta_Buffer (used for a direct-to-page frame 0).
    package func applyDelta(_ index: Int, to buffer: inout [UInt8], copy: Bool = false) {
        guard index >= 0, index < deltas.count, !deltas[index].isEmpty else { return }
        WestwoodCodec.applyXORDelta(&buffer, delta: deltas[index], copy: copy)
    }

    /// Decodes every frame in order. `base` is the page content under the
    /// animation before frame 0 (default black, as after SysMemPage.Clear()
    /// in MAPSEL.CPP); it must be width*height.
    package func decodeAllFrames(base: [UInt8]? = nil) -> [[UInt8]] {
        var player = WSAPlayer(self, base: base)
        return (0..<frameCount).map { player.seek(to: $0); return player.buffer }
    }

    /// Converts a decoded frame to RGBA8888 with the embedded palette, or
    /// `palette` when given / when the file has none.
    package func rgba(_ frame: [UInt8], palette override: VGAPalette? = nil) -> [UInt8]? {
        guard let pal = override ?? palette else { return nil }
        return pal.rgba(frame)
    }
}

// MARK: - Stateful playback (Animate_Frame semantics)

/// Holds the current frame buffer, like the WSA_OPEN_TO_PAGE path the game
/// uses: frame 0 is drawn onto `base` (copied, or XORed if
/// `frame0IsDelta`), then each step XORs one delta. Seeking takes the
/// shorter way round when a loop delta exists, exactly as Animate_Frame.
package struct WSAPlayer {
    package let wsa: WSAFile
    package private(set) var buffer: [UInt8]
    /// Current frame, or nil before the first `seek` (Animate_Frame's
    /// current_frame == total_frames state).
    package private(set) var currentFrame: Int?

    package init(_ wsa: WSAFile, base: [UInt8]? = nil) {
        self.wsa = wsa
        if let base, base.count == wsa.pixelCount {
            buffer = base
        } else {
            buffer = [UInt8](repeating: 0, count: wsa.pixelCount)
        }
        currentFrame = nil
    }

    /// Advances to the next frame, wrapping through the loop delta.
    package mutating func advance() {
        guard let cur = currentFrame else { seek(to: 0); return }
        seek(to: cur + 1 < wsa.frameCount ? cur + 1 : 0)
    }

    /// Animate_Frame(handle, page, frameNumber).
    package mutating func seek(to frame: Int) {
        let total = wsa.frameCount
        guard frame >= 0, frame < total else { return }
        if currentFrame == nil {
            if !wsa.frame0OnPage {
                wsa.applyDelta(0, to: &buffer, copy: !wsa.frame0IsDelta)
            }
            currentFrame = 0
        }
        var cur = currentFrame ?? 0
        let linearOnly = !wsa.hasLoopFrame
        let distance = abs(cur - frame)
        var dir = 1
        var steps: Int
        if frame > cur {
            steps = total - frame + cur
            if steps < distance && !linearOnly {
                dir = -1
            } else {
                steps = distance
            }
        } else {
            steps = total - cur + frame
            if steps >= distance || linearOnly {
                dir = -1
                steps = distance
            }
        }
        if dir > 0 {
            for _ in 0..<steps {
                cur += 1
                wsa.applyDelta(cur, to: &buffer)
                if cur == total { cur = 0 }
            }
        } else {
            for _ in 0..<steps {
                if cur == 0 { cur = total }
                wsa.applyDelta(cur, to: &buffer)
                cur -= 1
            }
        }
        currentFrame = frame
    }
}
