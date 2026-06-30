import Foundation

// MARK: - Editable Scenario Document (mission editor — E1)

/// An editable scenario document. Wraps a parsed `ScenarioData` and produces
/// classic-format INI text on save.
///
/// Round-trip strategy (see docs/MISSION_EDITOR_PLAN.md E1): the source
/// `INIFile` retains *every* section/key/value verbatim (only comments and
/// blank lines are dropped at parse). So `toINIFile()` starts from a copy of
/// that INI and **regenerates only the entity sections whose typed model is
/// lossless** — STRUCTURES, UNITS, INFANTRY, OVERLAY, CellTriggers, Base — with
/// the exact classic comma layouts (the inverse of `parseScenarioData`). Every
/// other section passes through untouched, including the ones the typed model
/// parses lossily (TERRAIN drops its trigger suffix; Waypoints drops cell < 0)
/// and the ones it never modeled (Triggers, TeamTypes, house/AI blocks, Map,
/// Briefing, Smudge, and the Tier-1 sections). Regenerating the lossless entity
/// sections is what lets the editor place/move/delete objects and save them;
/// the pass-through guarantees nothing else is lost.
///
/// Fidelity is verified by `--editor-roundtrip` (load → document → INI text →
/// re-parse → assert the typed models are equal, plus serialize-twice
/// idempotence). Byte-identity to a hand-authored original is intentionally not
/// a goal — the parser discards comments, so semantic equivalence is the bar.
final class EditorScenario {
    let name: String
    var data: ScenarioData

    init(name: String, data: ScenarioData) {
        self.name = name
        self.data = data
    }

    /// Build the INIFile to save: a copy of the source INI with the editable
    /// entity sections regenerated in place (each keeps its original position
    /// in the section order).
    func toINIFile() -> INIFile {
        var ini = data.ini  // struct copy — retains every section, in order

        ini.setEntries("OVERLAY", overlayEntries(), display: "OVERLAY")
        ini.setEntries("STRUCTURES", structureEntries(), display: "STRUCTURES")
        ini.setEntries("UNITS", unitEntries(), display: "UNITS")
        ini.setEntries("INFANTRY", infantryEntries(), display: "INFANTRY")
        ini.setEntries("CELLTRIGGERS", cellTriggerEntries(), display: "CellTriggers")
        ini.setEntries("BASE", baseEntries(), display: "Base")
        return ini
    }

    /// Serialize the document to INI text ready to write to disk.
    func serialize() -> String { toINIFile().serialize() }

    /// Write the scenario to a `.INI` file on disk. (MIX archives are read-only,
    /// so edited scenarios are saved as loose INI files — the same form the
    /// engine can load via `INIFile(data:)` / `parseScenarioData`.)
    func save(toPath path: String) throws {
        try serialize().write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Section writers (exact inverse of parseScenarioData)

    /// Classic entity sections key rows by a zero-padded sequential index. The
    /// loader ignores these keys (it parses the value), so the index is purely
    /// positional; we regenerate it densely from 0.
    private func indexKey(_ i: Int) -> String { String(format: "%03d", i) }

    private func overlayEntries() -> [(key: String, value: String)] {
        data.overlays.map { (key: String($0.cell), value: $0.typeName) }
    }

    // House,Type,Strength,Cell,Facing,Trigger
    private func structureEntries() -> [(key: String, value: String)] {
        data.structures.enumerated().map { i, s in
            (key: indexKey(i),
             value: "\(s.house.rawValue),\(s.typeName),\(s.strength),\(s.cell),\(s.facing),\(s.trigger)")
        }
    }

    // House,Type,Strength,Cell,Facing,Mission,Trigger
    private func unitEntries() -> [(key: String, value: String)] {
        data.units.enumerated().map { i, u in
            (key: indexKey(i),
             value: "\(u.house.rawValue),\(u.typeName),\(u.strength),\(u.cell),\(u.facing),\(u.mission),\(u.trigger)")
        }
    }

    // House,Type,Strength,Cell,SubLocation,Mission,Facing,Trigger
    private func infantryEntries() -> [(key: String, value: String)] {
        data.infantry.enumerated().map { i, f in
            (key: indexKey(i),
             value: "\(f.house.rawValue),\(f.typeName),\(f.strength),\(f.cell),\(f.subLocation),\(f.mission),\(f.facing),\(f.trigger)")
        }
    }

    // cell = triggerName
    private func cellTriggerEntries() -> [(key: String, value: String)] {
        data.cellTriggers.map { (key: String($0.cell), value: $0.triggerName) }
    }

    // Count=N, then index = Type,Cell
    private func baseEntries() -> [(key: String, value: String)] {
        var entries: [(key: String, value: String)] = [("Count", String(data.baseBuildings.count))]
        for (i, b) in data.baseBuildings.enumerated() {
            entries.append((key: indexKey(i), value: "\(b.typeName),\(b.cell)"))
        }
        return entries
    }
}
