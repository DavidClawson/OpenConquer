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

// --list-buildables SCEN...
// Loads each scenario and prints the player's owned structures and what the
// sidebar offers (getAvailableStructures / getAvailableUnits).
func runListBuildablesIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--list-buildables") else { return nil }
    for name in args[(i + 1)...] where !name.hasPrefix("--") {
        guard runHeadless(scenario: name.uppercased(), ticks: 1, seed: nil) != nil else {
            print("\(name): FAIL to load")
            return 1
        }
        // runHeadless doesn't set the campaign's BuildLevel; read it as startNextMission does.
        if let ini = mixManager.retrieve("\(name.uppercased()).INI").map({ INIFile(data: $0) }) {
            session.scenarioBuildLevel = ini.int("Basic", "BuildLevel", default: 1)
        }
        print("\(name.uppercased()) level \(session.scenarioBuildLevel) owns \(getOwnedBuildingTypes().sorted())")
        print("  structures: \(getAvailableStructures().map(\.name))")
        print("  units:      \(getAvailableUnits().map(\.name))")
    }
    return 0
}

// --test-mcv-deploy [SCEN...]
// Finds the player's MCV, orders it to deploy and reports the turn to
// south-west, the yard's FACTMAKE build-up (frames, ticks) and that the yard
// ends up working (mission guard). Default scenarios: those starting with an MCV.
func runMCVDeployTestIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--test-mcv-deploy") else { return nil }
    var names = args[(i + 1)...].filter { !$0.hasPrefix("--") }.map { $0.uppercased() }
    if names.isEmpty { names = ["SCG03EA", "SCB02EA"] }
    var tested = 0
    for name in names {
        guard runHeadless(scenario: name, ticks: 1, seed: 1) != nil, let world = session.world,
              let mcv = world.objects.first(where: { $0.isMCV && $0.house == world.playerHouse && $0.strength > 0 }) else {
            print("\(name): no player MCV")
            continue
        }
        tested += 1
        mcv.strength = mcv.maxStrength / 2
        let startFacing = mcv.facing
        issue(.deploy(mcv: mcv.id))
        var ticks = 0, turnTicks = 0, frames = Set<Int>()
        var yard: GameObject?
        while ticks < 600 {
            gameTick()
            ticks += 1
            if yard == nil { yard = world.objects.first { $0.typeName == "FACT" && $0.house == world.playerHouse && $0.strength > 0 } }
            if yard == nil { turnTicks = ticks }
            if let y = yard {
                if y.buildUpFrame >= 0 { frames.insert(y.buildUpFrame) }
                if y.mission == .guard_ { break }
            }
        }
        guard let y = yard else {
            print("FAIL \(name): the MCV never deployed (facing \(mcv.facing))")
            return 1
        }
        let buildTicks = ticks - turnTicks
        print("\(name): MCV turned \(startFacing) -> 160 in \(turnTicks) ticks; FACTMAKE \(y.buildUpTotalFrames) frames, "
              + "\(frames.count) shown over \(buildTicks) ticks; yard health \(y.strength)/\(y.maxStrength); mission \(y.mission)")
        guard y.mission == .guard_, frames.count == y.buildUpTotalFrames, y.buildUpTotalFrames > 1,
              (60...80).contains(buildTicks), y.strength < y.maxStrength else {
            print("FAIL \(name)")
            return 1
        }
    }
    print(tested > 0 ? "PASS" : "FAIL: no scenario with an MCV")
    return tested > 0 ? 0 : 1
}
