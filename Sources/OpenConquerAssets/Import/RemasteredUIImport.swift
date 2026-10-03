import Foundation

// MARK: - HD UI art: cursors + sidebar meters (TEXTURES_SRGB.MEG, CONFIG.MEG)
//
// Port of `extract_ui` in tools/extract_remastered_sprites.py:
//   ui/cursors/<FAMILY>/<FAMILY>[_X2]-NNNN.png + cursors.json  (Rendering/GameCursorHD.swift)
//   ui/sidebar/<TEXTURE>.png + sidebar.json                     (Rendering/SidebarHD.swift)
// Cursor families are the top-level ICON_*.DDS textures grouped by stem
// (`<FAMILY>[_X2]_<n>`); hotspots come from MOUSEPOINTERS(X2).XML.

private let uiPrefix = "DATA\\ART\\TEXTURES\\SRGB\\"

private let sidebarTextures = [
    "UI_SIDEBAR_POWERSEGMENT_EMPTY",
    "UI_SIDEBAR_POWERSEGMENT_FILLED",
    "UI_TOOLTIP_INPROGRESS_FILLED",
    "UI_TRAINQUEUEBAR_FILLED",
    "UI_WAVETIMER_PROGRESS_00",
    "UI_RESOURCEBAR_FILLED_CURRENT",
    "UI_RESOURCEBAR_FILLED_GOLD",
    "UI_RESOURCEBAR_FILLED_GROWTH",
    "UI_RESOURCEBAR_FILLED_LOSS",
    "UI_RESOURCEBAR_FILLED_COMMAND",
    "UI_XPBAR_FILLED_MID",
    "UI_HEALTHBAR_FILLED_GREYSCALE",
    "UI_HERO_HEALTHBAR_FILLED",
]

private struct CursorFamily {
    let family: String
    let scale: Int  // 1 or 2 (_X2)
    var frames: [(number: Int, entry: String)]
}

private enum UIJob {
    case cursor(Int)           // index into families
    case sidebar(String)       // texture base name
    case repairWrench
}

private struct UIResult { var count = 0; var w = 0; var h = 0 }

func importHDUI(remasteredData: URL, outDir: URL, ctx: ImportContext, isCancelled: () -> Bool) throws {
    let tex = try MEGArchive(url: remasteredData.appendingPathComponent("TEXTURES_SRGB.MEG"))
    let configURL = remasteredData.appendingPathComponent("CONFIG.MEG")
    let config = FileManager.default.fileExists(atPath: configURL.path) ? try MEGArchive(url: configURL) : nil
    let commonURL = remasteredData.appendingPathComponent("TEXTURES_COMMON_SRGB.MEG")
    let common = FileManager.default.fileExists(atPath: commonURL.path) ? try MEGArchive(url: commonURL) : nil

    let cursorDir = outDir.appendingPathComponent("ui").appendingPathComponent("cursors")
    let sidebarDir = outDir.appendingPathComponent("ui").appendingPathComponent("sidebar")
    try makeDirectory(cursorDir)
    try makeDirectory(sidebarDir)

    // Group ICON_* textures into (family, scale) -> frames.
    var groups: [String: CursorFamily] = [:]
    for name in tex.names where name.hasPrefix(uiPrefix) {
        let rel = String(name.dropFirst(uiPrefix.count))
        guard !rel.contains("\\"), rel.uppercased().hasSuffix(".DDS") else { continue }
        let stem = String(rel.dropLast(4))
        guard stem.uppercased().hasPrefix("ICON_") else { continue }
        let (family, x2, number) = splitCursorStem(stem)
        let key = "\(family)\u{0}\(x2 ? 2 : 1)"
        groups[key, default: CursorFamily(family: family, scale: x2 ? 2 : 1, frames: [])].frames.append((number, name))
    }
    var families = groups.values.sorted {
        $0.family == $1.family ? $0.scale < $1.scale : pyLess($0.family, $1.family)
    }
    for i in families.indices {
        families[i].frames.sort { $0.number == $1.number ? pyLess($0.entry, $1.entry) : $0.number < $1.number }
    }

    var jobs: [UIJob] = families.indices.map { .cursor($0) }
    jobs += sidebarTextures.map { .sidebar($0) }
    if common != nil { jobs.append(.repairWrench) }
    var results = [UIResult?](repeating: nil, count: jobs.count)
    let resultsLock = NSLock()

    try ctx.runJobs(.hdUI, count: jobs.count, isCancelled: isCancelled) { i in
        var result = UIResult()
        let item: String
        switch jobs[i] {
        case .cursor(let f):
            let fam = families[f]
            item = fam.family + (fam.scale == 2 ? " x2" : "")
            let suffix = fam.scale == 2 ? "_X2" : ""
            for (index, frame) in fam.frames.enumerated() {
                // The output index counts skipped frames too, as enumerate() does in python.
                guard let raw = try tex.read(frame.entry), let img = decodeDDS(raw) else { continue }
                let url = cursorDir.appendingPathComponent(fam.family)
                    .appendingPathComponent("\(fam.family)\(suffix)-\(pad4(index)).png")
                try writeAtomically(encodePNG(img), to: url)
                result.count += 1; result.w = img.width; result.h = img.height
            }
        case .sidebar(let base):
            item = base
            if let raw = try tex.read(uiPrefix + base + ".DDS"), let img = decodeDDS(raw) {
                try writeAtomically(encodePNG(img), to: sidebarDir.appendingPathComponent(base + ".png"))
                result = UIResult(count: 1, w: img.width, h: img.height)
            } else {
                ctx.failed(base)
            }
        case .repairWrench:
            item = "UI_REPAIRING"
            if let raw = try common?.read("DATA\\ART\\TEXTURES\\SRGB\\COMMON\\UI\\UI_REPAIRING.TGA"), let img = decodeTGA(raw) {
                try writeAtomically(encodePNG(img), to: sidebarDir.appendingPathComponent("UI_REPAIRING.png"))
                result = UIResult(count: 1, w: img.width, h: img.height)
            } else {
                ctx.failed("UI_REPAIRING")
            }
        }
        if result.count > 0 { ctx.wrote(.hdUI) }
        resultsLock.lock(); results[i] = result; resultsLock.unlock()
        return item
    }

    // cursors.json — written after every frame is on disk.
    var familyEntries: [String: [(String, PyJSON)]] = [:]
    for (i, job) in jobs.enumerated() {
        guard case .cursor(let f) = job, let r = results[i], r.count > 0 else { continue }
        let fam = families[f]
        var entry = familyEntries[fam.family] ?? []
        if fam.scale == 2 {
            entry += [("x2_frames", .int(r.count)), ("x2_w", .int(r.w)), ("x2_h", .int(r.h))]
        } else {
            entry += [("frames", .int(r.count)), ("w", .int(r.w)), ("h", .int(r.h))]
        }
        familyEntries[fam.family] = entry
    }
    var pointers: [(String, PyJSON)] = []
    if let config {
        let hot1 = try parseMousePointers(config, "DATA\\XML\\MOUSEPOINTERS.XML")
        let hot2 = try parseMousePointers(config, "DATA\\XML\\MOUSEPOINTERSX2.XML")
        for (name, p) in hot1 where familyEntries[p.family] != nil {
            var rec: [(String, PyJSON)] = [("family", .string(p.family)), ("hotX", .int(p.hotX)), ("hotY", .int(p.hotY))]
            if let p2 = hot2[name] { rec += [("hotX_x2", .int(p2.hotX)), ("hotY_x2", .int(p2.hotY))] }
            pointers.append((name, .object(rec)))
        }
    }
    let cursorManifest = PyJSON.object([
        ("pointers", .object(pointers)),
        ("families", .object(familyEntries.map { ($0.key, .object($0.value)) })),
    ])
    try writeAtomically(cursorManifest.serialized(sortKeys: true), to: cursorDir.appendingPathComponent("cursors.json"))

    // sidebar.json
    var sidebar: [(String, PyJSON)] = []
    for (i, job) in jobs.enumerated() {
        guard let r = results[i], r.count > 0 else { continue }
        switch job {
        case .sidebar(let base): sidebar.append((base, .object([("w", .int(r.w)), ("h", .int(r.h))])))
        case .repairWrench: sidebar.append(("UI_REPAIRING", .object([("w", .int(r.w)), ("h", .int(r.h))])))
        case .cursor: break
        }
    }
    try writeAtomically(PyJSON.object(sidebar).serialized(sortKeys: true), to: sidebarDir.appendingPathComponent("sidebar.json"))
}

/// Python: re.match(r'(.*?)(_X2)?_(\d+)$', stem, re.I), else r'(.*?)(_X2)?$'.
/// Returns the uppercased family, whether it is the _X2 set, and the frame number.
private func splitCursorStem(_ stem: String) -> (String, Bool, Int) {
    let chars = Array(stem)
    func isX2(_ i: Int) -> Bool {
        i + 3 <= chars.count && chars[i] == "_" && (chars[i + 1] == "X" || chars[i + 1] == "x") && chars[i + 2] == "2"
    }
    func digits(from i: Int) -> Int? {
        guard i < chars.count, chars[i...].allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return Int(String(chars[i...]))
    }
    // Lazy prefix: the first split point where the rest matches (_X2)?_(\d+)$.
    for p in 0...chars.count {
        if isX2(p), p + 3 < chars.count, chars[p + 3] == "_", let n = digits(from: p + 4) {
            return (String(chars[..<p]).uppercased(), true, n)
        }
        if p < chars.count, chars[p] == "_", let n = digits(from: p + 1) {
            return (String(chars[..<p]).uppercased(), false, n)
        }
    }
    if chars.count >= 3, isX2(chars.count - 3) {
        return (String(chars[..<(chars.count - 3)]).uppercased(), true, 0)
    }
    return (stem.uppercased(), false, 0)
}

private struct Hotspot { let family: String; let hotX: Int; let hotY: Int }

/// `_parse_mouse_pointers`: pointer name -> texture family (upper, extension
/// stripped) + hotspot. Keeps the python dict's first-insertion order.
private func parseMousePointers(_ config: MEGArchive, _ name: String) throws -> OrderedHotspots {
    var out = OrderedHotspots()
    guard let raw = try config.read(name) else { return out }
    let text = String(decoding: raw, as: UTF8.self) as NSString
    let block = try! NSRegularExpression(
        pattern: #"<MousePointerDataClass\s+Name="([^"]+)">(.*?)</MousePointerDataClass>"#,
        options: [.dotMatchesLineSeparators])
    let texRE = try! NSRegularExpression(pattern: #"<BaseTextureName>\s*(\S+)\s*</BaseTextureName>"#)
    let hxRE = try! NSRegularExpression(pattern: #"<HotX>\s*(-?\d+)\s*</HotX>"#)
    let hyRE = try! NSRegularExpression(pattern: #"<HotY>\s*(-?\d+)\s*</HotY>"#)
    for m in block.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
        let pointer = text.substring(with: m.range(at: 1))
        let body = text.substring(with: m.range(at: 2)) as NSString
        let range = NSRange(location: 0, length: body.length)
        guard let t = texRE.firstMatch(in: body as String, range: range) else { continue }
        var family = body.substring(with: t.range(at: 1))
        if let dot = family.range(of: ".", options: .backwards) { family = String(family[..<dot.lowerBound]) }
        let hx = hxRE.firstMatch(in: body as String, range: range).flatMap { Int(body.substring(with: $0.range(at: 1))) } ?? 0
        let hy = hyRE.firstMatch(in: body as String, range: range).flatMap { Int(body.substring(with: $0.range(at: 1))) } ?? 0
        out[pointer] = Hotspot(family: family.uppercased(), hotX: hx, hotY: hy)
    }
    return out
}

/// A tiny insertion-ordered dictionary (python dict semantics: reassigning a
/// key keeps its original position).
private struct OrderedHotspots: Sequence {
    private var keys: [String] = []
    private var values: [String: Hotspot] = [:]
    subscript(key: String) -> Hotspot? {
        get { values[key] }
        set {
            if values[key] == nil { keys.append(key) }
            values[key] = newValue
        }
    }
    func makeIterator() -> AnyIterator<(String, Hotspot)> {
        var i = 0
        return AnyIterator {
            guard i < keys.count else { return nil }
            defer { i += 1 }
            return (keys[i], values[keys[i]]!)
        }
    }
}
