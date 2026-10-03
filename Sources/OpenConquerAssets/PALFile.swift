import Foundation

// MARK: - VGA palette (.PAL, and the palettes embedded in CPS/WSA)
//
// 256 entries × RGB, 6 bits per channel (0-63), 768 bytes, no header —
// exactly what CCFileClass("DARK_E.PAL").Read(pal, 768) loads in MAPSEL.CPP.
// 6→8-bit expansion matches the app's `loadPalette` (main.swift):
// (v << 2) | (v >> 4), so 63 → 255 and 0 → 0.

package struct VGAPalette: Equatable {
    package static let byteCount = 768

    /// The raw 6-bit components, 768 bytes (r,g,b per index).
    package let raw6: [UInt8]

    /// Parses a raw palette. Extra trailing bytes are ignored; fewer than
    /// 768 bytes throws.
    package init(vga6 bytes: [UInt8]) throws {
        guard bytes.count >= VGAPalette.byteCount else {
            throw WestwoodImageError.truncated("palette needs 768 bytes, got \(bytes.count)")
        }
        raw6 = Array(bytes.prefix(VGAPalette.byteCount))
    }

    package init(data: Data) throws {
        try self.init(vga6: [UInt8](data))
    }

    /// 6-bit VGA DAC value → 8-bit (same formula as main.swift `loadPalette`).
    @inline(__always)
    package static func expand6(_ v: UInt8) -> UInt8 {
        let v = v & 0x3F
        return (v << 2) | (v >> 4)
    }

    /// 768 bytes of 8-bit RGB.
    package var rgb8: [UInt8] { raw6.map(VGAPalette.expand6) }

    /// 256 8-bit colors, in the tuple shape the app's renderers already use.
    package var colors: [(r: UInt8, g: UInt8, b: UInt8)] {
        (0..<256).map { i in
            (r: VGAPalette.expand6(raw6[i * 3]),
             g: VGAPalette.expand6(raw6[i * 3 + 1]),
             b: VGAPalette.expand6(raw6[i * 3 + 2]))
        }
    }

    /// Converts indexed pixels to RGBA8888 (byte order R,G,B,A). If
    /// `transparentIndex` is set, that index gets alpha 0.
    package func rgba(_ indices: [UInt8], transparentIndex: UInt8? = nil) -> [UInt8] {
        let lut = rgb8
        var out = [UInt8](repeating: 255, count: indices.count * 4)
        for (i, idx) in indices.enumerated() {
            let c = Int(idx) * 3
            out[i * 4] = lut[c]
            out[i * 4 + 1] = lut[c + 1]
            out[i * 4 + 2] = lut[c + 2]
            if let t = transparentIndex, idx == t { out[i * 4 + 3] = 0 }
        }
        return out
    }
}

// MARK: - Errors shared by the CPS/WSA/PAL decoders

package enum WestwoodImageError: Error, CustomStringConvertible, Equatable {
    case truncated(String)
    case badHeader(String)
    case unsupportedCompression(Int)

    package var description: String {
        switch self {
        case .truncated(let s): return "truncated: \(s)"
        case .badHeader(let s): return "bad header: \(s)"
        case .unsupportedCompression(let m): return "unsupported compression method \(m)"
        }
    }
}
