import Foundation

// MARK: - Generic INI File Parser

/// Parses standard INI files with [Section] headers, Key=Value pairs, and ; comments.
/// Case-insensitive section/key lookup. Preserves entry order within sections.
struct INIFile {
    private var sections: [String: [(key: String, value: String)]] = [:]
    private var sectionOrder: [String] = []
    // Original-cased header text per (uppercased) section, so a serialized
    // round-trip reproduces `[Basic]`/`[TeamTypes]` rather than `[BASIC]`.
    private var sectionDisplay: [String: String] = [:]

    /// An empty INI, for building a scenario document from scratch.
    init() {}

    /// True when no sections parsed — e.g. undecodable bytes or a wrong file.
    var isEmpty: Bool { sectionOrder.isEmpty }

    init(data: Data) {
        // isoLatin1 last: it never fails, so stray non-ASCII bytes (retail
        // SCG06EA.INI has 4 in a garbled section header) degrade to mojibake
        // in that one header instead of silently discarding the whole file —
        // the original engine's byte-based WWGetPrivateProfile ignored them.
        guard let text = String(data: data, encoding: .ascii)
           ?? String(data: data, encoding: .utf8)
           ?? String(data: data, encoding: .isoLatin1) else {
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
                    let raw = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
                        .trimmingCharacters(in: .whitespaces)
                    currentSection = raw.uppercased()
                    if sections[currentSection] == nil {
                        sections[currentSection] = []
                        sectionOrder.append(currentSection)
                        sectionDisplay[currentSection] = raw
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

    // MARK: - Mutation API (for the scenario editor / writer)

    /// Replace (or create) a whole section's ordered entries. `display` sets the
    /// header casing for a new section; omit to keep the existing/derived one.
    mutating func setEntries(_ section: String, _ entries: [(key: String, value: String)],
                             display: String? = nil) {
        let upper = section.uppercased()
        if sections[upper] == nil {
            sectionOrder.append(upper)
        }
        sections[upper] = entries
        if let display = display {
            sectionDisplay[upper] = display
        } else if sectionDisplay[upper] == nil {
            sectionDisplay[upper] = section
        }
    }

    /// Upsert a single key in a section (creating the section if needed).
    mutating func setValue(_ section: String, _ key: String, _ value: String) {
        let upper = section.uppercased()
        if sections[upper] == nil {
            sectionOrder.append(upper)
            sectionDisplay[upper] = section
        }
        if let idx = sections[upper]!.firstIndex(where: { $0.key.uppercased() == key.uppercased() }) {
            sections[upper]![idx].value = value
        } else {
            sections[upper]!.append((key: key, value: value))
        }
    }

    /// Remove a section entirely (no-op if absent).
    mutating func removeSection(_ section: String) {
        let upper = section.uppercased()
        sections[upper] = nil
        sectionDisplay[upper] = nil
        sectionOrder.removeAll { $0 == upper }
    }

    // MARK: - Serialization

    /// Serialize back to INI text: sections in first-seen order, entries in
    /// insertion order, original header casing preserved. Comments and blank
    /// lines from the source are not retained (the parser discards them), so
    /// this is a faithful *semantic* round-trip, not byte-identical to a
    /// hand-authored original.
    func serialize() -> String {
        var out = ""
        for name in sectionOrder {
            let header = sectionDisplay[name] ?? name
            out += "[\(header)]\n"
            for entry in sections[name] ?? [] {
                out += "\(entry.key)=\(entry.value)\n"
            }
            out += "\n"
        }
        return out
    }
}
