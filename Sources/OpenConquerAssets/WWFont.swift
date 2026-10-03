import Foundation

// MARK: - Westwood .FNT bitmap font (Load_Font / Buffer_Print, common/font.cpp)
//
// Layout (all little-endian; the FontHeader struct in font.cpp):
//   +0  u16  file length
//   +2  u8   compression (0)       +3  u8  data block count (5 for TD/RA)
//   +4  u16  info block offset     +6  u16 offset block (u16 per glyph → bitmap)
//   +8  u16  width block (u8 per glyph)
//  +10  u16  data block            +12 u16 height block (u16 per glyph)
//  +14  u16  unknown (0x1012)
// The info block (always at 0x0E in TD's fonts) holds, at +3, the char count
// - 1; at +4, the max height (FONTINFOMAXHEIGHT); at +5, the max width —
// i.e. file bytes 17/18/19, where Buffer_Print's FontHeader struct reads them.
//
// Each glyph's height-block entry packs the blank rows above the bitmap in
// its low byte (char_ypos) and the number of stored bitmap rows in its high
// byte (char_lines). A stored row is ceil(width / 2) bytes, 4 bits per pixel,
// LOW nibble first. Colour 0 is transparent; other colours go through the
// font palette (ColorXlat[0][c], set by Set_Font_Palette).

/// A Westwood .FNT bitmap font as used by TD (4 bits per pixel; color index 0 = transparent).
package struct WWFont {
    private let bytes: [UInt8]
    private let offsetBlock: Int
    private let widthBlock: Int
    private let heightBlock: Int
    /// Number of glyphs the font defines (codes 0..<glyphCount).
    package let glyphCount: Int
    package let maxWidth: Int
    private let maxHeight: Int

    package init?(data: Data) {
        let b = [UInt8](data)
        guard b.count >= 20, b[2] == 0, b[3] == 5 else { return nil }  // Load_Font's validity check
        func le16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        let info = le16(4)
        offsetBlock = le16(6)
        widthBlock = le16(8)
        heightBlock = le16(12)
        guard info + 6 <= b.count else { return nil }
        glyphCount = Int(b[info + 3]) + 1
        maxHeight = Int(b[info + 4])
        maxWidth = Int(b[info + 5])
        guard offsetBlock + glyphCount * 2 <= b.count,
              widthBlock + glyphCount <= b.count,
              heightBlock + glyphCount * 2 <= b.count else { return nil }
        bytes = b
    }

    /// Max glyph height (FontHeader.MaxHeight) — the line height Buffer_Print uses.
    package var height: Int { maxHeight }

    /// Char_Pixel_Width without FontXSpacing: the glyph's advance; 0 outside the font.
    package func width(of char: UInt8) -> Int {
        Int(char) < glyphCount ? Int(bytes[widthBlock + Int(char)]) : 0
    }

    /// Sum of glyph widths (String_Pixel_Width for a single line).
    package func width(of text: String) -> Int {
        WWFont.codes(text).reduce(0) { $0 + width(of: $1) }
    }

    /// Glyph placement for one character: blank rows above the bitmap
    /// (char_ypos) and the number of stored rows (char_lines).
    package func glyphRows(of char: UInt8) -> (yOffset: Int, lines: Int) {
        guard Int(char) < glyphCount else { return (0, 0) }
        let o = heightBlock + Int(char) * 2
        return (Int(bytes[o]), Int(bytes[o + 1]))
    }

    /// Pixel count per font colour (0...15) over every glyph's stored bitmap —
    /// shows which font-palette entries the font actually uses.
    package func colorHistogram() -> [Int] {
        var hist = [Int](repeating: 0, count: 16)
        for g in 0..<glyphCount {
            let w = Int(bytes[widthBlock + g])
            let lines = Int(bytes[heightBlock + g * 2 + 1])
            let src = Int(bytes[offsetBlock + g * 2]) | Int(bytes[offsetBlock + g * 2 + 1]) << 8
            let rowBytes = (w + 1) / 2
            guard lines > 0, src + rowBytes * lines <= bytes.count else { continue }
            for row in 0..<lines {
                for col in 0..<w {
                    let packed = bytes[src + row * rowBytes + col / 2]
                    hist[Int(col & 1 == 0 ? packed & 0x0F : packed >> 4)] += 1
                }
            }
        }
        return hist
    }

    /// Text as the game's 8-bit codes: scalars 0...255 map to themselves
    /// (StringTable decodes bytes as Latin-1), anything else is dropped.
    static func codes(_ text: String) -> [UInt8] {
        text.unicodeScalars.compactMap { $0.value < 256 ? UInt8($0.value) : nil }
    }

    /// Draw `text` into an 8-bit indexed page. Each glyph pixel with font color c != 0 is written as `remap[c]`
    /// (remap has 16 entries, like Set_Font_Palette). Clipped to the page. Returns the x after the last glyph.
    /// If `fixedAdvance` is non-nil every character advances by that many pixels instead of its own width.
    ///
    /// Like Buffer_Print, a pixel whose remapped colour is 0 is also left
    /// untouched (the blitter skips `if (color)`), so remap[c] = 0 hides colour c.
    /// The background (colour 0) is never filled. "\r" starts a new line at
    /// `x`, "\n" at column 0, each `height` rows down.
    @discardableResult
    package func draw(_ text: String, into page: inout [UInt8], pageWidth: Int, pageHeight: Int,
                      x: Int, y: Int, remap: [UInt8], fixedAdvance: Int? = nil) -> Int {
        var penX = x, penY = y
        for code in WWFont.codes(text) {
            if code == 0x0D || code == 0x0A {
                penX = code == 0x0D ? x : 0
                penY += maxHeight
                continue
            }
            guard Int(code) < glyphCount else {
                if let fixedAdvance { penX += fixedAdvance }
                continue
            }
            let w = Int(bytes[widthBlock + Int(code)])
            let (yOff, lines) = glyphRows(of: code)
            var src = Int(bytes[offsetBlock + Int(code) * 2]) | Int(bytes[offsetBlock + Int(code) * 2 + 1]) << 8
            let rowBytes = (w + 1) / 2
            for row in 0..<lines {
                let py = penY + yOff + row
                defer { src += rowBytes }
                guard py >= 0, py < pageHeight, src + rowBytes <= bytes.count else { continue }
                for col in 0..<w {
                    let px = penX + col
                    guard px >= 0, px < pageWidth else { continue }
                    let packed = bytes[src + col / 2]
                    let c = Int(col & 1 == 0 ? packed & 0x0F : packed >> 4)
                    guard c != 0, c < remap.count else { continue }
                    let out = remap[c]
                    if out != 0 { page[py * pageWidth + px] = out }
                }
            }
            penX += fixedAdvance ?? w
        }
        return penX
    }
}
