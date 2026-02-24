import Foundation

// MARK: - Speed Resolution from Type Data
// MPH values from VC are converted to pixels per tick at 15 FPS
// Formula: MPH * 0.08 gives a good gameplay feel

func resolveSpeed(typeName: String, kind: ObjectKind) -> Double {
    let upper = typeName.uppercased()
    let mph: UInt8

    // Check if it's an aircraft type first (aircraft use kind == .unit)
    if let at = AircraftType.from(iniName: upper), let data = aircraftTypeDataTable[at] {
        mph = data.maxSpeed.rawValue
        return Double(mph) * 0.08
    }

    switch kind {
    case .unit:
        if let ut = UnitType.from(iniName: upper), let data = unitTypeDataTable[ut] {
            mph = data.maxSpeed.rawValue
        } else {
            mph = MPHType.medium.rawValue
        }
    case .infantry:
        if let it = InfantryType.from(iniName: upper), let data = infantryTypeDataTable[it] {
            mph = data.maxSpeed.rawValue
        } else {
            mph = MPHType.slow.rawValue
        }
    case .structure:
        return 0.0
    }
    // Convert MPH to pixels/tick: scale factor tuned for 15 FPS gameplay
    return Double(mph) * 0.08
}

func resolveStrength(typeName: String, kind: ObjectKind, scenarioStrength: Int) -> Int {
    let upper = typeName.uppercased()
    let maxHP: Int

    // Check aircraft types first
    if let at = AircraftType.from(iniName: upper), let data = aircraftTypeDataTable[at] {
        if scenarioStrength >= 256 { return data.strength }
        return max(1, data.strength * scenarioStrength / 256)
    }

    switch kind {
    case .unit:
        if let ut = UnitType.from(iniName: upper), let data = unitTypeDataTable[ut] {
            maxHP = data.strength
        } else {
            return scenarioStrength
        }
    case .infantry:
        if let it = InfantryType.from(iniName: upper), let data = infantryTypeDataTable[it] {
            maxHP = data.strength
        } else {
            return scenarioStrength
        }
    case .structure:
        if let st = StructType.from(iniName: upper), let data = buildingTypeDataTable[st] {
            maxHP = data.strength
        } else {
            return scenarioStrength
        }
    }
    // Scenario strength is a percentage (256 = 100%)
    if scenarioStrength >= 256 {
        return maxHP
    }
    return max(1, maxHP * scenarioStrength / 256)
}

// MARK: - Game World Initialization

func initGameWorld(scenario: ScenarioData, scenarioName: String) {
    let world = GameWorld()
    world.theater = scenario.theater
    world.mapBounds = scenario.mapBounds

    // Spawn structures
    for structure in scenario.structures {
        let pos = cellToPixel(structure.cell)
        let size = buildingSize(structure.typeName)
        // Center of the building footprint
        let cx = Double(pos.px) + Double(size.w * 24) / 2.0
        let cy = Double(pos.py) + Double(size.h * 24) / 2.0
        let hp = resolveStrength(typeName: structure.typeName, kind: .structure, scenarioStrength: structure.strength)
        let obj = GameObject(
            id: world.allocateId(),
            typeName: structure.typeName,
            house: structure.house,
            kind: .structure,
            worldX: cx, worldY: cy,
            facing: structure.facing,
            strength: hp,
            mission: .guard_,
            speed: 0.0
        )
        // Attach trigger name
        if structure.trigger != "None" && !structure.trigger.isEmpty {
            obj.triggerName = structure.trigger
        }
        world.addObject(obj)
    }

    // Spawn units
    for unit in scenario.units {
        let pos = cellToPixel(unit.cell)
        let cx = Double(pos.px) + 12.0
        let cy = Double(pos.py) + 12.0
        let speed = resolveSpeed(typeName: unit.typeName, kind: .unit)
        let hp = resolveStrength(typeName: unit.typeName, kind: .unit, scenarioStrength: unit.strength)
        let obj = GameObject(
            id: world.allocateId(),
            typeName: unit.typeName,
            house: unit.house,
            kind: .unit,
            worldX: cx, worldY: cy,
            facing: unit.facing,
            strength: hp,
            mission: Mission.from(unit.mission),
            speed: speed
        )
        if unit.trigger != "None" && !unit.trigger.isEmpty {
            obj.triggerName = unit.trigger
        }
        world.addObject(obj)
    }

    // Spawn infantry
    for inf in scenario.infantry {
        let pos = cellToPixel(inf.cell)
        let sub = subCellOffset(inf.subLocation)
        let cx = Double(pos.px + sub.dx) + 3.0
        let cy = Double(pos.py + sub.dy) + 3.0
        let speed = resolveSpeed(typeName: inf.typeName, kind: .infantry)
        let hp = resolveStrength(typeName: inf.typeName, kind: .infantry, scenarioStrength: inf.strength)
        let obj = GameObject(
            id: world.allocateId(),
            typeName: inf.typeName,
            house: inf.house,
            kind: .infantry,
            worldX: cx, worldY: cy,
            facing: inf.facing,
            strength: hp,
            mission: Mission.from(inf.mission),
            speed: speed,
            subCell: inf.subLocation
        )
        if inf.trigger != "None" && !inf.trigger.isEmpty {
            obj.triggerName = inf.trigger
        }
        world.addObject(obj)
    }

    // Set player house based on scenario name (SCG = GDI, SCB = Nod)
    if scenarioName.uppercased().hasPrefix("SCB") {
        world.playerHouse = .badGuy
    } else {
        world.playerHouse = .goodGuy
    }

    gameWorld = world
    print("GameInit: Created \(world.objects.count) objects from \(scenarioName)")
    print("  Structures: \(scenario.structures.count), Units: \(scenario.units.count), Infantry: \(scenario.infantry.count)")
    print("  Player house: \(world.playerHouse.rawValue)")

    // Load map cell data (BIN file) if not already loaded
    let binName = scenarioName + ".BIN"
    if let cells = loadMap(binName, from: mixManager) {
        mapCells = cells
        print("GameInit: Loaded \(binName) (\(cells.count) cells)")
    } else if mapCells.count < 4096 {
        // Fallback: fill with empty cells
        print("GameInit: Warning - \(binName) not found, using empty map cells")
        mapCells = (0..<4096).map { _ in MapCell(templateType: 0xFF, iconIndex: 0) }
    }

    // Load palette for theater
    let palName: String
    switch scenario.theater {
    case .temperate: palName = "TEMPERAT.PAL"
    case .desert: palName = "DESERT.PAL"
    case .winter: palName = "WINTER.PAL"
    }
    gamePalette = loadPalette(palName)

    // Build static passability map
    buildPassabilityMap()

    // Initialize tiberium cells from overlays
    initTiberiumCells()

    // Set harvesters to harvest mission
    for obj in world.objects {
        if obj.typeName.uppercased() == "HARV" && obj.house == world.playerHouse {
            obj.mission = .harvest
        }
    }

    // Initialize fog of war
    initFog()

    // Initialize house states (credits, power, capacity)
    initHouseStates()

    // Reset super weapons
    resetSuperWeapons()

    // Parse and initialize triggers
    parseTriggers(from: scenario.ini)

    // Store waypoints for team AI
    scenarioWaypoints.removeAll()
    for wp in scenario.waypoints {
        scenarioWaypoints[wp.id] = wp.cell
    }

    // Parse team types and create initial teams
    parseTeamTypes(from: scenario.ini)
    activeTeams.removeAll()
    for tt in teamTypes {
        for _ in 0..<tt.initNum {
            if let team = createAndRecruitTeam(type: tt) {
                print("GameInit: Created initial team '\(tt.name)' with \(team.memberCount) members")
            }
        }
    }
}
