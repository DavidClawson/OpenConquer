import Foundation

// MARK: - Finding the player's C&C Remastered Collection
//
// The importer's first job: find the Remastered Collection's `Data/` folder.
// On a Mac it is usually a copy from a PC, or a Windows install inside a
// CrossOver or Whisky bottle, so besides the paths install-assets.sh probes we
// look inside bottles and at the top of external drives. A folder the player
// picks or drops can be the install folder, its `Data/` folder, or a Steam
// library folder above it.

/// A Remastered Collection install we can import from.
package struct RemasteredInstall: Equatable {
    /// The install's `Data/` folder.
    package let dataDir: URL
    /// True when the HD art and audio archives are there too (the classic
    /// archives alone are enough to play).
    package let hasHD: Bool

    /// The HD archives the extractors read.
    package static let hdArchives = ["TEXTURES_TD_SRGB.MEG", "TEXTURES_SRGB.MEG", "TEXTURES_COMMON_SRGB.MEG",
                                     "CONFIG.MEG", "SFX3D.MEG", "SFX2D_EN-US.MEG", "MUSIC.MEG"]

    var classicDir: URL { dataDir.appendingPathComponent("CNCDATA/TIBERIAN_DAWN") }
}

package enum RemasteredLocator {
    /// The folder names a Remastered install goes by.
    private static let installNames = ["CnCRemastered", "Command and Conquer Remastered Collection",
                                       "Command & Conquer Remastered Collection"]

    /// `url` as an install: the Data folder itself, the folder holding `Data/`,
    /// or a Steam library / steamapps / common folder above it.
    package static func resolve(_ url: URL) -> RemasteredInstall? {
        let url = url.standardizedFileURL
        var candidates = [url, url.appendingPathComponent("Data")]
        for prefix in ["", "steamapps/common/", "common/"] {
            for name in installNames {
                candidates.append(url.appendingPathComponent(prefix + name + "/Data"))
            }
        }
        // A folder inside Data (CNCDATA, or TIBERIAN_DAWN) picked by mistake.
        candidates.append(url.deletingLastPathComponent())
        candidates.append(url.deletingLastPathComponent().deletingLastPathComponent())
        for dir in candidates where isDataDir(dir) {
            let fm = FileManager.default
            let hd = RemasteredInstall.hdArchives.allSatisfy { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
            return RemasteredInstall(dataDir: dir, hasHD: hd)
        }
        return nil
    }

    private static func isDataDir(_ dir: URL) -> Bool {
        let td = dir.appendingPathComponent("CNCDATA/TIBERIAN_DAWN")
        let fm = FileManager.default
        return fm.fileExists(atPath: td.appendingPathComponent("CD1/CONQUER.MIX").path)
            && fm.fileExists(atPath: td.appendingPathComponent("CD2").path)
    }

    /// Every install found in the usual places, best first (with HD art).
    package static func search() -> [RemasteredInstall] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var roots: [URL] = [
            home.appendingPathComponent("CnCRemastered"),
            home.appendingPathComponent("Library/Application Support/Steam"),
            home.appendingPathComponent("Library/Application Support/Electronic Arts/Command and Conquer Remastered Collection"),
            home.appendingPathComponent("Applications/Command and Conquer Remastered Collection"),
            home.appendingPathComponent("Games"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            URL(fileURLWithPath: "/Applications/Command and Conquer Remastered Collection"),
        ]
        // Windows installs inside CrossOver / Whisky bottles.
        let bottleHomes = [
            home.appendingPathComponent("Library/Application Support/CrossOver/Bottles"),
            home.appendingPathComponent("Library/Containers/com.isaacmarovitz.Whisky/Bottles"),
        ]
        let windowsDirs = ["Program Files (x86)/Steam", "Program Files/Steam",
                           "Program Files/EA Games", "Program Files (x86)/EA Games",
                           "Program Files/Electronic Arts", "Program Files (x86)/Origin Games",
                           "Program Files/Origin Games"]
        for bottles in bottleHomes {
            for bottle in subfolders(bottles) {
                let c = bottle.appendingPathComponent("drive_c")
                roots += windowsDirs.map { c.appendingPathComponent($0) }
            }
        }
        // The top of external drives (a Steam library or a copied folder).
        for volume in subfolders(URL(fileURLWithPath: "/Volumes")) {
            roots += [volume, volume.appendingPathComponent("SteamLibrary"),
                      volume.appendingPathComponent("Games")]
        }

        var found: [RemasteredInstall] = []
        for root in roots where fm.fileExists(atPath: root.path) {
            if let install = resolve(root), !found.contains(install) {
                found.append(install)
            }
        }
        return found.sorted { $0.hasHD && !$1.hasHD }
    }

    private static func subfolders(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles])) ?? []
    }
}

// MARK: - Step 1: the classic archives

/// install-assets.sh's step 1: the classic MIX archives from CNCDATA, the
/// shared ones from CD1 (the GDI disc) into the data folder and the
/// side-specific ones from CD1 / CD2 (Nod) into gdi/ and nod/.
package enum ClassicArchiveImport {
    /// Shared archives. UPDATEC.MIX and the ICNH archives are the hi-res
    /// sidebar and cameos; CCLOCAL/UPDATE/UPDATA/TRANSIT.MIX the Win95
    /// release's fonts, strings, title and choose-your-side art.
    package static let shared = ["CONQUER.MIX", "DESERT.MIX", "TEMPERAT.MIX", "WINTER.MIX", "LOCAL.MIX",
                                 "SOUNDS.MIX", "SPEECH.MIX", "UPDATEC.MIX", "TEMPICNH.MIX", "DESEICNH.MIX",
                                 "WINTICNH.MIX", "CCLOCAL.MIX", "UPDATE.MIX", "UPDATA.MIX", "TRANSIT.MIX"]
    /// One copy per side.
    package static let perSide = ["GENERAL.MIX", "SCORES.MIX", "MOVIES.MIX"]

    /// (source, destination) for every archive, in copy order.
    package static func plan(from install: RemasteredInstall, to dataDir: URL) -> [(URL, URL)] {
        let cd1 = install.classicDir.appendingPathComponent("CD1")
        let cd2 = install.classicDir.appendingPathComponent("CD2")
        var plan = shared.map { (cd1.appendingPathComponent($0), dataDir.appendingPathComponent($0)) }
        for name in perSide {
            plan.append((cd1.appendingPathComponent(name), dataDir.appendingPathComponent("gdi/" + name)))
            plan.append((cd2.appendingPathComponent(name), dataDir.appendingPathComponent("nod/" + name)))
        }
        return plan
    }

    /// The source archives that aren't there.
    package static func missing(in install: RemasteredInstall) -> [String] {
        plan(from: install, to: URL(fileURLWithPath: "/")).compactMap { src, _ in
            FileManager.default.fileExists(atPath: src.path) ? nil
                : src.path.replacingOccurrences(of: install.dataDir.path + "/", with: "")
        }
    }

    /// Copies the archives, skipping any already there at the same size.
    /// Each lands under a temporary name and is renamed into place, so a
    /// cancelled import never leaves a truncated archive. `progress` gets
    /// (bytes done, bytes total, archive name).
    package static func run(from install: RemasteredInstall, to dataDir: URL,
                            progress: (Int64, Int64, String) -> Void, isCancelled: () -> Bool) throws {
        let fm = FileManager.default
        let plan = plan(from: install, to: dataDir)
        func size(_ url: URL) -> Int64 {
            ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? -1
        }
        let total = plan.reduce(Int64(0)) { $0 + max(0, size($1.0)) }
        var done: Int64 = 0
        for (src, dst) in plan {
            if isCancelled() { throw CocoaError(.userCancelled) }
            let n = size(src)
            let name = dst.path.replacingOccurrences(of: dataDir.path + "/", with: "")
            progress(done, total, name)
            if n >= 0 && size(dst) != n {
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                let part = dst.appendingPathExtension("part")
                try? fm.removeItem(at: part)
                try copy(src, to: part, isCancelled: isCancelled) { progress(done + $0, total, name) }
                _ = try fm.replaceItemAt(dst, withItemAt: part)
            }
            done += max(0, n)
        }
        progress(total, total, "")
    }

    /// A chunked copy, so a large MOVIES.MIX reports progress and can be cancelled.
    private static func copy(_ src: URL, to dst: URL, isCancelled: () -> Bool,
                             copied report: (Int64) -> Void) throws {
        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        let output = try FileHandle(forWritingTo: dst)
        defer { try? output.close() }
        var copied: Int64 = 0
        while let chunk = try input.read(upToCount: 8 << 20), !chunk.isEmpty {
            if isCancelled() {
                try? output.close()
                try? FileManager.default.removeItem(at: dst)
                throw CocoaError(.userCancelled)
            }
            try output.write(contentsOf: chunk)
            copied += Int64(chunk.count)
            report(copied)
        }
    }
}
