import Foundation

// MARK: - Westwood SHP (Shape) File Reader
// Two SHP formats exist:
// 1. ShapeBlock: uint16 numShapes + int32 offsets[] + Shape_Type frames (MOUSE.SHP, etc.)
// 2. KeyFrame: 14-byte header + 8 bytes/frame offset table + LCW/XOR delta data (unit sprites)
// Color index 0 = transparent.

package struct SHPFrame {
    package let width: Int
    package let height: Int
    package let pixels: [UInt8]  // palette indices, width * height, row-major
}

package struct SHPFile {
    package let frames: [SHPFrame]

    package init(data inputData: Data) throws {
        let data = inputData.startIndex == 0 ? inputData : Data(inputData)
        guard data.count >= 14 else { throw SHPError.tooSmall }

        // Auto-detect format by trying KeyFrame first
        // KeyFrame header: frames(2) x(2) y(2) width(2) height(2) largest(2) flags(2)
        let kfFrames = Int(readLE16(data, 0))
        let kfWidth = Int(readLE16(data, 6))
        let kfHeight = Int(readLE16(data, 8))

        // Heuristic: if width and height are reasonable and the data size
        // is consistent with keyframe format, use it
        let kfExpectedMinSize = 14 + kfFrames * 8  // header + offset table
        // Bounds cover the hi-res (640x400) UI art in UPDATEC.MIX: HSIDE2 and
        // HPWRBAR are 492px tall, and a keyframe-only file (no XOR deltas,
        // e.g. HSIDE1) stores 0 as its largest-delta size.
        let isKeyFrame = kfWidth > 0 && kfWidth <= 640
            && kfHeight > 0 && kfHeight <= 512
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

    // MARK: - Codecs (shared with CPS/WSA — see WestwoodCodec.swift)

    private static func applyXORDelta(_ buffer: inout [UInt8], delta: [UInt8]) {
        WestwoodCodec.applyXORDelta(&buffer, delta: delta)
    }

    /// LCW (Format 80). Kept here for existing call sites.
    package static func lcwDecompress(_ source: [UInt8], outputSize: Int) -> [UInt8] {
        WestwoodCodec.lcwDecompress(source, outputSize: outputSize)
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

package enum SHPError: Error, CustomStringConvertible {
    case tooSmall
    case invalidFrameCount(Int)
    case invalidOffset(frame: Int)
    case invalidFrameData(frame: Int)
    case unknownFormat

    package var description: String {
        switch self {
        case .tooSmall: return "SHP data too small"
        case .invalidFrameCount(let n): return "Invalid frame count: \(n)"
        case .invalidOffset(let f): return "Invalid offset for frame \(f)"
        case .invalidFrameData(let f): return "Invalid frame data for frame \(f)"
        case .unknownFormat: return "Unknown SHP format"
        }
    }
}
