import Foundation

// MARK: - HD music / sfx / voices (SFX3D.MEG, SFX2D_EN-US.MEG, MUSIC.MEG)
//
// Port of tools/extract_remastered_audio.py: the remastered TDR_* WAVs (MS
// ADPCM) are decoded, downmixed to mono and written as 16-bit PCM
// `audio_remastered/<ENGINE NAME>.WAV`, which AssetManager.loadWAV prefers over
// everything else. The python script writes in a fixed order and later writes
// overwrite earlier ones (SFX3D in full, then the first SFX2D / MUSIC entry per
// engine name); that is resolved up front here so files decode in parallel.

private let musicMap: [String: String] = [
    "ACT_ON_INSTINCT": "AOI", "AIRSTRIKE": "AIRSTRIK", "CC_80S_MIX": "80MX", "CANYON_CHASE": "CHRG",
    "CREEPING_UPON": "CREP", "DRILL": "DRIL", "DRONE": "DRON", "IRON_FIST": "FIST", "RECON": "RECON",
    "VOICE_OF_ROME": "VOICE", "HEAVY_GLOVE": "HEAVYG", "JUST_DO_IT_UP": "JUSTDOIT", "CC_THANG": "CCTHANG",
    "DIE": "DIE", "FIGHT_WIN_PREVAIL": "FWP", "INDUSTRIAL": "IND", "INDUSTRIAL_2": "IND2",
    "IN_THE_LINE_OF_FIRE": "LINEFIRE", "MARCH_TO_YOUR_DOOM": "MARCH", "MECHANICAL_MAN": "J1", "JDI_V2": "JDI_V2",
    "NO_MERCY": "NOMERCY", "ON_THE_PROWL": "OTP", "PREPARE_FOR_BATTLE": "PRP", "REACHING_OUT": "ROUT",
    "DECEPTION": "HEART", "STOP_THEM": "STOPTHEM", "LOOKS_LIKE_TROUBLE": "TROUBLE", "WARFARE": "WARFARE",
    "ENEMIES_TO_BE_FEARED": "BFEARED", "I_AM": "IAM", "TARGET_MECHANICAL_MAN": "J1", "GREAT_SHOT": "WIN1",
    "MAP_SELECT": "MAP1", "RADIO": "RADIO", "RAIN_IN_THE_NIGHT": "RAIN", "RIDE_OF_THE_VALKYRIES": "VALKYRIE",
]

private let evaNames: Set<String> = [
    "ACCOM1", "FAIL1", "BLDG1", "CONSTRU1", "UNITREDY", "NEWOPT1", "DEPLOY1", "GDIDEAD1", "NODDEAD1", "CIVDEAD1",
    "NOCASH1", "BATLCON1", "REINFOR1", "CANCEL1", "BLDGING1", "LOPOWER1", "NOPOWER1", "MOCASH1", "BASEATK1",
    "INCOME1", "ENEMYA", "NUKE1", "NOBUILD1", "PRIBLDG1", "NODCAPT1", "GDICAPT1", "IONCHRG1", "IONREDY1",
    "NUKAVAIL", "NUKLNCH1", "UNITLOST", "STRCLOST", "NEEDHARV", "SELECT1", "AIRREDY1", "NOREDY1", "TRANSSEE",
    "TRANLOAD", "ENMYAPP1", "SILOS1", "ONHOLD1", "REPAIR1", "ESTRUCX", "GSTRUC1", "NSTRUC1", "ENMYUNIT",
]

/// `map_sfx3d_name`: TDR_SFX_BAZOOK1.WAV -> BAZOOK1
private func mapSFX3D(_ megName: String) -> String? {
    let base = megName.replacingOccurrences(of: ".WAV", with: "")
    return base.hasPrefix("TDR_SFX_") ? String(base.dropFirst(8)) : nil
}

/// `map_sfx2d_name`: EN-US\TDR_SFX_UNT_YESSIR1.V00_EN-US.WAV -> YESSIR1, EVA and commando likewise.
private func mapSFX2D(_ megName: String) -> String? {
    let leaf = megName.split(separator: "\\", omittingEmptySubsequences: false).last.map(String.init) ?? megName
    guard leaf.hasPrefix("TDR_SFX_") else { return nil }
    var base = leaf.replacingOccurrences(of: ".WAV", with: "")
    if base.hasSuffix("_EN-US") { base = String(base.dropLast(6)) }
    for suffix in ["_DE", "_FR", "_JA", "_KO", "_ZH"] where base.hasSuffix(suffix) { return nil }
    if base.hasPrefix("TDR_SFX_UNT_") {
        var name = String(base.dropFirst(12))
        for ext in [".V00", ".V01", ".V02", ".V03"] where name.contains(ext) {
            if ext != ".V00" { return nil }
            name = name.replacingOccurrences(of: ext, with: "")
            break
        }
        return name
    }
    if base.hasPrefix("TDR_SFX_EVA_") {
        let name = String(base.dropFirst(12))
        return evaNames.contains(name) ? name : nil
    }
    if base.hasPrefix("TDR_SFX_CMD_") { return String(base.dropFirst(12)) }
    return nil
}

/// `map_music_name`: DATA\AUDIO\MUSIC\TDR_MUS_ACT_ON_INSTINCT.WAV -> AOI
private func mapMusic(_ megName: String) -> String? {
    let leaf = megName.split(separator: "\\", omittingEmptySubsequences: false).last.map(String.init) ?? megName
    let base = leaf.replacingOccurrences(of: ".WAV", with: "")
    guard base.hasPrefix("TDR_MUS_") else { return nil }
    var track = String(base.dropFirst(8))
    for suffix in ["_OST_VERSION", "_FKTS", "_CO", "_SHORT"] where track.hasSuffix(suffix) {
        track = String(track.dropLast(suffix.count))
        break
    }
    return musicMap[track]
}

private struct AudioJob {
    let engineName: String
    /// Candidates in the python write order; the last one that decodes is what ends up on disk.
    var sources: [(meg: MEGArchive, entry: String)]
    var size: Int
}

func importHDAudio(remasteredData: URL, outDir: URL, ctx: ImportContext, isCancelled: () -> Bool) throws {
    try makeDirectory(outDir)
    var jobs: [AudioJob] = []
    var index: [String: Int] = [:]
    func add(_ engine: String, _ meg: MEGArchive, _ entry: String) {
        let size = meg.entries[entry]!.size
        if let i = index[engine] {
            jobs[i].sources.append((meg, entry))
            jobs[i].size = max(jobs[i].size, size)
        } else {
            index[engine] = jobs.count
            jobs.append(AudioJob(engineName: engine, sources: [(meg, entry)], size: size))
        }
    }

    let sfx3d = try MEGArchive(url: remasteredData.appendingPathComponent("SFX3D.MEG"))
    for name in sfx3d.names.sorted(by: pyLess) {
        if let engine = mapSFX3D(name) { add(engine, sfx3d, name) }
    }
    for (file, mapper) in [("SFX2D_EN-US.MEG", mapSFX2D), ("MUSIC.MEG", mapMusic)] as [(String, (String) -> String?)] {
        let meg = try MEGArchive(url: remasteredData.appendingPathComponent(file))
        var seen = Set<String>()  // first entry per engine name only, within this MEG
        for name in meg.names.sorted(by: pyLess) {
            guard let engine = mapper(name), seen.insert(engine).inserted else { continue }
            add(engine, meg, name)
        }
    }

    jobs.sort { $0.size > $1.size }  // the music tracks first
    // Bounded: a stereo music track briefly holds ~100 MB of decoded samples.
    try ctx.runJobs(.hdAudio, count: jobs.count, maxWorkers: 4, isCancelled: isCancelled) { i in
        let job = jobs[i]
        for source in job.sources.reversed() {
            guard let raw = try source.meg.read(source.entry), let wav = decodeRemasteredWAV(raw) else {
                ctx.failed(source.entry)
                continue
            }
            let samples = downmixToMono(wav.samples, channels: wav.channels)
            let data = encodePCMWAV(samples: samples, sampleRate: wav.sampleRate, channels: wav.channels > 1 ? 1 : wav.channels)
            try writeAtomically(data, to: outDir.appendingPathComponent("\(job.engineName).WAV"))
            ctx.wrote(.hdAudio)
            break
        }
        return job.engineName
    }
}
