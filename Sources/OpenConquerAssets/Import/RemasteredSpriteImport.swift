import Foundation

// MARK: - HD unit / structure / vfx sprites (TEXTURES_TD_SRGB.MEG)
//
// Port of `extract_sprite_zip` + `categorize_meg_entries` + the rotor pass in
// tools/extract_remastered_sprites.py. Each sprite is a ZIP of cropped 32-bit
// TGA frames plus `.meta` JSON ({"size": [W, H], "crop": [L, T, R, B]}); every
// frame is pasted back onto its full canvas and written as
// `<category>/<NAME>/<NAME>-NNNN.png`, then `<category>/<NAME>.json` (read by
// Rendering/RemasteredSprites.swift: canvas_width, canvas_height, frame_count).
// The python sprite sheet `<category>/<NAME>.png` is not produced — nothing
// reads it.

private let tdPrefix = "DATA\\ART\\TEXTURES\\SRGB\\TIBERIAN_DAWN\\"
private let commonVFXPrefix = "DATA\\ART\\TEXTURES\\SRGB\\COMMON\\VFX\\"
private let commonVFX = ["LROTOR", "RROTOR"]

private struct SpriteJob {
    let name: String
    let outDir: URL
    /// Archives to extract from, in the python script's write order (a later
    /// successful source overwrites an earlier one).
    var sources: [(meg: MEGArchive, entry: String)]
    var size: Int
}

func importHDSprites(remasteredData: URL, outDir: URL, ctx: ImportContext, isCancelled: () -> Bool) throws {
    let td = try MEGArchive(url: remasteredData.appendingPathComponent("TEXTURES_TD_SRGB.MEG"))
    let commonURL = remasteredData.appendingPathComponent("TEXTURES_COMMON_SRGB.MEG")
    let common = FileManager.default.fileExists(atPath: commonURL.path) ? try MEGArchive(url: commonURL) : nil

    // categorize_meg_entries: name -> MEG path per category (a later duplicate wins).
    var categories: [String: [String: String]] = ["units": [:], "structures": [:], "vfx": [:]]
    for name in td.names where name.hasPrefix(tdPrefix) {
        let rel = String(name.dropFirst(tdPrefix.count))
        guard rel.uppercased().hasSuffix(".ZIP") else { continue }
        let category: String
        if rel.hasPrefix("UNITS\\") { category = "units" }
        else if rel.hasPrefix("STRUCTURES\\") { category = "structures" }
        else if rel.hasPrefix("VFX\\") { category = "vfx" }
        else { continue }
        let leaf = rel.split(separator: "\\", omittingEmptySubsequences: false).last.map(String.init) ?? rel
        let sprite = leaf.replacingOccurrences(of: ".ZIP", with: "").replacingOccurrences(of: ".zip", with: "").uppercased()
        categories[category]![sprite] = name
    }

    var jobs: [SpriteJob] = []
    var vfxIndex: [String: Int] = [:]
    for category in ["units", "structures", "vfx"] {
        let dir = outDir.appendingPathComponent(category)
        try makeDirectory(dir)
        for (sprite, entry) in categories[category]!.sorted(by: { pyLess($0.key, $1.key) }) {
            if category == "vfx" { vfxIndex[sprite] = jobs.count }
            jobs.append(SpriteJob(name: sprite, outDir: dir, sources: [(td, entry)], size: td.entries[entry]!.size))
        }
    }
    // Helicopter rotors are shared with Red Alert and live in the common MEG.
    if let common {
        let dir = outDir.appendingPathComponent("vfx")
        for sprite in commonVFX {
            let entry = commonVFXPrefix + sprite + ".ZIP"
            guard let e = common.entries[entry] else { ctx.failed("\(sprite) (common)"); continue }
            if let i = vfxIndex[sprite] {
                jobs[i].sources.append((common, entry))
                jobs[i].size += e.size
            } else {
                jobs.append(SpriteJob(name: sprite, outDir: dir, sources: [(common, entry)], size: e.size))
            }
        }
    }

    // Biggest first keeps every core busy to the end. A sprite bigger than a
    // twentieth of the total (ATOMSFX alone is ~70 MB of a ~300 MB set) would
    // still be the critical path on one core, so those go first, one at a time,
    // with their frames spread across all cores.
    jobs.sort { $0.size > $1.size }
    let total = jobs.reduce(0) { $0 + $1.size }
    let solo = jobs.prefix { $0.size * 20 > total }.count
    try ctx.runJobs(.hdSprites, count: jobs.count, soloCount: solo, isCancelled: isCancelled) { i in
        let job = jobs[i]
        var ok = false
        for source in job.sources {
            guard let zip = try source.meg.read(source.entry) else { continue }
            if try extractSpriteZIP(zip, name: job.name, outDir: job.outDir) { ok = true }
        }
        if ok { ctx.wrote(.hdSprites) } else { ctx.failed(job.name) }
        return job.name
    }
}

private struct FrameFiles { var tga: String?; var meta: String? }

/// `extract_sprite_zip` without the sheet. Returns false when the ZIP yields no frames.
private func extractSpriteZIP(_ bytes: [UInt8], name: String, outDir: URL) throws -> Bool {
    guard let zip = ZIPArchive(bytes: bytes) else { return false }

    var frames: [Int: FrameFiles] = [:]
    for entry in zip.entries {
        let member = entry.name
        let base = member.range(of: ".", options: .backwards).map { String(member[..<$0.lowerBound]) } ?? member
        guard let number = frameNumber(base) else { continue }
        let lower = member.lowercased()
        if lower.hasSuffix(".tga") { frames[number, default: FrameFiles()].tga = member }
        else if lower.hasSuffix(".meta") { frames[number, default: FrameFiles()].meta = member }
    }
    guard !frames.isEmpty else { return false }
    let sorted = frames.sorted { $0.key < $1.key }

    // Canvas size: from the metas (skipping 1x1 placeholders), else the largest TGA.
    var canvasW = 0, canvasH = 0
    if sorted.contains(where: { $0.value.meta != nil }) {
        for (_, files) in sorted {
            guard let metaName = files.meta else { continue }
            guard let meta = readMeta(zip, metaName) else { return false }
            let (mw, mh) = meta.size
            let crop = meta.crop ?? [0, 0, mw, mh]
            canvasW = max(canvasW, mw, crop.count > 2 ? crop[2] : mw)
            canvasH = max(canvasH, mh, crop.count > 3 ? crop[3] : mh)
            if mw > 1 && mh > 1 { break }
        }
    } else {
        for (_, files) in sorted {
            guard let t = files.tga, let tga = zip.read(t), tga.count >= 18 else { continue }
            canvasW = max(canvasW, Int(tga[12]) | Int(tga[13]) << 8)
            canvasH = max(canvasH, Int(tga[14]) | Int(tga[15]) << 8)
        }
        if canvasW == 0 || canvasH == 0 { return false }
    }

    let spriteDir = outDir.appendingPathComponent(name)
    try makeDirectory(spriteDir)
    // Frames are independent: decode, paste and encode them across all cores
    // (one sprite — ATOMSFX — is a 71 MB ZIP and would otherwise be the whole
    // critical path), then assemble the manifest in frame order.
    enum Outcome { case skipped, invalid, written(PyJSON) }
    func render(_ number: Int, _ files: FrameFiles) throws -> Outcome {
        guard let tgaName = files.tga, let tgaBytes = zip.read(tgaName), let tga = decodeTGA(tgaBytes) else { return .skipped }
        var canvas: RGBAImage
        let crop: [Int]
        let cropJSON: PyJSON
        if let metaName = files.meta {
            guard let meta = readMeta(zip, metaName), let c = meta.crop, c.count >= 2 else { return .invalid }
            let w = max(meta.size.0, c.count > 2 ? c[2] : meta.size.0)
            let h = max(meta.size.1, c.count > 3 ? c[3] : meta.size.1)
            canvas = RGBAImage(width: w, height: h)
            canvas.paste(tga, x: c[0], y: c[1])
            crop = c
            cropJSON = meta.cropJSON!
        } else {
            if tga.width == canvasW && tga.height == canvasH {
                canvas = tga
            } else {
                canvas = RGBAImage(width: canvasW, height: canvasH)
                canvas.paste(tga, x: floorDiv(canvasW - tga.width, 2), y: floorDiv(canvasH - tga.height, 2))
            }
            crop = [0, 0, tga.width, tga.height]
            cropJSON = .array(crop.map { .int($0) })
        }
        try writeAtomically(encodePNG(canvas), to: spriteDir.appendingPathComponent("\(name)-\(pad4(number)).png"))
        return .written(.object([
            ("frame", .int(number)),
            ("crop", cropJSON),
            ("crop_w", .int((crop.count > 2 ? crop[2] : 0) - crop[0])),
            ("crop_h", .int((crop.count > 3 ? crop[3] : 0) - crop[1])),
        ]))
    }

    var outcomes = [Outcome](repeating: .skipped, count: sorted.count)
    var firstError: Error?
    let errorLock = NSLock()
    outcomes.withUnsafeMutableBufferPointer { slots in
        DispatchQueue.concurrentPerform(iterations: sorted.count) { k in
            autoreleasepool {
                do {
                    slots[k] = try render(sorted[k].key, sorted[k].value)
                } catch {
                    errorLock.lock(); firstError = firstError ?? error; errorLock.unlock()
                }
            }
        }
    }
    if let firstError { throw firstError }
    var frameMeta: [PyJSON] = []
    for outcome in outcomes {
        switch outcome {
        case .skipped: continue
        case .invalid: return false
        case .written(let meta): frameMeta.append(meta)
        }
    }
    guard !frameMeta.isEmpty else { return false }

    let manifest = PyJSON.object([
        ("name", .string(name)),
        ("canvas_width", .int(canvasW)),
        ("canvas_height", .int(canvasH)),
        ("frame_count", .int(frameMeta.count)),
        ("frames", .array(frameMeta)),
    ])
    try writeAtomically(manifest.serialized(), to: outDir.appendingPathComponent("\(name).json"))
    return true
}

/// Frame number from a member's base name: "e1-0000" or "armor_0000"
/// (python: rsplit on '-' if the tail is all digits, else rsplit on '_', then int()).
private func frameNumber(_ base: String) -> Int? {
    func tail(after sep: Character) -> Substring? {
        guard let i = base.lastIndex(of: sep) else { return nil }
        return base[base.index(after: i)...]
    }
    if let t = tail(after: "-"), !t.isEmpty, t.allSatisfy(\.isASCIIDigit) { return Int(t) }
    guard let t = tail(after: "_") else { return nil }
    return Int(t.trimmingCharacters(in: .whitespaces))
}

private struct SpriteMeta {
    let size: (Int, Int)
    let crop: [Int]?
    let cropJSON: PyJSON?
}

private func readMeta(_ zip: ZIPArchive, _ name: String) -> SpriteMeta? {
    guard let bytes = zip.read(name),
          let obj = try? JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any],
          let size = obj["size"] as? [Any], size.count >= 2,
          let w = (size[0] as? NSNumber)?.intValue, let h = (size[1] as? NSNumber)?.intValue else { return nil }
    var crop: [Int]?
    var cropJSON: PyJSON?
    if let c = obj["crop"] as? [Any] {
        crop = c.compactMap { ($0 as? NSNumber)?.intValue }
        cropJSON = PyJSON(foundation: c)
    }
    return SpriteMeta(size: (w, h), crop: crop, cropJSON: cropJSON)
}

private func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
