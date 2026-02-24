import Foundation

// MARK: - Enemy AI
// Enhanced AI with squad coordination, hunt behavior, guard leash, and production

/// Maximum distance a guarding unit will chase before returning (in pixels)
let guardLeashRange: Double = 10.0 * 24.0  // 10 cells

// MARK: - Difficulty Helpers

/// Aggro scan range in cells, scaled by difficulty
func aiAggroRangeCells() -> Double {
    switch session.campaignState.difficulty {
    case 0:  return 6.0   // Easy
    case 2:  return 10.0  // Hard
    default: return 8.0   // Normal
    }
}

/// Ticks between rally raids, scaled by difficulty
func aiRallyInterval() -> Int {
    switch session.campaignState.difficulty {
    case 0:  return 450   // Easy — 30 seconds
    case 2:  return 200   // Hard — ~13 seconds
    default: return 300   // Normal — 20 seconds
    }
}

/// AI production cost multiplier, scaled by difficulty
func aiCostMultiplier() -> Double {
    switch session.campaignState.difficulty {
    case 0:  return 1.5   // Easy — AI pays 50% more
    case 2:  return 0.75  // Hard — AI pays 25% less
    default: return 1.0   // Normal
    }
}

/// AI update — called every game tick but only acts periodically
func tickAI() {
    guard let world = session.world else { return }
    session.aiTickCounter += 1

    // Tick AI production every tick (queues advance by 1 per tick)
    tickAIProduction()

    // AI behavioral scan every 30 ticks (~2 seconds)
    guard session.aiTickCounter % 30 == 0 else { return }

    let aggroRange = aiAggroRangeCells() * 24.0  // Convert cells to pixels

    for obj in world.objects {
        // Only control enemy (non-player) units
        if obj.house == world.playerHouse { continue }
        if obj.house == .neutral { continue }
        if obj.strength <= 0 { continue }

        // Turrets / defense structures auto-target
        if obj.kind == .structure {
            if obj.isArmed && obj.mission != .attack {
                if let enemy = findNearestEnemy(obj, range: aggroRange) {
                    obj.attackTarget = enemy.id
                    obj.mission = .attack
                }
            }
            continue
        }

        // Skip harvesters and MCVs — they have their own behavior
        let upper = obj.typeName.uppercased()
        if upper == "HARV" {
            if obj.mission == .guard_ || obj.mission == .stop {
                obj.mission = .harvest
            }
            continue
        }
        if upper == "MCV" { continue }

        // Hunt mission — actively seek and destroy
        if obj.mission == .hunt {
            if obj.attackTarget == nil {
                // Find nearest enemy anywhere on map
                if let enemy = findNearestEnemy(obj, range: 64.0 * 24.0) {
                    obj.attackTarget = enemy.id
                    obj.mission = .attack
                }
            }
            continue
        }

        // Idle enemy units (on guard/stop) — scan for nearby player units
        if obj.mission == .guard_ || obj.mission == .stop || obj.mission == .guardArea {
            if obj.isArmed {
                if let enemy = findNearestEnemy(obj, range: aggroRange) {
                    obj.attackTarget = enemy.id
                    obj.mission = .attack
                }
            }
        }
    }

    // Rally idle enemy units toward player base at difficulty-scaled interval
    let rallyInterval = aiRallyInterval()
    if session.aiTickCounter % rallyInterval == 0 {
        rallyEnemyUnits(world: world)
    }

    // Periodically create autocreate teams (every ~45 seconds)
    if session.aiTickCounter % 675 == 0 && session.aiTickCounter > 300 {
        tryAutocreateTeam()
    }

    // Escalation: after 5 minutes, send all idle units to hunt
    if session.aiTickCounter == 15 * 60 * 5 {
        escalateAI(world: world)
    }
}

/// Find the average position of player structures
func findPlayerBase(world: GameWorld) -> (x: Double, y: Double)? {
    var totalX = 0.0
    var totalY = 0.0
    var count = 0

    for obj in world.objects {
        if obj.kind == .structure && obj.house == world.playerHouse && obj.strength > 0 {
            totalX += obj.worldX
            totalY += obj.worldY
            count += 1
        }
    }

    if count == 0 { return nil }
    return (x: totalX / Double(count), y: totalY / Double(count))
}

/// Find the average position of enemy structures
func findEnemyBase(world: GameWorld) -> (x: Double, y: Double)? {
    var totalX = 0.0
    var totalY = 0.0
    var count = 0

    for obj in world.objects {
        if obj.kind == .structure && obj.house != world.playerHouse &&
           obj.house != .neutral && obj.strength > 0 {
            totalX += obj.worldX
            totalY += obj.worldY
            count += 1
        }
    }

    if count == 0 { return nil }
    return (x: totalX / Double(count), y: totalY / Double(count))
}

/// Rally idle enemy units toward the player's base
func rallyEnemyUnits(world: GameWorld) {
    guard let playerBase = findPlayerBase(world: world) else { return }

    // Gather idle enemy combat units
    var idleUnits: [GameObject] = []
    for obj in world.objects {
        if obj.house == world.playerHouse || obj.house == .neutral { continue }
        if obj.kind == .structure { continue }
        if obj.strength <= 0 { continue }
        let upper = obj.typeName.uppercased()
        if upper == "HARV" || upper == "MCV" { continue }
        if obj.mission == .guard_ || obj.mission == .stop {
            idleUnits.append(obj)
        }
    }

    // Send groups of 3-5 idle units toward the player base
    let squadSize = min(5, max(3, idleUnits.count))
    if idleUnits.count >= squadSize {
        let squad = Array(idleUnits.prefix(squadSize))
        for unit in squad {
            // Add some randomness to the target so they don't all stack
            let offsetX = Double.random(in: -48...48)
            let offsetY = Double.random(in: -48...48)
            unit.moveTargetX = max(12, min(64 * 24 - 12, playerBase.x + offsetX))
            unit.moveTargetY = max(12, min(64 * 24 - 12, playerBase.y + offsetY))
            unit.mission = .move
            unit.movePath = []
        }
    }
}

/// Escalate AI: send all idle enemy units to hunt mode
func escalateAI(world: GameWorld) {
    for obj in world.objects {
        if obj.house == world.playerHouse || obj.house == .neutral { continue }
        if obj.kind == .structure { continue }
        if obj.strength <= 0 { continue }
        let upper = obj.typeName.uppercased()
        if upper == "HARV" || upper == "MCV" { continue }
        if obj.mission == .guard_ || obj.mission == .stop {
            obj.mission = .hunt
        }
    }
    print("AI: Escalation — all idle enemy units set to hunt")
}

/// Try to create an autocreate team from available team types
func tryAutocreateTeam() {
    let autocreateTypes = session.teamTypes.filter { $0.isAutocreate }
    guard !autocreateTypes.isEmpty else { return }

    // Pick a random autocreate team type
    let type = autocreateTypes[Int.random(in: 0..<autocreateTypes.count)]

    if let team = createAndRecruitTeam(type: type) {
        if team.memberCount > 0 {
            print("AI: Auto-created team '\(type.name)' with \(team.memberCount) members")
        } else {
            // No units to recruit — remove the empty team
            session.activeTeams.removeAll { $0 === team }
        }
    }
}

// MARK: - AI Production System

/// Tick AI production for all non-player houses.
/// Called every game tick from tickAI. Advances queues and starts new builds.
func tickAIProduction() {
    guard let world = session.world else { return }
    let costMult = aiCostMultiplier()

    for (house, state) in session.houseStates {
        // Skip player and neutral houses
        if house == world.playerHouse || house == .neutral { continue }
        // Must have production enabled (via beginProduction trigger or auto-enable after delay)
        if !state.productionEnabled {
            // Auto-enable production after 3 minutes if not triggered
            if session.aiTickCounter > 15 * 60 * 3 {
                state.productionEnabled = true
                print("AI: Auto-enabled production for \(house.rawValue) after timeout")
            } else {
                continue
            }
        }

        let owned = state.ownedBuildingTypes()

        // --- Vehicle / Unit production ---
        tickAIQueue(
            queue: state.aiUnitQueue,
            house: house,
            houseState: state,
            owned: owned,
            costMultiplier: costMult,
            world: world,
            pickUnit: { aiPickVehicle(house: house, houseState: state, owned: $0, costMultiplier: $1) }
        )

        // --- Infantry production ---
        let hasBarracks = owned.contains("PYLE") || owned.contains("HAND")
        if hasBarracks {
            tickAIQueue(
                queue: state.aiInfantryQueue,
                house: house,
                houseState: state,
                owned: owned,
                costMultiplier: costMult,
                world: world,
                pickUnit: { aiPickInfantry(house: house, houseState: state, owned: $0, costMultiplier: $1) }
            )
        }
    }
}

/// Advance a single AI production queue and start new builds when idle.
private func tickAIQueue(
    queue: ProductionQueue,
    house: House,
    houseState: HouseState,
    owned: Set<String>,
    costMultiplier: Double,
    world: GameWorld,
    pickUnit: (Set<String>, Double) -> (typeName: String, cost: Int, buildTime: Int)?
) {
    // If a build is in progress, advance it
    if queue.item != nil {
        let completed = queue.tick(hasPower: houseState.hasPower, worldTickCount: world.tickCount)
        if completed {
            let typeName = queue.item!.typeName
            spawnAIUnit(typeName, house: house, world: world)
            queue.clear()
        }
        return
    }

    // Queue is idle — pick something to build (only check every 30 ticks to reduce CPU)
    guard session.aiTickCounter % 30 == 0 else { return }
    guard houseState.credits > 0 else { return }

    if let choice = pickUnit(owned, costMultiplier) {
        if houseState.spendCredits(choice.cost) {
            queue.start(typeName: choice.typeName, cost: choice.cost, buildTime: choice.buildTime)
        }
    }
}

/// Pick a vehicle for the AI to build based on heuristics.
private func aiPickVehicle(
    house: House,
    houseState: HouseState,
    owned: Set<String>,
    costMultiplier: Double
) -> (typeName: String, cost: Int, buildTime: Int)? {
    guard owned.contains("WEAP") || owned.contains("AFLD") else { return nil }
    guard let world = session.world else { return nil }

    // Count existing harvesters and combat vehicles for this house
    var harvesterCount = 0
    var combatVehicleCount = 0
    for obj in world.objects {
        guard obj.house == house && obj.strength > 0 else { continue }
        let upper = obj.typeName.uppercased()
        if upper == "HARV" { harvesterCount += 1 }
        if obj.kind == .unit && upper != "HARV" && upper != "MCV" { combatVehicleCount += 1 }
    }

    // Priority 1: Need at least 1 harvester if we have a refinery
    if harvesterCount == 0 && owned.contains("PROC") {
        if let data = getUnitTypeDataByName("HARV") {
            let cost = Int(Double(data.cost) * costMultiplier)
            let ticks = max(30, cost / 5)
            return (typeName: "HARV", cost: cost, buildTime: ticks)
        }
    }

    // Priority 2: Build combat vehicles
    let isNod = (houseToHousesType(house) == .bad)

    // Build pool based on faction
    var candidates: [(name: String, weight: Int)] = []
    if owned.contains("WEAP") {
        if isNod {
            candidates.append((name: "LTNK", weight: 4))
            candidates.append((name: "BGGY", weight: 3))
            candidates.append((name: "FTNK", weight: 2))
            candidates.append((name: "ARTY", weight: 2))
            candidates.append((name: "APC", weight: 1))
            if owned.contains("AFLD") {
                candidates.append((name: "STNK", weight: 2))
            }
        } else {
            candidates.append((name: "MTNK", weight: 5))
            candidates.append((name: "JEEP", weight: 3))
            candidates.append((name: "MSAM", weight: 2))
            candidates.append((name: "APC", weight: 1))
            candidates.append((name: "MLRS", weight: 2))
            if houseState.credits > 1500 {
                candidates.append((name: "HTNK", weight: 2))
            }
        }
    }

    // Filter candidates to only what this house can actually build
    candidates = candidates.filter { candidate in
        if let ut = UnitType.from(iniName: candidate.name),
           let data = unitTypeDataTable[ut] {
            return houseState.canBuildUnit(data)
        }
        return false
    }

    guard !candidates.isEmpty else { return nil }

    // Weighted random selection
    let totalWeight = candidates.reduce(0) { $0 + $1.weight }
    var roll = Int.random(in: 0..<totalWeight)
    for candidate in candidates {
        roll -= candidate.weight
        if roll < 0 {
            if let data = getUnitTypeDataByName(candidate.name) {
                let cost = Int(Double(data.cost) * costMultiplier)
                let ticks = max(30, cost / 5)
                return (typeName: candidate.name, cost: cost, buildTime: ticks)
            }
            break
        }
    }

    return nil
}

/// Pick an infantry for the AI to build based on heuristics.
private func aiPickInfantry(
    house: House,
    houseState: HouseState,
    owned: Set<String>,
    costMultiplier: Double
) -> (typeName: String, cost: Int, buildTime: Int)? {
    let isNod = (houseToHousesType(house) == .bad)

    var candidates: [(name: String, weight: Int)] = []
    if isNod {
        candidates.append((name: "E1", weight: 5))
        candidates.append((name: "E3", weight: 3))
        candidates.append((name: "E4", weight: 2))
        if owned.contains("TMPL") {
            candidates.append((name: "E5", weight: 1))
        }
    } else {
        candidates.append((name: "E1", weight: 5))
        candidates.append((name: "E2", weight: 3))
        candidates.append((name: "E3", weight: 3))
    }

    // Filter to what the house can actually build
    candidates = candidates.filter { candidate in
        if let it = InfantryType.from(iniName: candidate.name),
           let data = infantryTypeDataTable[it] {
            return houseState.canBuildInfantry(data)
        }
        return false
    }

    guard !candidates.isEmpty else { return nil }

    let totalWeight = candidates.reduce(0) { $0 + $1.weight }
    var roll = Int.random(in: 0..<totalWeight)
    for candidate in candidates {
        roll -= candidate.weight
        if roll < 0 {
            if let it = InfantryType.from(iniName: candidate.name),
               let data = infantryTypeDataTable[it] {
                let cost = Int(Double(data.cost) * costMultiplier)
                let ticks = max(20, cost / 5)
                return (typeName: candidate.name, cost: cost, buildTime: ticks)
            }
            break
        }
    }

    return nil
}

/// Spawn a completed AI unit at the appropriate factory.
private func spawnAIUnit(_ typeName: String, house: House, world: GameWorld) {
    let upper = typeName.uppercased()
    let infantryTypes: Set<String> = ["E1", "E2", "E3", "E4", "E5", "E6", "E7", "RMBO"]
    let isInfantry = infantryTypes.contains(upper)

    // Find the producing structure for this house
    let producerType: String
    if isInfantry {
        let owned = getHouseState(house).ownedBuildingTypes()
        if owned.contains("HAND") {
            producerType = "HAND"
        } else if owned.contains("PYLE") {
            producerType = "PYLE"
        } else {
            return  // No barracks
        }
    } else {
        producerType = "WEAP"
    }

    guard let producer = world.objects.first(where: {
        $0.kind == .structure && $0.typeName.uppercased() == producerType &&
        $0.house == house && $0.strength > 0
    }) else { return }

    let size = buildingSize(producerType)
    let exitX = producer.worldX + Double(size.w * 24) / 2.0 + 12.0
    let exitY = producer.worldY + Double(size.h * 24) / 2.0

    let kind: ObjectKind = isInfantry ? .infantry : .unit
    let speed = resolveSpeed(typeName: upper, kind: kind)

    let obj = GameObject(
        id: world.allocateId(),
        typeName: typeName,
        house: house,
        kind: kind,
        worldX: exitX, worldY: exitY,
        facing: 128,  // Face south
        strength: resolveStrength(typeName: upper, kind: kind, scenarioStrength: 256),
        mission: upper == "HARV" ? .harvest : .guard_,
        speed: speed
    )
    world.addObject(obj)
    print("AI: \(house.rawValue) produced \(typeName)")
}

