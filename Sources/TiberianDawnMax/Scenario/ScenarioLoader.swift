import Foundation

// MARK: - Theater Type

enum TheaterType: String, CaseIterable {
    case temperate = "TEMPERATE"
    case desert = "DESERT"
    case winter = "WINTER"

    var suffix: String {
        switch self {
        case .temperate: return ".TEM"
        case .desert:    return ".DES"
        case .winter:    return ".WIN"
        }
    }

    var paletteName: String {
        switch self {
        case .temperate: return "TEMPERAT.PAL"
        case .desert:    return "DESERT.PAL"
        case .winter:    return "WINTER.PAL"
        }
    }

    var mixName: String {
        switch self {
        case .temperate: return "TEMPERAT.MIX"
        case .desert:    return "DESERT.MIX"
        case .winter:    return "WINTER.MIX"
        }
    }

    static func from(_ string: String) -> TheaterType {
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

enum House: String, CaseIterable {
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

    var displayColor: (r: UInt8, g: UInt8, b: UInt8) {
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

    static func from(_ string: String) -> House {
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

struct MapBounds: Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct ScenarioTerrain: Equatable {
    let cell: Int
    let typeName: String  // e.g. "T08", "TC01"
}

struct ScenarioOverlay: Equatable {
    let cell: Int
    let typeName: String  // e.g. "TI1", "SBAG"
}

struct ScenarioStructure: Equatable {
    let house: House
    let typeName: String   // e.g. "FACT", "PYLE"
    let strength: Int
    let cell: Int
    let facing: Int
    let trigger: String
}

struct ScenarioUnit: Equatable {
    let house: House
    let typeName: String   // e.g. "MTNK", "JEEP"
    let strength: Int
    let cell: Int
    let facing: Int
    let mission: String
    let trigger: String
}

struct ScenarioInfantry: Equatable {
    let house: House
    let typeName: String   // e.g. "E1", "E3"
    let strength: Int
    let cell: Int
    let subLocation: Int   // 0-4 sub-cell position
    let mission: String
    let facing: Int
    let trigger: String
}

struct ScenarioWaypoint: Equatable {
    let id: Int
    let cell: Int
}

struct ScenarioCellTrigger: Equatable {
    let cell: Int
    let triggerName: String
}

struct ScenarioBaseBuilding: Equatable {
    let typeName: String
    let cell: Int
}

// MARK: - Scenario Data

struct ScenarioData {
    // `var` on the entity lists so the editor (EditorScenario) can place, move,
    // and delete objects. Readers (GameInit, renderers) are unaffected.
    let theater: TheaterType
    let mapBounds: MapBounds?
    let terrain: [ScenarioTerrain]
    let overlays: [ScenarioOverlay]
    var structures: [ScenarioStructure]
    var units: [ScenarioUnit]
    var infantry: [ScenarioInfantry]
    let waypoints: [ScenarioWaypoint]
    var cellTriggers: [ScenarioCellTrigger]
    var baseBuildings: [ScenarioBaseBuilding]
    let ini: INIFile  // Keep reference for trigger parsing
    let credits: Int      // Starting credits from [Basic] section
    let buildLevel: Int   // Tech level cap from [Basic] section (1-15)
}

// MARK: - Cell Coordinate Helpers

/// Convert cell number to (x, y) on the 64x64 grid
func cellToXY(_ cell: Int) -> (x: Int, y: Int) {
    return (x: cell % 64, y: cell / 64)
}

/// Convert cell number to pixel position (top-left of cell)
func cellToPixel(_ cell: Int) -> (px: Int, py: Int) {
    let xy = cellToXY(cell)
    return (px: xy.x * 24, py: xy.y * 24)
}

// MARK: - Sub-cell offsets for infantry (5 positions within a cell)

/// Returns pixel offset within a 24x24 cell for infantry sub-positions
func subCellOffset(_ subLocation: Int) -> (dx: Int, dy: Int) {
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
func buildingSize(_ typeName: String) -> (w: Int, h: Int) {
    let upper = typeName.uppercased()
    if let st = StructType.from(iniName: upper), let data = buildingTypeDataTable[st] {
        return (w: data.sizeW, h: data.sizeH)
    }
    return (w: 2, h: 2)  // fallback
}

// MARK: - Scenario Loader

func loadScenario(_ name: String, from mixManager: MIXFileManager) -> ScenarioData? {
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
func parseScenarioData(_ ini: INIFile, name: String) -> ScenarioData {
    // [Basic] section — build level
    let buildLevel = ini.int("Basic", "BuildLevel", default: 1)

    // Credits: check player house section first ([GoodGuy] or [BadGuy]),
    // then fall back to [Basic]. C&C stores credits as value/100.
    let playerSection = name.uppercased().hasPrefix("SCB") ? "BadGuy" : "GoodGuy"
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
            // Strip trigger name after comma (e.g. "T08,NONE" -> "T08")
            let typeName = entry.value.components(separatedBy: ",").first ?? entry.value
            terrain.append(ScenarioTerrain(cell: cell, typeName: typeName.trimmingCharacters(in: .whitespaces)))
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
        buildLevel: buildLevel
    )
}
