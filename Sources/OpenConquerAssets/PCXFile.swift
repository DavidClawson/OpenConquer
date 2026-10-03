import Foundation

// MARK: - ZSoft PCX picture (Load_Title_Screen → Read_PCX_File, the Win95 build's
// 640x400 title art, HTITLE.PCX in UPDATA.MIX)
//
// Layout (little-endian): a 128-byte header —
//   +0 u8 manufacturer (10)   +1 u8 version   +2 u8 encoding (1 = RLE)
//   +3 u8 bits per pixel (8)  +4 u16 xmin, ymin, xmax, ymax (inclusive)
//  +65 u8 colour planes (1)  +66 u16 bytes per line (per plane, even)
// — then RLE scanlines: a byte with the top two bits set is a run of
// (byte & 0x3F) copies of the next byte, anything else is a literal. Runs may
// cross scanline ends; each line is bytesPerLine wide, of which the first
// (xmax - xmin + 1) bytes are picture. A 256-colour file ends with 0x0C and
// a 768-byte 8-bit palette.

package struct PCXFile {
    package let width: Int
    package let height: Int
    /// Palette indices, row-major, width × height.
    package let pixels: [UInt8]
    /// The trailing palette, reduced to the VGA DAC's 6 bits the way the
    /// game's Set_Palette path sees it (Read_PCX_File shifts each component
    /// right by 2).
    package let palette: VGAPalette?

    package init(data: Data) throws {
        try self.init(bytes: [UInt8](data))
    }

    package init(bytes b: [UInt8]) throws {
        guard b.count >= 128 else { throw WestwoodImageError.truncated("PCX header") }
        guard b[0] == 10, b[2] == 1 else { throw WestwoodImageError.badHeader("not an RLE PCX") }
        guard b[3] == 8, b[65] == 1 else {
            throw WestwoodImageError.badHeader("PCX \(b[3]) bpp × \(b[65]) planes (only 8-bit single plane)")
        }
        let xmin = wwReadLE16(b, 4), ymin = wwReadLE16(b, 6)
        let xmax = wwReadLE16(b, 8), ymax = wwReadLE16(b, 10)
        let stride = wwReadLE16(b, 66)
        width = xmax - xmin + 1
        height = ymax - ymin + 1
        guard width > 0, height > 0, stride >= width, width * height <= 1024 * 1024 else {
            throw WestwoodImageError.badHeader("PCX size \(width)x\(height), stride \(stride)")
        }

        var out = [UInt8](repeating: 0, count: width * height)
        var src = 128
        var line = [UInt8](repeating: 0, count: stride)
        var run = 0, runByte: UInt8 = 0
        for y in 0..<height {
            var x = 0
            while x < stride {
                if run == 0 {
                    guard src < b.count else { throw WestwoodImageError.truncated("PCX scanline \(y)") }
                    let v = b[src]; src += 1
                    if v & 0xC0 == 0xC0 {
                        guard src < b.count else { throw WestwoodImageError.truncated("PCX run") }
                        run = Int(v & 0x3F); runByte = b[src]; src += 1
                        if run == 0 { continue }
                    } else {
                        run = 1; runByte = v
                    }
                }
                line[x] = runByte
                x += 1
                run -= 1
            }
            for i in 0..<width { out[y * width + i] = line[i] }
        }
        pixels = out

        let palStart = b.count - 769
        if palStart >= src, b[palStart] == 0x0C {
            palette = try VGAPalette(vga6: b[(palStart + 1)...].map { $0 >> 2 })
        } else {
            palette = nil
        }
    }
}
