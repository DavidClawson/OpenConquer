import Compression
import Foundation

// MARK: - In-memory ZIP reader (stored + deflate)
//
// The remastered sprite ZIPs inside TEXTURES_TD_SRGB.MEG are small (KB to a
// few MB) and use plain deflate, so the whole archive is held in memory and
// read through the central directory. Deflate is decoded with Apple's
// Compression framework (COMPRESSION_ZLIB is raw RFC 1951 deflate). No ZIP64,
// no encryption — neither occurs in the remaster.

package struct ZIPArchive {
    package struct Entry {
        package let name: String
        let method: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: [UInt8]
    /// Central-directory order (Python's `ZipFile.namelist()`).
    package let entries: [Entry]
    private let byName: [String: Int]

    package init?(bytes: [UInt8]) {
        self.data = bytes
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

        // End-of-central-directory record: scan back over a possible comment.
        guard bytes.count >= 22 else { return nil }
        var eocd = -1
        var p = bytes.count - 22
        let floor = max(0, bytes.count - 22 - 65535)
        while p >= floor {
            if bytes[p] == 0x50, bytes[p + 1] == 0x4B, bytes[p + 2] == 0x05, bytes[p + 3] == 0x06 { eocd = p; break }
            p -= 1
        }
        guard eocd >= 0 else { return nil }
        let count = u16(eocd + 10)
        var pos = u32(eocd + 16)

        var list: [Entry] = []
        var index: [String: Int] = [:]
        for _ in 0..<count {
            guard pos + 46 <= bytes.count, u32(pos) == 0x0201_4B50 else { return nil }
            let nameLen = u16(pos + 28), extraLen = u16(pos + 30), commentLen = u16(pos + 32)
            guard pos + 46 + nameLen <= bytes.count else { return nil }
            let name = String(decoding: bytes[(pos + 46)..<(pos + 46 + nameLen)], as: UTF8.self)
            index[name] = list.count  // a repeated name reads the last one, like zipfile
            list.append(Entry(name: name, method: u16(pos + 10), compressedSize: u32(pos + 20),
                              uncompressedSize: u32(pos + 24), localHeaderOffset: u32(pos + 42)))
            pos += 46 + nameLen + extraLen + commentLen
        }
        entries = list
        byName = index
    }

    /// Decompressed bytes of the named member, or nil if absent/corrupt.
    package func read(_ name: String) -> [UInt8]? {
        guard let i = byName[name] else { return nil }
        let e = entries[i]
        let h = e.localHeaderOffset
        guard h + 30 <= data.count,
              data[h] == 0x50, data[h + 1] == 0x4B, data[h + 2] == 0x03, data[h + 3] == 0x04 else { return nil }
        let start = h + 30 + (Int(data[h + 26]) | Int(data[h + 27]) << 8) + (Int(data[h + 28]) | Int(data[h + 29]) << 8)
        guard start + e.compressedSize <= data.count else { return nil }

        switch e.method {
        case 0:
            return Array(data[start..<(start + e.compressedSize)])
        case 8:
            if e.uncompressedSize == 0 { return [] }
            var out = [UInt8](repeating: 0, count: e.uncompressedSize)
            let written = out.withUnsafeMutableBufferPointer { dst in
                data.withUnsafeBufferPointer { src in
                    compression_decode_buffer(dst.baseAddress!, e.uncompressedSize,
                                              src.baseAddress! + start, e.compressedSize,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            return written == e.uncompressedSize ? out : nil
        default:
            return nil
        }
    }
}
