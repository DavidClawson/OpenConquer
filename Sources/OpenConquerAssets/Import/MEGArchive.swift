import Foundation

// MARK: - Petroglyph MEG V3 archive (C&C Remastered Collection)
//
// Port of `MEGFile` in tools/extract_remastered_*.py. The MEGs run to several
// GB, so only the header and tables are read up front; entries are read on
// demand with pread(2), which is safe to call from many threads at once.
//
// Layout: 24-byte header (flags 0xFFFFFFFF, magic 0x3F7D70A4, data start,
// filename count, file count, filename-table size), the filename table
// (u16 length + ASCII bytes each), then 20-byte file records whose size,
// offset and name index sit at +10, +14 and +18.

package final class MEGArchive {
    package struct Entry {
        package let offset: UInt64
        package let size: Int
    }

    package let url: URL
    /// Entry name -> location. A duplicated name keeps the last record, like the Python dict.
    package private(set) var entries: [String: Entry] = [:]
    /// Names in file-table order (first occurrence) — Python's dict insertion order.
    package private(set) var names: [String] = []
    private let fd: Int32

    package init(url: URL) throws {
        self.url = url
        fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw AssetImportError.missingArchive(url.lastPathComponent) }
        do { try parse() } catch { close(fd); throw error }
    }

    deinit { close(fd) }

    private func parse() throws {
        let bad = AssetImportError.invalidArchive(url.lastPathComponent, "not a MEG V3 file")
        let header = try readBytes(at: 0, count: 24)
        guard header.count == 24 else { throw bad }
        func u32(_ d: [UInt8], _ o: Int) -> Int {
            Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24
        }
        guard u32(header, 0) == 0xFFFF_FFFF, u32(header, 4) == 0x3F7D_70A4 else { throw bad }
        let numNames = u32(header, 12), numFiles = u32(header, 16), namesSize = u32(header, 20)

        let table = try readBytes(at: 24, count: namesSize)
        guard table.count == namesSize else { throw bad }
        var fileNames: [String] = []
        fileNames.reserveCapacity(numNames)
        var pos = 0
        for _ in 0..<numNames {
            guard pos + 2 <= table.count else { throw bad }
            let len = Int(table[pos]) | Int(table[pos + 1]) << 8
            pos += 2
            guard pos + len <= table.count else { throw bad }
            fileNames.append(String(decoding: table[pos..<(pos + len)], as: UTF8.self))
            pos += len
        }

        let records = try readBytes(at: UInt64(24 + namesSize), count: numFiles * 20)
        guard records.count == numFiles * 20 else { throw bad }
        for i in 0..<numFiles {
            let r = i * 20
            let size = u32(records, r + 10)
            let offset = u32(records, r + 14)
            let nameIndex = Int(records[r + 18]) | Int(records[r + 19]) << 8
            guard nameIndex < fileNames.count else { throw bad }
            let name = fileNames[nameIndex]
            if entries[name] == nil { names.append(name) }
            entries[name] = Entry(offset: UInt64(offset), size: size)
        }
    }

    /// Read one entry's bytes, or nil when the archive has no such name.
    package func read(_ name: String) throws -> [UInt8]? {
        guard let entry = entries[name] else { return nil }
        let bytes = try readBytes(at: entry.offset, count: entry.size)
        guard bytes.count == entry.size else {
            throw AssetImportError.invalidArchive(url.lastPathComponent, "entry \(name) is truncated")
        }
        return bytes
    }

    private func readBytes(at offset: UInt64, count: Int) throws -> [UInt8] {
        guard count > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: count)
        var done = 0
        try buffer.withUnsafeMutableBytes { raw in
            while done < count {
                let n = pread(fd, raw.baseAddress! + done, count - done, off_t(offset) + off_t(done))
                if n == 0 { break }
                if n < 0 {
                    if errno == EINTR { continue }
                    throw AssetImportError.invalidArchive(url.lastPathComponent, String(cString: strerror(errno)))
                }
                done += n
            }
        }
        if done < count { buffer.removeSubrange(done...) }
        return buffer
    }
}
