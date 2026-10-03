import CoreGraphics
import Foundation
import ImageIO
import OpenConquerAssets
import UniformTypeIdentifiers

// Asset-backed VQA movie diagnostics (OpenConquerAssets/VQAFile.swift).
//
//   --test-vqa NAME [NAME...]       decode every frame + the audio, print
//                                   size/fps/audio info, decode speed and a
//                                   digest; exit 1 if any movie fails
//   --dump-vqa NAME OUTDIR [--raw]  write frame_NNNNN.png + audio.wav (and,
//                                   with --raw, video.rgb24 + audio.s16le for
//                                   byte comparison against ffmpeg)
//   --ffmpeg-ima (either flag)      decode SND2 audio with ffmpeg's rounding
//
// NAME is a MIX entry ("GDI1" or "GDI1.VQA") or a path to a loose .VQA file.

/// Runs the VQA diagnostic named on the command line, if any, and returns its
/// exit code; nil when no VQA flag was given.
func runVQADiagnosticsIfRequested() -> Int32? {
    let args = CommandLine.arguments
    // --ffmpeg-ima: decode SND2 with ffmpeg's IMA rounding, to byte-compare
    // against `ffmpeg -f s16le` (the game's own arithmetic differs by a few LSBs).
    let ima: IMAArithmetic = args.contains("--ffmpeg-ima") ? .multiply : .westwood
    if let i = args.firstIndex(of: "--test-vqa") {
        let names = args[(i + 1)...].prefix { !$0.hasPrefix("--") }
        guard !names.isEmpty else {
            print("usage: --test-vqa NAME [NAME...]")
            return 2
        }
        return names.reduce(Int32(0)) { max($0, testVQA(String($1), ima: ima)) }
    }
    if let i = args.firstIndex(of: "--dump-vqa") {
        guard i + 2 < args.count else {
            print("usage: --dump-vqa NAME OUTDIR [--raw] [--ffmpeg-ima]")
            return 2
        }
        return dumpVQA(args[i + 1], to: URL(fileURLWithPath: args[i + 2]), raw: args.contains("--raw"), ima: ima)
    }
    if let i = args.firstIndex(of: "--test-movie-enhance") {
        guard i + 1 < args.count else {
            print("usage: --test-movie-enhance NAME [OUT.png]")
            return 2
        }
        let out = i + 2 < args.count && !args[i + 2].hasPrefix("--") ? args[i + 2] : nil
        return testMovieEnhance(args[i + 1], snapshot: out)
    }
    return nil
}

/// Run a movie through the Enhanced mode's super-resolution scaler: report
/// per-frame cost (it runs on the render thread, so it must stay well under
/// the 66 ms frame budget) and optionally save frame 45 upscaled.
private func testMovieEnhance(_ name: String, snapshot: String?) -> Int32 {
    guard let (label, data) = loadVQAData(name), let dec = VQADecoder(data: data) else {
        print("FAIL: cannot load \(name)")
        return 1
    }
    guard let enhancer = makeMovieFrameEnhancer(width: dec.width, height: dec.height) else {
        print("SKIP: super-resolution unavailable here (needs macOS 26+)")
        return 0
    }
    var times: [Double] = []
    var outSize = (0, 0)
    while let frame = dec.nextFrame(), frame.index < 150 {
        let t0 = DispatchTime.now().uptimeNanoseconds
        guard let out = enhancer.enhance(frame) else {
            print("FAIL: frame \(frame.index) not enhanced")
            return 1
        }
        times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        outSize = (out.width, out.height)
        if frame.index == 45, let snapshot {
            // BGRA rows → packed RGBA for the PNG writer.
            var rgba = [UInt8](repeating: 255, count: out.width * out.height * 4)
            for y in 0..<out.height {
                for x in 0..<out.width {
                    let s = y * out.bytesPerRow + x * 4, d = (y * out.width + x) * 4
                    rgba[d] = out.pixels[s + 2]; rgba[d + 1] = out.pixels[s + 1]; rgba[d + 2] = out.pixels[s]
                }
            }
            _ = writeRGBAPNG(rgba: rgba, width: out.width, height: out.height, to: URL(fileURLWithPath: snapshot))
        }
    }
    let sorted = times.dropFirst().sorted()  // frame 0 includes session warm-up
    let median = sorted[sorted.count / 2], worst = sorted.last ?? 0
    print(String(format: "%@: %dx%d -> %dx%d, %d frames, warm-up %.1f ms, median %.1f ms, worst %.1f ms",
                 label, dec.width, dec.height, outSize.0, outSize.1, times.count, times[0], median, worst))
    return worst < 66 ? 0 : 1
}

private func loadVQAData(_ name: String) -> (name: String, data: Data)? {
    if name.contains("/"), let data = try? Data(contentsOf: URL(fileURLWithPath: name)) {
        return ((name as NSString).lastPathComponent.uppercased(), data)
    }
    let file = name.uppercased().hasSuffix(".VQA") ? name.uppercased() : name.uppercased() + ".VQA"
    guard let data = assetManager.retrieve(file) else { return nil }
    return (file, data)
}

/// FNV-1a, 64-bit.
private struct Digest {
    var value: UInt64 = 0xCBF2_9CE4_8422_2325
    mutating func add(_ bytes: UnsafeRawBufferPointer) {
        for b in bytes {
            value ^= UInt64(b)
            value = value &* 0x0000_0100_0000_01B3
        }
    }
    var hex: String { String(format: "0x%016llX", value) }
}

private func testVQA(_ name: String, ima: IMAArithmetic) -> Int32 {
    guard let (file, data) = loadVQAData(name) else {
        print("\(name): not found")
        return 1
    }
    guard let decoder = VQADecoder(data: data, imaArithmetic: ima) else {
        print("\(file): not a decodable VQA")
        return 1
    }
    let h = decoder.header
    print("\(file): VQA v\(h.version), \(h.width)x\(h.height), \(h.frameCount) frames @ \(h.frameRate) fps, "
          + "\(h.blockWidth)x\(h.blockHeight) blocks, group \(h.groupSize), \(data.count) bytes")

    var video = Digest()
    var audio = Digest()
    var frameAudio: [Int16] = []
    var frames = 0
    var paletteChanges = 0
    let start = Date()
    while let frame = decoder.nextFrame() {
        frame.pixels.withUnsafeBytes { video.add($0) }
        frame.palette.withUnsafeBytes { video.add($0) }
        frameAudio += frame.audio
        if frame.paletteChanged { paletteChanges += 1 }
        frames += 1
    }
    let videoSeconds = Date().timeIntervalSince(start)
    let audioStart = Date()
    let track = VQADecoder.decodeAudioTrack(data: data, imaArithmetic: ima)
    let audioSeconds = Date().timeIntervalSince(audioStart)
    frameAudio.withUnsafeBytes { audio.add($0) }

    var failed = frames != h.frameCount
    print("  frames decoded: \(frames)/\(h.frameCount), palette changes: \(paletteChanges), "
          + String(format: "%.1f frames/s (%.3f s)", Double(frames) / max(videoSeconds, 1e-9), videoSeconds))
    if let track {
        let consistent = track.samples == frameAudio
        if !consistent { failed = true }
        print("  audio: \(track.sampleRate) Hz, \(track.channels) ch, \(track.sampleFrames) sample frames "
              + String(format: "(%.2f s; video %.2f s), track decode %.3f s, per-frame slices %@",
                       track.duration, Double(h.frameCount) / Double(h.frameRate), audioSeconds,
                       consistent ? "match" : "MISMATCH"))
    } else {
        print("  audio: none")
    }
    let s = decoder.stats
    print("  stats: fill blocks \(s.fillBlocks), stale codebook refs \(s.staleCodebookRefs), "
          + "relative-LCW streams \(s.relativeLCWStreams), skipped \(s.skippedChunks)")
    print("  video digest \(video.hex)  audio digest \(audio.hex)")
    print(failed ? "  FAIL" : "  OK")
    return failed ? 1 : 0
}

private func dumpVQA(_ name: String, to dir: URL, raw: Bool, ima: IMAArithmetic) -> Int32 {
    guard let (file, data) = loadVQAData(name), let decoder = VQADecoder(data: data, imaArithmetic: ima) else {
        print("\(name): not found or not a decodable VQA")
        return 1
    }
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        print("can't create \(dir.path): \(error)")
        return 1
    }
    var rgbStream = raw ? Data() : nil
    var samples: [Int16] = []
    var written = 0
    while let frame = decoder.nextFrame() {
        let url = dir.appendingPathComponent(String(format: "frame_%05d.png", frame.index))
        guard writeRGBAPNG(rgba: frame.rgba(), width: frame.width, height: frame.height, to: url) else {
            print("failed writing \(url.path)")
            return 1
        }
        rgbStream?.append(contentsOf: frame.rgb24())
        samples += frame.audio
        written += 1
    }
    if decoder.hasAudio {
        writeWAV(samples, sampleRate: decoder.audioSampleRate, channels: decoder.audioChannels,
                 to: dir.appendingPathComponent("audio.wav"))
    }
    if let rgbStream {
        try? rgbStream.write(to: dir.appendingPathComponent("video.rgb24"))
        samples.withUnsafeBytes { try? Data($0).write(to: dir.appendingPathComponent("audio.s16le")) }
    }
    print("\(file): wrote \(written) frames (\(decoder.width)x\(decoder.height) @ \(decoder.frameRate) fps)"
          + (decoder.hasAudio ? " + audio.wav (\(decoder.audioSampleRate) Hz, \(decoder.audioChannels) ch)" : "")
          + " to \(dir.path)")
    return 0
}


private func writeWAV(_ samples: [Int16], sampleRate: Int, channels: Int, to url: URL) {
    var d = Data()
    func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
    let dataBytes = samples.count * 2
    d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
    d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16)
    u16(1); u16(channels); u32(sampleRate); u32(sampleRate * channels * 2); u16(channels * 2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
    samples.withUnsafeBytes { d.append(contentsOf: $0) }
    try? d.write(to: url)
}
