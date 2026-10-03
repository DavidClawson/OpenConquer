import Foundation

// MARK: - CONQUER.ENG string table (Extract_String, common/dipthong.cpp)
//
// Layout (little-endian): a table of u16 offsets from the start of the file,
// one per string, immediately followed by the NUL-terminated strings. The
// table's length is implied by the first offset (count = offset[0] / 2), as
// in Extract_String's `string >= ptr_0 / 2` bounds check.

/// CONQUER.ENG: little-endian UInt16 offset table (count = firstOffset / 2) followed by NUL-terminated strings.
/// Index == the TXT_* value from ../Vanilla-Conquer/tiberiandawn/conquer.h (TXT_NONE = 0). Verify: [502] == "LOCATING COORDINATES", [576] == "CLICK TO CONTINUE", [742] == "READING IMAGE DATA".
package struct StringTable {
    private let strings: [String]

    package init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        func le16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        let first = le16(0)
        let n = first / 2
        guard n > 0, first <= bytes.count else { return nil }
        var out: [String] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let start = le16(i * 2)
            guard start < bytes.count else { out.append(""); continue }
            var end = start
            while end < bytes.count, bytes[end] != 0 { end += 1 }
            // Bytes are the game's 8-bit code page; Latin-1 keeps every byte
            // value as the matching Unicode scalar so WWFont can map it back.
            out.append(String(decoding: bytes[start..<end].map { UInt16($0) }, as: UTF16.self))
        }
        strings = out
    }

    /// Strings actually present in the file. The CONQUER.ENG shipped with
    /// the freeware/1.0x data has 710 (TXT_NONE...TXT_SCENES); later patches
    /// added up to TXT_INSUFFICIENT_FUNDS (756).
    package var count: Int { strings.count }

    /// The string for a TXT_* id; "" when out of range — except the seven
    /// map-selection strings TXT_READING_IMAGE_DATA (742) ... TXT_ENHANCING_IMAGE
    /// (748), which fall back to their English text when the file predates
    /// them, as Vanilla-Conquer's GetMapSelString does (mapsel.cpp:385-402).
    package subscript(id: Int) -> String {
        if id >= 0 && id < strings.count { return strings[id] }
        if id >= 742 && id < 742 + StringTable.mapSelFallback.count {
            return StringTable.mapSelFallback[id - 742]
        }
        return ""
    }

    /// mapsel.cpp `additional_strings`, ids 742...748.
    private static let mapSelFallback = [
        "READING IMAGE DATA", "ANALYZING", "ENHANCING IMAGE DATA", "ISOLATING OPERATIONAL",
        "ESTABLISHING TRADITIONAL", "FOR VISUAL REFERENCE", "ENHANCING IMAGE",
    ]
}
