import XCTest
import OpenConquerAssets

// Synthetic (asset-free) coverage for the VQA movie decoder and the stateful
// IMA ADPCM stream it uses. Every movie here is built in memory.

/// An IFF chunk: 4-char id, big-endian size, payload, pad byte to even size.
private func chunk(_ id: String, _ payload: [UInt8]) -> [UInt8] {
    let n = payload.count
    var out = Array(id.utf8)
    out += [UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
    out += payload
    if n & 1 != 0 { out.append(0) }
    return out
}

/// LCW stream made only of literal runs (0x80|n, n <= 63) + the 0x80 end mark.
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

/// FORM/WVQA container around the given top-level chunks.
private func vqaFile(_ header: VQAHeader, _ body: [[UInt8]]) -> Data {
    var inner = Array("WVQA".utf8) + chunk("VQHD", header.encoded())
    inner += chunk("FINF", [UInt8](repeating: 0, count: 4 * header.frameCount))
    for c in body { inner += c }
    return Data(chunk("FORM", inner))
}

/// Palette whose 6-bit entry i is (i & 63, 63 - (i & 63), 7).
private func testPalette() -> [UInt8] {
    (0..<256).flatMap { i -> [UInt8] in [UInt8(i & 63), UInt8(63 - (i & 63)), 7] }
}

private func scale6(_ v: UInt8) -> UInt8 { (v << 2) | (v >> 4) }

final class VQATests: XCTestCase {
    // 8x4 image of 4x2 blocks: 2 blocks per row, 2 block rows.
    private let header = VQAHeader(flags: 0, frameCount: 1, width: 8, height: 4, groupSize: 2,
                                   codebookEntries: 3)

    /// Three 4x2 codebook entries; entry e's pixel (x, y) = 10*(e+1) + 4*y + x.
    private func codebook() -> [UInt8] {
        (0..<3).flatMap { e in (0..<8).map { UInt8(10 * (e + 1) + $0) } }
    }

    func testSingleFrameRawChunks() throws {
        // Blocks (row-major): entry 0, entry 2, solid colour 7 (hi 0x0F), entry 1.
        let lo: [UInt8] = [0, 2, 7, 1]
        let hi: [UInt8] = [0, 0, 0x0F, 0]
        let frame = chunk("CBF0", codebook()) + chunk("CPL0", testPalette()) + chunk("VPT0", lo + hi)
        let data = vqaFile(header, [chunk("VQFR", frame)])

        let dec = try XCTUnwrap(VQADecoder(data: data))
        XCTAssertEqual(dec.width, 8)
        XCTAssertEqual(dec.height, 4)
        XCTAssertEqual(dec.frameRate, 15)
        XCTAssertEqual(dec.frameCount, 1)
        let f = try XCTUnwrap(dec.nextFrame())
        XCTAssertNil(dec.nextFrame())

        let expected: [UInt8] = [
            10, 11, 12, 13, 30, 31, 32, 33,
            14, 15, 16, 17, 34, 35, 36, 37,
            7, 7, 7, 7, 20, 21, 22, 23,
            7, 7, 7, 7, 24, 25, 26, 27,
        ]
        XCTAssertEqual(f.pixels, expected)
        XCTAssertTrue(f.paletteChanged)
        XCTAssertEqual(f.palette.count, 768)
        // 6-bit -> 8-bit like loadPalette: (v << 2) | (v >> 4).
        XCTAssertEqual(Array(f.palette[0..<3]), [0, 255, 28])
        XCTAssertEqual(Array(f.palette[63 * 3..<63 * 3 + 3]), [255, 0, 28])
        let rgba = f.rgba()
        XCTAssertEqual(rgba.count, 8 * 4 * 4)
        XCTAssertEqual(Array(rgba[0..<4]), [scale6(10), scale6(53), scale6(7), 255])
        XCTAssertEqual(f.rgb24().count, 8 * 4 * 3)
    }

    func testCompressedChunksAndPartialCodebookTiming() throws {
        // Frame 0: CBFZ (entries 0..2), CPLZ, VPTZ -> all blocks entry 1.
        // Frames 1-2: one CBP0 piece each (groupSize 2) of a new codebook whose
        // entry 1 is all 99s. Westwood timing: the group completes while frame
        // 2 loads, so frame 2 still draws the old codebook and frame 3 the new.
        var h = header
        h.frameCount = 4
        let allEntry1 = [UInt8](repeating: 1, count: 4) + [UInt8](repeating: 0, count: 4)
        let newCB = [UInt8](repeating: 50, count: 8) + [UInt8](repeating: 99, count: 8)
        let f0 = chunk("CBFZ", lcwLiteral(codebook())) + chunk("CPLZ", lcwLiteral(testPalette()))
            + chunk("VPTZ", lcwLiteral(allEntry1))
        let f1 = chunk("CBP0", Array(newCB[0..<8])) + chunk("VPT0", allEntry1)
        let f2 = chunk("CBP0", Array(newCB[8..<16])) + chunk("VPT0", allEntry1)
        let f3 = chunk("VPT0", allEntry1)
        let data = vqaFile(h, [f0, f1, f2, f3].map { chunk("VQFR", $0) })

        let dec = try XCTUnwrap(VQADecoder(data: data))
        let frames = (0..<4).compactMap { _ in dec.nextFrame() }
        XCTAssertEqual(frames.count, 4)
        // Two block columns: each pixel row is entry-1 row 0 / row 1 twice.
        let oldRows: [UInt8] = [20, 21, 22, 23, 20, 21, 22, 23, 24, 25, 26, 27, 24, 25, 26, 27]
        XCTAssertEqual(frames[0].pixels, oldRows + oldRows)
        XCTAssertEqual(frames[1].pixels, frames[0].pixels)
        XCTAssertEqual(frames[2].pixels, frames[0].pixels, "codebook completed in frame 2 must not apply to it")
        XCTAssertEqual(frames[3].pixels, [UInt8](repeating: 99, count: 32))
        XCTAssertTrue(frames[0].paletteChanged)
        XCTAssertFalse(frames[3].paletteChanged)
        XCTAssertEqual(frames[3].palette, frames[0].palette, "palette persists")
        XCTAssertEqual(frames[3].presentationTime, 3.0 / 15.0, accuracy: 1e-9)
    }

    func testRelativeLCW() {
        // 0x00 flag is stripped by the caller; 0xC1 = medium copy of 4 bytes
        // from 3 back (relative), vs absolute offset 3 in the plain variant.
        let stream: [UInt8] = [0x83, 1, 2, 3, 0xC1, 3, 0, 0x80]
        var out = [UInt8](repeating: 0, count: 7)
        let n = stream.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { WestwoodCodec.lcwDecompress(src, into: $0, relative: true) }
        }
        XCTAssertEqual(n, 7)
        XCTAssertEqual(out, [1, 2, 3, 1, 2, 3, 1])
        // The array API is unchanged by the pointer core.
        XCTAssertEqual(WestwoodCodec.lcwDecompress([0x83, 1, 2, 3, 0x80], outputSize: 4), [1, 2, 3, 0])
    }

    func testIMAStateCarriesAcrossChunks() {
        let bytes: [UInt8] = (0..<64).map { UInt8(($0 * 37 + 11) & 0xFF) }
        var whole: [IMAADPCMChannelState] = []
        let one = bytes.withUnsafeBytes { decodeWestwoodIMAChunk($0, channels: 1, states: &whole) }

        var split: [IMAADPCMChannelState] = []
        let a = bytes[0..<20].withUnsafeBytes { decodeWestwoodIMAChunk($0, channels: 1, states: &split) }
        let b = bytes[20...].withUnsafeBytes { decodeWestwoodIMAChunk($0, channels: 1, states: &split) }
        XCTAssertEqual(one.count, 128)
        XCTAssertEqual(a + b, one)
        XCTAssertEqual(split, whole)

        // Restarting the state per chunk (the AUD-style mistake) diverges.
        var fresh: [IMAADPCMChannelState] = []
        let b2 = bytes[20...].withUnsafeBytes { decodeWestwoodIMAChunk($0, channels: 1, states: &fresh) }
        XCTAssertNotEqual(b2, b)

        // Hand-checked first nibbles from predictor 0 / index 0 (step 7):
        // byte 0x0B: low nibble 0xB = -(0 + 3 + 1) = -4 (index -> 0 after -1 clamp),
        // high nibble 0x0 = +0 (step 7 >> 3).
        XCTAssertEqual(Array(one[0..<2]), [-4, -4])
    }

    func testIMAStereoLayoutAndArithmetic() {
        // Stereo: bytes interleave L,R; each byte is two samples of its channel.
        let bytes: [UInt8] = [0x77, 0x00, 0x77, 0x00]
        var st: [IMAADPCMChannelState] = []
        let out = bytes.withUnsafeBytes { decodeWestwoodIMAChunk($0, channels: 2, states: &st) }
        XCTAssertEqual(out.count, 8)
        let left = stride(from: 0, to: 8, by: 2).map { out[$0] }
        let right = stride(from: 1, to: 8, by: 2).map { out[$0] }
        XCTAssertTrue(left.allSatisfy { $0 > 0 }, "left channel climbs on nibble 7")
        XCTAssertEqual(right, [0, 0, 0, 0], "right channel stays at 0 on nibble 0 with step 7")

        // Westwood (bit-by-bit) vs ffmpeg (multiply) rounding: at step 7,
        // nibble 7 is 0 + 7 + 3 + 1 = 11 vs (15 * 7) >> 3 = 13.
        var w = IMAADPCMChannelState()
        var m = IMAADPCMChannelState()
        XCTAssertEqual(w.expand(7), 11)
        XCTAssertEqual(m.expand(7, arithmetic: .multiply), 13)
        XCTAssertEqual(w.stepIndex, 8)
        XCTAssertEqual(m.stepIndex, 8)
        // At step 130 they agree: 16 + 130 + 65 + 32 = 243 = (15 * 130) >> 3.
        var w2 = IMAADPCMChannelState(predictor: 0, stepIndex: 30)
        var m2 = w2
        XCTAssertEqual(w2.expand(7), 243)
        XCTAssertEqual(m2.expand(7, arithmetic: .multiply), 243)
    }

    func testAudioChunksAndTrack() throws {
        var h = header
        h.flags = 1
        h.frameCount = 2
        h.sampleRate = 22050
        h.channels = 1
        h.bitsPerSample = 16
        let snd = (0..<10).map { UInt8($0 * 23 & 0xFF) }
        let pal = chunk("CPL0", testPalette())
        let frame = chunk("VQFR", chunk("CBF0", codebook()) + pal + chunk("VPT0", [UInt8](repeating: 0, count: 8)))
        let frame2 = chunk("VQFR", chunk("VPT0", [UInt8](repeating: 0, count: 8)))
        // Pre-roll SND2, frame 0, SND2 (odd size -> padded), frame 1, trailing SND2.
        let data = vqaFile(h, [chunk("SND2", snd), frame, chunk("SND2", Array(snd[0..<5])), frame2,
                               chunk("SND2", Array(snd[5...]))])
        let dec = try XCTUnwrap(VQADecoder(data: data))
        XCTAssertTrue(dec.hasAudio)
        XCTAssertEqual(dec.audioSampleRate, 22050)
        XCTAssertEqual(dec.audioChannels, 1)
        let f0 = try XCTUnwrap(dec.nextFrame())
        let f1 = try XCTUnwrap(dec.nextFrame())
        XCTAssertNil(dec.nextFrame())
        XCTAssertEqual(f0.audio.count, 20)
        XCTAssertEqual(f1.audio.count, 10 + 10, "frame 1 gets its chunk plus the trailing one")
        let track = try XCTUnwrap(VQADecoder.decodeAudioTrack(data: data))
        XCTAssertEqual(track.samples, f0.audio + f1.audio)
        XCTAssertEqual(track.sampleFrames, 40)

        // Rewinding reproduces the same output.
        dec.reset()
        XCTAssertEqual(dec.nextFrame()?.audio, f0.audio)

        // SND0 (raw 16-bit) and SND1 (stored raw when OutSize == Size).
        let raw16: [UInt8] = [0x34, 0x12, 0xFE, 0xFF]
        let snd1: [UInt8] = [2, 0, 2, 0, 0x80, 0xFF]
        let d2 = vqaFile(h, [chunk("SND0", raw16), frame, chunk("SND1", snd1), frame2])
        let dec2 = try XCTUnwrap(VQADecoder(data: d2))
        XCTAssertEqual(dec2.nextFrame()?.audio, [0x1234, -2])
        XCTAssertEqual(dec2.nextFrame()?.audio, [0, 127 * 256])
    }

    func testRejectsNonVQA() {
        XCTAssertNil(VQADecoder(data: Data([1, 2, 3])))
        XCTAssertNil(VQADecoder(data: Data(chunk("FORM", Array("WSA ".utf8)))))
        var h = header
        h.blockWidth = 3
        XCTAssertNil(VQADecoder(data: vqaFile(h, [])))
        var v1 = header
        v1.version = 1  // Lands of Lore pointer format: not supported
        XCTAssertNil(VQADecoder(data: vqaFile(v1, [])))
        XCTAssertNotNil(VQADecoder(data: vqaFile(header, [])))
    }
}
