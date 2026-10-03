import Foundation

// MARK: - Westwood CPS picture (Load_Uncompress / Uncompress_Data, load.cpp)
//
// Layout (all little-endian):
//   +0  u16  file size, not counting these two bytes
//   +2  u8   compression method (CompressionType: 0 NOCOMPRESS, 4 LCW)
//   +3  u8   pad (0)
//   +4  u32  uncompressed size (64000 for a 320x200 picture)
//   +8  u16  skip size — "reserved data" before the image; a 768 here is the
//            embedded 6-bit palette (Load_Title_Screen passes its palette
//            pointer as reserved_data)
//  +10  skip bytes, then the (compressed) image.
// CPS images are always 320 wide (Load_Title_Screen hardcodes 320x200).

package struct CPSFile {
    package static let width = 320

    package let width: Int
    package let height: Int
    /// Palette indices, row-major, width × height.
    package let pixels: [UInt8]
    /// The embedded palette, if the skip block is a 768-byte palette.
    package let palette: VGAPalette?
    package let compressionMethod: Int

    package init(data: Data) throws {
        try self.init(bytes: [UInt8](data))
    }

    package init(bytes: [UInt8]) throws {
        guard bytes.count >= 10 else { throw WestwoodImageError.truncated("CPS header") }
        let method = Int(bytes[2])
        let uncompSize = Int(wwReadLE32(bytes, 4))
        let skip = wwReadLE16(bytes, 8)
        let dataStart = 10 + skip
        guard dataStart <= bytes.count else {
            throw WestwoodImageError.truncated("CPS skip block (\(skip) bytes)")
        }
        guard uncompSize > 0, uncompSize <= 320 * 400 else {
            throw WestwoodImageError.badHeader("CPS uncompressed size \(uncompSize)")
        }

        palette = skip == VGAPalette.byteCount
            ? try VGAPalette(vga6: Array(bytes[10..<dataStart])) : nil

        let body = Array(bytes[dataStart...])
        var out: [UInt8]
        switch method {
        case 0:  // NOCOMPRESS
            guard body.count >= uncompSize else {
                throw WestwoodImageError.truncated("CPS raw image")
            }
            out = Array(body.prefix(uncompSize))
        case 4:  // LCW
            out = WestwoodCodec.lcwDecompress(body, outputSize: uncompSize)
        default:
            throw WestwoodImageError.unsupportedCompression(method)
        }

        // Whole rows only; a non-multiple of 320 (never seen) is padded out.
        let h = (uncompSize + CPSFile.width - 1) / CPSFile.width
        if out.count < h * CPSFile.width {
            out += [UInt8](repeating: 0, count: h * CPSFile.width - out.count)
        }
        width = CPSFile.width
        height = h
        pixels = out
        compressionMethod = method
    }

    /// Palette index at (x, y), or nil outside the picture. This is the
    /// lookup MAPSEL.CPP does on the CLICK_*.CPS maps (SysMemPage.Get_Pixel).
    package func index(x: Int, y: Int) -> UInt8? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return pixels[y * width + x]
    }

    /// RGBA8888 using the embedded palette, or `palette` if given/needed.
    package func rgba(palette override: VGAPalette? = nil) -> [UInt8]? {
        guard let pal = override ?? palette else { return nil }
        return pal.rgba(pixels)
    }
}
