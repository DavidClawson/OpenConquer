import CSDL2
import Foundation

// MARK: - Build Data (derived from type data tables)

struct BuildableItem {
    let name: String
    let cost: Int
    let buildTicks: Int
    let prerequisite: String?
    let faction: String?  // "GDI", "NOD", or nil for both
}

struct BuildableStructure {
    let name: String
    let cost: Int
    let buildTicks: Int
    let faction: String?
}

/// Generate unit/infantry build list from type data tables
func generateBuildableUnits() -> [BuildableItem] {
    var items: [BuildableItem] = []

    // Infantry from infantryTypeDataTable
    for (_, data) in infantryTypeDataTable {
        guard data.isBuildable else { continue }
        let faction: String?
        if data.ownable.contains(.good) && data.ownable.contains(.bad) {
            faction = nil
        } else if data.ownable.contains(.good) {
            faction = "GDI"
        } else if data.ownable.contains(.bad) {
            faction = "NOD"
        } else {
            continue  // Not buildable by GDI or Nod
        }
        // Infantry need PYLE (GDI) or HAND (Nod) — use prerequisite field if set
        let prereq: String?
        if data.prerequisite != .none {
            prereq = nil  // Has specific prerequisite from struct flags
        } else {
            prereq = faction == "NOD" ? "HAND" : (faction == "GDI" ? "PYLE" : nil)
        }
        let ticks = max(20, data.cost / 5)
        items.append(BuildableItem(name: data.iniName, cost: data.cost,
                                   buildTicks: ticks, prerequisite: prereq, faction: faction))
    }

    // Vehicles from unitTypeDataTable
    for (_, data) in unitTypeDataTable {
        guard data.isBuildable else { continue }
        let faction: String?
        if data.ownable.contains(.good) && data.ownable.contains(.bad) {
            faction = nil
        } else if data.ownable.contains(.good) {
            faction = "GDI"
        } else if data.ownable.contains(.bad) {
            faction = "NOD"
        } else {
            continue
        }
        // Vehicles need WEAP (or PROC for HARV)
        let prereq: String
        if data.iniName == "HARV" {
            prereq = "PROC"
        } else if data.iniName == "MCV" {
            prereq = "WEAP"
        } else {
            prereq = "WEAP"
        }
        let ticks = max(30, data.cost / 5)
        items.append(BuildableItem(name: data.iniName, cost: data.cost,
                                   buildTicks: ticks, prerequisite: prereq, faction: faction))
    }

    // Aircraft from aircraftTypeDataTable
    for (_, data) in aircraftTypeDataTable {
        guard data.isBuildable else { continue }
        let faction: String?
        if data.ownable.contains(.good) && data.ownable.contains(.bad) {
            faction = nil
        } else if data.ownable.contains(.good) {
            faction = "GDI"
        } else if data.ownable.contains(.bad) {
            faction = "NOD"
        } else {
            continue
        }
        // Aircraft need HPAD or AFLD
        let prereq: String = faction == "NOD" ? "AFLD" : "HPAD"
        let ticks = max(30, data.cost / 5)
        items.append(BuildableItem(name: data.iniName, cost: data.cost,
                                   buildTicks: ticks, prerequisite: prereq, faction: faction))
    }

    // Sort by cost for consistent ordering
    items.sort { $0.cost < $1.cost }
    return items
}

/// Generate structure build list from type data tables
func generateBuildableStructures() -> [BuildableStructure] {
    var items: [BuildableStructure] = []

    for (_, data) in buildingTypeDataTable {
        guard data.isBuildable else { continue }
        guard !data.isWall else { continue }  // Walls aren't sidebar buildable
        let faction: String?
        if data.ownable.contains(.good) && data.ownable.contains(.bad) {
            faction = nil
        } else if data.ownable.contains(.good) {
            faction = "GDI"
        } else if data.ownable.contains(.bad) {
            faction = "NOD"
        } else {
            continue
        }
        let ticks = max(30, data.cost / 5)
        items.append(BuildableStructure(name: data.iniName, cost: data.cost,
                                        buildTicks: ticks, faction: faction))
    }

    // Sort by cost for consistent ordering
    items.sort { $0.cost < $1.cost }
    return items
}

// Lazy-initialized build lists from type data
private var _buildableUnits: [BuildableItem]? = nil
private var _buildableStructures: [BuildableStructure]? = nil

var buildableUnits: [BuildableItem] {
    if _buildableUnits == nil { _buildableUnits = generateBuildableUnits() }
    return _buildableUnits!
}

var buildableStructures: [BuildableStructure] {
    if _buildableStructures == nil { _buildableStructures = generateBuildableStructures() }
    return _buildableStructures!
}

// MARK: - Query Functions

/// Get the set of building type names owned by the player
func getOwnedBuildingTypes() -> Set<String> {
    guard let world = session.world else { return [] }
    var owned = Set<String>()
    for obj in world.objects {
        if obj.kind == .structure && obj.house == world.playerHouse && obj.strength > 0 {
            owned.insert(obj.typeName.uppercased())
        }
    }
    return owned
}

/// Get available units the player can build
func getAvailableUnits() -> [BuildableItem] {
    let owned = getOwnedBuildingTypes()
    let faction = session.world?.playerHouse == .goodGuy ? "GDI" : "NOD"
    var seen = Set<String>()
    var result: [BuildableItem] = []
    for item in buildableUnits {
        if let prereq = item.prerequisite, !owned.contains(prereq) { continue }
        if let f = item.faction, f != faction { continue }
        if seen.contains(item.name) { continue }
        seen.insert(item.name)
        result.append(item)
    }
    return result
}

/// Get available structures the player can build
func getAvailableStructures() -> [BuildableStructure] {
    let owned = getOwnedBuildingTypes()
    let faction = session.world?.playerHouse == .goodGuy ? "GDI" : "NOD"
    // Need a construction yard to build structures
    if !owned.contains("FACT") { return [] }
    var result: [BuildableStructure] = []
    for item in buildableStructures {
        if let f = item.faction, f != faction { continue }
        result.append(item)
    }
    return result
}

// MARK: - Production Tick

func tickProduction() {
    guard let world = session.world else { return }

    let houseState = getHouseState(world.playerHouse)

    // Advance unit production
    if session.unitBuildQueue.item != nil {
        let completed = session.unitBuildQueue.tick(hasPower: houseState.hasPower, worldTickCount: world.tickCount)
        if completed {
            spawnProducedUnit(session.unitBuildQueue.item!.typeName, world: world)
            session.unitBuildQueue.clear()
            audioManager.speak(.unitReady)
            audioManager.play(.construction)
        }
    }

    // Advance structure production
    if session.structureBuildQueue.item != nil && !session.structureBuildQueue.isComplete {
        let completed = session.structureBuildQueue.tick(hasPower: houseState.hasPower, worldTickCount: world.tickCount)
        if completed {
            audioManager.speak(.construction)
            audioManager.play(.construction)
        }
        // Don't auto-complete — wait for placement
    }
}

// MARK: - Unit Spawning

func spawnProducedUnit(_ typeName: String, world: GameWorld) {
    let upper = typeName.uppercased()

    // Check if this is an aircraft
    if let acType = AircraftType.from(iniName: upper) {
        // Aircraft spawn at helipad or airstrip
        let padType = world.playerHouse == .badGuy ? "AFLD" : "HPAD"
        guard let pad = world.objects.first(where: {
            $0.kind == .structure && $0.typeName.uppercased() == padType &&
            $0.house == world.playerHouse && $0.strength > 0
        }) else { return }

        let obj = createAircraft(
            world: world,
            type: acType,
            house: world.playerHouse,
            worldX: pad.worldX,
            worldY: pad.worldY,
            facing: 0,
            mission: .guard_
        )
        world.addObject(obj)
        return
    }

    // Find the producing structure
    let producerType: String
    if ["E1", "E2", "E3", "E4", "E5", "E6", "RMBO"].contains(upper) {
        producerType = getOwnedBuildingTypes().contains("PYLE") ? "PYLE" : "HAND"
    } else {
        producerType = "WEAP"
    }

    // Find the producing structure
    guard let producer = world.objects.first(where: {
        $0.kind == .structure && $0.typeName.uppercased() == producerType && $0.house == world.playerHouse && $0.strength > 0
    }) else { return }

    // Spawn near the exit of the producing structure
    let size = buildingSize(producerType)
    let exitX = producer.worldX + Double(size.w * 24) / 2.0 + 12.0
    let exitY = producer.worldY + Double(size.h * 24) / 2.0

    let isInfantry = ["E1", "E2", "E3", "E4", "E5", "E6", "E7", "RMBO"].contains(upper)
    let kind: ObjectKind = isInfantry ? .infantry : .unit
    let speed = resolveSpeed(typeName: upper, kind: kind)

    let obj = GameObject(
        id: world.allocateId(),
        typeName: typeName,
        house: world.playerHouse,
        kind: kind,
        worldX: exitX, worldY: exitY,
        facing: 128,  // Face south
        strength: resolveStrength(typeName: upper, kind: kind, scenarioStrength: 256),
        mission: upper == "HARV" ? .harvest : .guard_,
        speed: speed
    )
    world.addObject(obj)
}

// MARK: - Structure Placement

func handleStructurePlacement(_ x: Int32, _ y: Int32) {
    guard let world = session.world, let pType = session.placementType else { return }
    let worldPos = gameScreenToWorld(x, y)

    let cellX = Int(worldPos.worldX) / 24
    let cellY = Int(worldPos.worldY) / 24
    let size = buildingSize(pType)

    // Check if area is passable
    for dy in 0..<size.h {
        for dx in 0..<size.w {
            let cx = cellX + dx
            let cy = cellY + dy
            if cx < 0 || cx >= 64 || cy < 0 || cy >= 64 { return }
            let cell = cy * 64 + cx
            if !staticPassability[cell] { return }
        }
    }

    // Place the structure
    let pos = cellToPixel(cellY * 64 + cellX)
    let cx = Double(pos.px) + Double(size.w * 24) / 2.0
    let cy = Double(pos.py) + Double(size.h * 24) / 2.0

    let obj = GameObject(
        id: world.allocateId(),
        typeName: pType,
        house: world.playerHouse,
        kind: .structure,
        worldX: cx, worldY: cy,
        facing: 0,
        strength: resolveStrength(typeName: pType, kind: .structure, scenarioStrength: 256),
        mission: .guard_,
        speed: 0.0
    )
    world.addObject(obj)

    // Mark footprint as impassable
    for dy in 0..<size.h {
        for dx in 0..<size.w {
            let cell = (cellY + dy) * 64 + (cellX + dx)
            staticPassability[cell] = false
        }
    }

    // Clear placement mode
    session.isPlacingStructure = false
    session.placementType = nil
    session.structureBuildQueue.clear()
}
