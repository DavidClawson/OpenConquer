import Foundation

// MARK: - Generic INI File Parser

/// Parses standard INI files with [Section] headers, Key=Value pairs, and ; comments.
/// Case-insensitive section/key lookup. Preserves entry order within sections.
struct INIFile {
    private var sections: [String: [(key: String, value: String)]] = [:]
    private var sectionOrder: [String] = []

    init(data: Data) {
        guard let text = String(data: data, encoding: .ascii)
           ?? String(data: data, encoding: .utf8) else {
            return
        }
        parse(text)
    }

    init(string: String) {
        parse(string)
    }

    private mutating func parse(_ text: String) {
        var currentSection = ""

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("#") {
                continue
            }

            // Section header
            if trimmed.hasPrefix("[") {
                if let end = trimmed.firstIndex(of: "]") {
                    currentSection = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
                        .trimmingCharacters(in: .whitespaces)
                        .uppercased()
                    if sections[currentSection] == nil {
                        sections[currentSection] = []
                        sectionOrder.append(currentSection)
                    }
                }
                continue
            }

            // Key=Value pair
            if let eqIdx = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[trimmed.startIndex..<eqIdx])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: eqIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                if sections[currentSection] == nil {
                    sections[currentSection] = []
                    sectionOrder.append(currentSection)
                }
                sections[currentSection]!.append((key: key, value: value))
            }
        }
    }

    // MARK: - Query API

    /// Check if a section exists
    func hasSection(_ section: String) -> Bool {
        sections[section.uppercased()] != nil
    }

    /// Get all entries in a section as ordered (key, value) pairs
    func entries(_ section: String) -> [(key: String, value: String)] {
        sections[section.uppercased()] ?? []
    }

    /// Get a string value for a key in a section
    func string(_ section: String, _ key: String, default defaultValue: String = "") -> String {
        let sectionUpper = section.uppercased()
        let keyUpper = key.uppercased()
        guard let entries = sections[sectionUpper] else { return defaultValue }
        for entry in entries {
            if entry.key.uppercased() == keyUpper {
                return entry.value
            }
        }
        return defaultValue
    }

    /// Get an integer value for a key in a section
    func int(_ section: String, _ key: String, default defaultValue: Int = 0) -> Int {
        let str = string(section, key, default: "")
        return Int(str) ?? defaultValue
    }

    /// Get all section names in order
    var sectionNames: [String] {
        sectionOrder
    }
}
