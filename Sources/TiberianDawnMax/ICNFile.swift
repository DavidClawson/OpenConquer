import Foundation

// MARK: - Westwood ICN (Icon/Tile) File Reader
// ICN files store terrain tiles using the IControl_Type header format.
// Tiberian Dawn uses a 32-byte header (0x20). Each tile is 24x24 = 576 bytes
// of palette-indexed pixel data. A Map table maps logical icon indices to
// physical pixel data indices.

struct ICNFile {
    let width: Int      // always 24
    let height: Int     // always 24
    let count: Int      // number of physical icon images
    private let data: Data
    private let iconsOffset: Int
    private let mapOffset: Int
    private let transFlagOffset: Int

    init(data inputData: Data) throws {
        let data = inputData.startIndex == 0 ? inputData : Data(inputData)
        guard data.count >= 0x20 else {
            throw ICNError.tooSmall
        }

        // IControl_Type header (32 bytes for TD):
        // 0x00: Width (int16)    0x02: Height (int16)
        // 0x04: Count (int16)    0x06: Allocated (int16)
        // 0x08: Size (int32)
        // 0x0C: Icons (int32)    — offset to pixel data (0x20 for TD)
        // 0x10: Palettes (int32) 0x14: Remaps (int32)
        // 0x18: TransFlag (int32) — offset to transparency flags
        // 0x1C: Map (int32)       — offset to icon map table
        self.width = Int(ICNFile.readI16(data, 0))
        self.height = Int(ICNFile.readI16(data, 2))
        self.count = Int(ICNFile.readI16(data, 4))
        self.iconsOffset = Int(ICNFile.readI32(data, 0x0C))
        self.transFlagOffset = Int(ICNFile.readI32(data, 0x18))
        self.mapOffset = Int(ICNFile.readI32(data, 0x1C))
        self.data = data

        guard width > 0 && height > 0 && count > 0 else {
            throw ICNError.invalidHeader(width, height, count)
        }
    }

    /// Returns width*height pixels (24x24=576) for the given logical icon number, or nil if invalid.
    func tile(icon: Int) -> [UInt8]? {
        guard icon >= 0 else { return nil }

        // Use the Map table to translate logical icon → physical pixel data index
        let physicalIndex: Int
        if mapOffset > 0 && mapOffset + icon < data.count {
            let mapped = Int(data[mapOffset + icon])
            if mapped == 0xFF { return nil }  // explicitly empty position in template
            physicalIndex = mapped
        } else {
            physicalIndex = icon
        }

        guard physicalIndex >= 0 && physicalIndex < count else { return nil }

        let tileSize = width * height
        let pixelStart = iconsOffset + physicalIndex * tileSize
        let pixelEnd = pixelStart + tileSize
        guard pixelEnd <= data.count else { return nil }

        return Array(data[pixelStart..<pixelEnd])
    }

    /// Check if a tile has transparent pixels (palette index 0 treated as transparent).
    func isTransparent(icon: Int) -> Bool {
        let physicalIndex: Int
        if mapOffset > 0 && mapOffset + icon < data.count {
            physicalIndex = Int(data[mapOffset + icon])
        } else {
            physicalIndex = icon
        }
        guard transFlagOffset > 0 && transFlagOffset + physicalIndex < data.count else {
            return false
        }
        return data[transFlagOffset + physicalIndex] != 0
    }

    // MARK: - Little-endian helpers

    private static func readI16(_ data: Data, _ pos: Int) -> Int16 {
        Int16(bitPattern: UInt16(data[pos]) | (UInt16(data[pos + 1]) << 8))
    }

    private static func readI32(_ data: Data, _ pos: Int) -> Int32 {
        Int32(bitPattern: UInt32(data[pos]) | (UInt32(data[pos + 1]) << 8)
            | (UInt32(data[pos + 2]) << 16) | (UInt32(data[pos + 3]) << 24))
    }
}

// MARK: - Errors

enum ICNError: Error, CustomStringConvertible {
    case tooSmall
    case invalidHeader(Int, Int, Int)

    var description: String {
        switch self {
        case .tooSmall: return "ICN data too small for header"
        case .invalidHeader(let w, let h, let c): return "Invalid ICN header: \(w)x\(h), count=\(c)"
        }
    }
}
