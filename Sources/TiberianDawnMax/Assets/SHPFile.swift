import Foundation

// MARK: - Westwood SHP (Shape) File Reader
// Two SHP formats exist:
// 1. ShapeBlock: uint16 numShapes + int32 offsets[] + Shape_Type frames (MOUSE.SHP, etc.)
// 2. KeyFrame: 14-byte header + 8 bytes/frame offset table + LCW/XOR delta data (unit sprites)
// Color index 0 = transparent.

struct SHPFrame {
    let width: Int
    let height: Int
    let pixels: [UInt8]  // palette indices, width * height, row-major
}

struct SHPFile {
    let frames: [SHPFrame]

    init(data inputData: Data) throws {
        let data = inputData.startIndex == 0 ? inputData : Data(inputData)
        guard data.count >= 14 else { throw SHPError.tooSmall }

        // Auto-detect format by trying KeyFrame first
        // KeyFrame header: frames(2) x(2) y(2) width(2) height(2) largest(2) flags(2)
        let kfFrames = Int(readLE16(data, 0))
        let kfWidth = Int(readLE16(data, 6))
        let kfHeight = Int(readLE16(data, 8))
        let kfLargest = Int(readLE16(data, 10))

        // Heuristic: if width and height are reasonable and the data size
        // is consistent with keyframe format, use it
        let kfExpectedMinSize = 14 + kfFrames * 8  // header + offset table
        let isKeyFrame = kfWidth > 0 && kfWidth <= 320
            && kfHeight > 0 && kfHeight <= 200
            && kfLargest > 0
            && kfFrames > 0 && kfFrames < 1000
            && data.count >= kfExpectedMinSize

        // Also check ShapeBlock: first offset should point within the file
        let sbNumShapes = Int(readLE16(data, 0))
        let sbFirstOff = data.count >= 6 ? Int(readLE32(data, 2)) : Int.max
        let sbShapeStart = 2 + sbFirstOff
        let isShapeBlock = sbNumShapes > 0 && sbNumShapes < 10000
            && sbShapeStart >= 2 + sbNumShapes * 4
            && sbShapeStart + 10 <= data.count

        if isShapeBlock && sbFirstOff < kfExpectedMinSize {
            // ShapeBlock format
            self.frames = try SHPFile.parseShapeBlock(data: data)
        } else if isKeyFrame {
            // KeyFrame format
            self.frames = try SHPFile.parseKeyFrame(data: data)
        } else if isShapeBlock {
            self.frames = try SHPFile.parseShapeBlock(data: data)
        } else {
            throw SHPError.unknownFormat
        }
    }

    // MARK: - ShapeBlock format (MOUSE.SHP style)

    private static func parseShapeBlock(data: Data) throws -> [SHPFrame] {
        let numShapes = Int(readLE16(data, 0))
        guard numShapes > 0 else { throw SHPError.invalidFrameCount(numShapes) }

        var frames: [SHPFrame] = []
        for i in 0..<numShapes {
            let off = Int(readLE32(data, 2 + i * 4))
            let pos = 2 + off  // bytebuf + 2 + offset
            guard pos + 10 <= data.count else { continue }

            let shapeType = Int(readLE16(data, pos))
            let height = Int(data[pos + 2])
            let width = Int(readLE16(data, pos + 3))

            guard width > 0 && height > 0 else {
                frames.append(SHPFrame(width: 0, height: 0, pixels: []))
                continue
            }

            // Header is 10 bytes without colortable, 26 with (only for compact/type 1)
            let headerSize = (shapeType & 0x01) != 0 ? 26 : 10
            let compStart = pos + headerSize
            let expectedSize = width * height

            var pixels: [UInt8]

            if (shapeType & 0x02) != 0 {
                // Uncompressed
                let end = compStart + expectedSize
                if end <= data.count {
                    pixels = Array(data[compStart..<end])
                } else {
                    pixels = [UInt8](repeating: 0, count: expectedSize)
                }
            } else {
                // LCW compressed
                if compStart < data.count {
                    pixels = lcwDecompress(Array(data[compStart...]), outputSize: expectedSize)
                } else {
                    pixels = [UInt8](repeating: 0, count: expectedSize)
                }
            }

            // Pad or trim to expected size
            if pixels.count > expectedSize {
                pixels = Array(pixels.prefix(expectedSize))
            } else if pixels.count < expectedSize {
                pixels += [UInt8](repeating: 0, count: expectedSize - pixels.count)
            }

            frames.append(SHPFrame(width: width, height: height, pixels: pixels))
        }
        return frames
    }

    // MARK: - KeyFrame format (unit/building sprites)
    // Faithfully follows Build_Frame() from Vanilla Conquer keyframe.cpp

    private static func parseKeyFrame(data: Data) throws -> [SHPFrame] {
        // Header: frames(2) x(2) y(2) width(2) height(2) largest(2) flags(2) = 14 bytes
        let numFrames = Int(readLE16(data, 0))
        let width = Int(readLE16(data, 6))
        let height = Int(readLE16(data, 8))
        let flags = Int(readLE16(data, 12))
        let hasPalette = (flags & 1) != 0

        guard numFrames > 0 && width > 0 && height > 0 else {
            throw SHPError.invalidFrameCount(numFrames)
        }

        let buffSize = width * height
        let headerSize = 14  // sizeof(KeyFrameHeaderType)

        var frames: [SHPFrame] = []

        for f in 0..<numFrames {
            let offTablePos = headerSize + f * 8
            guard offTablePos + 8 <= data.count else { break }

            let off0 = readLE32(data, offTablePos)
            let frameFlags = UInt8(off0 >> 24)

            var buffer = [UInt8](repeating: 0, count: buffSize)

            if (frameFlags & 0x80) != 0 {  // KF_KEYFRAME = 0x80
                // Key frame: LCW decompress directly
                var ptr = Int(off0 & 0x00FFFFFF)
                if hasPalette { ptr += 768 }
                guard ptr < data.count else { break }
                let decompressed = lcwDecompress(Array(data[ptr...]), outputSize: buffSize)
                buffer = fitToSize(decompressed, buffSize)
            } else {
                // Delta or key-delta frame
                // Read offset table entries for this frame (we need 3 uint32s = 12 bytes)
                // offset[0] = frameflags:8 | offset:24 (this frame's delta data)
                // offset[1] = reference keyframe's LCW data offset (or ref frame index for KF_DELTA)

                let isDelta = (frameFlags & 0x20) != 0  // KF_DELTA = 0x20

                // For KF_DELTA frames, offset[1] low 16 bits is the reference frame number
                // We need to load that frame's offset table to find the actual key frame
                var offsets = [UInt32](repeating: 0, count: 7)  // SUBFRAMEOFFS = 7

                if isDelta {
                    let off1 = readLE32(data, offTablePos + 4)
                    let currframe = Int(off1 & 0xFFFF)

                    // Read offset table starting from the referenced key frame
                    let refTablePos = headerSize + currframe * 8
                    let bytesToRead = min(7, (data.count - refTablePos) / 4)
                    for i in 0..<bytesToRead {
                        let readPos = refTablePos + i * 4
                        guard readPos + 4 <= data.count else { break }
                        offsets[i] = readLE32(data, readPos)
                    }
                } else {
                    // Key-delta: read from this frame's offset table position
                    let bytesToRead = min(7, (data.count - offTablePos) / 4)
                    for i in 0..<bytesToRead {
                        let readPos = offTablePos + i * 4
                        guard readPos + 4 <= data.count else { break }
                        offsets[i] = readLE32(data, readPos)
                    }
                }

                // Key frame LCW data is at offsets[1] & 0x00FFFFFF
                let keyLCWOffset = Int(offsets[1] & 0x00FFFFFF)
                // Key delta data offset
                let keyDeltaOffset = Int(offsets[0] & 0x00FFFFFF)

                // Decompress the key frame
                var keyPtr = keyLCWOffset
                if hasPalette { keyPtr += 768 }
                if keyPtr < data.count {
                    let decompressed = lcwDecompress(Array(data[keyPtr...]), outputSize: buffSize)
                    buffer = fitToSize(decompressed, buffSize)
                }

                // Apply key delta (difference between key frame and key delta)
                let keyDeltaDiff = keyDeltaOffset - keyLCWOffset
                if keyDeltaDiff > 0 {
                    let deltaPtr = keyPtr + keyDeltaDiff
                    if deltaPtr < data.count {
                        applyXORDelta(&buffer, delta: Array(data[deltaPtr...]))
                    }
                }

                // For KF_DELTA: apply subsequent deltas up to the requested frame
                if isDelta {
                    let off1 = readLE32(data, offTablePos + 4)
                    var currframe = Int(off1 & 0xFFFF) + 1
                    var subframe = 2  // start at offset[2]

                    while currframe <= f {
                        let deltaOff = Int(offsets[subframe] & 0x00FFFFFF)
                        let deltaDiff = deltaOff - keyLCWOffset
                        if deltaDiff > 0 {
                            let deltaPtr = keyPtr + deltaDiff
                            if deltaPtr < data.count {
                                applyXORDelta(&buffer, delta: Array(data[deltaPtr...]))
                            }
                        }

                        currframe += 1
                        subframe += 2

                        // Reload offset table if we've exhausted current batch
                        if subframe >= 6 && currframe <= f {
                            let reloadPos = headerSize + currframe * 8
                            let bytesToRead = min(7, (data.count - reloadPos) / 4)
                            for i in 0..<bytesToRead {
                                let readPos = reloadPos + i * 4
                                guard readPos + 4 <= data.count else { break }
                                offsets[i] = readLE32(data, readPos)
                            }
                            subframe = 0
                        }
                    }
                }
            }

            frames.append(SHPFrame(width: width, height: height, pixels: buffer))
        }
        return frames
    }

    private static func fitToSize(_ data: [UInt8], _ size: Int) -> [UInt8] {
        if data.count >= size {
            return Array(data.prefix(size))
        }
        return data + [UInt8](repeating: 0, count: size - data.count)
    }

    // MARK: - XOR Delta (Apply_XOR_Delta from xordelta.cpp)

    private static func applyXORDelta(_ buffer: inout [UInt8], delta: [UInt8]) {
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
                        buffer[dp] ^= value
                        dp += 1
                    }
                } else {
                    // XOR next cmd bytes from delta stream
                    let count = Int(cmd)
                    for _ in 0..<count {
                        guard sp < delta.count && dp < buffer.count else { break }
                        buffer[dp] ^= delta[sp]
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
                            buffer[dp] ^= value
                            dp += 1
                        }
                    } else {
                        // Long XOR from delta stream
                        let xorCount = extCount & 0x3FFF
                        for _ in 0..<xorCount {
                            guard sp < delta.count && dp < buffer.count else { break }
                            buffer[dp] ^= delta[sp]
                            sp += 1
                            dp += 1
                        }
                    }
                }
            }
        }
    }

    // MARK: - LCW Decompression (Format 80)

    static func lcwDecompress(_ source: [UInt8], outputSize: Int) -> [UInt8] {
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
        return dest
    }
}

// MARK: - Helpers

private func readLE16(_ data: Data, _ pos: Int) -> UInt16 {
    UInt16(data[pos]) | (UInt16(data[pos + 1]) << 8)
}

private func readLE32(_ data: Data, _ pos: Int) -> UInt32 {
    UInt32(data[pos]) | (UInt32(data[pos + 1]) << 8)
    | (UInt32(data[pos + 2]) << 16) | (UInt32(data[pos + 3]) << 24)
}

// MARK: - Errors

enum SHPError: Error, CustomStringConvertible {
    case tooSmall
    case invalidFrameCount(Int)
    case invalidOffset(frame: Int)
    case invalidFrameData(frame: Int)
    case unknownFormat

    var description: String {
        switch self {
        case .tooSmall: return "SHP data too small"
        case .invalidFrameCount(let n): return "Invalid frame count: \(n)"
        case .invalidOffset(let f): return "Invalid offset for frame \(f)"
        case .invalidFrameData(let f): return "Invalid frame data for frame \(f)"
        case .unknownFormat: return "Unknown SHP format"
        }
    }
}
