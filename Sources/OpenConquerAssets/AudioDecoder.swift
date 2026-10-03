import Foundation

// MARK: - Westwood AUD Format Decoder

/// AUD file header (12 bytes, packed)
/// Matches Vanilla Conquer AUDHeaderType from audio.h:
///   uint16_t Rate, int32_t Size, int32_t UncompSize, uint8_t Flags, uint8_t Compression
package struct AUDHeader {
    package let sampleRate: UInt16     // offset 0
    package let compressedSize: Int32  // offset 2
    package let uncompressedSize: Int32 // offset 6
    package let flags: UInt8           // offset 10 — bit 0 = stereo, bit 1 = 16-bit
    package let compression: UInt8     // offset 11 — 0=none, 1=WW ADPCM, 99=IMA ADPCM
}

/// AUD chunk header (8 bytes)
package struct AUDChunkHeader {
    package let compressedSize: UInt16
    package let uncompressedSize: UInt16
    package let id: UInt32  // Should be 0x0000DEAF
}

/// Decode a Westwood AUD file to raw PCM samples
/// Returns (samples: [Int16], sampleRate: Int) or nil if not a valid AUD
package func decodeAUD(_ data: Data) -> (samples: [Int16], sampleRate: Int)? {
    // AUD header is 12 bytes (packed struct)
    guard data.count >= 12 else { return nil }

    // Parse 12-byte header matching VC's AUDHeaderType
    let sampleRate = UInt16(data[0]) | (UInt16(data[1]) << 8)
    // let compressedSize = Int32 at offset 2-5 (not needed for decoding)
    // let uncompressedSize = Int32 at offset 6-9 (not needed for decoding)
    let flags = data[10]
    let compression = data[11]
    let is16Bit = (flags & 2) != 0

    guard sampleRate > 0 && sampleRate <= 44100 else { return nil }

    let headerSize = 12  // sizeof(AUDHeaderType)

    // For uncompressed or unknown compression, try raw playback
    if compression == 0 {
        var samples = [Int16]()
        if is16Bit {
            // 16-bit signed PCM
            var i = headerSize
            while i + 1 < data.count {
                let sample = Int16(bitPattern: UInt16(data[i]) | (UInt16(data[i + 1]) << 8))
                samples.append(sample)
                i += 2
            }
        } else {
            // 8-bit unsigned PCM → convert to signed 16-bit
            for i in headerSize..<data.count {
                let sample = Int16(data[i]) - 128
                samples.append(sample * 256)
            }
        }
        if samples.isEmpty { return nil }
        return (samples, Int(sampleRate))
    }

    // Westwood ADPCM (compression == 1) — chunk-based decode
    if compression == 1 {
        var samples = [Int16]()
        var offset = headerSize

        while offset + 8 <= data.count {
            // Read chunk header (8 bytes)
            let compSize = Int(UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            let uncompSize = Int(UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8))
            let chunkId = UInt32(data[offset + 4]) | (UInt32(data[offset + 5]) << 8) |
                          (UInt32(data[offset + 6]) << 16) | (UInt32(data[offset + 7]) << 24)
            offset += 8

            guard chunkId == 0x0000DEAF else { break }
            guard offset + compSize <= data.count else { break }

            // Decode WW ADPCM chunk
            let chunkData = data.subdata(in: offset..<(offset + compSize))
            let decoded = decodeWWADPCM(chunkData, uncompressedSize: uncompSize)
            samples.append(contentsOf: decoded)
            offset += compSize
        }

        if samples.isEmpty { return nil }
        return (samples, Int(sampleRate))
    }

    // IMA ADPCM (compression == 99) — chunk-based decode
    if compression == 99 {
        var samples = [Int16]()
        var offset = headerSize

        while offset + 8 <= data.count {
            let compSize = Int(UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            let uncompSize = Int(UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8))
            let chunkId = UInt32(data[offset + 4]) | (UInt32(data[offset + 5]) << 8) |
                          (UInt32(data[offset + 6]) << 16) | (UInt32(data[offset + 7]) << 24)
            offset += 8

            guard chunkId == 0x0000DEAF else { break }
            guard offset + compSize <= data.count else { break }

            let chunkData = data.subdata(in: offset..<(offset + compSize))
            let decoded = decodeIMAADPCM(chunkData, sampleCount: uncompSize)
            samples.append(contentsOf: decoded)
            offset += compSize
        }

        if samples.isEmpty { return nil }
        return (samples, Int(sampleRate))
    }

    return nil
}

// MARK: - WW ADPCM Decoder

/// Westwood's custom ADPCM decompression — faithful port of Audio_Unzap() from auduncmp.cpp.
/// Supports 2-bit, 4-bit, raw, and silence modes encoded per-block.
package func decodeWWADPCM(_ data: Data, uncompressedSize: Int) -> [Int16] {
    let zapTabTwo: [Int] = [-2, -1, 0, 1]
    let zapTabFour: [Int] = [-9, -8, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 8]

    // Output is 8-bit unsigned PCM, we convert to Int16 at the end
    var output = [UInt8]()
    output.reserveCapacity(uncompressedSize)

    var sample: Int = 0x80  // Start at midpoint (unsigned 8-bit)
    var srcIdx = 0

    while output.count < uncompressedSize && srcIdx < data.count {
        // Read block header byte
        let headerByte = data[srcIdx]
        srcIdx += 1

        // Extract code (top 2 bits) and count (bottom 6 bits)
        let shifted = UInt16(headerByte) << 2
        let code = Int((shifted & 0xFF00) >> 8)   // top 2 bits of original byte
        let count = Int((shifted & 0x00FF) >> 2)  // bottom 6 bits of original byte

        switch code {
        case 0:
            // 2-bit ADPCM: 1 source byte → 4 output bytes
            for _ in 0...count {
                guard srcIdx < data.count else { break }
                let byte = data[srcIdx]; srcIdx += 1
                // 4 samples from 2-bit pairs
                sample += zapTabTwo[Int(byte & 0x03)]
                sample = max(0, min(255, sample))
                output.append(UInt8(sample))
                sample += zapTabTwo[Int((byte >> 2) & 0x03)]
                sample = max(0, min(255, sample))
                output.append(UInt8(sample))
                sample += zapTabTwo[Int((byte >> 4) & 0x03)]
                sample = max(0, min(255, sample))
                output.append(UInt8(sample))
                sample += zapTabTwo[Int((byte >> 6) & 0x03)]
                sample = max(0, min(255, sample))
                output.append(UInt8(sample))
            }

        case 1:
            // 4-bit ADPCM: 1 source byte → 2 output bytes
            for _ in 0...count {
                guard srcIdx < data.count else { break }
                let byte = data[srcIdx]; srcIdx += 1
                // Lower nibble
                sample += zapTabFour[Int(byte & 0x0F)]
                sample = max(0, min(255, sample))
                output.append(UInt8(sample))
                // Upper nibble
                sample += zapTabFour[Int(byte >> 4)]
                sample = max(0, min(255, sample))
                output.append(UInt8(sample))
            }

        case 2:
            // Raw / delta
            if (count & 0x20) != 0 {
                // Faithful VC: count <<= 3; sample += count >> 3;
                // count is signed char — the << 3 truncates to 8 bits, >> 3 is arithmetic
                let shifted = UInt8(truncatingIfNeeded: count << 3)  // truncate to 8-bit
                let signedShifted = Int8(bitPattern: shifted)  // reinterpret as signed
                let delta = Int(signedShifted) >> 3  // arithmetic shift right 3
                sample += delta
                sample = max(0, min(255, sample))
                output.append(UInt8(sample))
            } else {
                // Raw bytes: copy count+1 bytes directly
                for _ in 0...count {
                    guard srcIdx < data.count else { break }
                    let byte = data[srcIdx]; srcIdx += 1
                    output.append(byte)
                }
                // Update sample to last output byte
                if let last = output.last {
                    sample = Int(last)
                }
            }

        default:
            // Silence/repeat: fill count+1 bytes with current sample
            let fillByte = UInt8(max(0, min(255, sample)))
            for _ in 0...count {
                output.append(fillByte)
            }
        }
    }

    // Convert unsigned 8-bit PCM to signed 16-bit
    return output.map { Int16(Int($0) - 128) * 256 }
}

// MARK: - IMA ADPCM Decoder

package let imaIndexTable: [Int] = [
    -1, -1, -1, -1, 2, 4, 6, 8,
    -1, -1, -1, -1, 2, 4, 6, 8
]

package let imaStepTable: [Int] = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
    19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
    50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
    130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
    337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
    876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
    5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
]

package func decodeIMAADPCM(_ data: Data, sampleCount: Int) -> [Int16] {
    var samples = [Int16]()
    samples.reserveCapacity(sampleCount)

    // Each IMA ADPCM chunk starts with a 4-byte header:
    //   Int16: initial predictor value
    //   Int16: initial step index (only low byte used)
    // Matches Vanilla Conquer soscomp.cpp sosCODECDecompressData
    guard data.count >= 4 else { return samples }

    let initPredictor = Int16(bitPattern: UInt16(data[0]) | (UInt16(data[1]) << 8))
    let initIndex = Int(UInt16(data[2]) | (UInt16(data[3]) << 8))

    var predictor: Int32 = Int32(initPredictor)
    var stepIndex: Int = max(0, min(88, initIndex))
    var index = 4  // Skip past chunk header

    // First sample is the predictor itself
    samples.append(initPredictor)

    while index < data.count && samples.count < sampleCount {
        let byte = data[index]
        index += 1

        // Process low nibble, then high nibble
        for shift in [0, 4] {
            let nibble = Int((byte >> shift) & 0x0F)
            let step = imaStepTable[stepIndex]

            var diff = step >> 3
            if nibble & 1 != 0 { diff += step >> 2 }
            if nibble & 2 != 0 { diff += step >> 1 }
            if nibble & 4 != 0 { diff += step }
            if nibble & 8 != 0 { diff = -diff }

            predictor += Int32(diff)
            predictor = max(-32768, min(32767, predictor))
            samples.append(Int16(predictor))

            stepIndex += imaIndexTable[nibble]
            stepIndex = max(0, min(88, stepIndex))

            if samples.count >= sampleCount { break }
        }
    }

    return samples
}

// MARK: - Westwood IMA ADPCM stream (VQA SND2)

/// Per-channel IMA ADPCM decoder state that persists across chunks.
///
/// VQA SND2 audio is one continuous IMA stream chopped into per-frame chunks:
/// unlike the AUD chunks `decodeIMAADPCM` handles, an SND2 chunk carries no
/// predictor/index header, so the predictor and step index must carry over
/// from the previous chunk (Vanilla-Conquer common/soscodec.cpp keeps them in
/// `_SOS_COMPRESS_INFO.Channels[]`, initialised once per movie by
/// sosCODECInitStream: predictor 0, index 0).
package struct IMAADPCMChannelState: Equatable {
    package var predictor: Int32
    package var stepIndex: Int

    package init(predictor: Int32 = 0, stepIndex: Int = 0) {
        self.predictor = predictor
        self.stepIndex = stepIndex
    }

    /// Expand one 4-bit code. `.westwood` sums the diff bit by bit
    /// (step>>3 + step>>2 + step>>1 + step) — the reference IMA arithmetic the
    /// game's SOS codec uses (sosCODECGenerateDecompressTable, soscodec.cpp).
    /// `.multiply` is ffmpeg's shortcut `((2*(n&7)+1)*step) >> 3`
    /// (adpcm_ima_expand_nibble), which rounds differently by a few LSBs per
    /// step and so drifts by up to a few hundred over a movie.
    @inline(__always)
    package mutating func expand(_ nibble: Int, arithmetic: IMAArithmetic = .westwood) -> Int16 {
        let step = imaStepTable[stepIndex]
        var diff: Int
        if arithmetic == .westwood {
            diff = step >> 3
            if nibble & 4 != 0 { diff += step }
            if nibble & 2 != 0 { diff += step >> 1 }
            if nibble & 1 != 0 { diff += step >> 2 }
        } else {
            diff = ((2 * (nibble & 7) + 1) * step) >> 3
        }
        if nibble & 8 != 0 { diff = -diff }
        predictor = max(-32768, min(32767, predictor + Int32(diff)))
        stepIndex = max(0, min(88, stepIndex + imaIndexTable[nibble]))
        return Int16(predictor)
    }
}

/// How an IMA nibble becomes a predictor delta (see `IMAADPCMChannelState.expand`).
package enum IMAArithmetic {
    /// Bit-by-bit sum, as the original game decodes. The default.
    case westwood
    /// ffmpeg's multiply form; only for byte-comparing against ffmpeg output.
    case multiply
}

/// Decode one headerless Westwood IMA ADPCM chunk (VQA SND2), continuing from
/// `states` (one entry per channel, updated in place), and return interleaved
/// 16-bit samples.
///
/// Layout (sosCODECDecompressDataTemplate, soscodec.cpp): mono is one byte per
/// two samples, low nibble first. Stereo interleaves *bytes* L,R,L,R; each
/// byte holds two consecutive samples of its channel (low nibble first).
package func decodeWestwoodIMAChunk(
    _ bytes: UnsafeRawBufferPointer,
    channels: Int,
    states: inout [IMAADPCMChannelState],
    arithmetic: IMAArithmetic = .westwood
) -> [Int16] {
    let ch = max(1, channels)
    while states.count < ch { states.append(IMAADPCMChannelState()) }
    let bytesPerChannel = bytes.count / ch
    var out = [Int16](repeating: 0, count: bytesPerChannel * 2 * ch)
    out.withUnsafeMutableBufferPointer { dst in
        for c in 0..<ch {
            var state = states[c]
            var si = c
            var di = c
            for _ in 0..<bytesPerChannel {
                let b = Int(bytes[si])
                si += ch
                dst[di] = state.expand(b & 0x0F, arithmetic: arithmetic)
                di += ch
                dst[di] = state.expand(b >> 4, arithmetic: arithmetic)
                di += ch
            }
            states[c] = state
        }
    }
    return out
}
