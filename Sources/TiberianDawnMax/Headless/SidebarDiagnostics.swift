import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// --test-sidebar SCEN TICKS OUTDIR
// Renders both sidebars headlessly — an SDL software renderer on a surface, no
// window — after running SCEN for TICKS ticks with a unit and a structure in
// production, and writes sidebar-classic.png / sidebar-modern.png (the
// sidebar column of a 1280x800 frame). The classic power bar is settled
// first. Needs SDL_Init(VIDEO) and the game data; never part of
// --determinism (it starts production, which changes the game).

func runSidebarDiagnosticsIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--test-sidebar") else { return nil }
    guard i + 3 < args.count, let ticks = Int(args[i + 2]) else {
        print("usage: --test-sidebar SCEN TICKS OUTDIR")
        return 2
    }
    let scenario = args[i + 1].uppercased()
    let outDir = URL(fileURLWithPath: args[i + 3])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

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
    renderState.sdlRenderer = renderer
    renderState.windowWidth = w
    renderState.windowHeight = h

    guard runHeadless(scenario: scenario, ticks: 1, seed: nil) != nil, let world = session.world else {
        print("FAIL: could not load \(scenario)")
        return 1
    }
    renderState.gamePalette = loadPalette(world.theater.paletteName)
    if let unit = getAvailableUnits().first {
        issue(.startProduction(structure: false, type: unit.name, cost: unit.cost, buildTicks: unit.buildTicks))
    }
    if let structure = getAvailableStructures().first {
        issue(.startProduction(structure: true, type: structure.name, cost: structure.cost,
                               buildTicks: structure.buildTicks))
    }
    for _ in 0..<max(1, ticks) { gameTick() }
    let state = getHouseState(world.playerHouse)
    print("\(scenario) after \(ticks) ticks: power \(state.powerOutput)/\(state.powerDrain), credits \(session.sidebarCredits)"
          + ", building unit \(session.unitBuildQueue.item.map { "\($0.typeName) \(Int(session.unitBuildQueue.progressFraction * 100))%" } ?? "none")"
          + ", structure \(session.structureBuildQueue.item.map { "\($0.typeName) \(Int(session.structureBuildQueue.progressFraction * 100))%" } ?? "none")")

    for style in [SidebarStyle.classic, .modern] {
        sidebarStyleOverride = style
        if style == .classic {
            resetClassicSidebarState()
            stepClassicSidebarForTesting(steps: 400)
        }
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
        SDL_RenderClear(renderer)
        if style == .classic { renderClassicSidebar(renderer) } else { renderSidebar(renderer) }
        let sw = sidebarWidth
        var rect = SDL_Rect(x: w - sw, y: 0, w: sw, h: h)
        var rgba = [UInt8](repeating: 0, count: Int(sw) * Int(h) * 4)
        let ok = rgba.withUnsafeMutableBytes {
            SDL_RenderReadPixels(renderer, &rect, 0x16762004 /* ABGR8888 = RGBA bytes */, $0.baseAddress, sw * 4)
        }
        let name = "sidebar-\(style == .classic ? "classic" : "modern").png"
        guard ok == 0, writeRGBAPNG(rgba: rgba, width: Int(sw), height: Int(h), to: outDir.appendingPathComponent(name)) else {
            print("FAIL: could not capture \(name)")
            return 1
        }
        print("wrote \(name) (\(sw)x\(h))\(style == .classic && !classicSidebarActive ? " — classic art missing, modern shown" : "")")
    }
    sidebarStyleOverride = nil
    return 0
}
