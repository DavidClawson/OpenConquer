import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// MARK: - Mission Editor
//
// The map on the left, a side panel on the right with five tabs:
//   FILE   open a campaign map or one of your missions, rename, save, test
//   UNITS  place, move and delete units, infantry, buildings, walls and
//          tiberium, and set the selected object's owner, health, facing,
//          orders and flags (invulnerable, must survive, win/lose if destroyed)
//   SETUP  the player's side, each side's money and reinforcement edge, the
//          tech level and the mission's own changes to what it allows
//   GOALS  the win and lose conditions
//   REINF. reinforcements: who, how many, how they arrive, when
// The document is an `EditorScenario` (Core) plus the map's cells; the panel
// edits it through `edit { }`, which keeps an undo history. Missions save to
// <data>/missions/NAME.INI and NAME.BIN, as ordinary scenario files: the
// classic sections stay classic, and the editor's own additions ([Buildables],
// [ObjectFlags]) are sections the 1995 game ignores. Play-test builds a world
// from the document and comes back here when the game returns to the menu.

/// Where the editor saves missions (a test points it elsewhere).
var customMissionsDir = dataPath.appendingPathComponent("missions")

/// The custom missions saved so far, by name.
func customMissionNames() -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: customMissionsDir.path)) ?? []
    return files.filter { $0.uppercased().hasSuffix(".INI") }
        .map { String($0.dropLast(4)) }
        .sorted()
}

final class MissionEditorScreen: MenuScreen {
    enum Tab: String, CaseIterable {
        case file = "FILE", map = "MAP", units = "UNITS", setup = "SETUP", goals = "GOALS", reinforce = "REINF."
    }
    /// What a click on the map does on the MAP tab.
    enum MapTool: String, CaseIterable { case select = "SELECT", ground = "GROUND", trees = "TREES, ROCKS", erase = "ERASE" }
    /// One undo step: everything the editor changes.
    struct Snapshot {
        let data: ScenarioData
        let mission: MissionState
        let map: [MapCell]
    }
    enum Category: String, CaseIterable { case infantry = "INFANTRY", vehicles = "VEHICLES", buildings = "BUILDINGS", other = "WALLS ETC" }
    enum Selection: Equatable { case structure(Int), unit(Int), infantry(Int), overlay(Int), terrain(Int) }

    private(set) var doc: EditorScenario
    var map: [MapCell]
    var undoStack: [Snapshot] = []
    var redoStack: [Snapshot] = []
    private(set) var dirty = false

    var tab: Tab = .units
    var mapTool: MapTool = .select
    /// The faint red layer over cells ground units can't enter.
    var showBlocked = false
    /// Bumped by every change, so the blocked layer knows to recompute.
    var editVersion = 0
    var blockedCache: (version: Int, land: [Bool])?
    /// The play-area edges a drag is moving, while one is.
    var resizing: (left: Bool, right: Bool, top: Bool, bottom: Bool)?
    var tileGroup: TileGroup = .water
    /// The ground piece (a template number) the next click stamps.
    var brushTemplate: Int?
    /// The tree or rock the next click places.
    var brushTerrain: String?
    /// The cells the last stamp of a drag covered, so a drag doesn't restamp
    /// over its own piece.
    var lastStamp: Set<Int> = []
    /// True between a map press and release that's painting: the whole
    /// stroke is one undo step.
    var painting = false
    /// Tile sets loaded for this theater (to know which of a piece's cells exist).
    var icnFiles: [String: ICNFile] = [:]
    var category: Category = .infantry
    var placeHouse: House = .goodGuy
    /// The type the next map click places; nil selects instead.
    var placeType: String?
    var selection: Selection?
    /// The trigger whose spots a map click marks ("reach a spot" goals and
    /// reinforcements), or nil.
    var markingSpotsFor: String?
    /// The reinforcement the panel is editing.
    var activeReinforcement: String?
    /// A reinforcement's member being chosen from the type list.
    var addingMemberTo: String?

    var hits: [(rect: SDL_Rect, label: String, action: () -> Void)] = []
    var scroll: [Tab: Int32] = [:]
    var contentHeight: Int32 = 0
    var dragFrom: Int?       // the cell a map drag started on
    var dragCell: Int?
    var panning = false
    var renaming = false
    var status = ""
    var statusTicks: UInt64 = 0
    var savedCamera: (x: Int, y: Int, zoom: Double)?
    /// Mission names on disk, refreshed when the FILE tab opens.
    var savedMissions: [String] = customMissionNames()

    // MARK: Opening

    init(doc: EditorScenario, map: [MapCell]) {
        self.doc = doc
        self.map = map
        placeHouse = doc.mission.player
        showDocument(resetCamera: true)
    }

    /// A campaign map (SCG01EA, ...) as a new mission of your own.
    static func openCampaign(_ scenario: String) -> MissionEditorScreen? {
        guard let data = loadScenario(scenario + ".INI", from: mixManager) else { return nil }
        let cells = loadMap(scenario + ".BIN", from: mixManager)
            ?? Array(repeating: MapCell(templateType: 0xFF, iconIndex: 0), count: 4096)
        let doc = EditorScenario(name: scenario, data: data)
        let player = doc.mission.player
        doc.name = freeMissionName()
        doc.mission.player = player
        return MissionEditorScreen(doc: doc, map: cells)
    }

    /// One of the missions in the missions folder.
    static func openSaved(_ name: String) -> MissionEditorScreen? {
        let ini = customMissionsDir.appendingPathComponent(name + ".INI")
        let bin = customMissionsDir.appendingPathComponent(name + ".BIN")
        guard let text = try? Data(contentsOf: ini) else { return nil }
        let data = parseScenarioData(INIFile(data: text), name: name)
        let cells = (try? Data(contentsOf: bin)).flatMap(decodeMap)
            ?? Array(repeating: MapCell(templateType: 0xFF, iconIndex: 0), count: 4096)
        return MissionEditorScreen(doc: EditorScenario(name: name, data: data), map: cells)
    }

    /// An empty 48x48 map of open ground in `theater`.
    static func blank(_ theater: TheaterType) -> MissionEditorScreen {
        let ini = """
        [Basic]
        Name=New mission
        Player=GoodGuy
        BuildLevel=3

        [Map]
        Theater=\(theater.rawValue)
        X=8
        Y=8
        Width=48
        Height=48

        [GoodGuy]
        Credits=50
        Edge=South
        Allies=GoodGuy

        [BadGuy]
        Credits=50
        Edge=North
        Allies=BadGuy

        [Neutral]
        Credits=0
        Allies=Neutral

        [Triggers]
        WIN=All Destr.,Win,0,BadGuy,None,0
        LOSE=All Destr.,Lose,0,GoodGuy,None,0

        [TeamTypes]

        [Waypoints]
        26=2080

        """
        let name = freeMissionName()
        let data = parseScenarioData(INIFile(string: ini), name: name)
        let cells = Array(repeating: MapCell(templateType: 0xFF, iconIndex: 0), count: 4096)
        return MissionEditorScreen(doc: EditorScenario(name: name, data: data), map: cells)
    }

    static func freeMissionName() -> String {
        let taken = Set(customMissionNames().map { $0.uppercased() })
        for i in 1... where !taken.contains("MISSION\(i)") { return "MISSION\(i)" }
        return "MISSION"
    }

    /// Points the shared map view at this document.
    func showDocument(resetCamera: Bool) {
        session.world = nil
        clearMapViewTextures()
        mapCells = map
        scenarioData = doc.data
        renderState.gamePalette = loadPalette(doc.data.theater.paletteName)
        if resetCamera {
            renderState.zoomLevel = 1.0
            let b = doc.data.mapBounds ?? MapBounds(x: 0, y: 0, width: 64, height: 64)
            renderState.cameraX = b.x * 24
            renderState.cameraY = b.y * 24
        }
    }

    // MARK: Editing

    var snapshot: Snapshot { Snapshot(data: doc.data, mission: doc.mission, map: map) }

    func restore(_ s: Snapshot) {
        doc.data = s.data
        doc.mission = s.mission
        map = s.map
        selection = nil
        scenarioData = doc.data
        mapCells = map
        dirty = true
        editVersion += 1
    }

    /// Runs a change with undo. `continuing` folds it into the last step
    /// (the rest of a paint stroke).
    func edit(continuing: Bool = false, _ change: () -> Void) {
        if !continuing {
            undoStack.append(snapshot)
            if undoStack.count > 200 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        change()
        dirty = true
        editVersion += 1
        scenarioData = doc.data
        mapCells = map
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    func say(_ text: String) {
        status = text
        statusTicks = SDL_GetTicks64()
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: customMissionsDir, withIntermediateDirectories: true)
            try doc.save(toPath: customMissionsDir.appendingPathComponent(doc.name + ".INI").path)
            try encodeMap(map).write(to: customMissionsDir.appendingPathComponent(doc.name + ".BIN"))
            dirty = false
            savedMissions = customMissionNames()
            say("SAVED AS \(doc.name)")
        } catch {
            say("COULDN'T SAVE: \(error.localizedDescription)")
        }
    }

    /// Builds a world from the document and plays it; leaving the game comes
    /// back here.
    func playTest() {
        let data = parseScenarioData(INIFile(string: doc.serialize()), name: doc.name)
        savedCamera = (renderState.cameraX, renderState.cameraY, renderState.zoomLevel)
        session.campaignState.isActive = false
        session.campaignState.completedMissions.removeAll()
        session.campaignState.carryOverCredits = 0
        initGameWorld(scenario: data, scenarioName: doc.name, map: map)
        session.currentScenarioName = doc.name
        session.sidebarCredits = data.credits
        session.displayedCredits = data.credits
        session.scenarioBuildLevel = data.buildLevel
        session.missionScore.reset()
        app.lastTickTime = 0
        app.tickAccumulator = 0
        session.triggerWinState = .playing
        applyAutoFitCameraAndZoom()
        app.playTestReturn = self
        app.currentScreen = PlayingScreen()
    }

    // MARK: Objects

    func typeName(_ s: Selection) -> String {
        switch s {
        case .structure(let i): return doc.data.structures[i].typeName
        case .unit(let i): return doc.data.units[i].typeName
        case .infantry(let i): return doc.data.infantry[i].typeName
        case .overlay(let i): return doc.data.overlays[i].typeName
        case .terrain(let i): return doc.data.terrain[i].typeName
        }
    }

    func cellOf(_ s: Selection) -> Int {
        switch s {
        case .structure(let i): return doc.data.structures[i].cell
        case .unit(let i): return doc.data.units[i].cell
        case .infantry(let i): return doc.data.infantry[i].cell
        case .overlay(let i): return doc.data.overlays[i].cell
        case .terrain(let i): return doc.data.terrain[i].cell
        }
    }

    func isValid(_ s: Selection) -> Bool {
        switch s {
        case .structure(let i): return i < doc.data.structures.count
        case .unit(let i): return i < doc.data.units.count
        case .infantry(let i): return i < doc.data.infantry.count
        case .overlay(let i): return i < doc.data.overlays.count
        case .terrain(let i): return i < doc.data.terrain.count
        }
    }

    /// The topmost object at `cell`: infantry, then vehicles, buildings,
    /// trees and rocks, and overlays.
    func object(at cell: Int, sub: Int? = nil) -> Selection? {
        let inf = doc.data.infantry.indices.filter { doc.data.infantry[$0].cell == cell }
        if let sub, let i = inf.first(where: { doc.data.infantry[$0].subLocation == sub }) { return .infantry(i) }
        if let i = inf.first { return .infantry(i) }
        if let i = doc.data.units.firstIndex(where: { $0.cell == cell }) { return .unit(i) }
        if let i = doc.data.structures.firstIndex(where: { footprint($0.typeName, at: $0.cell).contains(cell) }) {
            return .structure(i)
        }
        if let i = doc.data.terrain.firstIndex(where: { $0.cell == cell }) { return .terrain(i) }
        if let i = doc.data.terrain.firstIndex(where: { terrainCells($0).contains(cell) }) { return .terrain(i) }
        if let i = doc.data.overlays.firstIndex(where: { $0.cell == cell }) { return .overlay(i) }
        return nil
    }

    func footprint(_ type: String, at cell: Int) -> [Int] {
        let size = buildingSize(type)
        let (x, y) = cellToXY(cell)
        var cells: [Int] = []
        for dy in 0..<size.h { for dx in 0..<size.w where x + dx < 64 && y + dy < 64 { cells.append((y + dy) * 64 + x + dx) } }
        return cells
    }

    /// Cells taken by vehicles and buildings (not counting `except`).
    func blockedCells(except: Selection? = nil) -> Set<Int> {
        var cells = Set<Int>()
        for (i, u) in doc.data.units.enumerated() where except != .unit(i) { cells.insert(u.cell) }
        for (i, s) in doc.data.structures.enumerated() where except != .structure(i) {
            cells.formUnion(footprint(s.typeName, at: s.cell))
        }
        return cells
    }

    func kind(of type: String) -> Category {
        let upper = type.uppercased()
        if InfantryType.from(iniName: upper) != nil { return .infantry }
        if UnitType.from(iniName: upper) != nil || AircraftType.from(iniName: upper) != nil { return .vehicles }
        if StructType.from(iniName: upper) != nil { return .buildings }
        return .other
    }

    /// Whether `type` fits at `cell`; for infantry, the free spot in it.
    func canPlace(_ type: String, at cell: Int, except: Selection? = nil, preferredSub: Int = 0) -> (ok: Bool, sub: Int) {
        let blocked = blockedCells(except: except)
        switch kind(of: type) {
        case .infantry:
            guard !blocked.contains(cell) else { return (false, 0) }
            let used = Set(doc.data.infantry.enumerated()
                .filter { $0.element.cell == cell && except != .infantry($0.offset) }.map(\.element.subLocation))
            if !used.contains(preferredSub) { return (true, preferredSub) }
            if let free = [0, 1, 2, 3, 4].first(where: { !used.contains($0) }) { return (true, free) }
            return (false, 0)
        case .vehicles:
            let hasInfantry = doc.data.infantry.enumerated().contains { $0.element.cell == cell && except != .infantry($0.offset) }
            return (!blocked.contains(cell) && !hasInfantry, 0)
        case .buildings:
            let cells = footprint(type, at: cell)
            let size = buildingSize(type)
            let (x, y) = cellToXY(cell)
            guard x + size.w <= 64, y + size.h <= 64 else { return (false, 0) }
            let infantryCells = Set(doc.data.infantry.enumerated().filter { except != .infantry($0.offset) }.map(\.element.cell))
            return (!cells.contains { blocked.contains($0) || infantryCells.contains($0) }, 0)
        case .other where terrainObjectTypes.contains(type.uppercased()):
            let taken = doc.data.terrain.enumerated().contains { $0.element.cell == cell && except != .terrain($0.offset) }
            return (!taken && !blocked.contains(cell), 0)
        case .other:
            let taken = doc.data.overlays.enumerated().contains { $0.element.cell == cell && except != .overlay($0.offset) }
            return (!taken, 0)
        }
    }

    func place(_ type: String, at cell: Int, sub: Int = 0) {
        let fit = canPlace(type, at: cell, preferredSub: sub)
        guard fit.ok else { return }
        let house = placeHouse
        edit {
            switch kind(of: type) {
            case .infantry:
                doc.data.infantry.append(ScenarioInfantry(house: house, typeName: type, strength: 256, cell: cell,
                                                          subLocation: fit.sub, mission: "Guard", facing: 0, trigger: "None"))
                selection = .infantry(doc.data.infantry.count - 1)
            case .vehicles:
                let mission = type.uppercased() == "HARV" ? "Harvest" : "Guard"
                doc.data.units.append(ScenarioUnit(house: house, typeName: type, strength: 256, cell: cell,
                                                   facing: 0, mission: mission, trigger: "None"))
                selection = .unit(doc.data.units.count - 1)
            case .buildings:
                doc.data.structures.append(ScenarioStructure(house: house, typeName: type, strength: 256, cell: cell,
                                                             facing: 0, trigger: "None"))
                selection = .structure(doc.data.structures.count - 1)
            case .other:
                var name = type
                if type == "TI1" { name = "TI\(Int.random(in: 1...12))" }  // cosmetic variety
                doc.data.overlays.append(ScenarioOverlay(cell: cell, typeName: name))
                selection = .overlay(doc.data.overlays.count - 1)
            }
        }
    }

    func move(_ s: Selection, to cell: Int, sub: Int = 0) {
        let fit = canPlace(typeName(s), at: cell, except: s, preferredSub: sub)
        var moved = cell != cellOf(s)
        if case .infantry(let i) = s, fit.sub != doc.data.infantry[i].subLocation { moved = true }
        guard fit.ok, moved else { return }
        let from = cellOf(s)
        edit {
            switch s {
            case .structure(let i): doc.data.structures[i].cell = cell
            case .unit(let i): doc.data.units[i].cell = cell
            case .infantry(let i):
                doc.data.infantry[i].cell = cell
                doc.data.infantry[i].subLocation = fit.sub
            case .overlay(let i): doc.data.overlays[i].cell = cell
            case .terrain(let i): doc.data.terrain[i].cell = cell
            }
            doc.mission.moveFlags(from: from, to: cell)
        }
    }

    func delete(_ s: Selection) {
        let cell = cellOf(s)
        edit {
            switch s {
            case .structure(let i): doc.data.structures.remove(at: i)
            case .unit(let i): doc.data.units.remove(at: i)
            case .infantry(let i): doc.data.infantry.remove(at: i)
            case .overlay(let i): doc.data.overlays.remove(at: i)
            case .terrain(let i): doc.data.terrain.remove(at: i)
            }
            if object(at: cell) == nil { doc.mission.objectFlags[cell] = nil }
        }
        selection = nil
    }

    func house(_ s: Selection) -> House? {
        switch s {
        case .structure(let i): return doc.data.structures[i].house
        case .unit(let i): return doc.data.units[i].house
        case .infantry(let i): return doc.data.infantry[i].house
        case .overlay, .terrain: return nil
        }
    }

    func setHouse(_ s: Selection, _ h: House) {
        edit {
            switch s {
            case .structure(let i): doc.data.structures[i].house = h
            case .unit(let i): doc.data.units[i].house = h
            case .infantry(let i): doc.data.infantry[i].house = h
            case .overlay, .terrain: break
            }
        }
    }

    func strength(_ s: Selection) -> Int {
        switch s {
        case .structure(let i): return doc.data.structures[i].strength
        case .unit(let i): return doc.data.units[i].strength
        case .infantry(let i): return doc.data.infantry[i].strength
        case .overlay, .terrain: return 256
        }
    }

    func setStrength(_ s: Selection, _ v: Int) {
        let v = max(1, min(256, v))
        edit {
            switch s {
            case .structure(let i): doc.data.structures[i].strength = v
            case .unit(let i): doc.data.units[i].strength = v
            case .infantry(let i): doc.data.infantry[i].strength = v
            case .overlay, .terrain: break
            }
        }
    }

    func facing(_ s: Selection) -> Int {
        switch s {
        case .structure(let i): return doc.data.structures[i].facing
        case .unit(let i): return doc.data.units[i].facing
        case .infantry(let i): return doc.data.infantry[i].facing
        case .overlay, .terrain: return 0
        }
    }

    func rotate(_ s: Selection, by step: Int) {
        let f = (facing(s) + step + 256) % 256
        edit {
            switch s {
            case .structure: break
            case .unit(let i): doc.data.units[i].facing = f
            case .infantry(let i): doc.data.infantry[i].facing = f
            case .overlay, .terrain: break
            }
        }
    }

    func mission(_ s: Selection) -> String? {
        switch s {
        case .unit(let i): return doc.data.units[i].mission
        case .infantry(let i): return doc.data.infantry[i].mission
        default: return nil
        }
    }

    func setMission(_ s: Selection, _ m: String) {
        edit {
            switch s {
            case .unit(let i): doc.data.units[i].mission = m
            case .infantry(let i): doc.data.infantry[i].mission = m
            default: break
            }
        }
    }

    func trigger(_ s: Selection) -> String {
        switch s {
        case .structure(let i): return doc.data.structures[i].trigger
        case .unit(let i): return doc.data.units[i].trigger
        case .infantry(let i): return doc.data.infantry[i].trigger
        case .overlay, .terrain: return "None"
        }
    }

    func setTrigger(_ s: Selection, _ t: String) {
        switch s {
        case .structure(let i): doc.data.structures[i].trigger = t
        case .unit(let i): doc.data.units[i].trigger = t
        case .infantry(let i): doc.data.infantry[i].trigger = t
        case .overlay, .terrain: break
        }
    }

    /// "Win when destroyed" / "Lose when destroyed": every object marked
    /// shares one Destroyed trigger. The win one is semi-persistent, so it
    /// fires once all of its targets are gone (TRIGGER.CPP's attached-object
    /// count); the lose one is volatile, so losing any of them loses.
    func setOutcomeIfDestroyed(_ s: Selection, action: String, _ on: Bool) {
        let persistence = action == "Win" ? 1 : 0
        edit {
            let current = trigger(s)
            let existing = doc.mission.triggers.first {
                $0.event == "Destroyed" && $0.action == action && $0.persistence == persistence
            }
            if on {
                let name: String
                if let existing { name = existing.name } else {
                    name = doc.mission.newTriggerName(action == "Win" ? "DW" : "DL")
                    doc.mission.addTrigger(EditorTrigger(name: name, event: "Destroyed", action: action,
                                                         house: (house(s) ?? doc.mission.enemy).rawValue,
                                                         persistence: persistence))
                }
                setTrigger(s, name)
            } else if current == existing?.name {
                setTrigger(s, "None")
            }
            dropUnusedObjectTriggers()
        }
    }

    /// Removes Destroyed goals no object carries any more.
    func dropUnusedObjectTriggers() {
        let used = Set(doc.data.structures.map(\.trigger) + doc.data.units.map(\.trigger) + doc.data.infantry.map(\.trigger))
        for t in doc.mission.triggers where t.event == "Destroyed" && !used.contains(t.name) {
            doc.mission.removeTrigger(named: t.name)
        }
    }

    /// Marks or unmarks `cell` as one of `trigger`'s spots.
    func toggleSpot(_ cell: Int, for trigger: String) {
        edit {
            if let i = doc.data.cellTriggers.firstIndex(where: { $0.cell == cell && $0.triggerName == trigger }) {
                doc.data.cellTriggers.remove(at: i)
            } else {
                doc.data.cellTriggers.removeAll { $0.cell == cell }
                doc.data.cellTriggers.append(ScenarioCellTrigger(cell: cell, triggerName: trigger))
            }
        }
    }

    func removeTrigger(_ name: String) {
        edit {
            doc.mission.removeTrigger(named: name)
            doc.data.cellTriggers.removeAll { $0.triggerName == name }
            for s in allObjects() where trigger(s) == name { setTrigger(s, "None") }
        }
        if markingSpotsFor == name { markingSpotsFor = nil }
        if activeReinforcement == name { activeReinforcement = nil }
    }

    func allObjects() -> [Selection] {
        doc.data.structures.indices.map { .structure($0) } + doc.data.units.indices.map { .unit($0) }
            + doc.data.infantry.indices.map { .infantry($0) }
    }

    // MARK: Layout

    var panelWidth: Int32 { renderState.windowWidth >= 1100 ? 420 : 360 }
    var panelX: Int32 { renderState.windowWidth - panelWidth }
    /// The toolbar across the top, and where the panel's scrolling content starts.
    let toolbarHeight: Int32 = 36
    let headerHeight: Int32 = 70

    // MARK: Render

    func render(_ renderer: OpaquePointer?) {
        if session.world != nil {  // back from a play-test
            showDocument(resetCamera: false)
            if let c = savedCamera {
                renderState.cameraX = c.x
                renderState.cameraY = c.y
                renderState.zoomLevel = c.zoom
            }
        }
        renderState.animationFrame += 1
        mapViewRightInset = panelWidth
        renderState.showCellTriggers = false
        renderState.showInfoPanel = false
        renderMapViewer(renderer)
        mapViewRightInset = 0
        hits.removeAll()
        drawMapOverlays(renderer)
        drawPanel(renderer)
        drawToolbar(renderer)
        drawStatusBar(renderer)
    }

    func toScreen(_ wx: Int, _ wy: Int) -> (Int32, Int32) {
        let z = renderState.zoomLevel
        return (Int32(Double(wx - renderState.cameraX) * z), Int32(Double(wy - renderState.cameraY) * z))
    }

    func cellRect(_ cell: Int, w: Int = 1, h: Int = 1) -> SDL_Rect {
        let (x, y) = cellToXY(cell)
        let (sx, sy) = toScreen(x * 24, y * 24)
        let side = Double(24) * renderState.zoomLevel
        return SDL_Rect(x: sx, y: sy, w: Int32(side * Double(w)), h: Int32(side * Double(h)))
    }

    func outline(_ r: OpaquePointer?, _ rect: SDL_Rect, _ c: Color, thick: Int32 = 2) {
        SDL_SetRenderDrawColor(r, c.r, c.g, c.b, c.a)
        for i in 0..<thick {
            var rr = SDL_Rect(x: rect.x + i, y: rect.y + i, w: rect.w - 2 * i, h: rect.h - 2 * i)
            SDL_RenderDrawRect(r, &rr)
        }
    }

    func fill(_ r: OpaquePointer?, _ rect: SDL_Rect, _ c: Color, alpha: UInt8) {
        SDL_SetRenderDrawBlendMode(r, SDL_BLENDMODE_BLEND)
        SDL_SetRenderDrawColor(r, c.r, c.g, c.b, alpha)
        var rr = rect
        SDL_RenderFillRect(r, &rr)
    }

    func objectRect(_ s: Selection) -> SDL_Rect {
        switch s {
        case .structure(let i):
            let st = doc.data.structures[i]
            let size = buildingSize(st.typeName)
            return cellRect(st.cell, w: size.w, h: size.h)
        case .terrain(let i):
            // The picture stands on its cell and reaches up a cell.
            let cell = doc.data.terrain[i].cell
            return cellToXY(cell).y > 0 ? cellRect(cell - 64, w: 2, h: 2) : cellRect(cell, w: 2, h: 1)
        default:
            return cellRect(cellOf(s))
        }
    }

    func drawMapOverlays(_ r: OpaquePointer?) {
        var clip = SDL_Rect(x: 0, y: 0, w: panelX, h: renderState.windowHeight)
        SDL_RenderSetClipRect(r, &clip)
        defer { SDL_RenderSetClipRect(r, nil) }
        if showBlocked { drawBlocked(r) }
        if let s = selection, isValid(s), tab == .map {
            outline(r, objectRect(s), .white)
        }
        if tab == .map {
            drawMapToolOverlays(r)
            return
        }

        // Marked spots: the goal or reinforcement being edited bright, the
        // rest dim.
        for ct in doc.data.cellTriggers {
            let mine = ct.triggerName == markingSpotsFor
            let t = doc.mission.triggers.first { $0.name == ct.triggerName }
            let c: Color = t?.actionType == .lose ? .red : (t?.actionType == .reinforcements ? .cyan : .brightGreen)
            fill(r, cellRect(ct.cell), c, alpha: mine ? 110 : 50)
            if mine { outline(r, cellRect(ct.cell), c, thick: 1) }
        }
        // Objects carrying a win/lose-if-destroyed goal.
        for s in allObjects() {
            let t = trigger(s)
            guard t != "None", let trig = doc.mission.triggers.first(where: { $0.name == t }),
                  trig.event == "Destroyed" else { continue }
            outline(r, objectRect(s), trig.action == "Win" ? .brightGreen : .red, thick: 1)
        }
        if let s = selection, isValid(s) {
            outline(r, objectRect(s), .white)
        }
        // Where a placement or drag would land.
        if let cell = cellUnderMouse() {
            let type = dragFrom != nil ? selection.map(typeName) : placeType
            if let type, markingSpotsFor == nil {
                let fit = canPlace(type, at: cell, except: dragFrom != nil ? selection : nil, preferredSub: subUnderMouse())
                let size = kind(of: type) == .buildings ? buildingSize(type) : (w: 1, h: 1)
                let rect = cellRect(cell, w: size.w, h: size.h)
                fill(r, rect, fit.ok ? .brightGreen : .red, alpha: 70)
                outline(r, rect, fit.ok ? .brightGreen : .red, thick: 1)
            } else if markingSpotsFor != nil {
                outline(r, cellRect(cell), .cyan, thick: 1)
            }
        }
    }

    func drawStatusBar(_ r: OpaquePointer?) {
        let w = panelX
        var hint: String
        if tab == .map {
            hint = mapHint
        } else if markingSpotsFor != nil {
            hint = "CLICK CELLS TO MARK OR UNMARK. RIGHT CLICK WHEN DONE"
        } else if let t = placeType {
            hint = "CLICK TO PLACE \(displayName(t).uppercased()). RIGHT CLICK TO STOP"
        } else {
            hint = "CLICK SELECTS. DRAG MOVES. DEL DELETES. R TURNS. RIGHT DRAG PANS"
        }
        if SDL_GetTicks64() - statusTicks < 4000 && !status.isEmpty { hint = status }
        fill(r, SDL_Rect(x: 0, y: renderState.windowHeight - 20, w: w, h: 20), .black, alpha: 170)
        drawTextLeft(r, hint, x: 8, y: renderState.windowHeight - 16, color: .green, scale: 1)
    }

    // MARK: Input

    func cellUnderMouse() -> Int? { cell(atX: input.mouseX, y: input.mouseY) }

    func subUnderMouse() -> Int { sub(atX: input.mouseX, y: input.mouseY) }

    func cell(atX x: Int32, y: Int32) -> Int? {
        guard x >= 0, x < panelX, y >= toolbarHeight, y < renderState.windowHeight else { return nil }
        let wx = renderState.cameraX + Int(Double(x) / renderState.zoomLevel)
        let wy = renderState.cameraY + Int(Double(y) / renderState.zoomLevel)
        guard wx >= 0, wy >= 0, wx < 64 * 24, wy < 64 * 24 else { return nil }
        return (wy / 24) * 64 + wx / 24
    }

    /// The infantry spot under the mouse: the middle, or a corner.
    func sub(atX x: Int32, y: Int32) -> Int {
        let wx = (renderState.cameraX + Int(Double(x) / renderState.zoomLevel)) % 24
        let wy = (renderState.cameraY + Int(Double(y) / renderState.zoomLevel)) % 24
        if (7...16).contains(wx) && (7...16).contains(wy) { return 0 }
        return wy < 12 ? (wx < 12 ? 1 : 2) : (wx < 12 ? 3 : 4)
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        if x >= panelX || y < toolbarHeight {
            guard button == UInt8(SDL_BUTTON_LEFT) else { return }
            renaming = renaming && y < headerHeight + 60 && tab == .file
            for hit in hits.reversed() where SDL_PointInRect([SDL_Point(x: x, y: y)], [hit.rect]) == SDL_TRUE {
                hit.action()
                return
            }
            return
        }
        renaming = false
        if tab == .map && button == UInt8(SDL_BUTTON_LEFT) {
            if let edges = boundsEdges(nearX: x, y: y) {
                edit {}  // the drag is one undo step
                resizing = edges
                return
            }
            if mapTool != .select {
                if let cell = cell(atX: x, y: y) { startPainting(at: cell) }
                return
            }
        }
        if button == UInt8(SDL_BUTTON_RIGHT) {
            if markingSpotsFor != nil || placeType != nil {
                markingSpotsFor = nil
                placeType = nil
            } else {
                panning = true
            }
            return
        }
        guard button == UInt8(SDL_BUTTON_LEFT), let cell = cell(atX: x, y: y) else { return }
        if let trigger = markingSpotsFor {
            toggleSpot(cell, for: trigger)
            return
        }
        if let type = placeType {
            place(type, at: cell, sub: sub(atX: x, y: y))
            return
        }
        if tab != .units && tab != .map { switchTab(.units) }
        selection = object(at: cell, sub: sub(atX: x, y: y))
        if selection != nil {
            dragFrom = cell
            dragCell = cell
            dragMoved = false
        }
    }

    func handleMouseUp(_ x: Int32, _ y: Int32, button: UInt8) {
        panning = false
        painting = false
        resizing = nil
        guard let from = dragFrom else { return }
        dragFrom = nil
        guard let s = selection, let cell = cell(atX: x, y: y) else { return }
        // A click without a drag leaves the object where it is; within its
        // own cell, a drag moves infantry to another spot.
        if cell == from {
            guard case .infantry = s, dragMoved else { return }
        }
        move(s, to: structureAnchor(s, from: from, to: cell), sub: sub(atX: x, y: y))
    }

    /// Whether the mouse left the press point by more than a few pixels.
    var dragMoved = false

    /// Dragging a building by any of its cells keeps that grip.
    func structureAnchor(_ s: Selection, from: Int, to: Int) -> Int {
        guard case .structure(let i) = s else { return to }
        let origin = doc.data.structures[i].cell
        let (ox, oy) = cellToXY(origin), (fx, fy) = cellToXY(from), (tx, ty) = cellToXY(to)
        let nx = max(0, min(63, ox + tx - fx)), ny = max(0, min(63, oy + ty - fy))
        return ny * 64 + nx
    }

    func handleMouseMotion(_ x: Int32, _ y: Int32, xrel: Int32, yrel: Int32) {
        if panning {
            renderState.cameraX -= Int(Double(xrel) / renderState.zoomLevel)
            renderState.cameraY -= Int(Double(yrel) / renderState.zoomLevel)
            clampCamera()
        }
        if painting, let cell = cell(atX: x, y: y) { paint(at: cell) }
        if let edges = resizing { dragBounds(edges, toX: x, y: y) }
        if dragFrom != nil {
            dragCell = cell(atX: x, y: y)
            if abs(xrel) + abs(yrel) > 0 { dragMoved = true }
        }
    }

    func handleMouseWheel(_ dy: Int32, atX: Int32, atY: Int32) {
        if atX >= panelX || atY < toolbarHeight {
            let s = (scroll[tab] ?? 0) - dy * 40
            scroll[tab] = max(0, min(max(0, contentHeight - (renderState.windowHeight - headerHeight)), s))
            return
        }
        let old = renderState.zoomLevel
        let new = max(0.5, min(3.0, old + (dy > 0 ? 0.25 : -0.25)))
        guard abs(new - old) > 0.001 else { return }
        renderState.cameraX += Int(Double(atX) * (1 / old - 1 / new))
        renderState.cameraY += Int(Double(atY) * (1 / old - 1 / new))
        renderState.zoomLevel = new
        clampCamera()
    }

    func clampCamera() {
        let visW = Int(Double(panelX) / renderState.zoomLevel)
        let visH = Int(Double(renderState.windowHeight) / renderState.zoomLevel)
        renderState.cameraX = max(-visW / 2, min(64 * 24 - visW / 2, renderState.cameraX))
        renderState.cameraY = max(-visH / 2, min(64 * 24 - visH / 2, renderState.cameraY))
    }

    func handleContinuousInput() {
        guard !renaming, let keys = SDL_GetKeyboardState(nil) else { return }
        let speed = max(1, Int(10.0 / renderState.zoomLevel))
        if keys[Int(SDL_SCANCODE_LEFT.rawValue)] != 0 { renderState.cameraX -= speed }
        if keys[Int(SDL_SCANCODE_RIGHT.rawValue)] != 0 { renderState.cameraX += speed }
        if keys[Int(SDL_SCANCODE_UP.rawValue)] != 0 { renderState.cameraY -= speed }
        if keys[Int(SDL_SCANCODE_DOWN.rawValue)] != 0 { renderState.cameraY += speed }
        clampCamera()
    }

    func handleTextInput(_ text: String) {
        guard renaming else { return }
        let allowed = text.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        rename(String((doc.name + allowed).prefix(12)))
    }

    func rename(_ name: String) {
        // SCG/SCB names are the campaign's: the game reads the side from them.
        guard !name.uppercased().hasPrefix("SC") else {
            say("NAMES STARTING WITH SC ARE THE CAMPAIGN'S")
            return
        }
        doc.name = name
        dirty = true
    }

    func handleKeyDown(_ key: Int32) {
        let cmd = (SDL_GetModState().rawValue & UInt32(KMOD_GUI.rawValue | KMOD_CTRL.rawValue)) != 0
        let shift = (SDL_GetModState().rawValue & UInt32(KMOD_SHIFT.rawValue)) != 0
        if renaming {
            switch key {
            case Int32(SDLK_RETURN.rawValue), Int32(SDLK_ESCAPE.rawValue): renaming = false
            case Int32(SDLK_BACKSPACE.rawValue) where doc.name.count > 1: rename(String(doc.name.dropLast()))
            default: break
            }
            return
        }
        switch key {
        case Int32(SDLK_ESCAPE.rawValue):
            if markingSpotsFor != nil || placeType != nil {
                markingSpotsFor = nil
                placeType = nil
            } else if selection != nil {
                selection = nil
            } else {
                exit()
            }
        case Int32(SDLK_z.rawValue) where cmd: shift ? redo() : undo()
        case Int32(SDLK_y.rawValue) where cmd: redo()
        case Int32(SDLK_DELETE.rawValue), Int32(SDLK_BACKSPACE.rawValue):
            if let s = selection { delete(s) }
        case Int32(SDLK_r.rawValue):
            if let s = selection { rotate(s, by: shift ? -32 : 32) }
        case Int32(SDLK_g.rawValue):
            renderState.showGrid.toggle()
        case Int32(SDLK_p.rawValue) where cmd:
            playTest()
        case Int32(SDLK_EQUALS.rawValue):
            renderState.zoomLevel = min(3.0, renderState.zoomLevel + 0.25)
        case Int32(SDLK_MINUS.rawValue):
            renderState.zoomLevel = max(0.5, renderState.zoomLevel - 0.25)
        default:
            break
        }
    }
}
