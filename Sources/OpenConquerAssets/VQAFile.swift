import Foundation

// MARK: - Westwood VQA (Vector Quantized Animation) decoder
//
// The FMV format of Tiberian Dawn (1995): every movie in GDI/NOD MOVIES.MIX is
// VQA version 2, 320x156 (LOGO/TANKKILL 320x200), 15 fps, 4x2-pixel blocks,
// 8-bit paletted, with 22050 Hz 16-bit IMA ADPCM audio (SND2; mono except
// GDI3LOSE, which is stereo).
//
// Container: an IFF "FORM"/"WVQA" file of big-endian-sized chunks, each padded
// to an even size. "VQHD" (the header) and "FINF" (frame offset index) come
// first, then per frame any number of audio chunks followed by one "VQFR"
// whose sub-chunks carry the codebook, palette and pointer table.
//
//   CBF0 / CBFZ  full codebook, raw / LCW
//   CBP0 / CBPZ  one 1/Groupsize piece of the next codebook, raw / LCW (the
//                pieces of a group are concatenated, then decompressed as one)
//   CPL0 / CPLZ  palette, 6-bit VGA RGB, raw / LCW
//   VPT0 / VPTZ  pointer table, raw / LCW: a lo-byte table then a hi-byte
//                table, one entry per block; (hi<<8 | lo) indexes the codebook,
//                hi == 0x0F (4x2) / 0xFF (4x4) means "solid block of colour lo"
//   SND0/1/2     audio: raw PCM / Westwood ADPCM / Westwood IMA ADPCM
//
// This is a port of the Westwood VQA library as preserved in Vanilla-Conquer
// (common/vqaloader.cpp, vqadrawer.cpp, unvqbuff.cpp, soscodec.cpp), including
// its codebook timing: the codebook a frame is drawn with is the one that was
// complete *before* that frame's chunks were loaded (VQA_LoadFrame:
// `curframe->Codebook = loader->FullCB`), so a codebook finished inside frame
// N's chunk first shows up in frame N+1, and the codebook buffers rotate
// through a ring of 3 (VQAConfig NumCBBufs, vqaconfig.cpp).
//
// Streaming: `VQADecoder` keeps the file `Data` (typically a zero-copy slice of
// the already-loaded MIX) and decodes one frame per `nextFrame()` call, so a
// 30 MB movie never exists as decoded frames all at once.

// MARK: - Header

/// The 42-byte VQHD chunk (VQAHeader, Vanilla-Conquer common/vqafile.h).
package struct VQAHeader: Equatable {
    package var version: Int
    package var flags: Int            // bit 0 = has audio, bit 1 = has alt audio
    package var frameCount: Int
    package var width: Int
    package var height: Int
    package var blockWidth: Int
    package var blockHeight: Int
    package var frameRate: Int
    package var groupSize: Int        // codebook pieces per partial codebook
    package var num1Colors: Int
    package var codebookEntries: Int
    package var xPos: Int
    package var yPos: Int
    package var maxFrameSize: Int
    package var sampleRate: Int
    package var channels: Int
    package var bitsPerSample: Int

    package static let size = 42

    package init(version: Int = 2, flags: Int = 1, frameCount: Int, width: Int, height: Int,
                 blockWidth: Int = 4, blockHeight: Int = 2, frameRate: Int = 15, groupSize: Int = 8,
                 num1Colors: Int = 0, codebookEntries: Int = 0, xPos: Int = 0, yPos: Int = 0,
                 maxFrameSize: Int = 0, sampleRate: Int = 22050, channels: Int = 1, bitsPerSample: Int = 16) {
        self.version = version; self.flags = flags; self.frameCount = frameCount
        self.width = width; self.height = height
        self.blockWidth = blockWidth; self.blockHeight = blockHeight
        self.frameRate = frameRate; self.groupSize = groupSize
        self.num1Colors = num1Colors; self.codebookEntries = codebookEntries
        self.xPos = xPos; self.yPos = yPos; self.maxFrameSize = maxFrameSize
        self.sampleRate = sampleRate; self.channels = channels; self.bitsPerSample = bitsPerSample
    }

    init(_ b: UnsafeRawBufferPointer) {
        func u16(_ o: Int) -> Int { Int(b[o]) | (Int(b[o + 1]) << 8) }
        self.init(version: u16(0), flags: u16(2), frameCount: u16(4), width: u16(6), height: u16(8),
                  blockWidth: Int(b[10]), blockHeight: Int(b[11]), frameRate: Int(b[12]),
                  groupSize: Int(b[13]), num1Colors: u16(14), codebookEntries: u16(16),
                  xPos: u16(18), yPos: u16(20), maxFrameSize: u16(22), sampleRate: u16(24),
                  channels: Int(b[26]), bitsPerSample: Int(b[27]))
    }

    /// Serialize (for building synthetic movies in tests).
    package func encoded() -> [UInt8] {
        var b = [UInt8](repeating: 0, count: VQAHeader.size)
        func put16(_ o: Int, _ v: Int) { b[o] = UInt8(v & 0xFF); b[o + 1] = UInt8((v >> 8) & 0xFF) }
        put16(0, version); put16(2, flags); put16(4, frameCount); put16(6, width); put16(8, height)
        b[10] = UInt8(blockWidth); b[11] = UInt8(blockHeight); b[12] = UInt8(frameRate); b[13] = UInt8(groupSize)
        put16(14, num1Colors); put16(16, codebookEntries); put16(18, xPos); put16(20, yPos)
        put16(22, maxFrameSize); put16(24, sampleRate); b[26] = UInt8(channels); b[27] = UInt8(bitsPerSample)
        return b
    }

    package var hasAudio: Bool { flags & 1 != 0 }
}

// MARK: - Output types

/// One decoded movie frame.
package struct VQAFrame {
    package let index: Int
    package let width: Int
    package let height: Int
    /// Palette indices, `width * height`, row-major.
    package let pixels: [UInt8]
    /// 256 RGB triplets (768 bytes), 8-bit, scaled from the 6-bit VGA values
    /// as `(v << 2) | (v >> 4)` — the same expansion as `loadPalette` (and
    /// ffmpeg). A palette persists until a later frame replaces it.
    package let palette: [UInt8]
    /// True when this frame carried a palette chunk (a renderer can skip
    /// re-uploading a palette texture otherwise).
    package let paletteChanged: Bool
    /// Interleaved 16-bit audio from the audio chunks stored ahead of this
    /// frame in the file (frame 0 also gets the ~0.5 s pre-roll chunk; the
    /// last frame gets any trailing chunks). Concatenated across all frames
    /// this is exactly the movie's whole audio track.
    package let audio: [Int16]
    /// Presentation time on the audio clock: frame N is due at N / frameRate
    /// seconds after audio sample 0 (Westwood's player times frames off the
    /// audio position; VQA_SelectFrame, vqadrawer.cpp).
    package let presentationTime: Double

    /// RGBA8888 (R,G,B,A byte order), `width * height * 4` bytes.
    package func rgba(alpha: UInt8 = 255) -> [UInt8] {
        var out = [UInt8](repeating: alpha, count: pixels.count * 4)
        palette.withUnsafeBufferPointer { pal in
            pixels.withUnsafeBufferPointer { px in
                out.withUnsafeMutableBufferPointer { dst in
                    for i in 0..<px.count {
                        let p = Int(px[i]) * 3
                        dst[i * 4] = pal[p]
                        dst[i * 4 + 1] = pal[p + 1]
                        dst[i * 4 + 2] = pal[p + 2]
                    }
                }
            }
        }
        return out
    }

    /// Packed RGB24, `width * height * 3` bytes (ffmpeg's `-pix_fmt rgb24`).
    package func rgb24() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: pixels.count * 3)
        palette.withUnsafeBufferPointer { pal in
            pixels.withUnsafeBufferPointer { px in
                out.withUnsafeMutableBufferPointer { dst in
                    for i in 0..<px.count {
                        let p = Int(px[i]) * 3
                        dst[i * 3] = pal[p]
                        dst[i * 3 + 1] = pal[p + 1]
                        dst[i * 3 + 2] = pal[p + 2]
                    }
                }
            }
        }
        return out
    }
}

/// A movie's complete audio track.
package struct VQAAudioTrack {
    /// Interleaved signed 16-bit samples.
    package let samples: [Int16]
    package let sampleRate: Int
    package let channels: Int
    package var sampleFrames: Int { samples.count / max(1, channels) }
    package var duration: Double { Double(sampleFrames) / Double(max(1, sampleRate)) }
}

/// Counters for format oddities met while decoding (diagnostics only).
package struct VQADecodeStats: Equatable {
    /// Blocks whose codebook index lay beyond the bytes the current codebook
    /// was actually given (they read stale ring-buffer contents).
    package var staleCodebookRefs = 0
    /// Blocks drawn as a solid colour (hi byte == fill marker).
    package var fillBlocks = 0
    /// LCW streams that started with 0x00 (the "relative" variant).
    package var relativeLCWStreams = 0
    /// Chunk IDs this decoder skipped (unknown or not applicable).
    package var skippedChunks: [String: Int] = [:]
}

// MARK: - Decoder

package final class VQADecoder {
    package let header: VQAHeader
    package var width: Int { header.width }
    package var height: Int { header.height }
    package var frameRate: Int { header.frameRate }
    package var frameCount: Int { header.frameCount }

    /// Audio format of the decoded output (always 16-bit samples).
    package let hasAudio: Bool
    package let audioSampleRate: Int
    package let audioChannels: Int

    package private(set) var framesDecoded = 0
    /// Audio sample frames (per channel) handed out so far via `VQAFrame.audio`.
    package private(set) var audioSampleFramesDecoded = 0
    package private(set) var stats = VQADecodeStats()

    private let data: Data
    private let imaArithmetic: IMAArithmetic
    private let firstChunk: Int
    private var pos: Int

    // Video state
    private let blocksPerRow: Int
    private let blockRows: Int
    private let numBlocks: Int
    private let blockBytes: Int
    private let fillMarker: UInt8
    private let maxCBSize: Int
    private var codebooks: [[UInt8]]       // ring of NumCBBufs buffers
    private var codebookValid: [Int]       // bytes actually written to each
    private var curCB = 0                  // buffer the loader fills next
    private var fullCB = 0                 // newest complete codebook
    private var numPartialCB = 0
    private var partialCBSize = 0
    private var partialCompressed: [UInt8] = []
    private var pointers: [UInt8]
    private var palette8: [UInt8]

    // Audio state
    private var imaStates: [IMAADPCMChannelState] = []

    private static let numCBBufs = 3        // VQAConfig default, vqaconfig.cpp
    private static let maxPalSize = 1792    // VQA_AllocBuffers

    /// Parse the FORM/WVQA container and VQHD header. Returns nil for data that
    /// isn't a decodable 8-bit VQA (version 2, 4x2 or 4x4 blocks).
    /// `imaArithmetic: .multiply` reproduces ffmpeg's SND2 rounding (for
    /// byte-comparison only); the default is the game's own arithmetic.
    package init?(data: Data, imaArithmetic: IMAArithmetic = .westwood) {
        guard data.count >= 12 else { return nil }
        var found: VQAHeader?
        data.withUnsafeBytes { raw in
            guard fourCC(raw, 0) == ChunkID.form, fourCC(raw, 8) == ChunkID.wvqa else { return }
            var p = 12
            var header: VQAHeader?
            while p + 8 <= raw.count {
                let id = fourCC(raw, p)
                let size = Int(be32(raw, p + 4))
                let body = p + 8
                if id == ChunkID.vqhd {
                    guard size >= VQAHeader.size, body + VQAHeader.size <= raw.count else { return }
                    header = VQAHeader(UnsafeRawBufferPointer(rebasing: raw[body..<(body + VQAHeader.size)]))
                } else if id == ChunkID.finf || id == ChunkID.vqfr || id == ChunkID.vqfl
                            || id == ChunkID.vqfk || isAudioChunk(id) {
                    break
                }
                p = body + size + (size & 1)
            }
            found = header
        }
        // Version 2 only: v1 (Lands of Lore) stores pointers as 16-bit
        // index*8 words and v3 (TS/RA2) is hi-colour; TD ships neither.
        guard var h = found, h.version == 2,
              h.width > 0, h.height > 0,
              h.blockWidth == 4, h.blockHeight == 2 || h.blockHeight == 4,
              h.width % h.blockWidth == 0, h.height % h.blockHeight == 0 else { return nil }
        // VQA_Open: LOLG files store Groupsize 0; the library forces 8.
        if h.groupSize == 0 { h.groupSize = 8 }
        if h.frameRate == 0 { h.frameRate = 15 }
        self.header = h
        self.data = data
        self.imaArithmetic = imaArithmetic
        self.firstChunk = 12
        self.pos = 12

        hasAudio = h.hasAudio
        audioSampleRate = h.sampleRate > 0 ? h.sampleRate : 22050
        audioChannels = max(1, h.channels)

        blocksPerRow = h.width / h.blockWidth
        blockRows = h.height / h.blockHeight
        numBlocks = blocksPerRow * blockRows
        blockBytes = h.blockWidth * h.blockHeight
        // UnVQ_4x2 tests 15, UnVQ_4x4 tests 255 (unvqbuff.cpp).
        fillMarker = h.blockHeight == 2 ? 0x0F : 0xFF
        // VQA_AllocBuffers sizes a codebook buffer from CBentries; leave room for
        // every index a pointer can encode so a bad index can't run off the end.
        let declared = (blockBytes * h.codebookEntries + 250) & ~3
        maxCBSize = max(declared, blockBytes * 0x10000)
        codebooks = Array(repeating: [UInt8](repeating: 0, count: maxCBSize), count: VQADecoder.numCBBufs)
        codebookValid = Array(repeating: 0, count: VQADecoder.numCBBufs)
        pointers = [UInt8](repeating: 0, count: numBlocks * 2)
        palette8 = [UInt8](repeating: 0, count: 768)
    }

    /// Rewind to the first frame and clear all decoder state.
    package func reset() {
        pos = firstChunk
        framesDecoded = 0
        audioSampleFramesDecoded = 0
        stats = VQADecodeStats()
        for i in codebooks.indices {
            codebooks[i].withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
            codebookValid[i] = 0
        }
        curCB = 0; fullCB = 0; numPartialCB = 0; partialCBSize = 0
        partialCompressed.removeAll(keepingCapacity: true)
        pointers.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        palette8.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        imaStates.removeAll()
    }

    /// Frame due at a given audio position (audio is the master clock).
    package func frameIndex(atAudioTime seconds: Double) -> Int {
        max(0, Int((seconds * Double(frameRate)).rounded(.down)))
    }

    /// Decode the next frame, or nil at the end of the movie.
    package func nextFrame() -> VQAFrame? {
        guard framesDecoded < frameCount else { return nil }

        // VQA_LoadFrame: the frame is drawn with the codebook that was complete
        // before its chunks were read.
        let frameCB = fullCB
        var audio: [Int16] = []
        var gotFrame = false
        var paletteChanged = false

        data.withUnsafeBytes { raw in
            while !gotFrame, pos + 8 <= raw.count {
                let id = fourCC(raw, pos)
                let size = Int(be32(raw, pos + 4))
                let body = pos + 8
                let end = min(body + size, raw.count)
                pos = body + size + (size & 1)
                let chunk = UnsafeRawBufferPointer(rebasing: raw[body..<max(body, end)])
                switch id {
                case ChunkID.vqfr, ChunkID.vqfl, ChunkID.vqfk:
                    paletteChanged = loadFrameChunks(chunk) || paletteChanged
                    gotFrame = true
                case ChunkID.snd0, ChunkID.snd1, ChunkID.snd2:
                    if hasAudio { audio += decodeAudioChunk(id, chunk) }
                case ChunkID.vqhd, ChunkID.finf:
                    break
                default:
                    // VQA_LoadFrame also accepts codebook/palette/pointer chunks
                    // at the top level; a top-level pointer table ends the frame.
                    let r = loadSubChunk(id, chunk)
                    paletteChanged = r.palette || paletteChanged
                    if r.pointers { gotFrame = true }
                }
            }
            // Hand any audio stored after the last frame to the last frame.
            if gotFrame && framesDecoded + 1 == frameCount {
                while pos + 8 <= raw.count {
                    let id = fourCC(raw, pos)
                    let size = Int(be32(raw, pos + 4))
                    let body = pos + 8
                    let end = min(body + size, raw.count)
                    pos = body + size + (size & 1)
                    if hasAudio && isAudioChunk(id) {
                        audio += decodeAudioChunk(id, UnsafeRawBufferPointer(rebasing: raw[body..<max(body, end)]))
                    }
                }
            }
        }
        guard gotFrame else { return nil }

        let pixels = drawFrame(codebook: frameCB)
        let index = framesDecoded
        framesDecoded += 1
        audioSampleFramesDecoded += audio.count / audioChannels
        return VQAFrame(index: index, width: width, height: height, pixels: pixels,
                        palette: palette8, paletteChanged: paletteChanged, audio: audio,
                        presentationTime: Double(index) / Double(frameRate))
    }

    // MARK: Frame chunks

    /// Load the sub-chunks of one VQFR. Returns whether a palette was set.
    private func loadFrameChunks(_ frame: UnsafeRawBufferPointer) -> Bool {
        var p = 0
        var palette = false
        while p + 8 <= frame.count {
            let id = fourCC(frame, p)
            let size = Int(be32(frame, p + 4))
            let body = p + 8
            let end = min(body + size, frame.count)
            p = body + size + (size & 1)
            palette = loadSubChunk(id, UnsafeRawBufferPointer(rebasing: frame[body..<max(body, end)])).palette || palette
        }
        return palette
    }

    /// One codebook / palette / pointer chunk (VQA_Load_VQF's switch).
    private func loadSubChunk(_ id: UInt32, _ c: UnsafeRawBufferPointer) -> (palette: Bool, pointers: Bool) {
        switch id {
        case ChunkID.cbf0:
            // VQA_Load_CBF0: raw full codebook into the next ring buffer.
            let n = min(c.count, maxCBSize)
            codebooks[curCB].withUnsafeMutableBytes { dst in
                dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: c[0..<n]))
            }
            codebookValid[curCB] = n
            numPartialCB = 0
            completeCodebook()
        case ChunkID.cbfz:
            // VQA_Load_CBFZ (+ VQA_PrepareFrame's LCW_Uncompress).
            codebookValid[curCB] = decompress(c, into: curCB)
            numPartialCB = 0
            completeCodebook()
        case ChunkID.cbp0:
            // VQA_Load_CBP0: append this piece; after Groupsize pieces it's whole.
            let n = max(0, min(c.count, maxCBSize - partialCBSize))
            let at = partialCBSize
            codebooks[curCB].withUnsafeMutableBytes { dst in
                UnsafeMutableRawBufferPointer(rebasing: dst[at..<(at + n)])
                    .copyMemory(from: UnsafeRawBufferPointer(rebasing: c[0..<n]))
            }
            partialCBSize += n
            numPartialCB += 1
            if numPartialCB == header.groupSize {
                codebookValid[curCB] = partialCBSize
                numPartialCB = 0
                partialCBSize = 0
                completeCodebook()
            }
        case ChunkID.cbpz:
            // VQA_Load_CBPZ: the compressed pieces are concatenated and the
            // whole group is LCW-decompressed once it's complete.
            partialCompressed.append(contentsOf: c)
            numPartialCB += 1
            if numPartialCB == header.groupSize {
                codebookValid[curCB] = partialCompressed.withUnsafeBytes { decompress($0, into: curCB) }
                partialCompressed.removeAll(keepingCapacity: true)
                numPartialCB = 0
                partialCBSize = 0
                completeCodebook()
            }
        case ChunkID.cpl0:
            setPalette(c)
            return (true, false)
        case ChunkID.cplz:
            var pal = [UInt8](repeating: 0, count: VQADecoder.maxPalSize)
            let n = pal.withUnsafeMutableBufferPointer { lcw(c, into: $0) }
            pal.withUnsafeBytes { setPalette(UnsafeRawBufferPointer(rebasing: $0[0..<n])) }
            return (true, false)
        case ChunkID.vpt0, ChunkID.vptr:
            let n = min(c.count, pointers.count)
            pointers.withUnsafeMutableBytes { dst in
                dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: c[0..<n]))
            }
            return (false, true)
        case ChunkID.vptz, ChunkID.vprz:
            _ = pointers.withUnsafeMutableBufferPointer { lcw(c, into: $0) }
            return (false, true)
        default:
            stats.skippedChunks[fourCCString(id), default: 0] += 1
        }
        return (false, false)
    }

    /// The loader's current buffer becomes the newest full codebook and the
    /// loader moves on to the next buffer in the ring.
    private func completeCodebook() {
        fullCB = curCB
        curCB = (curCB + 1) % VQADecoder.numCBBufs
    }

    private func decompress(_ src: UnsafeRawBufferPointer, into cb: Int) -> Int {
        codebooks[cb].withUnsafeMutableBufferPointer { dst in
            lcw(src, into: UnsafeMutableBufferPointer(rebasing: dst[0..<min(dst.count, maxCBSize)]))
        }
    }

    /// LCW with the leading-0x00 "relative" variant detected the way ffmpeg's
    /// decode_format80 does. Tiberian Dawn's own movies never use it.
    private func lcw(_ src: UnsafeRawBufferPointer, into dst: UnsafeMutableBufferPointer<UInt8>) -> Int {
        let bytes = src.bindMemory(to: UInt8.self)
        if let first = bytes.first, first == 0 {
            stats.relativeLCWStreams += 1
            return WestwoodCodec.lcwDecompress(UnsafeBufferPointer(rebasing: bytes[1...]), into: dst, relative: true)
        }
        return WestwoodCodec.lcwDecompress(bytes, into: dst, relative: false)
    }

    /// Replace the first `c.count / 3` palette entries (a short palette only
    /// updates its prefix; VQA_Flag_To_Set_Palette with PaletteSize).
    private func setPalette(_ c: UnsafeRawBufferPointer) {
        let n = min(c.count, 768)
        for i in 0..<n {
            let v = c[i] & 0x3F
            palette8[i] = (v << 2) | (v >> 4)
        }
    }

    // MARK: Drawing

    /// UnVQ_4x2 / UnVQ_4x4 (unvqbuff.cpp) into a fresh indexed frame.
    private func drawFrame(codebook cbIndex: Int) -> [UInt8] {
        let w = width
        let bw = header.blockWidth
        let bh = header.blockHeight
        let bytesPerBlock = blockBytes
        let valid = codebookValid[cbIndex]
        let marker = fillMarker
        var stale = 0
        var fills = 0
        var out = [UInt8](repeating: 0, count: w * height)
        out.withUnsafeMutableBufferPointer { dst in
            pointers.withUnsafeBufferPointer { ptr in
                codebooks[cbIndex].withUnsafeBufferPointer { cb in
                    let cbCount = cb.count
                    var i = 0
                    for row in 0..<blockRows {
                        let rowBase = row * bh * w
                        for col in 0..<blocksPerRow {
                            let lo = ptr[i]
                            let hi = ptr[i + numBlocks]
                            i += 1
                            let base = rowBase + col * bw
                            if hi == marker {
                                fills += 1
                                for y in 0..<bh {
                                    let o = base + y * w
                                    for x in 0..<bw { dst[o + x] = lo }
                                }
                            } else {
                                let src = ((Int(hi) << 8) | Int(lo)) * bytesPerBlock
                                if src + bytesPerBlock > valid { stale += 1 }
                                guard src + bytesPerBlock <= cbCount else { continue }
                                var s = src
                                for y in 0..<bh {
                                    let o = base + y * w
                                    for x in 0..<bw { dst[o + x] = cb[s + x] }
                                    s += bw
                                }
                            }
                        }
                    }
                }
            }
        }
        stats.staleCodebookRefs += stale
        stats.fillBlocks += fills
        return out
    }

    // MARK: Audio

    private func decodeAudioChunk(_ id: UInt32, _ c: UnsafeRawBufferPointer) -> [Int16] {
        VQADecoder.decodeAudioChunk(id, c, version: header.version, bits: header.bitsPerSample,
                                    channels: audioChannels, imaStates: &imaStates, arithmetic: imaArithmetic)
    }

    private static func decodeAudioChunk(_ id: UInt32, _ c: UnsafeRawBufferPointer, version: Int, bits: Int,
                                         channels: Int, imaStates: inout [IMAADPCMChannelState],
                                         arithmetic: IMAArithmetic) -> [Int16] {
        switch id {
        case ChunkID.snd0:
            // VQA_Load_SND0: raw PCM, 16-bit signed LE or 8-bit unsigned.
            if version >= 2 && bits == 16 {
                return (0..<(c.count / 2)).map { Int16(bitPattern: UInt16(c[$0 * 2]) | (UInt16(c[$0 * 2 + 1]) << 8)) }
            }
            return c.map { Int16(Int($0) - 128) * 256 }
        case ChunkID.snd1:
            // VQA_Load_SND1: {Int16 OutSize, Int16 Size} then Westwood ADPCM,
            // or raw 8-bit when the two sizes match. Audio_Unzap restarts per chunk.
            guard c.count >= 4 else { return [] }
            let outSize = Int(c[0]) | (Int(c[1]) << 8)
            let inSize = Int(c[2]) | (Int(c[3]) << 8)
            let payload = UnsafeRawBufferPointer(rebasing: c[4...])
            if outSize == inSize {
                return payload.prefix(outSize).map { Int16(Int($0) - 128) * 256 }
            }
            return decodeWWADPCM(Data(payload), uncompressedSize: outSize)
        case ChunkID.snd2:
            // VQA_Load_SND2: headerless IMA, state carried across chunks.
            return decodeWestwoodIMAChunk(c, channels: channels, states: &imaStates, arithmetic: arithmetic)
        default:
            return []
        }
    }

    /// Decode just the audio of a movie (no video work), as one track.
    package static func decodeAudioTrack(data: Data, imaArithmetic: IMAArithmetic = .westwood) -> VQAAudioTrack? {
        guard let probe = VQADecoder(data: data), probe.hasAudio else { return nil }
        var samples: [Int16] = []
        var states: [IMAADPCMChannelState] = []
        data.withUnsafeBytes { raw in
            var p = probe.firstChunk
            while p + 8 <= raw.count {
                let id = fourCC(raw, p)
                let size = Int(be32(raw, p + 4))
                let body = p + 8
                let end = min(body + size, raw.count)
                p = body + size + (size & 1)
                guard isAudioChunk(id) else { continue }
                samples += decodeAudioChunk(id, UnsafeRawBufferPointer(rebasing: raw[body..<max(body, end)]),
                                            version: probe.header.version, bits: probe.header.bitsPerSample,
                                            channels: probe.audioChannels, imaStates: &states,
                                            arithmetic: imaArithmetic)
            }
        }
        return VQAAudioTrack(samples: samples, sampleRate: probe.audioSampleRate, channels: probe.audioChannels)
    }
}

// MARK: - Chunk helpers

enum ChunkID {
    static func make(_ s: StaticString) -> UInt32 {
        let p = s.utf8Start
        return (UInt32(p[0]) << 24) | (UInt32(p[1]) << 16) | (UInt32(p[2]) << 8) | UInt32(p[3])
    }
    static let form = make("FORM"), wvqa = make("WVQA"), vqhd = make("VQHD"), finf = make("FINF")
    static let vqfr = make("VQFR"), vqfl = make("VQFL"), vqfk = make("VQFK")
    static let cbf0 = make("CBF0"), cbfz = make("CBFZ"), cbp0 = make("CBP0"), cbpz = make("CBPZ")
    static let cpl0 = make("CPL0"), cplz = make("CPLZ")
    static let vpt0 = make("VPT0"), vptz = make("VPTZ"), vptr = make("VPTR"), vprz = make("VPRZ")
    static let snd0 = make("SND0"), snd1 = make("SND1"), snd2 = make("SND2")
}

@inline(__always)
private func isAudioChunk(_ id: UInt32) -> Bool {
    id == ChunkID.snd0 || id == ChunkID.snd1 || id == ChunkID.snd2
}

@inline(__always)
private func be32(_ b: UnsafeRawBufferPointer, _ o: Int) -> UInt32 {
    (UInt32(b[o]) << 24) | (UInt32(b[o + 1]) << 16) | (UInt32(b[o + 2]) << 8) | UInt32(b[o + 3])
}

@inline(__always)
private func fourCC(_ b: UnsafeRawBufferPointer, _ o: Int) -> UInt32 { be32(b, o) }

private func fourCCString(_ id: UInt32) -> String {
    String(decoding: [UInt8(id >> 24), UInt8((id >> 16) & 0xFF), UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF)],
           as: UTF8.self)
}
