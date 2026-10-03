import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// --screenshot SCEN TICKS OUT.png [--classic|--modern] [--camera CX CY] [--zoom Z]
//              [--size W H] [--mouse X Y]
// Runs SCEN headlessly for TICKS ticks (fixed seed) and renders one full
// game frame — battlefield, sidebar and HUD — through an SDL software
// renderer on a surface (no window), as --test-sidebar does, then writes it
// as a PNG. The camera centres on cell (CX, CY), or on the player's units
// when omitted. Used for the README screenshots; never part of --determinism.

func runScreenshotIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--screenshot") else { return nil }
    guard i + 3 < args.count, let ticks = Int(args[i + 2]) else {
        print("usage: --screenshot SCEN TICKS OUT.png [--classic|--modern] [--camera CX CY] [--zoom Z] [--size W H]")
        return 2
    }
    func value(_ flag: String, _ n: Int = 1) -> [String]? {
        guard let j = args.firstIndex(of: flag), j + n < args.count else { return nil }
        return Array(args[(j + 1)...(j + n)])
    }
    let scenario = args[i + 1].uppercased()
    let out = URL(fileURLWithPath: args[i + 3])
    let size = value("--size", 2).flatMap { v in Int32(v[0]).flatMap { w in Int32(v[1]).map { (w, $0) } } } ?? (1280, 800)
    let (w, h) = size

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
    if args.contains("--classic") { sidebarStyleOverride = .classic }
    if args.contains("--modern") { sidebarStyleOverride = .modern }
    defer { sidebarStyleOverride = nil }

    guard runHeadless(scenario: scenario, ticks: 1, seed: 1) != nil, let world = session.world else {
        print("FAIL: could not load \(scenario)")
        return 1
    }
    renderState.gamePalette = loadPalette(world.theater.paletteName)
    // What a campaign start sets and runHeadless doesn't: the HUD's mission
    // title and the sidebar's BuildLevel.
    session.currentScenarioName = scenario
    if let ini = mixManager.retrieve("\(scenario).INI").map({ INIFile(data: $0) }) {
        session.scenarioBuildLevel = ini.int("Basic", "BuildLevel", default: 1)
    }
    for _ in 0..<max(0, ticks - 1) { gameTick() }
    if classicSidebarActive {
        resetClassicSidebarState()
        stepClassicSidebarForTesting(steps: 400)
    }

    // Camera: the requested cell, else the middle of the player's forces.
    applyAutoFitCameraAndZoom()
    if let z = value("--zoom").flatMap({ Double($0[0]) }) { renderState.gameZoomLevel = z }
    let vpW = Double(w - sidebarWidth) / renderState.gameZoomLevel
    let vpH = Double(h) / renderState.gameZoomLevel
    var focus: (x: Double, y: Double)?
    if let c = value("--camera", 2), let cx = Double(c[0]), let cy = Double(c[1]) {
        focus = (cx * 24 + 12, cy * 24 + 12)
    } else {
        // Prefer the player's base; else all their forces.
        let all = world.objects.filter { $0.house == world.playerHouse && $0.strength > 0 }
        let base = all.filter { $0.kind == .structure }
        let mine = base.isEmpty ? all : base
        if !mine.isEmpty {
            focus = (mine.map(\.worldX).reduce(0, +) / Double(mine.count),
                     mine.map(\.worldY).reduce(0, +) / Double(mine.count))
        }
    }
    if let f = focus {
        renderState.gameCameraX = f.x - vpW / 2
        renderState.gameCameraY = f.y - vpH / 2
        clampGameCamera()
    }
    // Park the pointer (the game draws its own cursor at the mouse position).
    let mouse = value("--mouse", 2).flatMap { v in Int32(v[0]).flatMap { x in Int32(v[1]).map { (x, $0) } } }
    input.mouseX = mouse?.0 ?? (w - sidebarWidth) / 2
    input.mouseY = mouse?.1 ?? h / 2

    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
    SDL_RenderClear(renderer)
    renderGame(renderer)
    var rect = SDL_Rect(x: 0, y: 0, w: w, h: h)
    var rgba = [UInt8](repeating: 0, count: Int(w) * Int(h) * 4)
    let ok = rgba.withUnsafeMutableBytes {
        SDL_RenderReadPixels(renderer, &rect, 0x16762004 /* ABGR8888 = RGBA bytes */, $0.baseAddress, w * 4)
    }
    for k in stride(from: 3, to: rgba.count, by: 4) { rgba[k] = 255 }
    guard ok == 0, writeRGBAPNG(rgba: rgba, width: Int(w), height: Int(h), to: out) else {
        print("FAIL: could not write \(out.path)")
        return 1
    }
    print("\(scenario) at tick \(world.tickCount): camera (\(Int(renderState.gameCameraX)), \(Int(renderState.gameCameraY))) "
          + "zoom \(renderState.gameZoomLevel) -> \(out.path)")
    return 0
}
