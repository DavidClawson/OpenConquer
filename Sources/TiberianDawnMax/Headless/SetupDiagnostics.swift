import CSDL2
import Foundation
import OpenConquerAssets

// --test-setup OUTDIR
// Drives the setup screen headlessly. Snapshots its four cases — the
// Remastered Collection found with HD (setup-hd.png), one missing its HD
// archives (setup-partial.png), the original game's discs (setup-discs.png)
// and nothing found (setup-none.png) — then imports from the discs and from
// the Remastered Collection into the data folder, checking every classic
// archive arrives. Run it with OPENCONQUER_DATA_DIR pointing at a scratch
// folder (it refuses the real one). The partial install and the discs are
// symlink folders under OUTDIR built from the real install's CD1/CD2.
// Needs SDL_Init(VIDEO) and a Remastered install.

func runSetupDiagnosticsIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--test-setup") else { return nil }
    guard i + 1 < args.count else {
        print("usage: OPENCONQUER_DATA_DIR=/scratch/dir --test-setup OUTDIR")
        return 2
    }
    let fm = FileManager.default
    let outDir = URL(fileURLWithPath: args[i + 1])
    try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
    guard !dataPath.path.hasPrefix(fm.homeDirectoryForCurrentUser.path + "/Library/Application Support/Vanilla-Conquer") else {
        print("FAIL: set OPENCONQUER_DATA_DIR to a scratch folder; this imports into it")
        return 2
    }

    let w: Int32 = 1280, h: Int32 = 800
    guard let surface = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, 0x16362004 /* ARGB8888 */),
          let renderer = SDL_CreateSoftwareRenderer(surface) else {
        print("FAIL: no software renderer: \(String(cString: SDL_GetError()))")
        return 1
    }
    defer {
        SDL_DestroyRenderer(renderer)
        SDL_FreeSurface(surface)
    }
    renderState.windowWidth = w
    renderState.windowHeight = h

    func snapshot(_ screen: SetupScreen, _ name: String) -> Bool {
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
        SDL_RenderClear(renderer)
        screen.render(renderer)
        var rgba = [UInt8](repeating: 0, count: Int(w) * Int(h) * 4)
        let ok = rgba.withUnsafeMutableBytes {
            SDL_RenderReadPixels(renderer, nil, 0x16762004 /* ABGR8888 = RGBA bytes */, $0.baseAddress, w * 4)
        }
        return ok == 0 && writeRGBAPNG(rgba: rgba, width: Int(w), height: Int(h), to: outDir.appendingPathComponent(name))
    }

    /// Imports whatever the screen has chosen; true when it finished.
    func runImport(_ screen: SetupScreen, shot: String?) -> Bool {
        var imported = false
        screen.onImported = { imported = true }
        let start = Date()
        screen.startImport()
        var shotTaken = shot == nil
        while !imported {
            Thread.sleep(forTimeInterval: 0.05)
            if !shotTaken, let shot {
                shotTaken = snapshot(screen, shot)
            } else {
                screen.render(renderer)  // polls the job
            }
            if let message = screen.failureMessage {
                _ = snapshot(screen, "setup-failed.png")
                print("FAIL: \(message)")
                return false
            }
            if Date().timeIntervalSince(start) > 1800 { print("FAIL: import timed out"); return false }
        }
        print(String(format: "  import finished in %.1f s", Date().timeIntervalSince(start)))
        return true
    }

    func check(_ plan: [(URL, URL)], _ what: String) -> Bool {
        let missing = plan.filter { !fm.fileExists(atPath: $0.1.path) }
        guard missing.isEmpty else {
            print("FAIL: \(what): not copied: \(missing.map(\.1.lastPathComponent))")
            return false
        }
        assetManager.initialize()
        print("  \(what): \(plan.count) archives in place, \(assetManager.mixManager.totalEntries) MIX entries")
        return assetManager.mixManager.totalEntries > 0
    }

    let installs = RemasteredLocator.search()
    print("found \(installs.count) install(s): " + installs.map { "\($0.dataDir.path)\($0.hasHD ? " (HD)" : "")" }.joined(separator: ", "))
    guard let install = installs.first(where: \.hasHD) else {
        _ = snapshot(SetupScreen(), "setup-none.png")
        print("no Remastered install with HD found — wrote setup-none.png only")
        return 0
    }

    // Symlink folders standing in for a half-downloaded install and the discs.
    func link(_ src: URL, _ dst: URL) {
        try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: dst)
        try? fm.createSymbolicLink(at: dst, withDestinationURL: src)
    }
    let cncdata = install.dataDir.appendingPathComponent("CNCDATA")
    let partial = outDir.appendingPathComponent("fixtures/Partial/Data")
    link(cncdata, partial.appendingPathComponent("CNCDATA"))
    for meg in RemasteredInstall.hdArchives.prefix(3) {
        link(install.dataDir.appendingPathComponent(meg), partial.appendingPathComponent(meg))
    }
    var discFolders: [URL] = []
    for (side, cd) in [("GDI", "CD1"), ("NOD", "CD2")] {
        let disc = outDir.appendingPathComponent("fixtures/\(side)")
        let src = cncdata.appendingPathComponent("TIBERIAN_DAWN/\(cd)")
        for name in ClassicArchiveImport.shared + ClassicArchiveImport.perSide
            where fm.fileExists(atPath: src.appendingPathComponent(name).path) {
            // Lower case, as a copied CD often is.
            link(src.appendingPathComponent(name), disc.appendingPathComponent(name.lowercased()))
        }
        discFolders.append(disc)
    }

    let screen = SetupScreen()
    guard snapshot(screen, "setup-hd.png") else { print("FAIL: snapshot"); return 1 }
    screen.testUse(partial)
    _ = snapshot(screen, "setup-partial.png")
    screen.testClear()
    _ = snapshot(screen, "setup-none.png")
    for folder in discFolders { screen.testUse(folder) }
    _ = snapshot(screen, "setup-discs.png")
    let discs = discFolders.compactMap(OriginalDisc.resolve)
    print("discs: " + discs.map { "\($0.side.rawValue) at \($0.folder.lastPathComponent)" }.joined(separator: ", "))
    guard discs.count == 2 else { print("FAIL: didn't recognise both discs"); return 1 }

    print("importing from the discs")
    try? fm.removeItem(at: dataPath)
    try? fm.createDirectory(at: dataPath, withIntermediateDirectories: true)
    guard runImport(screen, shot: nil),
          check(ClassicArchiveImport.plan(from: discs, to: dataPath), "discs") else { return 1 }

    // Disc images, as the freeware release comes: GDI95.iso and NOD95.zip
    // (holding NOD95.iso), built from the install's CD1/CD2 with hdiutil and
    // zip. Built once and kept under OUTDIR/fixtures; ~1.2 GB.
    let isoGDI = outDir.appendingPathComponent("fixtures/GDI95.iso")
    let zipNod = outDir.appendingPathComponent("fixtures/NOD95.zip")
    func sh(_ cmd: String) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
    let td = cncdata.appendingPathComponent("TIBERIAN_DAWN").path
    if !fm.fileExists(atPath: isoGDI.path) {
        print("building GDI95.iso")
        _ = sh("hdiutil makehybrid -quiet -iso -joliet -o '\(isoGDI.path)' '\(td)/CD1'")
    }
    if !fm.fileExists(atPath: zipNod.path) {
        print("building NOD95.zip")
        let iso = outDir.appendingPathComponent("fixtures/NOD95.iso").path
        _ = sh("hdiutil makehybrid -quiet -iso -joliet -o '\(iso)' '\(td)/CD2' && cd '\(outDir.path)/fixtures' && zip -q -0 NOD95.zip NOD95.iso && rm NOD95.iso")
    }
    let images = [isoGDI, zipNod].compactMap(DiscImage.identify)
    print("images: " + images.map { "\($0.file.lastPathComponent) (\($0.side?.rawValue ?? "?"))" }.joined(separator: ", "))
    guard images.count == 2 else { print("FAIL: didn't recognise both disc images"); return 1 }
    let imageScreen = SetupScreen()
    imageScreen.testClear()
    imageScreen.testUse(isoGDI)
    imageScreen.testUse(zipNod)
    _ = snapshot(imageScreen, "setup-images.png")
    print("importing from the disc images")
    try? fm.removeItem(at: dataPath)
    try? fm.createDirectory(at: dataPath, withIntermediateDirectories: true)
    guard runImport(imageScreen, shot: "setup-unpacking.png") else { return 1 }
    let copied = ClassicArchiveImport.shared.filter { fm.fileExists(atPath: dataPath.appendingPathComponent($0).path) }.count
    let sides = ["gdi", "nod"].filter { fm.fileExists(atPath: dataPath.appendingPathComponent("\($0)/MOVIES.MIX").path) }
    let leftovers = (try? fm.contentsOfDirectory(atPath: dataPath.appendingPathComponent(".import").path)) ?? []
    print("  images: \(copied) shared archives, sides \(sides), scratch left: \(leftovers)")
    guard copied == ClassicArchiveImport.shared.count, sides.count == 2, leftovers.isEmpty else {
        print("FAIL: disc image import incomplete")
        return 1
    }

    print("importing from the Remastered Collection")
    try? fm.removeItem(at: dataPath)
    try? fm.createDirectory(at: dataPath, withIntermediateDirectories: true)
    let fresh = SetupScreen()
    guard runImport(fresh, shot: "setup-importing.png"),
          check(ClassicArchiveImport.plan(from: install, to: dataPath), "Remastered") else { return 1 }
    print("PASS")
    return 0
}
