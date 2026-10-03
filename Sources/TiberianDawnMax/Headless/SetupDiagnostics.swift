import CSDL2
import Foundation
import OpenConquerAssets

// --test-setup OUTDIR
// Drives the setup screen headlessly against the Remastered install it finds:
// snapshots the choice (setup-choose.png), runs a real import into the data
// folder (run it with OPENCONQUER_DATA_DIR pointing at a scratch folder),
// snapshots it part-way (setup-importing.png) and checks every classic
// archive arrived. Needs SDL_Init(VIDEO) and a Remastered install.

func runSetupDiagnosticsIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--test-setup") else { return nil }
    guard i + 1 < args.count else {
        print("usage: OPENCONQUER_DATA_DIR=/scratch/dir --test-setup OUTDIR")
        return 2
    }
    let outDir = URL(fileURLWithPath: args[i + 1])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard !dataPath.path.hasPrefix(home + "/Library/Application Support/Vanilla-Conquer") else {
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

    let installs = RemasteredLocator.search()
    print("found \(installs.count) install(s): " + installs.map { "\($0.dataDir.path)\($0.hasHD ? " (HD)" : "")" }.joined(separator: ", "))
    let screen = SetupScreen()
    guard snapshot(screen, "setup-choose.png") else { print("FAIL: snapshot"); return 1 }
    guard let install = installs.first else {
        print("no install found — wrote the not-found screen only")
        return 0
    }

    var imported = false
    screen.onImported = { imported = true }
    let start = Date()
    screen.startImport()
    var shotTaken = false
    while !imported {
        Thread.sleep(forTimeInterval: 0.05)
        if !shotTaken && Date().timeIntervalSince(start) > 0.1 {
            shotTaken = snapshot(screen, "setup-importing.png")
        } else {
            screen.render(renderer)  // polls the job
        }
        if Date().timeIntervalSince(start) > 1800 { print("FAIL: import timed out"); return 1 }
        if !imported, case .some = screen.failureMessage {
            _ = snapshot(screen, "setup-failed.png")
            print("FAIL: \(screen.failureMessage ?? "")")
            return 1
        }
    }
    print(String(format: "import finished in %.1f s", Date().timeIntervalSince(start)))

    let plan = ClassicArchiveImport.plan(from: install, to: dataPath)
    let missing = plan.filter { !FileManager.default.fileExists(atPath: $0.1.path) }
    guard missing.isEmpty else {
        print("FAIL: not copied: \(missing.map(\.1.lastPathComponent))")
        return 1
    }
    assetManager.initialize()
    print("\(plan.count) archives in place; \(assetManager.mixManager.totalEntries) MIX entries registered")
    print(assetManager.mixManager.totalEntries > 0 ? "PASS" : "FAIL: nothing registered")
    return assetManager.mixManager.totalEntries > 0 ? 0 : 1
}
