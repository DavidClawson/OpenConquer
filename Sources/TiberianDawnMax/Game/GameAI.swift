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

    // Tick AI structure building every tick (queue advances by 1 per tick)
    tickAIStructureProduction()

    // AI attack coordination every 30 ticks
    if session.aiTickCounter % 30 == 0 {
        tickAIAttackWaves(world: world)
        tickAIDamagedRetreat(world: world)
    }

    // AI tactical behaviors (recon, hit-and-run, flanking, harassment)
    tickAITactics()

    // AI building priority evaluation every 60 ticks (~4 seconds)
    if session.aiTickCounter % 60 == 0 {
        tickAIBuilding()
        tickAIHarvesterManagement()
    }

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
                    // Record enemy position in AI memory
                    let houseState = getHouseState(obj.house)
                    recordEnemyPosition(houseState: houseState, enemy: enemy, tick: world.tickCount)
                }
            }
            continue
        }

        // Skip harvesters and MCVs — they have their own behavior
        if obj.isHarvester {
            if obj.mission == .guard_ || obj.mission == .stop {
                obj.mission = .harvest
            }
            continue
        }
        if obj.isMCV { continue }

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
                    // Record enemy position in AI memory
                    let houseState = getHouseState(obj.house)
                    recordEnemyPosition(houseState: houseState, enemy: enemy, tick: world.tickCount)
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
    guard let squad = decideRally(world: world) else { return }
    applyRally(squad: squad, playerBase: playerBase)
}

/// PURE (B3-P3): gather a 3-5 unit rally squad of idle enemy combat units, or
/// nil if there aren't enough. No RNG, no mutation.
func decideRally(world: GameWorld) -> [GameObject]? {
    // Gather idle enemy combat units
    var idleUnits: [GameObject] = []
    for obj in world.objects {
        if obj.house == world.playerHouse || obj.house == .neutral { continue }
        if obj.kind == .structure { continue }
        if obj.strength <= 0 { continue }
        if obj.isHarvester || obj.isMCV { continue }
        if obj.mission == .guard_ || obj.mission == .stop {
            idleUnits.append(obj)
        }
    }

    // Send groups of 3-5 idle units toward the player base
    let squadSize = min(5, max(3, idleUnits.count))
    guard idleUnits.count >= squadSize else { return nil }
    return Array(idleUnits.prefix(squadSize))
}

/// EFFECTFUL (B3-P3): order a rally squad toward the player base, with a per-unit
/// ±48px jitter draw so they don't stack. The only RNG in the rally path.
func applyRally(squad: [GameObject], playerBase: (x: Double, y: Double)) {
    for unit in squad {
        // Add some randomness to the target so they don't all stack
        let offsetX = rndDouble(-48...48)
        let offsetY = rndDouble(-48...48)
        unit.moveTargetX = max(12, min(64 * 24 - 12, playerBase.x + offsetX))
        unit.moveTargetY = max(12, min(64 * 24 - 12, playerBase.y + offsetY))
        unit.mission = .move
        unit.movePath = []
    }
}

/// Escalate AI: send all idle enemy units to hunt mode.
func escalateAI(world: GameWorld) {
    applyEscalation(units: decideEscalation(world: world))
    print("AI: Escalation — all idle enemy units set to hunt")
}

/// PURE (B3-P3): gather all idle enemy combat units. No RNG, no mutation.
func decideEscalation(world: GameWorld) -> [GameObject] {
    var idleUnits: [GameObject] = []
    for obj in world.objects {
        if obj.house == world.playerHouse || obj.house == .neutral { continue }
        if obj.kind == .structure { continue }
        if obj.strength <= 0 { continue }
        if obj.isHarvester || obj.isMCV { continue }
        if obj.mission == .guard_ || obj.mission == .stop {
            idleUnits.append(obj)
        }
    }
    return idleUnits
}

/// EFFECTFUL (B3-P3): set the escalation squad to hunt mode.
func applyEscalation(units: [GameObject]) {
    for obj in units { obj.mission = .hunt }
}

/// Try to create an autocreate team from available team types
func tryAutocreateTeam() {
    let autocreateTypes = session.teamTypes.filter { $0.isAutocreate }
    guard !autocreateTypes.isEmpty else { return }

    // Pick a random autocreate team type
    let type = autocreateTypes[rndInt(0..<autocreateTypes.count)]

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

    for house in session.houseStates.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        guard let state = session.houseStates[house] else { continue }
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

/// Pick a vehicle for the AI to build. Thin shim over the B3 decide/apply split:
/// `decideUnitBuild` (pure) chooses the plan, `applyBuildPlan` does the single
/// weighted RNG draw. Behavior — and RNG consumption — is identical to the
/// former inline implementation (gated by `--determinism`).
private func aiPickVehicle(
    house: House,
    houseState: HouseState,
    owned: Set<String>,
    costMultiplier: Double
) -> (typeName: String, cost: Int, buildTime: Int)? {
    return applyBuildPlan(decideUnitBuild(house: house, houseState: houseState,
                                          owned: owned, costMultiplier: costMultiplier))
}

/// PURE (B3-P2): decide what vehicle to build, without consuming RNG. Returns a
/// `.forced` plan for the priority harvester (no draw) or a `.weighted` pool for
/// combat vehicles (one draw in apply). Mirrors the former aiPickVehicle body.
func decideUnitBuild(
    house: House,
    houseState: HouseState,
    owned: Set<String>,
    costMultiplier: Double
) -> AIBuildPlan {
    guard owned.contains("WEAP") || owned.contains("AFLD") else { return .none }
    guard let world = session.world else { return .none }

    // Count existing harvesters and combat vehicles for this house
    var harvesterCount = 0
    var combatVehicleCount = 0
    for obj in world.objects {
        guard obj.house == house && obj.strength > 0 else { continue }
        if obj.isHarvester { harvesterCount += 1 }
        if obj.kind == .unit && !obj.isHarvester && !obj.isMCV { combatVehicleCount += 1 }
    }

    // Priority 1: Need at least 1 harvester if we have a refinery (no RNG draw)
    if harvesterCount == 0 && owned.contains("PROC") {
        if let data = getUnitTypeDataByName("HARV") {
            let cost = Int(Double(data.cost) * costMultiplier)
            let ticks = max(30, cost / 5)
            return .forced(BuildCandidate(name: "HARV", weight: 0, cost: cost, buildTime: ticks))
        }
    }

    // Priority 2: Build combat vehicles
    let isNod = (houseToHousesType(house) == .bad)

    // Build pool based on faction
    var pool: [(name: String, weight: Int)] = []
    if owned.contains("WEAP") {
        if isNod {
            pool.append((name: "LTNK", weight: 4))
            pool.append((name: "BGGY", weight: 3))
            pool.append((name: "FTNK", weight: 2))
            pool.append((name: "ARTY", weight: 2))
            pool.append((name: "APC", weight: 1))
            if owned.contains("AFLD") {
                pool.append((name: "STNK", weight: 2))
            }
        } else {
            pool.append((name: "MTNK", weight: 5))
            pool.append((name: "JEEP", weight: 3))
            pool.append((name: "MSAM", weight: 2))
            pool.append((name: "APC", weight: 1))
            pool.append((name: "MLRS", weight: 2))
            if houseState.credits > 1500 {
                pool.append((name: "HTNK", weight: 2))
            }
        }
    }

    // Filter to what this house can build, precomputing cost/buildTime (pure).
    var candidates: [BuildCandidate] = []
    for c in pool {
        guard let ut = UnitType.from(iniName: c.name),
              let data = unitTypeDataTable[ut],
              houseState.canBuildUnit(data) else { continue }
        let cost = Int(Double(data.cost) * costMultiplier)
        let ticks = max(30, cost / 5)
        candidates.append(BuildCandidate(name: c.name, weight: c.weight, cost: cost, buildTime: ticks))
    }

    guard !candidates.isEmpty else { return .none }
    return .weighted(candidates)
}

/// Pick an infantry for the AI to build. Shim over the decide/apply split (see
/// aiPickVehicle). RNG consumption is identical to the former inline version.
private func aiPickInfantry(
    house: House,
    houseState: HouseState,
    owned: Set<String>,
    costMultiplier: Double
) -> (typeName: String, cost: Int, buildTime: Int)? {
    return applyBuildPlan(decideInfantryBuild(house: house, houseState: houseState,
                                              owned: owned, costMultiplier: costMultiplier))
}

/// PURE (B3-P2): decide what infantry to build, without consuming RNG. Always a
/// `.weighted` pool (no priority/forced case). Mirrors the former body.
func decideInfantryBuild(
    house: House,
    houseState: HouseState,
    owned: Set<String>,
    costMultiplier: Double
) -> AIBuildPlan {
    let isNod = (houseToHousesType(house) == .bad)

    var pool: [(name: String, weight: Int)] = []
    if isNod {
        pool.append((name: "E1", weight: 5))
        pool.append((name: "E3", weight: 3))
        pool.append((name: "E4", weight: 2))
        if owned.contains("TMPL") {
            pool.append((name: "E5", weight: 1))
        }
    } else {
        pool.append((name: "E1", weight: 5))
        pool.append((name: "E2", weight: 3))
        pool.append((name: "E3", weight: 3))
    }

    // Filter to what the house can build, precomputing cost/buildTime (pure).
    var candidates: [BuildCandidate] = []
    for c in pool {
        guard let it = InfantryType.from(iniName: c.name),
              let data = infantryTypeDataTable[it],
              houseState.canBuildInfantry(data) else { continue }
        let cost = Int(Double(data.cost) * costMultiplier)
        let ticks = max(20, cost / 5)
        candidates.append(BuildCandidate(name: c.name, weight: c.weight, cost: cost, buildTime: ticks))
    }

    guard !candidates.isEmpty else { return .none }
    return .weighted(candidates)
}

/// EFFECTFUL (B3-P2): turn a production plan into the chosen build. The ONLY
/// place a production RNG draw happens — exactly one `rndInt(0..<totalWeight)`
/// for `.weighted`, none for `.forced`, matching the procedural AI's behavior.
func applyBuildPlan(_ plan: AIBuildPlan) -> (typeName: String, cost: Int, buildTime: Int)? {
    switch plan {
    case .none:
        return nil
    case .forced(let c):
        return (typeName: c.name, cost: c.cost, buildTime: c.buildTime)
    case .weighted(let candidates):
        guard !candidates.isEmpty else { return nil }
        let totalWeight = candidates.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        var roll = rndInt(0..<totalWeight)
        for c in candidates {
            roll -= c.weight
            if roll < 0 {
                return (typeName: c.name, cost: c.cost, buildTime: c.buildTime)
            }
        }
        return nil
    }
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

// MARK: - AI Structure Production System

/// Tick AI structure production queues — advances build progress each tick.
func tickAIStructureProduction() {
    guard let world = session.world else { return }

    for house in session.houseStates.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        guard let state = session.houseStates[house] else { continue }
        if house == world.playerHouse || house == .neutral { continue }
        if !state.productionEnabled { continue }

        // Must have a construction yard to build structures
        let owned = state.ownedBuildingTypes()
        guard owned.contains("FACT") else { continue }

        // Advance structure build queue
        if state.aiStructureQueue.item != nil {
            let completed = state.aiStructureQueue.tick(hasPower: state.hasPower, worldTickCount: world.tickCount)
            if completed {
                let typeName = state.aiStructureQueue.item!.typeName
                placeAIStructure(typeName, house: house, world: world)
                state.aiStructureQueue.clear()
                state.aiBuildCycleCount += 1
            }
        }
    }
}

/// Evaluate building priorities and start structure production for AI houses.
/// Called every 60 ticks (~4 seconds).
func tickAIBuilding() {
    guard let world = session.world else { return }

    for house in session.houseStates.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        guard let state = session.houseStates[house] else { continue }
        if house == world.playerHouse || house == .neutral { continue }
        if !state.productionEnabled { continue }

        let owned = state.ownedBuildingTypes()
        guard owned.contains("FACT") else { continue }

        // Don't start a new build if one is in progress
        guard state.aiStructureQueue.item == nil else { continue }

        let isNod = (houseToHousesType(house) == .bad)
        let costMult = aiCostMultiplier()

        // Count existing structures for this house
        var refineryCount = 0
        var harvesterCount = 0
        for obj in world.objects {
            guard obj.house == house && obj.strength > 0 else { continue }
            if obj.isRefinery { refineryCount += 1 }
            if obj.isHarvester { harvesterCount += 1 }
        }

        // Pick a structure to build based on priority
        if let choice = decideStructureBuild(
            house: house, houseState: state, owned: owned,
            isNod: isNod, costMultiplier: costMult,
            refineryCount: refineryCount, harvesterCount: harvesterCount
        ) {
            if state.spendCredits(choice.cost) {
                state.aiStructureQueue.start(typeName: choice.typeName, cost: choice.cost, buildTime: choice.buildTime)
                print("AI: \(house.rawValue) started building \(choice.typeName) ($\(choice.cost))")
            }
        }
    }
}

/// PURE (B3-P2): pick the highest-priority structure for the AI to build via a
/// deterministic priority ladder — consumes NO RNG. The effectful enqueue
/// (spendCredits + queue.start) stays in `tickAIBuilding`.
func decideStructureBuild(
    house: House,
    houseState: HouseState,
    owned: Set<String>,
    isNod: Bool,
    costMultiplier: Double,
    refineryCount: Int,
    harvesterCount: Int
) -> (typeName: String, cost: Int, buildTime: Int)? {

    // Helper to create a build choice from building data
    func choice(_ iniName: String) -> (typeName: String, cost: Int, buildTime: Int)? {
        guard let data = getBuildingTypeDataByName(iniName) else { return nil }
        guard houseState.canBuildStructure(data) else { return nil }
        let cost = Int(Double(data.cost) * costMultiplier)
        guard houseState.credits >= cost else { return nil }
        let ticks = max(30, cost / 5)
        return (typeName: iniName, cost: cost, buildTime: ticks)
    }

    // Priority 1: Power Plant when power deficit or no power at all
    if !houseState.hasPower || houseState.powerOutput == 0 {
        // Prefer Advanced Power Plant if we already have one regular and enough credits
        if owned.contains("NUKE") && houseState.credits > 1500 {
            if let c = choice("NUK2") { return c }
        }
        if let c = choice("NUKE") { return c }
    }

    // Priority 2: Refinery when fewer than 2
    if refineryCount < 2 {
        if let c = choice("PROC") { return c }
    }

    // Priority 3: Barracks if none exists
    let barracksType = isNod ? "HAND" : "PYLE"
    if !owned.contains("PYLE") && !owned.contains("HAND") {
        if let c = choice(barracksType) { return c }
    }

    // Priority 4: War Factory / Airstrip if none exists
    if isNod {
        if !owned.contains("AFLD") && !owned.contains("WEAP") {
            if let c = choice("AFLD") { return c }
        }
    } else {
        if !owned.contains("WEAP") {
            if let c = choice("WEAP") { return c }
        }
    }

    // Priority 5: Defense structures every 3rd building cycle
    if houseState.aiBuildCycleCount % 3 == 2 {
        if isNod {
            // Nod: Gun Turret first, then Obelisk if HQ is built
            if owned.contains("HQ") {
                if let c = choice("OBLI") { return c }
            }
            if let c = choice("GUN") { return c }
        } else {
            // GDI: Guard Tower first, then Advanced Guard Tower if HQ is built
            if owned.contains("HQ") {
                if let c = choice("ATWR") { return c }
            }
            if let c = choice("GTWR") { return c }
        }
    }

    // Priority 6: Tiberium Silo when storage nearly full
    if houseState.capacity > 0 && houseState.tiberium > houseState.capacity * 3 / 4 {
        if let c = choice("SILO") { return c }
    }

    // Priority 7: Communications Center (HQ)
    if !owned.contains("HQ") && (owned.contains("PROC")) {
        if let c = choice("HQ") { return c }
    }

    // Priority 8: Advanced structures when economy is strong
    if houseState.credits > 2000 {
        if isNod {
            if !owned.contains("AFLD") {
                if let c = choice("AFLD") { return c }
            }
            if !owned.contains("SAM") {
                if let c = choice("SAM") { return c }
            }
            if !owned.contains("TMPL") && owned.contains("HQ") {
                if let c = choice("TMPL") { return c }
            }
        } else {
            if !owned.contains("HPAD") {
                if let c = choice("HPAD") { return c }
            }
            if !owned.contains("ATWR") && owned.contains("HQ") {
                if let c = choice("ATWR") { return c }
            }
            if !owned.contains("EYE") && owned.contains("HQ") {
                if let c = choice("EYE") { return c }
            }
        }
        // Repair Bay for both factions
        if !owned.contains("FIX") {
            if let c = choice("FIX") { return c }
        }
    }

    // Priority 9: Additional power if close to deficit
    if houseState.powerOutput < houseState.powerDrain + 50 {
        if houseState.credits > 800 {
            if let c = choice("NUK2") { return c }
        }
        if let c = choice("NUKE") { return c }
    }

    // Priority 10: Additional refinery for extra income
    if refineryCount < 3 && houseState.credits > 3000 {
        if let c = choice("PROC") { return c }
    }

    return nil
}

// MARK: - AI Building Placement

/// Find a valid cell for the AI to place a building near its base.
/// Returns the top-left cell index, or nil if no valid placement found.
func findAIBuildLocation(typeName: String, house: House) -> Int? {
    guard let world = session.world else { return nil }
    let size = buildingSize(typeName)
    let upper = typeName.uppercased()

    // Determine if this is a defense structure (prefer base edges)
    // / power plant (prefer interior). Resolved via the StructType enum so
    // the role-flag list stays in one place (Data/GameTypes.swift).
    let st = StructType.from(iniName: upper)
    let isDefense = st?.isDefenseStructure ?? false
    let isPower = st?.isPowerPlant ?? false

    // Collect all existing buildings for this AI house
    var ownedBuildings: [(cellX: Int, cellY: Int, w: Int, h: Int)] = []
    var baseCenterX = 0.0
    var baseCenterY = 0.0
    var buildingCount = 0

    for obj in world.objects {
        guard obj.house == house && obj.kind == .structure && obj.strength > 0 else { continue }
        let bSize = buildingSize(obj.typeName)
        // Calculate top-left cell of the building from its center world position
        let topLeftX = Int(obj.worldX - Double(bSize.w * 24) / 2.0) / 24
        let topLeftY = Int(obj.worldY - Double(bSize.h * 24) / 2.0) / 24
        ownedBuildings.append((cellX: topLeftX, cellY: topLeftY, w: bSize.w, h: bSize.h))
        baseCenterX += obj.worldX
        baseCenterY += obj.worldY
        buildingCount += 1
    }

    guard buildingCount > 0 else { return nil }
    baseCenterX /= Double(buildingCount)
    baseCenterY /= Double(buildingCount)
    let baseCellX = Int(baseCenterX) / 24
    let baseCellY = Int(baseCenterY) / 24

    // Candidate cells: scan area around existing buildings (within 5 cells)
    var bestCell: Int? = nil
    var bestScore = -Double.infinity

    // Build a set of cells occupied by existing buildings for quick lookup
    var occupiedCells = Set<Int>()
    for b in ownedBuildings {
        for dy in 0..<b.h {
            for dx in 0..<b.w {
                let c = (b.cellY + dy) * 64 + (b.cellX + dx)
                if c >= 0 && c < 4096 {
                    occupiedCells.insert(c)
                }
            }
        }
    }

    for b in ownedBuildings {
        // Search in a ring around each existing building
        let searchRadius = 4
        let minX = max(2, b.cellX - searchRadius)
        let maxX = min(62 - size.w, b.cellX + b.w + searchRadius)
        let minY = max(2, b.cellY - searchRadius)
        let maxY = min(62 - size.h, b.cellY + b.h + searchRadius)

        for cy in minY...maxY {
            for cx in minX...maxX {
                // Check if all footprint cells are passable and not occupied
                var valid = true
                for dy in 0..<size.h {
                    for dx in 0..<size.w {
                        let checkCell = (cy + dy) * 64 + (cx + dx)
                        if checkCell < 0 || checkCell >= 4096 {
                            valid = false
                            break
                        }
                        if !staticPassability[checkCell] {
                            valid = false
                            break
                        }
                        if occupiedCells.contains(checkCell) {
                            valid = false
                            break
                        }
                    }
                    if !valid { break }
                }
                if !valid { continue }

                // Check adjacency: at least one cell of the footprint must be
                // adjacent to an existing owned building
                var isAdjacent = false
                for existingB in ownedBuildings {
                    for dy in -1...size.h {
                        for dx in -1...size.w {
                            let checkX = cx + dx
                            let checkY = cy + dy
                            if checkX >= existingB.cellX && checkX < existingB.cellX + existingB.w &&
                               checkY >= existingB.cellY && checkY < existingB.cellY + existingB.h {
                                isAdjacent = true
                                break
                            }
                        }
                        if isAdjacent { break }
                    }
                    if isAdjacent { break }
                }
                if !isAdjacent { continue }

                // Score this position
                let centerX = Double(cx) + Double(size.w) / 2.0
                let centerY = Double(cy) + Double(size.h) / 2.0
                let distFromBase = sqrt(pow(centerX - Double(baseCellX), 2) +
                                       pow(centerY - Double(baseCellY), 2))

                var score = 0.0

                if isDefense {
                    // Defenses prefer base edges (farther from center)
                    score = distFromBase * 2.0
                } else if isPower {
                    // Power plants prefer interior (closer to center)
                    score = -distFromBase * 2.0
                } else {
                    // Other buildings: moderate distance, slight outward expansion
                    score = distFromBase * 0.5
                }

                // Small random factor to avoid always placing in same spot
                score += rndDouble(0.0...2.0)

                if score > bestScore {
                    bestScore = score
                    bestCell = cy * 64 + cx
                }
            }
        }
    }

    return bestCell
}

/// Place a completed AI structure on the map.
private func placeAIStructure(_ typeName: String, house: House, world: GameWorld) {
    guard let cell = findAIBuildLocation(typeName: typeName, house: house) else {
        print("AI: \(house.rawValue) could not find placement for \(typeName)")
        return
    }

    let pos = cellToPixel(cell)
    let size = buildingSize(typeName)
    let cx = Double(pos.px) + Double(size.w * 24) / 2.0
    let cy = Double(pos.py) + Double(size.h * 24) / 2.0

    let obj = GameObject(
        id: world.allocateId(),
        typeName: typeName,
        house: house,
        kind: .structure,
        worldX: cx, worldY: cy,
        facing: 0,
        strength: resolveStrength(typeName: typeName, kind: .structure, scenarioStrength: 256),
        mission: .construction,
        speed: 0.0
    )
    // Start build-up animation
    obj.buildUpFrame = 0
    obj.buildUpDelay = 0
    world.addObject(obj)

    // Mark footprint as impassable
    let cellXY = cellToXY(cell)
    for dy in 0..<size.h {
        for dx in 0..<size.w {
            let c = (cellXY.y + dy) * 64 + (cellXY.x + dx)
            if c >= 0 && c < 4096 {
                staticPassability[c] = false
            }
        }
    }

    // Recalculate power for all houses
    recalculateAllHousePower()

    print("AI: \(house.rawValue) placed \(typeName) at cell \(cell)")
}

// MARK: - AI Attack Coordination

/// Minimum ticks between attack waves, scaled by difficulty
func aiAttackInterval() -> Int {
    switch session.campaignState.difficulty {
    case 0:  return 15 * 90   // Easy — 90 seconds
    case 2:  return 15 * 60   // Hard — 60 seconds
    default: return 15 * 75   // Normal — 75 seconds
    }
}

/// Idle unit threshold for launching an attack wave, scaled by difficulty
func aiAttackThreshold() -> Int {
    switch session.campaignState.difficulty {
    case 0:  return 5    // Easy — needs more units before attacking
    case 2:  return 4    // Hard — attacks sooner with fewer units
    default: return 6    // Normal
    }
}

/// A decided attack wave: which idle units to send at which target. Coarse plan
/// (object refs) consumed synchronously by `applyAttackWave` in the same tick;
/// the per-unit flank RNG lives in applyFlankingTactics (the apply phase).
struct AttackWavePlan { let units: [GameObject]; let target: GameObject }

/// Check for idle combat units and launch attack waves (B3-P3 decide/apply split).
func tickAIAttackWaves(world: GameWorld) {
    for house in session.houseStates.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        guard let state = session.houseStates[house] else { continue }
        if house == world.playerHouse || house == .neutral { continue }
        if !state.productionEnabled { continue }

        if let plan = decideAttackWave(house: house, state: state, world: world) {
            applyAttackWave(plan, house: house, state: state, world: world)
        }
    }
}

/// PURE (B3-P3): decide whether `house` should launch an attack wave this tick,
/// and if so which idle units to send at which target. No RNG, no mutation.
func decideAttackWave(house: House, state: HouseState, world: GameWorld) -> AttackWavePlan? {
    let attackInterval = aiAttackInterval()
    let threshold = aiAttackThreshold()

    // Enforce minimum interval between attacks
    let ticksSinceLastAttack = session.aiTickCounter - state.aiLastAttackTick
    guard ticksSinceLastAttack >= attackInterval else { return nil }

    // Gather idle combat units (on guard or stop), excluding those with tactical roles
    var idleUnits: [GameObject] = []
    for obj in world.objects {
        guard obj.house == house && obj.strength > 0 else { continue }
        guard obj.kind == .unit || obj.kind == .infantry else { continue }
        if obj.isHarvester || obj.isMCV { continue }
        guard obj.mission == .guard_ || obj.mission == .stop else { continue }
        guard obj.isArmed else { continue }
        guard obj.aiTacticalRole == .none else { continue }
        idleUnits.append(obj)
    }

    guard idleUnits.count >= threshold else { return nil }

    // Find a target: use AI memory for weakest known cluster, else nearest player structure
    var target: GameObject? = nil
    var targetDist = Double.infinity

    // Calculate AI base center for distance measurement
    guard let aiBase = findHouseBase(house: house, world: world) else { return nil }

    // Try to use known enemy positions to find the weakest cluster
    if !state.aiKnownEnemyPositions.isEmpty {
        // Find the known position with the weakest nearby concentration
        // (prefer isolated enemy positions for easier attacks)
        var bestKnownTarget: GameObject? = nil
        var bestKnownScore = Double.infinity
        for known in state.aiKnownEnemyPositions {
            // Find actual enemy near this known position
            for obj in world.objects {
                guard obj.house != house && obj.house != .neutral && obj.strength > 0 else { continue }
                let dx = obj.worldX - known.x
                let dy = obj.worldY - known.y
                guard abs(dx) < 120 && abs(dy) < 120 else { continue }
                // Score: lower is better (fewer nearby defenders + closer to AI base)
                let distToBase = sqrt(pow(obj.worldX - aiBase.x, 2) + pow(obj.worldY - aiBase.y, 2))
                let score = distToBase
                if score < bestKnownScore {
                    bestKnownScore = score
                    bestKnownTarget = obj
                }
            }
        }
        target = bestKnownTarget
    }

    // Fallback: nearest player structure or harvester
    if target == nil {
        for obj in world.objects {
            guard obj.house == world.playerHouse && obj.strength > 0 else { continue }
            guard obj.kind == .structure || obj.isHarvester else { continue }
            let dx = obj.worldX - aiBase.x
            let dy = obj.worldY - aiBase.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist < targetDist {
                target = obj
                targetDist = dist
            }
        }
    }

    guard let attackTarget = target else { return nil }
    return AttackWavePlan(units: idleUnits, target: attackTarget)
}

/// EFFECTFUL (B3-P3): execute a decided attack wave. Delegates to
/// applyFlankingTactics (the only RNG here) and records the attack tick.
func applyAttackWave(_ plan: AttackWavePlan, house: House, state: HouseState, world: GameWorld) {
    // Use flanking tactics for large waves (6+ units on Hard difficulty)
    applyFlankingTactics(
        units: plan.units, target: plan.target,
        house: house, houseState: state, world: world
    )

    state.aiLastAttackTick = session.aiTickCounter
    print("AI: \(house.rawValue) launched attack wave with \(plan.units.count) units")
}

/// Retreat damaged AI units below 30% health to their base.
func tickAIDamagedRetreat(world: GameWorld) {
    for obj in world.objects {
        if obj.house == world.playerHouse || obj.house == .neutral { continue }
        if obj.kind == .structure { continue }
        if obj.strength <= 0 { continue }
        if obj.isHarvester || obj.isMCV { continue }

        // Only retreat units that are in combat (attacking) and badly hurt
        guard obj.mission == .attack else { continue }
        guard obj.healthFraction < 0.3 else { continue }

        // Retreat to nearest friendly building
        obj.attackTarget = nil
        obj.mission = .retreat
        obj.movePath = []
    }
}

/// Find the average position of a specific house's structures.
func findHouseBase(house: House, world: GameWorld) -> (x: Double, y: Double)? {
    var totalX = 0.0
    var totalY = 0.0
    var count = 0

    for obj in world.objects {
        if obj.kind == .structure && obj.house == house && obj.strength > 0 {
            totalX += obj.worldX
            totalY += obj.worldY
            count += 1
        }
    }

    guard count > 0 else { return nil }
    return (x: totalX / Double(count), y: totalY / Double(count))
}

// MARK: - AI Harvester Management

/// Ensure AI houses have harvesters and refineries.
func tickAIHarvesterManagement() {
    guard let world = session.world else { return }

    for house in session.houseStates.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        guard let state = session.houseStates[house] else { continue }
        if house == world.playerHouse || house == .neutral { continue }
        if !state.productionEnabled { continue }

        let owned = state.ownedBuildingTypes()
        guard owned.contains("PROC") else { continue }

        // Count harvesters
        var harvesterCount = 0
        for obj in world.objects {
            guard obj.house == house && obj.strength > 0 else { continue }
            if obj.isHarvester { harvesterCount += 1 }
        }

        // If no harvesters and unit queue is idle, prioritize building one
        if harvesterCount == 0 && state.aiUnitQueue.item == nil {
            // Check if the unit queue isn't already building a harvester
            if let data = getUnitTypeDataByName("HARV") {
                let cost = Int(Double(data.cost) * aiCostMultiplier())
                if state.spendCredits(cost) {
                    let ticks = max(30, cost / 5)
                    state.aiUnitQueue.start(typeName: "HARV", cost: cost, buildTime: ticks)
                    print("AI: \(house.rawValue) emergency harvester build")
                }
            }
        }
    }
}

