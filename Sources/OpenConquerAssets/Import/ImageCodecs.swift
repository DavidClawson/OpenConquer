import Foundation

// MARK: - Straight-alpha RGBA image + TGA / DDS decoders
//
// Ports of `read_tga` / `read_dds` and PIL's `Image.new` + `paste` as used by
// tools/extract_remastered_sprites.py. Pixels are straight (not premultiplied)
// RGBA8888, row-major, top row first — exactly what PIL hands to its PNG writer.

package struct RGBAImage {
    package let width: Int
    package let height: Int
    package var pixels: [UInt8]

    /// A fully transparent canvas (PIL `Image.new('RGBA', size, (0, 0, 0, 0))`).
    package init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
        pixels = [UInt8](repeating: 0, count: self.width * self.height * 4)
    }

    package init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// PIL `paste(src, (x, y))` without a mask: source pixels (alpha included)
    /// replace the destination, clipped to the canvas.
    package mutating func paste(_ src: RGBAImage, x: Int, y: Int) {
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(width, x + src.width), y1 = min(height, y + src.height)
        guard x1 > x0, y1 > y0 else { return }
        let rowBytes = (x1 - x0) * 4
        let dstWidth = width
        pixels.withUnsafeMutableBufferPointer { dst in
            src.pixels.withUnsafeBufferPointer { s in
                for row in y0..<y1 {
                    let d = (row * dstWidth + x0) * 4
                    let o = ((row - y) * src.width + (x0 - x)) * 4
                    (dst.baseAddress! + d).update(from: s.baseAddress! + o, count: rowBytes)
                }
            }
        }
    }
}

/// Uncompressed true-colour TGA (type 2, 24 or 32 bpp), flipped upright unless
/// the descriptor's top-left-origin bit is set. Mirrors `read_tga`.
package func decodeTGA(_ data: [UInt8]) -> RGBAImage? {
    guard data.count >= 18 else { return nil }
    let idLength = Int(data[0])
    let imageType = data[2]
    let width = Int(data[12]) | Int(data[13]) << 8
    let height = Int(data[14]) | Int(data[15]) << 8
    let depth = Int(data[16])
    let originUpper = (data[17] & 0x20) != 0
    guard imageType == 2, depth == 24 || depth == 32 else { return nil }
    let bpp = depth / 8
    let start = 18 + idLength
    guard data.count >= start + width * height * bpp else { return nil }

    var out = [UInt8](repeating: 255, count: width * height * 4)
    out.withUnsafeMutableBufferPointer { dst in
        data.withUnsafeBufferPointer { src in
            for y in 0..<height {
                let dy = originUpper ? y : height - 1 - y
                var s = start + y * width * bpp
                var d = dy * width * 4
                for _ in 0..<width {
                    dst[d] = src[s + 2]
                    dst[d + 1] = src[s + 1]
                    dst[d + 2] = src[s]
                    if bpp == 4 { dst[d + 3] = src[s + 3] }
                    s += bpp
                    d += 4
                }
            }
        }
    }
    return RGBAImage(width: width, height: height, pixels: out)
}

/// Uncompressed 32-bit DDS surface (no FourCC), BGRA unless the masks say RGBA.
/// Mirrors `read_dds`: compressed / DX10 surfaces return nil.
package func decodeDDS(_ data: [UInt8]) -> RGBAImage? {
    guard data.count >= 128, data[0] == 0x44, data[1] == 0x44, data[2] == 0x53, data[3] == 0x20 else { return nil }
    func u32(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 | Int(data[o + 2]) << 16 | Int(data[o + 3]) << 24 }
    let height = u32(12), width = u32(16)
    var pitch = u32(20)
    let fourCC = u32(84), rgbBits = u32(88)
    let rMask = u32(92), gMask = u32(96), bMask = u32(100)
    guard fourCC == 0, rgbBits == 32, width > 0, height > 0 else { return nil }
    if pitch == 0 { pitch = width * 4 }
    let rgbaOrder = rMask == 0x0000_00FF && gMask == 0x0000_FF00 && bMask == 0x00FF_0000
    let rowBytes = width * 4

    // Python slices row by row (or the whole block when pitch == row bytes) and
    // rejects the surface if the result is short; a partial last row counts.
    let available = data.count - 128
    if pitch == rowBytes {
        guard available >= rowBytes * height else { return nil }
    } else {
        var total = 0
        for y in 0..<height {
            let s = y * pitch
            total += max(0, min(available, s + rowBytes) - s)
        }
        guard total >= rowBytes * height else { return nil }
    }

    var out = [UInt8](repeating: 0, count: rowBytes * height)
    out.withUnsafeMutableBufferPointer { dst in
        data.withUnsafeBufferPointer { src in
            for y in 0..<height {
                var s = 128 + y * pitch
                var d = y * rowBytes
                for _ in 0..<width {
                    if rgbaOrder {
                        dst[d] = src[s]; dst[d + 1] = src[s + 1]; dst[d + 2] = src[s + 2]
                    } else {
                        dst[d] = src[s + 2]; dst[d + 1] = src[s + 1]; dst[d + 2] = src[s]
                    }
                    dst[d + 3] = src[s + 3]
                    s += 4
                    d += 4
                }
            }
        }
    }
    return RGBAImage(width: width, height: height, pixels: out)
}
