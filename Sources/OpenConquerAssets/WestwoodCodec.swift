import Foundation

// MARK: - Westwood codecs shared by SHP, CPS and WSA
//
// LCW ("format80", LCW_Uncompress in lcw.cpp) and the XOR delta
// ("format40", Apply_XOR_Delta in xordelta.cpp). Moved verbatim out of
// SHPFile.swift so the CPS/WSA decoders reuse the exact same code paths.

package enum WestwoodCodec {

    // MARK: LCW (Format 80)

    /// Decompresses an absolute-offset LCW stream into a buffer of exactly
    /// `outputSize` bytes (zero-padded if the stream ends early).
    package static func lcwDecompress(_ source: [UInt8], outputSize: Int) -> [UInt8] {
        lcwDecompressCounted(source, outputSize: outputSize).output
    }

    /// As `lcwDecompress`, also returning how many bytes the stream actually
    /// wrote (the WSA decoder trims each delta to that length).
    package static func lcwDecompressCounted(_ source: [UInt8], outputSize: Int) -> (output: [UInt8], written: Int) {
        var dest = [UInt8](repeating: 0, count: outputSize)
        var sp = 0
        var dp = 0

        while dp < outputSize && sp < source.count {
            let op = source[sp]
            sp += 1

            if (op & 0x80) == 0 {
                // 0x00-0x7F: Short copy back from dest
                let count = Int(op >> 4) + 3
                guard sp < source.count else { break }
                let offset = Int(source[sp]) + (Int(op & 0x0F) << 8)
                sp += 1
                let copyFrom = dp - offset
                guard copyFrom >= 0 else { break }
                let n = min(count, outputSize - dp)
                for i in 0..<n {
                    dest[dp] = dest[copyFrom + i]
                    dp += 1
                }

            } else if (op & 0x40) == 0 {
                if op == 0x80 { break }  // End of data
                let count = Int(op & 0x3F)
                let n = min(count, min(outputSize - dp, source.count - sp))
                for _ in 0..<n {
                    dest[dp] = source[sp]
                    dp += 1
                    sp += 1
                }

            } else if op == 0xFE {
                guard sp + 2 < source.count else { break }
                let count = Int(source[sp]) | (Int(source[sp + 1]) << 8)
                let fillByte = source[sp + 2]
                sp += 3
                let n = min(count, outputSize - dp)
                for _ in 0..<n {
                    dest[dp] = fillByte
                    dp += 1
                }

            } else if op == 0xFF {
                guard sp + 3 < source.count else { break }
                let count = Int(source[sp]) | (Int(source[sp + 1]) << 8)
                let offset = Int(source[sp + 2]) | (Int(source[sp + 3]) << 8)
                sp += 4
                let n = min(count, outputSize - dp)
                for i in 0..<n {
                    let srcIdx = offset + i
                    dest[dp] = srcIdx < outputSize ? dest[srcIdx] : 0
                    dp += 1
                }

            } else {
                // 0xC0-0xFD: Medium copy from dest (absolute offset)
                let count = Int(op & 0x3F) + 3
                guard sp + 1 < source.count else { break }
                let offset = Int(source[sp]) | (Int(source[sp + 1]) << 8)
                sp += 2
                let n = min(count, outputSize - dp)
                for i in 0..<n {
                    let srcIdx = offset + i
                    dest[dp] = srcIdx < outputSize ? dest[srcIdx] : 0
                    dp += 1
                }
            }
        }
        return (dest, dp)
    }

    // MARK: XOR Delta (Format 40)

    /// Apply_XOR_Delta (xordelta.cpp): XORs `delta` onto `buffer` in place.
    /// Writes past the end of `buffer` are dropped rather than trapping.
    /// `copy: true` is Copy_Delta_Buffer (the DO_COPY mode WSA uses for a
    /// non-delta frame 0 drawn straight to a page): the same stream, but
    /// bytes are stored instead of XORed; skipped bytes keep their value.
    package static func applyXORDelta(_ buffer: inout [UInt8], delta: [UInt8], copy: Bool = false) {
        var sp = 0
        var dp = 0

        while true {
            guard sp < delta.count else { break }
            let cmd = delta[sp]
            sp += 1

            if (cmd & 0x80) == 0 {
                // cmd 0b0???????
                if cmd == 0 {
                    // Fill mode: XOR next count bytes with a single value
                    guard sp + 1 < delta.count else { break }
                    let count = Int(delta[sp])
                    let value = delta[sp + 1]
                    sp += 2
                    for _ in 0..<count {
                        guard dp < buffer.count else { break }
                        if copy { buffer[dp] = value } else { buffer[dp] ^= value }
                        dp += 1
                    }
                } else {
                    // XOR next cmd bytes from delta stream
                    let count = Int(cmd)
                    for _ in 0..<count {
                        guard sp < delta.count && dp < buffer.count else { break }
                        if copy { buffer[dp] = delta[sp] } else { buffer[dp] ^= delta[sp] }
                        sp += 1
                        dp += 1
                    }
                }
            } else {
                // cmd 0b1???????
                let count7 = Int(cmd & 0x7F)
                if count7 != 0 {
                    // Short skip
                    dp += count7
                } else {
                    // Extended command: read 16-bit count
                    guard sp + 1 < delta.count else { break }
                    let extCount = Int(delta[sp]) | (Int(delta[sp + 1]) << 8)
                    sp += 2

                    if extCount == 0 {
                        // End of delta
                        break
                    }

                    if (extCount & 0x8000) == 0 {
                        // Long skip
                        dp += extCount
                    } else if (extCount & 0x4000) != 0 {
                        // Long fill: XOR count bytes with a single value
                        let fillCount = extCount & 0x3FFF
                        guard sp < delta.count else { break }
                        let value = delta[sp]
                        sp += 1
                        for _ in 0..<fillCount {
                            guard dp < buffer.count else { break }
                            if copy { buffer[dp] = value } else { buffer[dp] ^= value }
                            dp += 1
                        }
                    } else {
                        // Long XOR from delta stream
                        let xorCount = extCount & 0x3FFF
                        for _ in 0..<xorCount {
                            guard sp < delta.count && dp < buffer.count else { break }
                            if copy { buffer[dp] = delta[sp] } else { buffer[dp] ^= delta[sp] }
                            sp += 1
                            dp += 1
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Little-endian readers (module-internal)

func wwReadLE16(_ bytes: [UInt8], _ pos: Int) -> Int {
    Int(bytes[pos]) | (Int(bytes[pos + 1]) << 8)
}

func wwReadLE32(_ bytes: [UInt8], _ pos: Int) -> UInt32 {
    UInt32(bytes[pos]) | (UInt32(bytes[pos + 1]) << 8)
        | (UInt32(bytes[pos + 2]) << 16) | (UInt32(bytes[pos + 3]) << 24)
}
