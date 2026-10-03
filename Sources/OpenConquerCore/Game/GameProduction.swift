import Foundation

// MARK: - Build Data (derived from type data tables)

package struct BuildableItem {
    package let name: String
    package let displayName: String
    package let cost: Int
    package let buildTicks: Int
    package let prerequisite: String?
    package let faction: String?  // "GDI", "NOD", or nil for both
    package let buildLevel: Int
}

package struct BuildableStructure {
    package let name: String
    package let displayName: String
    package let cost: Int
    package let buildTicks: Int
    package let faction: String?
    package let buildLevel: Int
}

/// Generate unit/infantry build list from type data tables
package func generateBuildableUnits() -> [BuildableItem] {
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
        items.append(BuildableItem(name: data.iniName, displayName: data.fullName, cost: data.cost,
                                   buildTicks: ticks, prerequisite: prereq, faction: faction,
                                   buildLevel: data.buildLevel))
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
        items.append(BuildableItem(name: data.iniName, displayName: data.fullName, cost: data.cost,
                                   buildTicks: ticks, prerequisite: prereq, faction: faction,
                                   buildLevel: data.buildLevel))
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
        items.append(BuildableItem(name: data.iniName, displayName: data.fullName, cost: data.cost,
                                   buildTicks: ticks, prerequisite: prereq, faction: faction,
                                   buildLevel: data.buildLevel))
    }

    // Sort by cost for consistent ordering
    items.sort { $0.cost < $1.cost }
    return items
}

/// Generate structure build list from type data tables
package func generateBuildableStructures() -> [BuildableStructure] {
    var items: [BuildableStructure] = []

    for (_, data) in buildingTypeDataTable {
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
        let ticks = max(30, data.cost / 5)
        items.append(BuildableStructure(name: data.iniName, displayName: data.fullName, cost: data.cost,
                                        buildTicks: ticks, faction: faction,
                                        buildLevel: data.buildLevel))
    }

    // Sort by cost for consistent ordering
    items.sort { $0.cost < $1.cost }
    return items
}

// Lazy-initialized build lists from type data
private var _buildableUnits: [BuildableItem]? = nil
private var _buildableStructures: [BuildableStructure]? = nil

package var buildableUnits: [BuildableItem] {
    if _buildableUnits == nil { _buildableUnits = generateBuildableUnits() }
    return _buildableUnits ?? []
}

package var buildableStructures: [BuildableStructure] {
    if _buildableStructures == nil { _buildableStructures = generateBuildableStructures() }
    return _buildableStructures ?? []
}

// MARK: - Query Functions

/// Get the set of building type names owned by the player
package func getOwnedBuildingTypes() -> Set<String> {
    guard let world = session.world else { return [] }
    var owned = Set<String>()
    for obj in world.objects {
        if obj.kind == .structure && obj.house == world.playerHouse && obj.strength > 0 {
            owned.insert(obj.typeName.uppercased())
        }
    }
    return owned
}

// MARK: - What the player may build (HouseClass::Can_Build, HOUSE.CPP:449)
//
// An item is on the sidebar while the player owns a factory that makes its
// kind — a barracks (PYLE or HAND) for infantry, a weapons factory or
// airstrip for vehicles, a helipad for aircraft, a construction yard for
// structures (BuildingClass::Update_Buildables adds it, StripClass::Recalc
// drops it once no factory can build it, Who_Can_Build_Me) — and
// HouseClass::Can_Build allows it: ownable by the player's side, every
// prerequisite building owned (with the original's equivalences: a Hand of Nod
// counts as a barracks, an advanced power plant as a power plant, and so on),
// first available at or below the scenario's BuildLevel, and not excluded by
// one of the original's campaign special cases. Not yet modelled: the Nod
// mission 11 Stealth Tank rule (prerequisite = the mission objective
// buildings).

/// The player's ActiveBScan, with Can_Build's equivalency fixups.
private func playerStructFlags(_ owned: Set<String>) -> StructFlag {
    var flags = StructFlag.none
    for name in owned {
        if let st = StructType.from(iniName: name) { flags.insert(structTypeToFlag(st)) }
    }
    if flags.contains(.advancedPower) { flags.insert(.power) }
    if flags.contains(.hand) { flags.insert(.barracks) }
    if flags.contains(.obelisk) { flags.insert(.atower) }
    if flags.contains(.temple) { flags.insert(.eye) }
    if flags.contains(.airstrip) { flags.insert(.weap) }
    if flags.contains(.sam) { flags.insert(.helipad) }
    return flags
}

private enum BuildKind { case infantry(InfantryType), unit(UnitType), aircraft(AircraftType), structure(StructType) }

/// Can_Build's legality test for the human player (HOUSE.CPP:449-606).
private func playerCanBuild(_ kind: BuildKind, isBuildable: Bool, ownable: HouseFlag, pre: StructFlag,
                            scenario: Int, gdi: Bool, flags: StructFlag) -> Bool {
    guard isBuildable, ownable.contains(gdi ? .good : .bad) else { return false }
    var level = session.scenarioBuildLevel
    var scenario = scenario
    switch kind {
    case .infantry(.e3) where gdi && level < 7: return false        // no bazooka for GDI before #8
    case .unit(.mlrs) where gdi && level < 9: return false          // MSAM from #9
    case .unit(.mlrs) where !gdi: return false
    case .unit(.apc) where !gdi: return false
    case .structure(.temple), .structure(.obelisk): if gdi { return false }
    case .structure(.eye): if !gdi { return false }
    case .structure(.advancedPower) where !gdi && level >= 12: scenario = level  // Nod gets it at #12
    case .structure(.helipad) where !gdi: return false
    case .structure(.sandbagWall) where gdi && level < 8: return false
    default: break
    }
    if gdi && level == 2 { level = 1 }  // GDI's second training mission feels like #1
    return flags.isSuperset(of: pre) && scenario <= level
}

/// Get available units the player can build
package func getAvailableUnits() -> [BuildableItem] {
    let owned = getOwnedBuildingTypes()
    let gdi = session.world?.playerHouse != .badGuy
    let flags = playerStructFlags(owned)
    let hasBarracks = owned.contains("PYLE") || owned.contains("HAND")
    let hasVehicleFactory = owned.contains("WEAP") || owned.contains("AFLD")
    let hasHelipad = owned.contains("HPAD")
    var seen = Set<String>()
    var result: [BuildableItem] = []
    for item in buildableUnits where !seen.contains(item.name) {
        let name = item.name.uppercased()
        let ok: Bool
        if let d = infantryTypeDataTable.values.first(where: { $0.iniName.uppercased() == name }) {
            ok = hasBarracks && playerCanBuild(.infantry(d.type), isBuildable: d.isBuildable, ownable: d.ownable,
                                               pre: d.prerequisite, scenario: d.scenario, gdi: gdi, flags: flags)
        } else if let d = unitTypeDataTable.values.first(where: { $0.iniName.uppercased() == name }) {
            ok = hasVehicleFactory && playerCanBuild(.unit(d.type), isBuildable: d.isBuildable, ownable: d.ownable,
                                                     pre: d.prerequisite, scenario: d.scenario, gdi: gdi, flags: flags)
        } else if let d = aircraftTypeDataTable.values.first(where: { $0.iniName.uppercased() == name }) {
            ok = hasHelipad && playerCanBuild(.aircraft(d.type), isBuildable: d.isBuildable, ownable: d.ownable,
                                              pre: d.prerequisite, scenario: d.scenario, gdi: gdi, flags: flags)
        } else {
            ok = false
        }
        guard ok else { continue }
        seen.insert(item.name)
        result.append(item)
    }
    return result
}

/// Get available structures the player can build
package func getAvailableStructures() -> [BuildableStructure] {
    let owned = getOwnedBuildingTypes()
    guard owned.contains("FACT") else { return [] }  // only a construction yard builds structures
    let gdi = session.world?.playerHouse != .badGuy
    let flags = playerStructFlags(owned)
    return buildableStructures.filter { item in
        let name = item.name.uppercased()
        guard let d = buildingTypeDataTable.values.first(where: { $0.iniName.uppercased() == name }),
              let st = StructType.from(iniName: name) else { return false }
        return playerCanBuild(.structure(st), isBuildable: d.isBuildable, ownable: d.ownable,
                              pre: d.prerequisite, scenario: d.scenario, gdi: gdi, flags: flags)
    }
}

// MARK: - Production Tick

package func tickProduction() {
    guard let world = session.world else { return }

    let houseState = getHouseState(world.playerHouse)

    // Advance unit production
    if session.unitBuildQueue.item != nil {
        let completed = session.unitBuildQueue.tick(hasPower: houseState.hasPower, worldTickCount: world.tickCount)
        if completed {
            let producedType = session.unitBuildQueue.item!.typeName.uppercased()
            spawnProducedUnit(session.unitBuildQueue.item!.typeName, world: world)
            session.unitBuildQueue.clear()
            audioManager.speak(.unitReady)
            // Only play mechanical construction sound for vehicles, not infantry
            let isInfantry = ["E1", "E2", "E3", "E4", "E5", "E6", "E7", "RMBO"].contains(producedType)
            if !isInfantry {
                audioManager.play(.construction)
            }
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

package func spawnProducedUnit(_ typeName: String, world: GameWorld) {
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
    let infantryTypes: Set<String> = ["E1", "E2", "E3", "E4", "E5", "E6", "E7", "RMBO"]
    if infantryTypes.contains(upper) {
        // GDI uses PYLE (Barracks), Nod uses HAND (Hand of Nod)
        let owned = getOwnedBuildingTypes()
        if owned.contains("PYLE") {
            producerType = "PYLE"
        } else if owned.contains("HAND") {
            producerType = "HAND"
        } else {
            // Fallback: check for either
            producerType = "PYLE"
        }
    } else {
        producerType = "WEAP"
    }

    // Find the producing structure
    guard let producer = world.objects.first(where: {
        $0.kind == .structure && $0.typeName.uppercased() == producerType && $0.house == world.playerHouse && $0.strength > 0
    }) else { return }

    // Spawn near the exit of the producing structure
    let size = buildingSize(producerType)
    let isInfantry = ["E1", "E2", "E3", "E4", "E5", "E6", "E7", "RMBO"].contains(upper)
    let kind: ObjectKind = isInfantry ? .infantry : .unit
    let speed = resolveSpeed(typeName: upper, kind: kind)
    let preferredX = producer.worldX + Double(size.w * 24) / 2.0 + 12.0
    let preferredY = producer.worldY + Double(size.h * 24) / 2.0
    // Resolve the actual spawn cell — preferred exit if free, else the
    // nearest empty cell. Without this, two production cycles in a row
    // park the second unit on top of the first.
    let spawn = findFreeSpawnCell(nearWorldX: preferredX, nearWorldY: preferredY, kind: kind)
        ?? (cellX: Int(preferredX) / 24, cellY: Int(preferredY) / 24)
    let exitX = Double(spawn.cellX * 24) + 12.0
    let exitY = Double(spawn.cellY * 24) + 12.0

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

    // Rally point: if producer has a rally point, send the new unit there
    if upper != "HARV",
       let rpX = producer.rallyPointX,
       let rpY = producer.rallyPointY {
        obj.moveTargetX = rpX
        obj.moveTargetY = rpY
        obj.mission = .move
        obj.movePath = []
    }
}

// MARK: - Structure Placement

/// Place the finished structure with its top-left at the given cell, if the
/// footprint is clear and touches one of the player's buildings.
package func placeStructure(type pType: String, cellX: Int, cellY: Int) {
    guard let world = session.world,
          session.structureBuildQueue.item?.typeName == pType,
          session.structureBuildQueue.isComplete else { return }
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

    // Check adjacency to existing player structures (must be within 1 cell of a friendly building)
    var isAdjacent = false
    for obj in world.objects {
        if obj.kind != .structure { continue }
        if obj.house != world.playerHouse { continue }
        if obj.strength <= 0 { continue }
        let bSize = buildingSize(obj.typeName)
        let bCellX = (Int(obj.worldX) - bSize.w * 12) / 24
        let bCellY = (Int(obj.worldY) - bSize.h * 12) / 24
        // Check if any cell of the new building is adjacent to any cell of this existing building
        for dy in -1...size.h {
            for dx in -1...size.w {
                let checkX = cellX + dx
                let checkY = cellY + dy
                if checkX >= bCellX && checkX < bCellX + bSize.w &&
                   checkY >= bCellY && checkY < bCellY + bSize.h {
                    isAdjacent = true
                    break
                }
            }
            if isAdjacent { break }
        }
        if isAdjacent { break }
    }
    if !isAdjacent { return }

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
        mission: .construction,
        speed: 0.0
    )
    // Start build-up animation — will be resolved when frame count is known
    obj.buildUpFrame = 0
    obj.buildUpDelay = 0
    world.addObject(obj)
    audioManager.play(.construction)

    // Mark footprint as impassable
    for dy in 0..<size.h {
        for dx in 0..<size.w {
            let cell = (cellY + dy) * 64 + (cellX + dx)
            staticPassability[cell] = false
        }
    }

    // Fire "Built It" triggers for this structure type
    springTriggerBuiltIt(structureType: pType)

    // Clear placement mode
    session.isPlacingStructure = false
    session.placementType = nil
    session.structureBuildQueue.clear()
}
