import Foundation

// MARK: - Remastered WAV decode (MS ADPCM / PCM) + 16-bit PCM WAV writer
//
// Port of `decode_ms_adpcm_wav`, `stereo_to_mono` and `write_pcm_wav` from
// tools/extract_remastered_audio.py, kept sample-for-sample identical
// (including its quirks: Python's floor division in the downmix, `>> 8` on
// negative products, and the preamble layout for >2 channels).

private let msADPCMAdaptation = [230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230]
private let msADPCMDefaultCoefs: [(Int, Int)] = [(256, 0), (512, -256), (0, 0), (192, 64), (240, 0), (460, -208), (392, -232)]

package struct DecodedWAV {
    package var samples: [Int16]  // interleaved
    package let sampleRate: Int
    package var channels: Int
}

/// Decode a RIFF WAV holding MS ADPCM (format 2) or 16-bit PCM (format 1).
package func decodeRemasteredWAV(_ data: [UInt8]) -> DecodedWAV? {
    guard data.count >= 12,
          data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46,
          data[8] == 0x57, data[9] == 0x41, data[10] == 0x56, data[11] == 0x45 else { return nil }
    func u16(_ d: ArraySlice<UInt8>, _ o: Int) -> Int { Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
    func s16(_ d: ArraySlice<UInt8>, _ o: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(d, o)))) }
    func u32(_ d: ArraySlice<UInt8>, _ o: Int) -> Int { u16(d, o) | u16(d, o + 2) << 16 }

    var pos = 12
    var fmt: ArraySlice<UInt8>?
    var audio: ArraySlice<UInt8>?
    let all = data[...]
    while pos + 8 <= data.count {
        let size = u32(all, pos + 4)
        let body = data[min(data.count, pos + 8)..<min(data.count, pos + 8 + size)]
        if data[pos] == 0x66, data[pos + 1] == 0x6D, data[pos + 2] == 0x74, data[pos + 3] == 0x20 { fmt = body }
        if data[pos] == 0x64, data[pos + 1] == 0x61, data[pos + 2] == 0x74, data[pos + 3] == 0x61 { audio = body }
        pos += 8 + size
        if pos % 2 != 0 { pos += 1 }
    }
    guard let fmt, let audio, fmt.count >= 16 else { return nil }

    let format = u16(fmt, 0)
    let channels = u16(fmt, 2)
    let sampleRate = u32(fmt, 4)
    if format == 1 {
        guard u16(fmt, 14) == 16 else { return nil }
        var samples = [Int16]()
        samples.reserveCapacity(audio.count / 2)
        var i = 0
        while i + 1 < audio.count { samples.append(Int16(s16(audio, i))); i += 2 }
        return DecodedWAV(samples: samples, sampleRate: sampleRate, channels: channels)
    }
    guard format == 2, fmt.count >= 22, channels > 0 else { return nil }

    let blockAlign = u16(fmt, 12)
    let samplesPerBlock = u16(fmt, 18)
    let numCoefs = u16(fmt, 20)
    var coefs: [(Int, Int)] = []
    var co = 22
    for i in 0..<numCoefs {
        if co + 4 <= fmt.count {
            coefs.append((s16(fmt, co), s16(fmt, co + 2)))
            co += 4
        } else {
            coefs.append(i < msADPCMDefaultCoefs.count ? msADPCMDefaultCoefs[i] : (0, 0))
        }
    }
    while coefs.count < 7 { coefs.append(msADPCMDefaultCoefs[coefs.count]) }
    guard blockAlign > 0, blockAlign >= 7 * channels else { return nil }

    var out = [Int16]()
    let blocks = audio.count / blockAlign
    out.reserveCapacity(blocks * samplesPerBlock * channels)
    var predictor = [Int](repeating: 0, count: channels)
    var delta = [Int](repeating: 0, count: channels)
    var s1 = [Int](repeating: 0, count: channels)
    var s2 = [Int](repeating: 0, count: channels)
    audio.withUnsafeBufferPointer { buf in
        let base = buf.baseAddress!
        func rs16(_ o: Int) -> Int { Int(Int16(bitPattern: UInt16(base[o]) | UInt16(base[o + 1]) << 8)) }
        for blk in 0..<blocks {
            let start = blk * blockAlign
            var p = start
            for ch in 0..<channels {
                let idx = Int(base[p]); p += 1
                predictor[ch] = idx < coefs.count ? idx : 0
            }
            for ch in 0..<channels { delta[ch] = rs16(p); p += 2 }
            for ch in 0..<channels { s1[ch] = rs16(p); p += 2 }
            for ch in 0..<channels { s2[ch] = rs16(p); p += 2 }
            if channels == 1 {
                out.append(Int16(s2[0])); out.append(Int16(s1[0]))
            } else {
                out.append(Int16(s2[0])); out.append(Int16(s2[1]))
                out.append(Int16(s1[0])); out.append(Int16(s1[1]))
            }
            let total = samplesPerBlock * channels
            var count = 2 * channels
            let end = start + blockAlign
            while p < end && count < total {
                let byte = Int(base[p]); p += 1
                for shift in [4, 0] {
                    if count >= total { break }
                    var nibble = (byte >> shift) & 0x0F
                    if nibble >= 8 { nibble -= 16 }
                    let ch = count % channels
                    let (c1, c2) = coefs[predictor[ch]]
                    let predicted = (s1[ch] * c1 + s2[ch] * c2) >> 8
                    let sample = max(-32768, min(32767, predicted + nibble * delta[ch]))
                    out.append(Int16(sample))
                    s2[ch] = s1[ch]
                    s1[ch] = sample
                    delta[ch] = max(16, (delta[ch] * msADPCMAdaptation[nibble & 0x0F]) >> 8)
                    count += 1
                }
            }
        }
    }
    return DecodedWAV(samples: out, sampleRate: sampleRate, channels: channels)
}

/// Average interleaved frames to mono with Python's floor division.
package func downmixToMono(_ samples: [Int16], channels: Int) -> [Int16] {
    guard channels > 1 else { return samples }
    var mono = [Int16]()
    mono.reserveCapacity(samples.count / channels)
    var i = 0
    while i + channels <= samples.count {
        var sum = 0
        for c in 0..<channels { sum += Int(samples[i + c]) }
        let q = sum >= 0 ? sum / channels : -((-sum + channels - 1) / channels)
        mono.append(Int16(max(-32768, min(32767, q))))
        i += channels
    }
    return mono
}

/// Standard 44-byte-header 16-bit PCM WAV (`write_pcm_wav`).
package func encodePCMWAV(samples: [Int16], sampleRate: Int, channels: Int) -> Data {
    let dataSize = samples.count * 2
    var d = Data(capacity: 44 + dataSize)
    func le32(_ v: Int) { withUnsafeBytes(of: UInt32(truncatingIfNeeded: v).littleEndian) { d.append(contentsOf: $0) } }
    func le16(_ v: Int) { withUnsafeBytes(of: UInt16(truncatingIfNeeded: v).littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); le32(36 + dataSize)
    d.append(contentsOf: Array("WAVEfmt ".utf8)); le32(16)
    le16(1); le16(channels); le32(sampleRate); le32(sampleRate * channels * 2); le16(channels * 2); le16(16)
    d.append(contentsOf: Array("data".utf8)); le32(dataSize)
    samples.withUnsafeBytes { d.append(contentsOf: $0) }  // little-endian host = WAV byte order
    return d
}
