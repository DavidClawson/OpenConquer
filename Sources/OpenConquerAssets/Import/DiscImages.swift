import Foundation

// MARK: - The freeware disc images
//
// EA made the Win95 release free in 2007 as two disc images, one per side,
// each zipped: GDI95.zip and NOD95.zip. EA no longer hosts them; fan sites
// such as CnCNZ do. The setup screen sends the player there in their browser
// and picks the downloads up from their Downloads folder. Importing one
// unzips the image (if zipped) into a scratch folder, mounts it read-only
// with hdiutil, copies the archives off it like any disc folder, then
// detaches it and removes the scratch copy.

/// A disc image (.iso, or a .zip holding one) of the original game.
package struct DiscImage: Equatable {
    package let file: URL
    /// From the file name; checked against the disc itself when it's opened.
    package let side: OriginalDisc.Side?

    package init(file: URL, side: OriginalDisc.Side?) {
        self.file = file
        self.side = side
    }

    /// The page the setup screen sends players to for the free release.
    package static let freewarePage = URL(string: "https://cncnz.com/features/freeware-classic-command-conquer-games/")!

    /// `url` as a disc image: a .iso, or a .zip, big enough to be a CD.
    package static func identify(_ url: URL) -> DiscImage? {
        let ext = url.pathExtension.lowercased()
        guard ext == "iso" || ext == "zip" else { return nil }
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 100 << 20 else { return nil }
        let name = url.deletingPathExtension().lastPathComponent.uppercased()
        let side: OriginalDisc.Side? = name.contains("GDI") ? .gdi : name.contains("NOD") ? .nod : nil
        // A zip must be a side's disc by name; any big zip isn't a game.
        if ext == "zip" && side == nil { return nil }
        return DiscImage(file: url, side: side)
    }

    /// Disc images in Downloads (and the folders a browser may have unzipped
    /// them into), one per side, preferring a plain .iso over a .zip.
    package static func searchDownloads() -> [DiscImage] {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        var candidates = items(in: downloads)
        for folder in candidates where folder.hasDirectoryPath || isDirectory(folder) {
            let name = folder.lastPathComponent.uppercased()
            if name.contains("GDI") || name.contains("NOD") { candidates += items(in: folder) }
        }
        var found: [OriginalDisc.Side: DiscImage] = [:]
        for url in candidates {
            guard let image = identify(url), let side = image.side else { continue }
            if let have = found[side], have.file.pathExtension.lowercased() == "iso" { continue }
            found[side] = image
        }
        return [found[.gdi], found[.nod]].compactMap { $0 }
    }

    /// Downloads of a side's disc still in progress (Safari's .download,
    /// Chrome's .crdownload, Firefox's .part), by file name.
    package static func downloadsInProgress() -> [String] {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        return items(in: downloads).compactMap { url in
            let name = url.lastPathComponent
            let upper = name.uppercased()
            guard ["DOWNLOAD", "CRDOWNLOAD", "PART"].contains(url.pathExtension.uppercased()),
                  upper.contains("GDI") || upper.contains("NOD") else { return nil }
            return url.deletingPathExtension().lastPathComponent
        }
    }

    private static func items(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles])) ?? []
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    // MARK: Opening

    /// The image opened as a disc folder. `close` detaches it and deletes the
    /// scratch copy; call it when done, also after a failure.
    package struct Opened {
        package let disc: OriginalDisc
        package let close: () -> Void
    }

    package enum OpenError: LocalizedError {
        case noImageInZip(String)
        case mountFailed(String)
        case notTheGame(String)

        package var errorDescription: String? {
            switch self {
            case .noImageInZip(let name): return "\(name) has no disc image (.iso) in it."
            case .mountFailed(let name): return "macOS couldn't open the disc image \(name)."
            case .notTheGame(let name): return "\(name) isn't a Command & Conquer GDI or Nod disc."
            }
        }
    }

    /// Unzips (if needed) into `scratch` and mounts the image read-only.
    /// `progress` gets 0...1 while unzipping.
    package func open(scratch: URL, progress: (Double) -> Void, isCancelled: () -> Bool) throws -> Opened {
        let fm = FileManager.default
        let work = scratch.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        var mounted: URL?
        let close = {
            if let mounted { _ = try? Self.run("/usr/bin/hdiutil", ["detach", mounted.path, "-force", "-quiet"]) }
            try? fm.removeItem(at: work)
        }
        do {
            var iso = file
            if file.pathExtension.lowercased() == "zip" {
                iso = try unzipImage(into: work, progress: progress, isCancelled: isCancelled)
            }
            let mountPoint = work.appendingPathComponent("disc")
            try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            let (status, _) = try Self.run("/usr/bin/hdiutil", ["attach", iso.path, "-readonly", "-nobrowse",
                                                                "-noverify", "-noautoopen", "-mountpoint", mountPoint.path])
            guard status == 0 else { throw OpenError.mountFailed(file.lastPathComponent) }
            mounted = mountPoint
            guard let disc = OriginalDisc.resolve(mountPoint) else { throw OpenError.notTheGame(file.lastPathComponent) }
            return Opened(disc: disc, close: close)
        } catch {
            close()
            throw error
        }
    }

    /// Extracts the zip's .iso with the system unzip, reporting progress by
    /// how much of it has been written.
    private func unzipImage(into work: URL, progress: (Double) -> Void, isCancelled: () -> Bool) throws -> URL {
        // `unzip -Z1` lists the entry names; `-l` gives sizes.
        let (_, listing) = try Self.run("/usr/bin/unzip", ["-l", file.path])
        guard let line = listing.split(separator: "\n").first(where: { $0.lowercased().hasSuffix(".iso") }) else {
            throw OpenError.noImageInZip(file.lastPathComponent)
        }
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        let expected = Double(fields.first.flatMap { Int64($0) } ?? 0)
        let entry = fields.dropFirst(3).joined(separator: " ")
        let out = work.appendingPathComponent("disc.iso")

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-p", file.path, entry]
        FileManager.default.createFile(atPath: out.path, contents: nil)
        let handle = try FileHandle(forWritingTo: out)
        defer { try? handle.close() }
        unzip.standardOutput = handle
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        while unzip.isRunning {
            if isCancelled() {
                unzip.terminate()
                unzip.waitUntilExit()
                throw CocoaError(.userCancelled)
            }
            let written = ((try? FileManager.default.attributesOfItem(atPath: out.path))?[.size] as? NSNumber)?.doubleValue ?? 0
            progress(expected > 0 ? written / expected : 0)
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard unzip.terminationStatus == 0 else { throw OpenError.noImageInZip(file.lastPathComponent) }
        return out
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self))
    }
}
