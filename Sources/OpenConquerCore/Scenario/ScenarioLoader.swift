import Foundation
import OpenConquerAssets

// MARK: - Theater Type

package enum TheaterType: String, CaseIterable {
    case temperate = "TEMPERATE"
    case desert = "DESERT"
    case winter = "WINTER"

    package var suffix: String {
        switch self {
        case .temperate: return ".TEM"
        case .desert:    return ".DES"
        case .winter:    return ".WIN"
        }
    }

    package var paletteName: String {
        switch self {
        case .temperate: return "TEMPERAT.PAL"
        case .desert:    return "DESERT.PAL"
        case .winter:    return "WINTER.PAL"
        }
    }

    package var mixName: String {
        switch self {
        case .temperate: return "TEMPERAT.MIX"
        case .desert:    return "DESERT.MIX"
        case .winter:    return "WINTER.MIX"
        }
    }

    package static func from(_ string: String) -> TheaterType {
        let upper = string.uppercased()
        for theater in TheaterType.allCases {
            if upper == theater.rawValue {
                return theater
            }
        }
        return .temperate
    }
}

// MARK: - House (Faction)

package enum House: String, CaseIterable {
    case goodGuy = "GoodGuy"   // GDI
    case badGuy = "BadGuy"     // Nod
    case neutral = "Neutral"
    case special = "Special"
    case multi1 = "Multi1"
    case multi2 = "Multi2"
    case multi3 = "Multi3"
    case multi4 = "Multi4"
    case multi5 = "Multi5"
    case multi6 = "Multi6"

    package var displayColor: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .goodGuy: return (r: 220, g: 180, b: 40)   // Gold/yellow for GDI
        case .badGuy:  return (r: 200, g: 40,  b: 40)   // Red for Nod
        case .neutral: return (r: 140, g: 140, b: 140)  // Gray
        case .special: return (r: 180, g: 180, b: 40)   // Yellow-ish
        case .multi1:  return (r: 100, g: 160, b: 220)  // Light blue
        case .multi2:  return (r: 220, g: 140, b: 40)   // Orange
        case .multi3:  return (r: 40,  g: 180, b: 40)   // Green
        case .multi4:  return (r: 220, g: 180, b: 40)   // Gold (same as GDI)
        case .multi5:  return (r: 200, g: 40,  b: 40)   // Red (same as Nod)
        case .multi6:  return (r: 40,  g: 40,  b: 200)  // Blue
        }
    }

    package static func from(_ string: String) -> House {
        let lower = string.lowercased()
        // Check raw values first (GoodGuy, BadGuy, etc.)
        for house in House.allCases {
            if lower == house.rawValue.lowercased() {
                return house
            }
        }
        // Also accept common INI aliases
        switch lower {
        case "gdi":      return .goodGuy
        case "nod":      return .badGuy
        case "civilian": return .neutral
        case "jp":       return .neutral   // Japanese campaign
        default:         return .neutral
        }
    }
}

// MARK: - Scenario Data Types

package struct MapBounds: Equatable {
    package let x: Int
    package let y: Int
    package let width: Int
    package let height: Int

    package init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

package struct ScenarioTerrain: Equatable {
    package var cell: Int
    package var typeName: String  // e.g. "T08", "TC01"
    package var trigger: String   // the [TERRAIN] value's second field, usually "None"

    package init(cell: Int, typeName: String, trigger: String = "None") {
        self.cell = cell
        self.typeName = typeName
        self.trigger = trigger
    }
}

package struct ScenarioOverlay: Equatable {
    package var cell: Int
    package var typeName: String  // e.g. "TI1", "SBAG"

    package init(cell: Int, typeName: String) {
        self.cell = cell
        self.typeName = typeName
    }
}

package struct ScenarioStructure: Equatable {
    package var house: House
    package var typeName: String   // e.g. "FACT", "PYLE"
    package var strength: Int
    package var cell: Int
    package var facing: Int
    package var trigger: String

    package init(house: House, typeName: String, strength: Int, cell: Int, facing: Int, trigger: String) {
        self.house = house
        self.typeName = typeName
        self.strength = strength
        self.cell = cell
        self.facing = facing
        self.trigger = trigger
    }
}

package struct ScenarioUnit: Equatable {
    package var house: House
    package var typeName: String   // e.g. "MTNK", "JEEP"
    package var strength: Int
    package var cell: Int
    package var facing: Int
    package var mission: String
    package var trigger: String

    package init(house: House, typeName: String, strength: Int, cell: Int, facing: Int, mission: String, trigger: String) {
        self.house = house
        self.typeName = typeName
        self.strength = strength
        self.cell = cell
        self.facing = facing
        self.mission = mission
        self.trigger = trigger
    }
}

package struct ScenarioInfantry: Equatable {
    package var house: House
    package var typeName: String   // e.g. "E1", "E3"
    package var strength: Int
    package var cell: Int
    package var subLocation: Int   // 0-4 sub-cell position
    package var mission: String
    package var facing: Int
    package var trigger: String

    package init(house: House, typeName: String, strength: Int, cell: Int, subLocation: Int,
                 mission: String, facing: Int, trigger: String) {
        self.house = house
        self.typeName = typeName
        self.strength = strength
        self.cell = cell
        self.subLocation = subLocation
        self.mission = mission
        self.facing = facing
        self.trigger = trigger
    }
}

package struct ScenarioWaypoint: Equatable {
    package var id: Int
    package var cell: Int

    package init(id: Int, cell: Int) {
        self.id = id
        self.cell = cell
    }
}

package struct ScenarioCellTrigger: Equatable {
    package var cell: Int
    package var triggerName: String

    package init(cell: Int, triggerName: String) {
        self.cell = cell
        self.triggerName = triggerName
    }
}

package struct ScenarioBaseBuilding: Equatable {
    package let typeName: String
    package let cell: Int
}

// MARK: - Scenario Data

package struct ScenarioData {
    // `var` on the entity lists so the editor (EditorScenario) can place, move,
    // and delete objects. Readers (GameInit, renderers) are unaffected.
    package let theater: TheaterType
    package var mapBounds: MapBounds?
    package var terrain: [ScenarioTerrain]
    package var overlays: [ScenarioOverlay]
    package var structures: [ScenarioStructure]
    package var units: [ScenarioUnit]
    package var infantry: [ScenarioInfantry]
    package var waypoints: [ScenarioWaypoint]
    package var cellTriggers: [ScenarioCellTrigger]
    package var baseBuildings: [ScenarioBaseBuilding]
    package let ini: INIFile  // Keep reference for trigger parsing
    package let credits: Int      // Starting credits from [Basic] section
    package let buildLevel: Int   // Tech level cap from [Basic] section (1-15)
    package let houseEdges: [House: MapEdge]  // Edge= per house section (reinforcement entry)
    package let playerHouse: House  // See scenarioPlayerHouse
}

/// The side the player commands. The campaign's names say it (SCG = GDI,
/// SCB = Nod), as the game has always read them; any other mission, such as
/// one made in the mission editor, says it with [Basic] Player= (INI.CPP:354,
/// default GoodGuy).
package func scenarioPlayerHouse(_ ini: INIFile, name: String) -> House {
    let upper = name.uppercased()
    if upper.hasPrefix("SCB") { return .badGuy }
    if upper.hasPrefix("SCG") { return .goodGuy }
    let player = House.from(ini.string("Basic", "Player", default: "GoodGuy"))
    return player == .badGuy ? .badGuy : .goodGuy
}

/// [Buildables] Allow=TYPE,TYPE / Deny=TYPE,TYPE — a mission's changes to
/// what its tech level gives the player. The mission editor's own section;
/// the 1995 game ignores it (it reads only the sections it knows).
package func parseBuildables(_ ini: INIFile) -> (allow: Set<String>, deny: Set<String>) {
    func list(_ key: String) -> Set<String> {
        Set(ini.string("Buildables", key).split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty })
    }
    return (list("Allow"), list("Deny"))
}

// MARK: - Cell Coordinate Helpers

/// Convert cell number to (x, y) on the 64x64 grid
package func cellToXY(_ cell: Int) -> (x: Int, y: Int) {
    return (x: cell % 64, y: cell / 64)
}

/// Convert cell number to pixel position (top-left of cell)
package func cellToPixel(_ cell: Int) -> (px: Int, py: Int) {
    let xy = cellToXY(cell)
    return (px: xy.x * 24, py: xy.y * 24)
}

// MARK: - Sub-cell offsets for infantry (5 positions within a cell)

/// Returns pixel offset within a 24x24 cell for infantry sub-positions
package func subCellOffset(_ subLocation: Int) -> (dx: Int, dy: Int) {
    switch subLocation {
    case 0: return (dx: 6,  dy: 6)   // Center
    case 1: return (dx: 2,  dy: 2)   // Top-left
    case 2: return (dx: 14, dy: 2)   // Top-right
    case 3: return (dx: 2,  dy: 14)  // Bottom-left
    case 4: return (dx: 14, dy: 14)  // Bottom-right
    default: return (dx: 6, dy: 6)
    }
}

// MARK: - Building Size Lookup

/// Returns (width, height) in cells for known building types
package func buildingSize(_ typeName: String) -> (w: Int, h: Int) {
    let upper = typeName.uppercased()
    if let st = StructType.from(iniName: upper), let data = buildingTypeDataTable[st] {
        return (w: data.sizeW, h: data.sizeH)
    }
    return (w: 2, h: 2)  // fallback
}

// MARK: - Scenario Loader

package func loadScenario(_ name: String, from mixManager: MIXFileManager) -> ScenarioData? {
    guard let data = mixManager.retrieve(name) else {
        print("ScenarioLoader: Could not find \(name)")
        return nil
    }
    let ini = INIFile(data: data)
    if ini.isEmpty {
        print("ScenarioLoader: WARNING — \(name) parsed to zero INI sections (\(data.count) bytes); scenario would load blank")
    }
    return parseScenarioData(ini, name: name)
}

/// Parse an already-loaded `INIFile` into a `ScenarioData`. Split out of
/// `loadScenario` so the editor can re-parse serialized INI text (round-trip)
/// without going through the MIX archive.
package func parseScenarioData(_ ini: INIFile, name: String) -> ScenarioData {
    // [Basic] section — build level
    let buildLevel = ini.int("Basic", "BuildLevel", default: 1)

    // Credits: check player house section first ([GoodGuy] or [BadGuy]),
    // then fall back to [Basic]. C&C stores credits as value/100.
    let playerHouse = scenarioPlayerHouse(ini, name: name)
    let playerSection = playerHouse.rawValue
    let houseCredits = ini.int(playerSection, "Credits", default: -1)
    let basicCredits = ini.int("Basic", "Credits", default: 0)
    let credits = (houseCredits >= 0 ? houseCredits : basicCredits) * 100

    // [MAP] section
    let theaterStr = ini.string("MAP", "Theater", default: "TEMPERATE")
    let theater = TheaterType.from(theaterStr)

    var mapBounds: MapBounds? = nil
    if ini.hasSection("MAP") {
        let x = ini.int("MAP", "X", default: 0)
        let y = ini.int("MAP", "Y", default: 0)
        let width = ini.int("MAP", "Width", default: 64)
        let height = ini.int("MAP", "Height", default: 64)
        mapBounds = MapBounds(x: x, y: y, width: width, height: height)
    }

    // [TERRAIN] — key is cell number, value is "TypeName" or "TypeName,TriggerName"
    var terrain: [ScenarioTerrain] = []
    for entry in ini.entries("TERRAIN") {
        if let cell = Int(entry.key) {
            // "T08,None": the type, then a trigger name
            let parts = entry.value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            terrain.append(ScenarioTerrain(cell: cell, typeName: parts[0], trigger: parts.count > 1 ? parts[1] : "None"))
        }
    }

    // [OVERLAY] — key is cell number, value is overlay type
    var overlays: [ScenarioOverlay] = []
    for entry in ini.entries("OVERLAY") {
        if let cell = Int(entry.key) {
            let typeName = entry.value.trimmingCharacters(in: .whitespaces)
            overlays.append(ScenarioOverlay(cell: cell, typeName: typeName))
        }
    }

    // [STRUCTURES] — value format: House,Type,Strength,Cell,Facing,Trigger
    var structures: [ScenarioStructure] = []
    for entry in ini.entries("STRUCTURES") {
        let parts = entry.value.components(separatedBy: ",")
        if parts.count >= 5 {
            let house = House.from(parts[0].trimmingCharacters(in: .whitespaces))
            let typeName = parts[1].trimmingCharacters(in: .whitespaces)
            let strength = Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 256
            let cell = Int(parts[3].trimmingCharacters(in: .whitespaces)) ?? 0
            let facing = Int(parts[4].trimmingCharacters(in: .whitespaces)) ?? 0
            let trigger = parts.count > 5 ? parts[5].trimmingCharacters(in: .whitespaces) : "None"
            structures.append(ScenarioStructure(
                house: house, typeName: typeName, strength: strength,
                cell: cell, facing: facing, trigger: trigger
            ))
        }
    }

    // [UNITS] — value format: House,Type,Strength,Cell,Facing,Mission,Trigger
    var units: [ScenarioUnit] = []
    for entry in ini.entries("UNITS") {
        let parts = entry.value.components(separatedBy: ",")
        if parts.count >= 6 {
            let house = House.from(parts[0].trimmingCharacters(in: .whitespaces))
            let typeName = parts[1].trimmingCharacters(in: .whitespaces)
            let strength = Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 256
            let cell = Int(parts[3].trimmingCharacters(in: .whitespaces)) ?? 0
            let facing = Int(parts[4].trimmingCharacters(in: .whitespaces)) ?? 0
            let mission = parts[5].trimmingCharacters(in: .whitespaces)
            let trigger = parts.count > 6 ? parts[6].trimmingCharacters(in: .whitespaces) : "None"
            units.append(ScenarioUnit(
                house: house, typeName: typeName, strength: strength,
                cell: cell, facing: facing, mission: mission, trigger: trigger
            ))
        }
    }

    // [INFANTRY] — value format: House,Type,Strength,Cell,SubLocation,Mission,Facing,Trigger
    var infantry: [ScenarioInfantry] = []
    for entry in ini.entries("INFANTRY") {
        let parts = entry.value.components(separatedBy: ",")
        if parts.count >= 7 {
            let house = House.from(parts[0].trimmingCharacters(in: .whitespaces))
            let typeName = parts[1].trimmingCharacters(in: .whitespaces)
            let strength = Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 256
            let cell = Int(parts[3].trimmingCharacters(in: .whitespaces)) ?? 0
            let subLocation = Int(parts[4].trimmingCharacters(in: .whitespaces)) ?? 0
            let mission = parts[5].trimmingCharacters(in: .whitespaces)
            let facing = Int(parts[6].trimmingCharacters(in: .whitespaces)) ?? 0
            let trigger = parts.count > 7 ? parts[7].trimmingCharacters(in: .whitespaces) : "None"
            infantry.append(ScenarioInfantry(
                house: house, typeName: typeName, strength: strength,
                cell: cell, subLocation: subLocation, mission: mission,
                facing: facing, trigger: trigger
            ))
        }
    }

    // [WAYPOINTS] — key is waypoint ID, value is cell number
    var waypoints: [ScenarioWaypoint] = []
    for entry in ini.entries("WAYPOINTS") {
        if let id = Int(entry.key), let cell = Int(entry.value), cell >= 0 {
            waypoints.append(ScenarioWaypoint(id: id, cell: cell))
        }
    }

    // [CellTriggers] — key is cell number, value is trigger name
    var cellTriggers: [ScenarioCellTrigger] = []
    for entry in ini.entries("CELLTRIGGERS") {
        if let cell = Int(entry.key) {
            cellTriggers.append(ScenarioCellTrigger(cell: cell, triggerName: entry.value.trimmingCharacters(in: .whitespaces)))
        }
    }

    // [Base] — numbered keys (000, 001, ...), value = "TypeName,CellNumber"
    var baseBuildings: [ScenarioBaseBuilding] = []
    for entry in ini.entries("BASE") {
        // Skip "Count" key
        if entry.key.uppercased() == "COUNT" { continue }
        let parts = entry.value.components(separatedBy: ",")
        if parts.count >= 2 {
            let typeName = parts[0].trimmingCharacters(in: .whitespaces)
            if let cell = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                baseBuildings.append(ScenarioBaseBuilding(typeName: typeName, cell: cell))
            }
        }
    }

    print("ScenarioLoader: Loaded \(name)")
    print("  Theater: \(theater.rawValue)")
    if let bounds = mapBounds {
        print("  Map bounds: \(bounds.x),\(bounds.y) \(bounds.width)x\(bounds.height)")
    }
    print("  Terrain: \(terrain.count), Overlays: \(overlays.count)")
    print("  Structures: \(structures.count), Units: \(units.count), Infantry: \(infantry.count)")
    print("  Waypoints: \(waypoints.count), CellTriggers: \(cellTriggers.count), Base: \(baseBuildings.count)")

    print("  Credits: \(credits), BuildLevel: \(buildLevel)")


    // Edge= from each house section (HOUSE.CPP:1672-1675): the map edge that
    // house's ground/air reinforcements enter from. Missing/invalid → north.
    var houseEdges: [House: MapEdge] = [:]
    for house in House.allCases where ini.hasSection(house.rawValue) {
        if let edge = MapEdge.from(ini.string(house.rawValue, "Edge", default: "")) {
            houseEdges[house] = edge
        }
    }

    return ScenarioData(
        theater: theater,
        mapBounds: mapBounds,
        terrain: terrain,
        overlays: overlays,
        structures: structures,
        units: units,
        infantry: infantry,
        waypoints: waypoints,
        cellTriggers: cellTriggers,
        baseBuildings: baseBuildings,
        ini: ini,
        credits: credits,
        buildLevel: buildLevel,
        houseEdges: houseEdges,
        playerHouse: playerHouse
    )
}
