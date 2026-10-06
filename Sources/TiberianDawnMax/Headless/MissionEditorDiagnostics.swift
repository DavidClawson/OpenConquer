import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// --test-mission-editor OUTDIR
// Drives the mission editor headlessly on SCG01EA, through its panel's own
// buttons where it can: places and moves objects, marks a Nod building
// "win when destroyed", adds a survive-for-a-time goal and a reinforcement,
// sets money and the tech level and takes a unit out of the build list,
// snapshots every tab, saves to OUTDIR/missions, reopens the saved mission
// and checks it matches, then plays it headlessly: the money, the build list,
// the reinforcement's arrival and the timed win. Needs SDL_Init(VIDEO) and
// the game data.

func runMissionEditorDiagnosticsIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--test-mission-editor") else { return nil }
    guard i + 1 < args.count else {
        print("usage: --test-mission-editor OUTDIR")
        return 2
    }
    setvbuf(stdout, nil, _IOLBF, 0)
    let fm = FileManager.default
    let outDir = URL(fileURLWithPath: args[i + 1])
    try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
    customMissionsDir = outDir.appendingPathComponent("missions")
    try? fm.removeItem(at: customMissionsDir)

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
    renderState.sdlRenderer = renderer

    var failures: [String] = []
    func check(_ ok: Bool, _ what: String) {
        print("  \(ok ? "ok  " : "FAIL") \(what)")
        if !ok { failures.append(what) }
    }

    func snapshot(_ screen: MissionEditorScreen, _ name: String) {
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
        SDL_RenderClear(renderer)
        screen.render(renderer)
        var rgba = [UInt8](repeating: 0, count: Int(w) * Int(h) * 4)
        let ok = rgba.withUnsafeMutableBytes {
            SDL_RenderReadPixels(renderer, nil, 0x16762004 /* ABGR8888 = RGBA bytes */, $0.baseAddress, w * 4)
        }
        if ok != 0 || !writeRGBAPNG(rgba: rgba, width: Int(w), height: Int(h), to: outDir.appendingPathComponent(name)) {
            failures.append("snapshot \(name)")
        }
    }

    /// Clicks the panel button whose label starts with `label`, as a player
    /// would: render, find it, press.
    @discardableResult
    func click(_ screen: MissionEditorScreen, _ label: String) -> Bool {
        screen.render(renderer)
        guard let hit = screen.hits.first(where: { $0.label.hasPrefix(label.uppercased()) }) else {
            check(false, "button \(label) on the \(screen.tab.rawValue) tab")
            return false
        }
        screen.handleMouseDown(hit.rect.x + hit.rect.w / 2, hit.rect.y + hit.rect.h / 2, button: UInt8(SDL_BUTTON_LEFT))
        screen.handleMouseUp(hit.rect.x + hit.rect.w / 2, hit.rect.y + hit.rect.h / 2, button: UInt8(SDL_BUTTON_LEFT))
        return true
    }

    /// The screen point of a cell's middle.
    func point(_ cell: Int) -> (Int32, Int32) {
        let (x, y) = cellToXY(cell)
        let z = renderState.zoomLevel
        return (Int32(Double(x * 24 + 12 - renderState.cameraX) * z), Int32(Double(y * 24 + 12 - renderState.cameraY) * z))
    }

    func clickMap(_ screen: MissionEditorScreen, _ cell: Int, drag to: Int? = nil) {
        let (x, y) = point(cell)
        screen.handleMouseDown(x, y, button: UInt8(SDL_BUTTON_LEFT))
        if let to {
            let (tx, ty) = point(to)
            screen.handleMouseMotion(tx, ty, xrel: tx - x, yrel: ty - y)
            screen.handleMouseUp(tx, ty, button: UInt8(SDL_BUTTON_LEFT))
        } else {
            screen.handleMouseUp(x, y, button: UInt8(SDL_BUTTON_LEFT))
        }
    }

    print("mission editor on SCG01EA")
    guard let editor = MissionEditorScreen.openCampaign("SCG01EA") else {
        print("FAIL: couldn't open SCG01EA")
        return 1
    }
    let name = editor.doc.name
    check(!name.uppercased().hasPrefix("SC"), "a campaign map opens as a new mission (\(name))")
    check(editor.doc.mission.player == .goodGuy, "SCG01EA's player is GDI")
    snapshot(editor, "editor-units.png")

    // Place a medium tank and three minigunners for GDI, a Hand of Nod for Nod.
    let b = editor.doc.data.mapBounds!
    let tankCell = (b.y + b.height / 2) * 64 + b.x + b.width / 2
    let unitsBefore = editor.doc.data.units.count
    click(editor, "VEHICLES")
    click(editor, "MTNK")
    clickMap(editor, tankCell)
    check(editor.doc.data.units.count == unitsBefore + 1, "placed a medium tank")
    check(editor.doc.data.units.last?.house == .goodGuy, "it's GDI's")
    click(editor, "INFANTRY")
    click(editor, "E1 ")
    for _ in 0..<3 { clickMap(editor, tankCell + 2) }
    check(editor.doc.data.infantry.filter { $0.cell == tankCell + 2 }.count == 3, "three minigunners share a cell")
    check(Set(editor.doc.data.infantry.filter { $0.cell == tankCell + 2 }.map(\.subLocation)).count == 3,
          "each on its own spot")
    clickMap(editor, tankCell)  // a vehicle is already there: refused
    check(editor.doc.data.infantry.filter { $0.cell == tankCell }.isEmpty, "infantry can't stand on the tank")
    editor.handleKeyDown(Int32(SDLK_ESCAPE.rawValue))  // stop placing
    editor.handleKeyDown(Int32(SDLK_ESCAPE.rawValue))  // deselect
    click(editor, "NOD")
    click(editor, "BUILDINGS")
    click(editor, "HAND")
    guard let handCell = (0..<4096).first(where: { c in
        let (x, y) = cellToXY(c)
        return x > b.x + 2 && y > b.y + 2 && x < b.x + b.width - 4 && y < b.y + b.height - 4 &&
            editor.canPlace("HAND", at: c).ok
    }) else {
        print("FAIL: no room for a Hand of Nod")
        return 1
    }
    clickMap(editor, handCell)
    let hand = editor.doc.data.structures.lastIndex { $0.typeName == "HAND" }
    guard let hand else {
        print("FAIL: couldn't place a Hand of Nod")
        return 1
    }
    check(editor.doc.data.structures[hand].house == .badGuy, "placed a Nod Hand of Nod")
    click(editor, "SELECT")

    // Select the tank, drag it two cells right, turn it, half its health.
    clickMap(editor, tankCell, drag: tankCell + 1)
    check(editor.doc.data.units.last?.cell == tankCell + 1, "dragged the tank one cell")
    editor.handleKeyDown(Int32(SDLK_r.rawValue))
    check(editor.doc.data.units.last?.facing == 32, "R turns it")
    click(editor, "HEALTH -")
    click(editor, "HEALTH -")
    check(editor.doc.data.units.last?.strength == 192, "health down to 75%")
    click(editor, "INVULNERABLE")
    check(editor.doc.mission.flag("Invulnerable", at: tankCell + 1), "made it invulnerable")
    snapshot(editor, "editor-selected.png")

    // The Hand of Nod: win when it's destroyed.
    clickMap(editor, handCell)
    click(editor, "WIN WHEN DESTROYED")
    let winTrigger = editor.doc.mission.triggers.first { $0.event == "Destroyed" && $0.action == "Win" }
    check(winTrigger != nil, "a Destroyed/Win goal exists")
    check(editor.doc.data.structures[hand].trigger == winTrigger?.name, "the Hand of Nod carries it")

    // Undo and redo the whole thing.
    editor.undo()
    check(editor.doc.mission.triggers.first { $0.event == "Destroyed" } == nil, "undo removes it")
    editor.redo()
    check(editor.doc.mission.triggers.first { $0.event == "Destroyed" } != nil, "redo brings it back")

    // Goals: survive for 1:00 as well.
    click(editor, "GOALS")
    click(editor, "SURVIVE FOR A TIME")
    var survive = editor.doc.mission.goals.first { $0.event == "Time" && $0.action == "Win" }
    check(survive?.data == 100, "survive defaults to 10:00")
    for _ in 0..<18 { click(editor, "TIME -") }  // 10:00 - 18 x 0:30 = 1:00
    survive = editor.doc.mission.goals.first { $0.event == "Time" && $0.action == "Win" }
    check(survive?.data == 10, "survive set to 1:00 (\(survive.map { EditorTrigger.clock(tenths: $0.data) } ?? "-"))")
    snapshot(editor, "editor-goals.png")

    // Setup: GDI gets 5000, Nod 1000; tech level 4; no grenadiers.
    click(editor, "SETUP")
    let gdiCredits = editor.doc.mission.credits[.goodGuy] ?? 0
    editor.setCredits(.goodGuy, 5000)
    editor.setCredits(.badGuy, 1000)
    check(gdiCredits == 2000 && editor.doc.mission.credits[.goodGuy] == 5000, "GDI money 2000 -> 5000")
    for _ in 0..<3 { click(editor, "LEVEL +") }
    check(editor.doc.mission.buildLevel == 4, "tech level 1 -> 4 (\(editor.doc.mission.buildLevel))")
    click(editor, "GRENADIER")
    check(editor.doc.mission.deny.contains("E2"), "grenadiers taken out of the build list")
    snapshot(editor, "editor-setup.png")

    // A reinforcement: GDI, after 0:30, two medium tanks driving in.
    click(editor, "REINF.")
    let reinforcementsBefore = editor.doc.mission.reinforcements.count
    click(editor, "+ FOR GDI")
    check(editor.doc.mission.reinforcements.count == reinforcementsBefore + 1, "added a reinforcement")
    guard let rf = editor.doc.mission.reinforcements.last else { return 1 }
    click(editor, "+ ADD A UNIT TYPE")
    click(editor, "MTNK")
    click(editor, "MTNK")
    // The default three minigunners: remove them.
    for n in (1...3).reversed() { click(editor, "\(n) X MINIGUNNER -") }
    click(editor, "TIME -")  // 1:00 -> 0:30
    let team = editor.doc.mission.team(named: rf.team)
    check(team?.members == [EditorTeamMember(type: "MTNK", count: 2)], "team is 2 MTNK (\(team?.value ?? "-"))")
    let rfNow = editor.doc.mission.reinforcements.last
    check(rfNow?.data == 5, "arrives at 0:30 (\(rfNow.map { EditorTrigger.clock(tenths: $0.data) } ?? "-"))")
    snapshot(editor, "editor-reinforcements.png")

    // Save, reopen, compare.
    click(editor, "FILE")
    snapshot(editor, "editor-file.png")
    click(editor, "SAVE")
    let iniURL = customMissionsDir.appendingPathComponent(name + ".INI")
    check(fm.fileExists(atPath: iniURL.path), "saved \(name).INI")
    check(fm.fileExists(atPath: customMissionsDir.appendingPathComponent(name + ".BIN").path), "saved \(name).BIN")
    guard let reopened = MissionEditorScreen.openSaved(name) else {
        print("FAIL: couldn't reopen \(name)")
        return 1
    }
    check(reopened.doc.data.units == editor.doc.data.units, "units survive the save")
    check(reopened.doc.data.infantry == editor.doc.data.infantry, "infantry survive the save")
    check(reopened.doc.data.structures == editor.doc.data.structures, "buildings survive the save")
    check(reopened.doc.mission == editor.doc.mission, "the mission's rules survive the save")
    check(reopened.map.map(\.templateType) == editor.map.map(\.templateType), "the map survives the save")

    // Play it headlessly.
    print("playing \(name)")
    let text = (try? String(contentsOf: iniURL, encoding: .utf8)) ?? ""
    let data = parseScenarioData(INIFile(string: text), name: name)
    initGameWorld(scenario: data, scenarioName: name, map: reopened.map)
    session.scenarioBuildLevel = data.buildLevel
    guard let world = session.world else { return 1 }
    check(world.playerHouse == .goodGuy, "the player is GDI")
    check(session.sidebarCredits == 5000, "starts with 5000 credits (\(session.sidebarCredits))")
    check(session.buildDeny == ["E2"], "the build list leaves out grenadiers")
    let tanks = { world.objects.filter { $0.house == .goodGuy && $0.typeName == "MTNK" && $0.strength > 0 }.count }
    let startTanks = tanks()
    let tank = world.objects.first { $0.typeName == "MTNK" && $0.house == .goodGuy && $0.isInvulnerable }
    check(tank != nil, "the placed tank is in the world, invulnerable")
    var arrived = -1
    var won = -1
    for t in 1...1200 {
        gameTick()
        if arrived < 0 && tanks() >= startTanks + 2 { arrived = t }
        if session.triggerWinState == .won { won = t; break }
        if session.triggerWinState == .lost { break }
    }
    check(arrived > 0 && arrived < 600, "two tanks arrive at about 0:30 (tick \(arrived))")
    check(won >= 890 && won <= 1000, "won by surviving 1:00 (tick \(won), state \(session.triggerWinState))")

    // Play-test from the editor, then leave the game: back in the editor.
    reopened.playTest()
    check(app.currentScreen is PlayingScreen && session.world != nil, "PLAY-TEST starts the mission")
    let back = makeMainMenu()
    check(back === reopened, "leaving the game goes back to the editor")
    app.currentScreen = back
    reopened.render(renderer)
    check(session.world == nil && scenarioData?.units == reopened.doc.data.units, "the editor shows its mission again")
    check(!(makeMainMenu() is MissionEditorScreen), "only once: the editor's own EXIT goes to the menu")

    print(failures.isEmpty ? "PASS" : "FAIL: \(failures.count) check(s)")
    return failures.isEmpty ? 0 : 1
}
