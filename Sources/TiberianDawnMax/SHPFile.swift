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
            guard pos + 26 <= data.count else { continue }

            let shapeType = Int(readLE16(data, pos))
            let height = Int(data[pos + 2])
            let width = Int(readLE16(data, pos + 3))
            let dataLength = Int(readLE16(data, pos + 8))

            guard width > 0 && height > 0 else {
                frames.append(SHPFrame(width: 0, height: 0, pixels: []))
                continue
            }

            let headerSize = 26
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
                let uncompSize = dataLength > 0 ? dataLength : expectedSize
                if compStart < data.count {
                    pixels = lcwDecompress(Array(data[compStart...]), outputSize: uncompSize)
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

        // After header: numFrames * 8 bytes of offset data (2 uint32s per frame)
        // Then: compressed frame data

        var frames: [SHPFrame] = []
        var baseBuffer = [UInt8](repeating: 0, count: buffSize)

        for f in 0..<numFrames {
            let offTablePos = 14 + f * 8
            guard offTablePos + 8 <= data.count else { break }

            let off0 = readLE32(data, offTablePos)
            let off1 = readLE32(data, offTablePos + 4)

            let frameFlags = UInt8(off0 >> 24)
            let frameOffset = Int(off0 & 0x00FFFFFF)

            let isKeyframe = (frameFlags & 0x20) != 0  // KF_KEYFRAME

            if isKeyframe {
                // Key frame: LCW decompress directly
                var ptr = frameOffset
                if hasPalette { ptr += 768 }
                guard ptr < data.count else { break }
                let decompressed = lcwDecompress(Array(data[ptr...]), outputSize: buffSize)
                baseBuffer = decompressed.count >= buffSize
                    ? Array(decompressed.prefix(buffSize))
                    : decompressed + [UInt8](repeating: 0, count: buffSize - decompressed.count)
            } else {
                // Delta frame: find the referenced keyframe and apply deltas
                let refFrame = Int(off1 & 0xFFFF)
                let refOffTablePos = 14 + refFrame * 8
                guard refOffTablePos + 12 <= data.count else { break }

                let refOff0 = readLE32(data, refOffTablePos)
                let refOff1 = readLE32(data, refOffTablePos + 4)
                let refOffset = Int(refOff1 & 0x00FFFFFF)

                // Decompress the key frame
                var keyPtr = refOffset
                if hasPalette { keyPtr += 768 }
                if keyPtr < data.count {
                    let decompressed = lcwDecompress(Array(data[keyPtr...]), outputSize: buffSize)
                    baseBuffer = decompressed.count >= buffSize
                        ? Array(decompressed.prefix(buffSize))
                        : decompressed + [UInt8](repeating: 0, count: buffSize - decompressed.count)
                }

                // Apply key delta
                let keyDeltaOffset = Int(refOff0 & 0x00FFFFFF)
                if keyDeltaOffset < data.count {
                    applyXORDelta(&baseBuffer, delta: Array(data[keyDeltaOffset...]))
                }

                // Apply subsequent deltas up to current frame
                // (simplified — just apply the current frame's delta)
                if frameOffset < data.count && frameOffset != keyDeltaOffset {
                    applyXORDelta(&baseBuffer, delta: Array(data[frameOffset...]))
                }
            }

            frames.append(SHPFrame(width: width, height: height, pixels: baseBuffer))
        }
        return frames
    }

    // MARK: - XOR Delta

    private static func applyXORDelta(_ buffer: inout [UInt8], delta: [UInt8]) {
        var sp = 0
        var dp = 0

        while sp < delta.count && dp < buffer.count {
            let cmd = delta[sp]
            sp += 1

            if cmd == 0 {
                // Skip N bytes
                guard sp < delta.count else { break }
                let count = Int(delta[sp])
                sp += 1
                if count == 0 { break }  // end marker
                dp += count
            } else if cmd < 0x80 {
                // XOR next N bytes
                let count = Int(cmd)
                for _ in 0..<count {
                    guard sp < delta.count && dp < buffer.count else { break }
                    buffer[dp] ^= delta[sp]
                    sp += 1
                    dp += 1
                }
            } else {
                // Skip (cmd - 0x80) bytes
                dp += Int(cmd) - 0x80
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
