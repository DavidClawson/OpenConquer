import Foundation

// MARK: - Unit Speed Table (pixels per tick at 15 FPS)

let unitSpeeds: [String: Double] = [
    // Vehicles
    "MTNK": 1.5,   // Medium tank
    "LTNK": 2.0,   // Light tank
    "HTNK": 1.0,   // Mammoth tank
    "FTNK": 1.5,   // Flame tank
    "STNK": 2.5,   // Stealth tank
    "ARTY": 1.2,   // Artillery
    "MSAM": 1.5,   // Rocket launcher (MLRS)
    "HMMV": 2.5,   // Humvee
    "APC":  2.0,   // APC
    "BGGY": 2.5,   // Nod buggy
    "BIKE": 3.0,   // Recon bike
    "MHQ":  1.5,   // Mobile HQ
    "HARV": 1.0,   // Harvester
    "MCV":  1.0,   // MCV
    "JEEP": 2.5,   // (alias for Humvee)
    "LST":  1.5,   // Hovercraft

    // Infantry
    "E1":   0.8,   // Minigunner
    "E2":   0.8,   // Grenadier
    "E3":   0.8,   // Rocket soldier
    "E4":   0.8,   // Flamethrower
    "E5":   0.8,   // Chem warrior
    "E6":   0.8,   // Engineer
    "E7":   0.8,   // (civilian)
    "RMBO": 1.0,   // Commando
    "C1":   0.6,   // Civilian
    "C2":   0.6,
    "C3":   0.6,
    "C4":   0.6,
    "C5":   0.6,
    "C6":   0.6,
    "C7":   0.6,
    "C8":   0.6,
    "C9":   0.6,
    "C10":  0.6,
    "MOEB": 0.6,   // Dr. Mobius
    "DELPHI": 0.6, // Agent Delphi
    "CHAN": 0.6,    // Scientist
]

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
        let obj = GameObject(
            id: world.allocateId(),
            typeName: structure.typeName,
            house: structure.house,
            kind: .structure,
            worldX: cx, worldY: cy,
            facing: structure.facing,
            strength: structure.strength,
            mission: .guard_,
            speed: 0.0
        )
        world.addObject(obj)
    }

    // Spawn units
    for unit in scenario.units {
        let pos = cellToPixel(unit.cell)
        let cx = Double(pos.px) + 12.0
        let cy = Double(pos.py) + 12.0
        let speed = unitSpeeds[unit.typeName.uppercased()] ?? 1.5
        let obj = GameObject(
            id: world.allocateId(),
            typeName: unit.typeName,
            house: unit.house,
            kind: .unit,
            worldX: cx, worldY: cy,
            facing: unit.facing,
            strength: unit.strength,
            mission: Mission.from(unit.mission),
            speed: speed
        )
        world.addObject(obj)
    }

    // Spawn infantry
    for inf in scenario.infantry {
        let pos = cellToPixel(inf.cell)
        let sub = subCellOffset(inf.subLocation)
        let cx = Double(pos.px + sub.dx) + 3.0
        let cy = Double(pos.py + sub.dy) + 3.0
        let speed = unitSpeeds[inf.typeName.uppercased()] ?? 0.8
        let obj = GameObject(
            id: world.allocateId(),
            typeName: inf.typeName,
            house: inf.house,
            kind: .infantry,
            worldX: cx, worldY: cy,
            facing: inf.facing,
            strength: inf.strength,
            mission: Mission.from(inf.mission),
            speed: speed,
            subCell: inf.subLocation
        )
        world.addObject(obj)
    }

    gameWorld = world
    print("GameInit: Created \(world.objects.count) objects from \(scenarioName)")
    print("  Structures: \(scenario.structures.count), Units: \(scenario.units.count), Infantry: \(scenario.infantry.count)")

    // Build static passability map
    buildPassabilityMap()
}
