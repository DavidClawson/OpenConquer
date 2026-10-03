import XCTest
import OpenConquerAssets

// Synthetic (asset-free) coverage for the CONQUER.ENG string table and the
// Westwood .FNT decoder. Every file here is built in memory.

private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }

/// A string table in CONQUER.ENG layout: u16 offsets, then NUL-terminated strings.
private func makeStringTable(_ strings: [[UInt8]]) -> Data {
    var offsets: [UInt8] = [], body: [UInt8] = []
    let base = strings.count * 2
    for s in strings {
        offsets += le16(base + body.count)
        body += s + [0]
    }
    return Data(offsets + body)
}

/// A TD-layout .FNT with glyphs only for 'A' and 'B' (every lower code has
/// width 0 and no rows, so the font's range is 0...'B'):
///   'A': width 3, 1 blank row, then rows [1 2 3] and [0 1 0]
///   'B': width 2, no blank rows, one row [4 0]
/// Max height 4, max width 3.
private func makeFont() -> Data {
    let count = Int(UInt8(ascii: "B")) + 1
    let offsetBlock = 0x14
    let widthBlock = offsetBlock + count * 2
    let heightBlock = widthBlock + count
    let dataBlock = heightBlock + count * 2
    let glyphA: [UInt8] = [0x21, 0x03, 0x10, 0x00]  // low nibble = left pixel
    let glyphB: [UInt8] = [0x04]
    var offsets = [UInt8](), widths = [UInt8](), heights = [UInt8]()
    for c in 0..<count {
        switch c {
        case 65: offsets += le16(dataBlock); widths.append(3); heights += [1, 2]
        case 66: offsets += le16(dataBlock + glyphA.count); widths.append(2); heights += [0, 1]
        default: offsets += le16(dataBlock); widths.append(0); heights += [0, 0]
        }
    }
    var header = le16(0) + [0, 5] + le16(0x0E) + le16(offsetBlock) + le16(widthBlock)
        + le16(dataBlock) + le16(heightBlock)
    header += [0x12, 0x10, 0x00, UInt8(count - 1), 4, 3]  // info block at 0x0E
    var file = header + offsets + widths + heights + glyphA + glyphB
    let len = le16(file.count - 2)
    file[0] = len[0]; file[1] = len[1]
    return Data(file)
}

final class FontTests: XCTestCase {
    func testStringTable() throws {
        let table = try XCTUnwrap(StringTable(data: makeStringTable([[], Array("HELLO".utf8), [0x41, 0xE9]])))
        XCTAssertEqual(table.count, 3)
        XCTAssertEqual(table[0], "")
        XCTAssertEqual(table[1], "HELLO")
        XCTAssertEqual(table[2].unicodeScalars.map(\.value), [0x41, 0xE9])  // 8-bit bytes kept as Latin-1
        XCTAssertEqual(table[3], "")
        XCTAssertEqual(table[-1], "")
        // Ids the older CONQUER.ENG lacks fall back like mapsel.cpp's GetMapSelString.
        XCTAssertEqual(table[742], "READING IMAGE DATA")
        XCTAssertEqual(table[748], "ENHANCING IMAGE")
        XCTAssertEqual(table[749], "")
        XCTAssertNil(StringTable(data: Data([1])))
    }

    func testFontMetrics() throws {
        let font = try XCTUnwrap(WWFont(data: makeFont()))
        XCTAssertEqual(font.height, 4)
        XCTAssertEqual(font.width(of: UInt8(ascii: "A")), 3)
        XCTAssertEqual(font.width(of: UInt8(ascii: "B")), 2)
        XCTAssertEqual(font.width(of: UInt8(ascii: "C")), 0)  // beyond the font's range
        XCTAssertEqual(font.width(of: "ABA"), 8)
        XCTAssertEqual(font.width(of: "ACB"), 5)
        XCTAssertNil(WWFont(data: Data([0, 0, 1, 5])))
    }

    func testFontDraw() throws {
        let font = try XCTUnwrap(WWFont(data: makeFont()))
        let w = 8, h = 5, bg: UInt8 = 0xEE
        let remap: [UInt8] = (0..<16).map { UInt8($0 * 10) }
        var page = [UInt8](repeating: bg, count: w * h)
        let end = font.draw("ACB", into: &page, pageWidth: w, pageHeight: h, x: 1, y: 0, remap: remap)
        XCTAssertEqual(end, 6)
        var want = [UInt8](repeating: bg, count: w * h)
        // 'A' at x=1: one blank row, then [1 2 3] / [0 1 0]; colour 0 leaves the page alone.
        want[1 * w + 1] = 10; want[1 * w + 2] = 20; want[1 * w + 3] = 30
        want[2 * w + 2] = 10
        // 'C' is outside the font: nothing drawn, no advance. 'B' at x=4: [4 0] on row 0.
        want[0 * w + 4] = 40
        XCTAssertEqual(page, want)

        // Fixed advance, clipping at both edges, and a zero remap entry hiding a colour.
        var page2 = [UInt8](repeating: 0, count: w * h)
        var hide = remap
        hide[2] = 0
        let end2 = font.draw("AB", into: &page2, pageWidth: w, pageHeight: h, x: -1, y: 2,
                             remap: hide, fixedAdvance: 6)
        XCTAssertEqual(end2, 11)
        var want2 = [UInt8](repeating: 0, count: w * h)
        // 'A' at x=-1, rows y=3,4: [1 2 3] → col -1 clipped, col 0 hidden (remap 0), col 1 = 30;
        // [0 1 0] → col 0 = 10. 'B' at x=5, row y=2: [4 0].
        want2[3 * w + 1] = 30
        want2[4 * w + 0] = 10
        want2[2 * w + 5] = 40
        XCTAssertEqual(page2, want2)

        // Off the bottom: rows past the page are clipped, not wrapped.
        var page3 = [UInt8](repeating: 0, count: w * h)
        font.draw("A", into: &page3, pageWidth: w, pageHeight: h, x: 0, y: 3, remap: remap)
        XCTAssertEqual(page3.filter { $0 != 0 }.count, 3)
        XCTAssertEqual(Array(page3[(4 * w)..<(4 * w + 3)]), [10, 20, 30])
    }
}
