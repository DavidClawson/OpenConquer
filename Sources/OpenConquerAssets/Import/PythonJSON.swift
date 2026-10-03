import Foundation

// MARK: - JSON in Python's `json.dump(indent=2)` layout
//
// The sprite / cursor / sidebar manifests were written by Python; emitting the
// same layout (insertion-ordered keys, or sorted for `sort_keys=True`) keeps
// the native import byte-identical to the scripts, so the two can be diffed.

package indirect enum PyJSON {
    case int(Int)
    case double(Double)
    case string(String)
    case array([PyJSON])
    case object([(String, PyJSON)])

    /// Convert a JSONSerialization value (as read from a `.meta` file).
    init?(foundation value: Any) {
        switch value {
        case let n as NSNumber:
            if CFNumberIsFloatType(n) { self = .double(n.doubleValue) } else { self = .int(n.intValue) }
        case let s as String: self = .string(s)
        case let a as [Any]:
            var items: [PyJSON] = []
            for v in a { guard let j = PyJSON(foundation: v) else { return nil }; items.append(j) }
            self = .array(items)
        default: return nil
        }
    }

    package func serialized(sortKeys: Bool = false) -> Data {
        var out = ""
        write(into: &out, indent: 0, sortKeys: sortKeys)
        return Data(out.utf8)
    }

    private func write(into out: inout String, indent: Int, sortKeys: Bool) {
        switch self {
        case .int(let v): out += String(v)
        case .double(let v): out += v == v.rounded() && abs(v) < 1e16 ? String(format: "%.1f", v) : String(v)
        case .string(let s): out += PyJSON.quote(s)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += String(repeating: " ", count: indent + 2)
                item.write(into: &out, indent: indent + 2, sortKeys: sortKeys)
                out += i == items.count - 1 ? "\n" : ",\n"
            }
            out += String(repeating: " ", count: indent) + "]"
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            let ordered = sortKeys ? pairs.sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) } : pairs
            out += "{\n"
            for (i, (key, value)) in ordered.enumerated() {
                out += String(repeating: " ", count: indent + 2) + PyJSON.quote(key) + ": "
                value.write(into: &out, indent: indent + 2, sortKeys: sortKeys)
                out += i == ordered.count - 1 ? "\n" : ",\n"
            }
            out += String(repeating: " ", count: indent) + "}"
        }
    }

    /// `ensure_ascii=True` string quoting.
    private static func quote(_ s: String) -> String {
        var r = "\""
        for u in s.utf16 {
            switch u {
            case 0x22: r += "\\\""
            case 0x5C: r += "\\\\"
            case 0x0A: r += "\\n"
            case 0x0D: r += "\\r"
            case 0x09: r += "\\t"
            case 0x08: r += "\\b"
            case 0x0C: r += "\\f"
            case 0x20..<0x7F: r.unicodeScalars.append(Unicode.Scalar(u)!)
            default: r += String(format: "\\u%04x", u)
            }
        }
        return r + "\""
    }
}
