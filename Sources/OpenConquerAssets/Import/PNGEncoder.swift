import Foundation
import zlib

// MARK: - PNG encoder (8-bit straight-alpha RGBA)
//
// A self-contained writer so import code needs neither the app target nor
// ImageIO. ImageIO would take the pixels through a CGImage, whose alpha is
// premultiplied on the way in — that rounds the colour of every
// semi-transparent pixel, and the HD sprites are full of soft shadow edges.
// Writing the PNG directly keeps the RGBA exactly as decoded, matching what
// PIL wrote for tools/extract_remastered_sprites.py.
//
// Rows use libpng's adaptive filter choice (minimum sum of absolute
// differences); IDAT is compressed with the system zlib at level 2. Measured on
// the full sprite set (~14,000 frames, 10 cores): level 6 (PIL's default) takes
// 6.2s for 258 MB, level 2 takes 2.6s for 287 MB — the player is watching a
// progress bar, and inflate speed at load time is the same either way.

package func encodePNG(_ image: RGBAImage) -> Data {
    let w = image.width, h = image.height
    let stride = w * 4
    var filtered = [UInt8](repeating: 0, count: (stride + 1) * h)
    let zeroRow = [UInt8](repeating: 0, count: stride)
    // One buffer per filter type, filled in a single pass over the row.
    var residuals = [UInt8](repeating: 0, count: stride * 5)
    filtered.withUnsafeMutableBufferPointer { out in
        image.pixels.withUnsafeBufferPointer { px in
            zeroRow.withUnsafeBufferPointer { zero in
                residuals.withUnsafeMutableBufferPointer { r in
                    let r0 = r.baseAddress!, r1 = r0 + stride, r2 = r1 + stride, r3 = r2 + stride, r4 = r3 + stride
                    for y in 0..<h {
                        let row = px.baseAddress! + y * stride
                        let o = y * (stride + 1)
                        // Sprite canvases are mostly empty: an all-zero row is
                        // already optimal unfiltered (score 0), and `out` is zeroed.
                        if isAllZero(row, stride) { continue }
                        let prev = y > 0 ? px.baseAddress! + (y - 1) * stride : zero.baseAddress!
                        var s0 = 0, s1 = 0, s2 = 0, s3 = 0, s4 = 0
                        @inline(__always) func filter(_ i: Int, _ a: Int32, _ c: Int32) {
                            let x = Int32(row[i]), b = Int32(prev[i])
                            let pa = abs(b - c), pb = abs(a - c), pc = abs(a + b - 2 * c)
                            let paeth = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
                            let v0 = UInt8(truncatingIfNeeded: x)
                            let v1 = UInt8(truncatingIfNeeded: x &- a)
                            let v2 = UInt8(truncatingIfNeeded: x &- b)
                            let v3 = UInt8(truncatingIfNeeded: x &- ((a &+ b) >> 1))
                            let v4 = UInt8(truncatingIfNeeded: x &- paeth)
                            r0[i] = v0; r1[i] = v1; r2[i] = v2; r3[i] = v3; r4[i] = v4
                            s0 &+= Int(abs(Int16(Int8(bitPattern: v0))))
                            s1 &+= Int(abs(Int16(Int8(bitPattern: v1))))
                            s2 &+= Int(abs(Int16(Int8(bitPattern: v2))))
                            s3 &+= Int(abs(Int16(Int8(bitPattern: v3))))
                            s4 &+= Int(abs(Int16(Int8(bitPattern: v4))))
                        }
                        for i in 0..<min(4, stride) { filter(i, 0, 0) }
                        if stride > 4 {
                            for i in 4..<stride { filter(i, Int32(row[i - 4]), Int32(prev[i - 4])) }
                        }
                        var best = r0, bestType: UInt8 = 0, bestScore = s0
                        if s1 < bestScore { best = r1; bestType = 1; bestScore = s1 }
                        if s2 < bestScore { best = r2; bestType = 2; bestScore = s2 }
                        if s3 < bestScore { best = r3; bestType = 3; bestScore = s3 }
                        if s4 < bestScore { best = r4; bestType = 4; bestScore = s4 }
                        out[o] = bestType
                        (out.baseAddress! + o + 1).update(from: best, count: stride)
                    }
                }
            }
        }
    }

    var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    var ihdr = [UInt8]()
    ihdr.appendBE32(UInt32(w)); ihdr.appendBE32(UInt32(h))
    ihdr += [8, 6, 0, 0, 0]  // 8-bit, RGBA, deflate, adaptive filtering, no interlace
    png.appendPNGChunk("IHDR", ihdr)
    png.appendPNGChunk("IDAT", zlibCompress(filtered))
    png.appendPNGChunk("IEND", [])
    return png
}

@inline(__always)
private func isAllZero(_ p: UnsafePointer<UInt8>, _ count: Int) -> Bool {
    var i = 0
    let raw = UnsafeRawPointer(p)
    while i + 8 <= count {
        if raw.loadUnaligned(fromByteOffset: i, as: UInt64.self) != 0 { return false }
        i += 8
    }
    while i < count { if p[i] != 0 { return false }; i += 1 }
    return true
}

private let pngDeflateLevel: Int32 = 2

/// zlib (RFC 1950) stream via the system libz.
func zlibCompress(_ input: [UInt8]) -> [UInt8] {
    var capacity = compressBound(uLong(input.count))
    var out = [UInt8](repeating: 0, count: Int(capacity))
    let status = out.withUnsafeMutableBufferPointer { dst in
        input.withUnsafeBufferPointer { src in
            compress2(dst.baseAddress!, &capacity, src.baseAddress, uLong(input.count), pngDeflateLevel)
        }
    }
    precondition(status == Z_OK, "compress2 failed: \(status)")
    out.removeSubrange(Int(capacity)...)
    return out
}

private extension Array where Element == UInt8 {
    mutating func appendBE32(_ v: UInt32) {
        append(UInt8(v >> 24)); append(UInt8((v >> 16) & 0xFF)); append(UInt8((v >> 8) & 0xFF)); append(UInt8(v & 0xFF))
    }
}

private extension Data {
    mutating func appendPNGChunk(_ type: String, _ body: [UInt8]) {
        var length = [UInt8](); length.appendBE32(UInt32(body.count))
        append(contentsOf: length)
        let typed = Array(type.utf8) + body
        append(contentsOf: typed)
        let sum = typed.withUnsafeBufferPointer { UInt32(zlib.crc32(0, $0.baseAddress, uInt($0.count))) }
        var crc = [UInt8](); crc.appendBE32(sum)
        append(contentsOf: crc)
    }
}
