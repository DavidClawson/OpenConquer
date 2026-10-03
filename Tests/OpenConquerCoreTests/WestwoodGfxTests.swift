import XCTest
import OpenConquerAssets

// Synthetic (asset-free) coverage for the CPS / WSA / PAL decoders and the
// shared LCW + XOR-delta codec. Every file here is built in memory.

private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
private func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }

/// LCW stream made only of literal runs (0x80|n, n ≤ 63) + the 0x80 end mark.
private func lcwLiteral(_ bytes: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    var i = 0
    while i < bytes.count {
        let n = min(63, bytes.count - i)
        out.append(0x80 | UInt8(n))
        out += bytes[i..<(i + n)]
        i += n
    }
    return out + [0x80]
}

/// A 6-bit ramp palette: index i = (i&63, (i>>2)&63, 63-(i&63)).
private func rampPalette() -> [UInt8] {
    var out: [UInt8] = []
    for i in 0..<256 {
        out.append(UInt8(i & 63))
        out.append(UInt8((i >> 2) & 63))
        out.append(UInt8(63 - (i & 63)))
    }
    return out
}

/// Builds a TD WSA: header, offsets[n+2], optional palette, LCW'd deltas.
/// `deltas` holds n frame deltas plus (optionally) the loop delta; a nil
/// frame-0 delta means "frame 0 on page" (offset 0).
private func makeWSA(width: Int, height: Int, frameCount n: Int, deltas: [[UInt8]?],
                     palette: [UInt8]? = nil, extraFlags: Int = 0) -> [UInt8] {
    let flags = (palette != nil ? 1 : 0) | extraFlags
    let compressed = deltas.map { $0.map(lcwLiteral) }
    var offsets: [Int] = []
    var pos = 14 + (n + 2) * 4
    for c in compressed {
        if let c { offsets.append(pos); pos += c.count } else { offsets.append(0) }
    }
    let hasLoop = deltas.count > n
    offsets.append(hasLoop ? pos : 0)  // final end offset (0 = linear only)
    if !hasLoop { offsets[n] = pos }    // linear: offsets[n] = end of last frame
    while offsets.count < n + 2 { offsets.append(0) }
    let largest = compressed.compactMap { $0?.count }.max() ?? 0
    var out: [UInt8] = le16(n)
    for v in [0, 0, width, height, largest + 64, flags] { out += le16(v) }
    for o in offsets { out += le32(o) }
    if let palette { out += palette }
    for c in compressed { if let c { out += c } }
    return out
}

final class WestwoodGfxTests: XCTestCase {

    // MARK: Palette

    func testPaletteScaling() throws {
        XCTAssertEqual(VGAPalette.expand6(0), 0)
        XCTAssertEqual(VGAPalette.expand6(63), 255)
        XCTAssertEqual(VGAPalette.expand6(32), 130)  // (32<<2)|(32>>4)
        let pal = try VGAPalette(vga6: rampPalette())
        XCTAssertEqual(pal.colors[63].r, 255)
        XCTAssertEqual(pal.colors[63].b, 0)
        XCTAssertEqual(pal.rgba([63, 0], transparentIndex: 0), [255, 60, 0, 255, 0, 0, 255, 0])
        XCTAssertThrowsError(try VGAPalette(vga6: [UInt8](repeating: 0, count: 767)))
    }

    // MARK: Codec

    func testXORDeltaCommands() {
        // short XOR(2), fill(0,count 3,val 0x0F), short skip 1, long skip 2,
        // long fill 0xC000|2 val 0xF0, long XOR 0x8000|1, end.
        let delta: [UInt8] = [2, 0xAA, 0xBB, 0, 3, 0x0F, 0x81, 0x80, 2, 0, 0x80, 2, 0xC0, 0xF0,
                              0x80, 1, 0x80, 0x55, 0x80, 0, 0]
        var buf = [UInt8](repeating: 0x01, count: 12)
        WestwoodCodec.applyXORDelta(&buf, delta: delta)
        XCTAssertEqual(buf, [0xAB, 0xBA, 0x0E, 0x0E, 0x0E, 0x01, 0x01, 0x01, 0xF1, 0xF1, 0x54, 0x01])
        var copied = [UInt8](repeating: 0x01, count: 12)
        WestwoodCodec.applyXORDelta(&copied, delta: delta, copy: true)
        XCTAssertEqual(copied, [0xAA, 0xBB, 0x0F, 0x0F, 0x0F, 0x01, 0x01, 0x01, 0xF0, 0xF0, 0x55, 0x01])
        // XOR is self-inverse: applying twice restores the input.
        WestwoodCodec.applyXORDelta(&buf, delta: delta)
        XCTAssertEqual(buf, [UInt8](repeating: 0x01, count: 12))
    }

    func testLCWOpsAndSHPForwarding() {
        // literal "AB", short back-copy (count 3, offset 2) → ABABA,
        // fill 0xFE n=3 'Z', absolute copy 0xC0 (3 bytes from 0), end.
        let src: [UInt8] = [0x82, 0x41, 0x42, 0x00, 0x02, 0xFE, 3, 0, 0x5A, 0xC0, 0, 0, 0x80]
        let (out, written) = WestwoodCodec.lcwDecompressCounted(src, outputSize: 16)
        XCTAssertEqual(written, 11)
        XCTAssertEqual(Array(out.prefix(11)), Array("ABABAZZZABA".utf8))
        XCTAssertEqual(SHPFile.lcwDecompress(src, outputSize: 16), out)
    }

    // MARK: CPS

    func testCPSUncompressedWithPalette() throws {
        let pixels = (0..<64000).map { UInt8($0 % 251) }
        var body: [UInt8] = [0, 0]
        body += le32(64000); body += le16(768); body += rampPalette(); body += pixels
        let file = le16(body.count) + body
        let cps = try CPSFile(bytes: file)
        XCTAssertEqual(cps.width, 320)
        XCTAssertEqual(cps.height, 200)
        XCTAssertEqual(cps.compressionMethod, 0)
        XCTAssertEqual(cps.pixels, pixels)
        XCTAssertEqual(cps.palette?.raw6, rampPalette())
        XCTAssertEqual(cps.index(x: 5, y: 1), UInt8(325 % 251))
        XCTAssertNil(cps.index(x: 320, y: 0))
        XCTAssertEqual(cps.rgba()?.count, 64000 * 4)
    }

    func testCPSLCWNoPalette() throws {
        // Fill the picture with 0x80, then overwrite the start with a literal
        // isn't possible in one pass, so: literal 3 bytes then a long fill.
        var lcw: [UInt8] = [0x83, 7, 8, 9, 0xFE]
        lcw += le16(64000 - 3); lcw += [0x81, 0x80]
        var body: [UInt8] = [4, 0]
        body += le32(64000); body += le16(0); body += lcw
        let cps = try CPSFile(bytes: le16(body.count) + body)
        XCTAssertNil(cps.palette)
        XCTAssertEqual(Array(cps.pixels.prefix(4)), [7, 8, 9, 0x81])
        XCTAssertEqual(cps.pixels.last, 0x81)
        XCTAssertEqual(cps.index(x: 2, y: 0), 9)
        XCTAssertNil(cps.rgba())
        // Unsupported method (LZW12 = 1) is rejected.
        var bad: [UInt8] = [1, 0]
        bad += le32(64000); bad += le16(0); bad += lcw
        XCTAssertThrowsError(try CPSFile(bytes: le16(bad.count) + bad))
    }

    // MARK: WSA

    /// 4x2 animation. frame0 = 1..8 over black; frame1 XORs bytes 2-4 with
    /// 0xFF; the loop delta is the same XOR (self-inverse) back to frame 0.
    private let f0: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
    private let d0: [UInt8] = [8, 1, 2, 3, 4, 5, 6, 7, 8, 0x80, 0, 0]
    private let d1: [UInt8] = [0x82, 0, 3, 0xFF, 0x80, 0, 0]
    private var f1: [UInt8] { [1, 2, 3 ^ 0xFF, 4 ^ 0xFF, 5 ^ 0xFF, 6, 7, 8] }

    func testWSATwoFramesWithLoop() throws {
        let file = makeWSA(width: 4, height: 2, frameCount: 2, deltas: [d0, d1, d1], palette: rampPalette())
        let wsa = try WSAFile(bytes: file)
        XCTAssertEqual(wsa.frameCount, 2)
        XCTAssertEqual(wsa.width, 4)
        XCTAssertEqual(wsa.height, 2)
        XCTAssertTrue(wsa.hasLoopFrame)
        XCTAssertFalse(wsa.frame0OnPage)
        XCTAssertEqual(wsa.palette?.raw6, rampPalette())
        XCTAssertEqual(wsa.decodeAllFrames(), [f0, f1])

        // Animate_Frame semantics: forward wrap uses the loop delta, and
        // seeking backwards re-applies the current frame's delta.
        var p = WSAPlayer(wsa)
        p.seek(to: 1)
        XCTAssertEqual(p.buffer, f1)
        p.advance()  // 1 → 0 through the loop delta
        XCTAssertEqual(p.currentFrame, 0)
        XCTAssertEqual(p.buffer, f0)
        p.advance()
        p.seek(to: 0)  // backwards
        XCTAssertEqual(p.buffer, f0)
        XCTAssertEqual(wsa.rgba(f0)?.count, 8 * 4)
    }

    func testWSALinearOnly() throws {
        let file = makeWSA(width: 4, height: 2, frameCount: 2, deltas: [d0, d1])
        let wsa = try WSAFile(bytes: file)
        XCTAssertFalse(wsa.hasLoopFrame)
        XCTAssertNil(wsa.palette)
        XCTAssertEqual(wsa.decodeAllFrames(), [f0, f1])
        var p = WSAPlayer(wsa)
        p.seek(to: 1)
        p.advance()  // no loop delta: walks back to frame 0
        XCTAssertEqual(p.buffer, f0)
    }

    func testWSAFrame0OnPageAndBases() throws {
        let base: [UInt8] = [9, 9, 9, 9, 9, 9, 9, 9]
        // Frame 0 has no data: it is whatever is on the page.
        let onPage = try WSAFile(bytes: makeWSA(width: 4, height: 2, frameCount: 2, deltas: [nil, d1, d1]))
        XCTAssertTrue(onPage.frame0OnPage)
        let frames = onPage.decodeAllFrames(base: base)
        XCTAssertEqual(frames[0], base)
        XCTAssertEqual(frames[1], [9, 9, 9 ^ 0xFF, 9 ^ 0xFF, 9 ^ 0xFF, 9, 9, 9])

        // A partial frame-0 delta (skip 2, write 2) over a non-black page:
        // copied normally, XORed when flags & 2 (WSA_FRAME_0_IS_DELTA).
        let partial: [UInt8] = [0x82, 2, 0x0F, 0x0F, 0x80, 0, 0]
        let copyWSA = try WSAFile(bytes: makeWSA(width: 4, height: 2, frameCount: 1, deltas: [partial]))
        XCTAssertEqual(copyWSA.decodeAllFrames(base: base)[0], [9, 9, 0x0F, 0x0F, 9, 9, 9, 9])
        let xorWSA = try WSAFile(bytes: makeWSA(width: 4, height: 2, frameCount: 1, deltas: [partial], extraFlags: 2))
        XCTAssertTrue(xorWSA.frame0IsDelta)
        XCTAssertEqual(xorWSA.decodeAllFrames(base: base)[0], [9, 9, 9 ^ 0x0F, 9 ^ 0x0F, 9, 9, 9, 9])
        // Over black (MAPSEL clears SysMemPage first) copy and XOR agree.
        XCTAssertEqual(copyWSA.decodeAllFrames()[0], xorWSA.decodeAllFrames()[0])
    }

    func testWSARejectsTruncated() {
        let file = makeWSA(width: 4, height: 2, frameCount: 2, deltas: [d0, d1, d1])
        XCTAssertThrowsError(try WSAFile(bytes: Array(file.prefix(file.count - 3))))
        XCTAssertThrowsError(try WSAFile(bytes: Array(file.prefix(10))))
    }

    /// 3x2 picture, stride 4: a run crossing the line end, a literal ≥ 0xC0
    /// escaped as a run of 1, and the 8-bit trailing palette shifted to 6 bits.
    func testPCXRunsAndPalette() throws {
        var header = [UInt8](repeating: 0, count: 128)
        header[0] = 10; header[1] = 5; header[2] = 1; header[3] = 8; header[65] = 1
        header.replaceSubrange(8..<12, with: le16(2) + le16(1))   // xmax=2, ymax=1
        header.replaceSubrange(66..<68, with: le16(4))
        // Line 0: 7 7 7 [pad 7]; line 1: 7 7 (run of 6 crosses the line end), 0xC5, 1
        let body: [UInt8] = [0xC6, 7, 0xC1, 0xC5, 1]
        var palette = [UInt8](repeating: 0, count: 768)
        palette[7 * 3] = 255; palette[7 * 3 + 1] = 128; palette[0xC5 * 3 + 2] = 4
        let pcx = try PCXFile(bytes: header + body + [0x0C] + palette)
        XCTAssertEqual(pcx.width, 3)
        XCTAssertEqual(pcx.height, 2)
        XCTAssertEqual(pcx.pixels, [7, 7, 7, 7, 7, 0xC5])
        XCTAssertEqual(Array(pcx.palette!.raw6[21..<24]), [63, 32, 0])
        XCTAssertEqual(pcx.palette!.raw6[0xC5 * 3 + 2], 1)
        XCTAssertThrowsError(try PCXFile(bytes: header + [0xC6]))
    }
}
