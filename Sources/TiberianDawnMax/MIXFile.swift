import Foundation

// MARK: - Westwood MIX File Reader
// MIX files are archive files used by Command & Conquer to store game assets.
// Files inside are identified by a CRC hash of their uppercase filename.
// Format: [header][index entries][raw data]

struct MIXEntry {
    let crc: Int32
    let offset: Int32
    let size: Int32
}

struct MIXFile {
    let url: URL
    let entries: [MIXEntry]
    let dataStart: Int
    let fileData: Data
    private let crcIndex: [Int32: Int]

    init(url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url)
        self.fileData = data

        let parsed = try MIXFile.parse(data)
        self.entries = parsed.entries
        self.dataStart = parsed.dataStart

        var index: [Int32: Int] = [:]
        for (i, entry) in parsed.entries.enumerated() {
            index[entry.crc] = i
        }
        self.crcIndex = index
    }

    private static func readInt16(_ data: Data, at pos: inout Int) -> Int16 {
        var val: Int16 = 0
        withUnsafeMutableBytes(of: &val) { dest in
            data.copyBytes(to: dest.bindMemory(to: UInt8.self), from: pos..<pos+2)
        }
        pos += 2
        return Int16(littleEndian: val)
    }

    private static func readInt32(_ data: Data, at pos: inout Int) -> Int32 {
        var val: Int32 = 0
        withUnsafeMutableBytes(of: &val) { dest in
            data.copyBytes(to: dest.bindMemory(to: UInt8.self), from: pos..<pos+4)
        }
        pos += 4
        return Int32(littleEndian: val)
    }

    private static func parse(_ data: Data) throws -> (entries: [MIXEntry], dataStart: Int) {
        var pos = 0

        let first = readInt16(data, at: &pos)
        let second = readInt16(data, at: &pos)

        let count: Int

        if first == 0 {
            // Extended format (Red Alert and later)
            let isEncrypted = (second & 0x02) != 0
            if isEncrypted {
                throw MIXError.encryptedNotSupported
            }
            let fileCount = readInt16(data, at: &pos)
            _ = readInt32(data, at: &pos) // dataSize
            count = Int(fileCount)
        } else {
            // Standard format (original C&C Tiberian Dawn)
            // bytes 0-1 = count, bytes 2-5 = size
            pos = 2
            _ = readInt32(data, at: &pos) // dataSize
            count = Int(first)
        }

        var entries: [MIXEntry] = []
        entries.reserveCapacity(count)

        for _ in 0..<count {
            let crc = readInt32(data, at: &pos)
            let offset = readInt32(data, at: &pos)
            let size = readInt32(data, at: &pos)
            entries.append(MIXEntry(crc: crc, offset: offset, size: size))
        }

        return (entries, pos)
    }

    func data(forCRC crc: Int32) -> Data? {
        guard let idx = crcIndex[crc] else { return nil }
        let entry = entries[idx]
        let start = dataStart + Int(entry.offset)
        let end = start + Int(entry.size)
        guard start >= 0 && end <= fileData.count else { return nil }
        return fileData[start..<end]
    }

    func data(forName name: String) -> Data? {
        data(forCRC: MIXFile.crc(for: name))
    }

    func contains(name: String) -> Bool {
        crcIndex[MIXFile.crc(for: name)] != nil
    }

    var allCRCs: [Int32] {
        entries.map { $0.crc }
    }

    // MARK: - Westwood CRC Algorithm
    // Custom hash: for each 4-byte block, CRC = rotateLeft(CRC, 1) + block

    static func crc(for filename: String) -> Int32 {
        crcFromBytes(Array(filename.uppercased().utf8))
    }

    static func crcFromBytes(_ bytes: [UInt8]) -> Int32 {
        var crc: UInt32 = 0
        var i = 0

        while i + 4 <= bytes.count {
            let block = UInt32(bytes[i])
                | (UInt32(bytes[i + 1]) << 8)
                | (UInt32(bytes[i + 2]) << 16)
                | (UInt32(bytes[i + 3]) << 24)
            crc = rotl(crc) &+ block
            i += 4
        }

        if i < bytes.count {
            var staging: UInt32 = 0
            for j in i..<bytes.count {
                staging |= UInt32(bytes[j]) << ((j - i) * 8)
            }
            crc = rotl(crc) &+ staging
        }

        return Int32(bitPattern: crc)
    }

    private static func rotl(_ v: UInt32) -> UInt32 {
        (v << 1) | (v >> 31)
    }
}

// MARK: - MIX File Collection

class MIXFileManager {
    private var mixFiles: [(name: String, mix: MIXFile)] = []

    func register(_ url: URL) throws {
        let mix = try MIXFile(url: url)
        let name = url.lastPathComponent.uppercased()
        mixFiles.append((name: name, mix: mix))
        print("MIX: Registered \(name) (\(mix.entries.count) files)")
    }

    func registerAll(in directory: URL) throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let mixURLs = contents
            .filter { $0.pathExtension.uppercased() == "MIX" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in mixURLs {
            do {
                try register(url)
            } catch {
                print("MIX: Failed to load \(url.lastPathComponent): \(error)")
            }
        }
    }

    func retrieve(_ filename: String) -> Data? {
        let crc = MIXFile.crc(for: filename)
        for (_, mix) in mixFiles {
            if let data = mix.data(forCRC: crc) {
                return data
            }
        }
        return nil
    }

    func contains(_ filename: String) -> Bool {
        let crc = MIXFile.crc(for: filename)
        return mixFiles.contains { $0.mix.data(forCRC: crc) != nil }
    }

    func locate(_ filename: String) -> String? {
        let crc = MIXFile.crc(for: filename)
        for (name, mix) in mixFiles {
            if mix.data(forCRC: crc) != nil {
                return name
            }
        }
        return nil
    }

    /// Register a MIX file that is nested inside another already-registered MIX archive.
    /// This allows finding AUD files inside SOUNDS.MIX, SPEECH.MIX, etc.
    func registerSubArchive(_ name: String) {
        let upperName = name.uppercased()
        // Check if already registered
        if mixFiles.contains(where: { $0.name == upperName }) { return }

        guard let data = retrieve(name) else {
            // Not an error — some sub-archives may not exist
            return
        }

        do {
            // Write to temp file so MIXFile(url:) can parse it
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("_sub_\(upperName)")
            try data.write(to: tempURL)
            let mix = try MIXFile(url: tempURL)
            mixFiles.append((name: upperName, mix: mix))
            print("MIX: Registered sub-archive \(upperName) (\(mix.entries.count) files)")
        } catch {
            print("MIX: Failed to register sub-archive \(name): \(error)")
        }
    }

    var registeredFiles: [String] {
        mixFiles.map { $0.name }
    }

    var totalEntries: Int {
        mixFiles.reduce(0) { $0 + $1.mix.entries.count }
    }
}

// MARK: - Errors

enum MIXError: Error, CustomStringConvertible {
    case encryptedNotSupported
    case invalidHeader
    case fileNotFound(String)

    var description: String {
        switch self {
        case .encryptedNotSupported: return "Encrypted MIX files are not supported"
        case .invalidHeader: return "Invalid MIX file header"
        case .fileNotFound(let name): return "File not found in MIX archives: \(name)"
        }
    }
}
