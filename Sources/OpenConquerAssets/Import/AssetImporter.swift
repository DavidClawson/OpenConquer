import Foundation

// MARK: - Native asset import (replaces the Python extractors for players)
//
// `extractRemasteredAssets` produces the same `extracted/` tree that
// install-assets.sh's python steps write, so a player who downloads the app
// never needs a terminal:
//
//   hdSprites  tools/extract_remastered_sprites.py (units/structures/vfx + rotors)
//              -> extracted/sprites_remastered/{units,structures,vfx}/
//   hdUI       the same script's `--category ui` (cursors, sidebar meters, wrench)
//              -> extracted/sprites_remastered/ui/{cursors,sidebar}/
//   hdAudio    tools/extract_remastered_audio.py -> extracted/audio_remastered/
//
// Deliberately NOT ported (nothing at runtime needs them):
//   - the per-sprite sheets (`<category>/<NAME>.png`): the renderer only reads
//     the per-frame PNGs and the JSON manifest;
//   - extract_audio.py's classic AUD->WAV dump (extracted/audio/): the game
//     decodes AUD straight from the MIX when no WAV exists (SoundLibrary), and
//     its decoder is the faithful one — the python IMA decoder resets its state
//     every chunk, so those WAVs are slightly off and would override it.
//
// Every file is written atomically (temp file + rename), frames before their
// manifest, so a cancelled or crashed import never leaves a half-written PNG
// and the renderer never indexes a sprite whose frames aren't all there.
// Re-running overwrites with identical output.

package enum ImportStep: String, CaseIterable {
    case hdSprites, hdUI, hdAudio
}

package struct ImportProgress {
    package let step: ImportStep
    package let done: Int
    package let total: Int
    package let item: String
}

package enum AssetImportError: Error, CustomStringConvertible {
    case cancelled
    case missingArchive(String)
    case invalidArchive(String, String)
    case writeFailed(String, String)

    package var description: String {
        switch self {
        case .cancelled: return "Import cancelled"
        case .missingArchive(let name): return "Missing \(name)"
        case .invalidArchive(let name, let why): return "\(name): \(why)"
        case .writeFailed(let path, let why): return "Could not write \(path): \(why)"
        }
    }
}

package struct ImportSummary {
    /// Items written per step (sprites, UI textures/families, audio files).
    package var written: [ImportStep: Int] = [:]
    /// Items the source data could not supply (the python scripts' "FAILED" lines).
    package var failures: [String] = []
}

/// Remastered `Data/` archives the import reads. TEXTURES_COMMON_SRGB.MEG (rotors,
/// repair wrench) is optional, as it is for the python scripts.
package let requiredRemasteredArchives = [
    "TEXTURES_TD_SRGB.MEG", "TEXTURES_SRGB.MEG", "CONFIG.MEG", "SFX3D.MEG", "SFX2D_EN-US.MEG", "MUSIC.MEG",
]

/// Which required archives are absent from `remasteredData` (empty = good to go).
package func missingRemasteredArchives(in remasteredData: URL) -> [String] {
    requiredRemasteredArchives.filter {
        !FileManager.default.fileExists(atPath: remasteredData.appendingPathComponent($0).path)
    }
}

/// Extract the HD sprites, UI art and audio from the Remastered Collection's
/// `Data/` folder into `dataDir/extracted/`.
///
/// Blocking and CPU-heavy: call it from a background thread. `progress` is
/// called from worker threads (never concurrently — calls are serialised) and
/// should hop to the main thread itself. `isCancelled` is polled before each
/// sprite / UI texture / audio file, from worker threads (one at a time), so it
/// must read a flag that is safe to set from another thread (an atomic or a
/// lock-guarded Bool). Once it returns true, jobs already running finish their
/// current file and the import throws `AssetImportError.cancelled` — typically
/// well under a second. Files already written stay (each is complete);
/// re-running the import overwrites everything.
///
/// Peak memory is roughly 0.7 GB on top of the caller's (ATOMSFX's 71 MB ZIP plus
/// a frame per core, then up to four music tracks decoding at once).
@discardableResult
package func extractRemasteredAssets(remasteredData: URL, dataDir: URL,
                                     progress: @escaping (ImportProgress) -> Void,
                                     isCancelled: () -> Bool) throws -> ImportSummary {
    let missing = missingRemasteredArchives(in: remasteredData)
    if let first = missing.first { throw AssetImportError.missingArchive(first) }

    let ctx = ImportContext(progress: progress)
    let extracted = dataDir.appendingPathComponent("extracted")
    let sprites = extracted.appendingPathComponent("sprites_remastered")
    try importHDSprites(remasteredData: remasteredData, outDir: sprites, ctx: ctx, isCancelled: isCancelled)
    try importHDUI(remasteredData: remasteredData, outDir: sprites, ctx: ctx, isCancelled: isCancelled)
    try importHDAudio(remasteredData: remasteredData, outDir: extracted.appendingPathComponent("audio_remastered"),
                      ctx: ctx, isCancelled: isCancelled)
    return ctx.summary
}

// MARK: - Shared plumbing

final class ImportContext {
    private let lock = NSLock()
    private let progressHandler: (ImportProgress) -> Void
    private(set) var summary = ImportSummary()

    init(progress: @escaping (ImportProgress) -> Void) { progressHandler = progress }

    func report(_ step: ImportStep, done: Int, total: Int, item: String) {
        lock.lock(); defer { lock.unlock() }
        progressHandler(ImportProgress(step: step, done: done, total: total, item: item))
    }

    func wrote(_ step: ImportStep, _ count: Int = 1) {
        lock.lock(); defer { lock.unlock() }
        summary.written[step, default: 0] += count
    }

    func failed(_ what: String) {
        lock.lock(); defer { lock.unlock() }
        summary.failures.append(what)
    }

    /// Run `count` independent jobs across all cores (at most `maxWorkers` at a
    /// time), reporting each completion as progress for `step`. Jobs are pulled in
    /// index order, so put the big ones first. The first `soloCount` jobs run one at
    /// a time instead — for jobs that parallelise internally and are big enough to be
    /// the critical path (a nested concurrentPerform gets no extra threads while the
    /// outer one has them all). A thrown error or cancellation stops new jobs from
    /// starting; the first error is rethrown once workers drain.
    func runJobs(_ step: ImportStep, count: Int, soloCount: Int = 0,
                 maxWorkers: Int = ProcessInfo.processInfo.activeProcessorCount,
                 isCancelled: () -> Bool, job: (Int) throws -> String) throws {
        report(step, done: 0, total: count, item: "")
        guard count > 0 else { return }
        let solo = min(soloCount, count)
        for index in 0..<solo {
            if isCancelled() { throw AssetImportError.cancelled }
            let item = try autoreleasepool { try job(index) }
            report(step, done: index + 1, total: count, item: item)
        }
        let state = NSLock()
        var next = solo, done = solo
        var firstError: Error?
        let workers = max(1, min(count - solo, maxWorkers))
        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            while true {
                state.lock()
                if firstError != nil || next >= count { state.unlock(); return }
                if isCancelled() {
                    firstError = firstError ?? AssetImportError.cancelled
                    state.unlock(); return
                }
                let index = next
                next += 1
                state.unlock()
                do {
                    let item = try autoreleasepool { try job(index) }
                    state.lock(); done += 1; let d = done; state.unlock()
                    report(step, done: d, total: count, item: item)
                } catch {
                    state.lock(); firstError = firstError ?? error; state.unlock()
                    return
                }
            }
        }
        if let firstError { throw firstError }
    }
}

/// Write via a temp file in the same directory + rename(2), so readers never
/// see a partial file; a killed import leaves at most a stray `.*.importtmp`.
/// No fsync (Foundation's Data.write does one per file, ~10% of the run):
/// a power cut mid-import just means re-running it.
func writeAtomically(_ data: Data, to url: URL) throws {
    let dir = url.deletingLastPathComponent()
    let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(getpid()).importtmp").path
    var fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if fd < 0 && errno == ENOENT {
        try makeDirectory(dir)
        fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    }
    guard fd >= 0 else { throw AssetImportError.writeFailed(url.path, String(cString: strerror(errno))) }
    var failure: String?
    data.withUnsafeBytes { raw in
        var done = 0
        while done < raw.count {
            let n = write(fd, raw.baseAddress! + done, raw.count - done)
            if n < 0 {
                if errno == EINTR { continue }
                failure = String(cString: strerror(errno)); return
            }
            done += n
        }
    }
    if close(fd) != 0 && failure == nil { failure = String(cString: strerror(errno)) }
    if failure == nil && Foundation.rename(tmp, url.path) != 0 { failure = String(cString: strerror(errno)) }
    if let failure {
        unlink(tmp)
        throw AssetImportError.writeFailed(url.path, failure)
    }
}

func makeDirectory(_ url: URL) throws {
    do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } catch {
        throw AssetImportError.writeFailed(url.path, error.localizedDescription)
    }
}

/// Python's default string order (code points; byte order for these ASCII names).
func pyLess(_ a: String, _ b: String) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }

/// `"%04d" % n`
func pad4(_ n: Int) -> String {
    let s = String(n)
    return s.count >= 4 || n < 0 ? s : String(repeating: "0", count: 4 - s.count) + s
}
