import Foundation

// MARK: - AI Tactical Behaviors
// Scouting, hit-and-run, flanking attacks, and harvester harassment

/// Fast unit type names used for tactical roles
private let fastUnitTypes: Set<String> = ["BIKE", "BGGY", "JEEP", "STNK"]
/// Units eligible for hit-and-run (fast + armed)
private let hitAndRunTypes: Set<String> = ["BIKE", "BGGY", "JEEP", "MSAM", "STNK"]

// MARK: - Difficulty Check

/// Returns true if the given tactic is enabled for the current difficulty.
/// Easy (0): recon only. Normal (1): recon + hit-and-run. Hard (2): all tactics.
private func isTacticEnabled(_ tactic: AITactic) -> Bool {
    let difficulty = session.campaignState.difficulty
    switch tactic {
    case .recon:
        return true  // All difficulties
    case .hitAndRun:
        return difficulty >= 1
    case .flanking, .harassment:
        return difficulty >= 2
    }
}

private enum AITactic {
    case recon
    case hitAndRun
    case flanking
    case harassment
}

// MARK: - Master Tactical Tick

/// Main entry point for AI tactical behaviors. Called from tickAI().
///
/// B3-P4: each tactic is split into a PURE `decide*` (gate predicate + the
/// management-independent selection — no RNG, no mutation) and an EFFECTFUL
/// `apply*` (the per-unit state machine: mutation + the RNG draws via
/// retreatToBase / scout-target / flank jitter). The decide is called first and
/// consumes no RNG, so the simulation digest is unchanged. Where a tactic's
/// selection genuinely depends on its own management mutations (hit-and-run
/// attacker selection), that selection stays in apply — see decideHitAndRun.
func tickAITactics() {
    guard let world = session.world else { return }

    for house in session.houseStates.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        guard let state = session.houseStates[house] else { continue }
        if house == world.playerHouse || house == .neutral { continue }
        if !state.productionEnabled { continue }

        // Expire stale enemy position memory (older than 2700 ticks = 3 minutes)
        expireEnemyMemory(houseState: state, currentTick: world.tickCount)

        // Recon / scouting — every 90 ticks (~6 seconds check interval)
        if isTacticEnabled(.recon) && world.tickCount % 90 == 0 {
            applyRecon(decideRecon(house: house, houseState: state, world: world),
                       houseState: state, world: world)
        }

        // Hit-and-run — every 60 ticks (~4 seconds check interval)
        if isTacticEnabled(.hitAndRun) && world.tickCount % 60 == 0 {
            if let plan = decideHitAndRun(house: house, houseState: state, world: world) {
                applyHitAndRun(plan, house: house, houseState: state, world: world)
            }
        }

        // Harvester harassment — every 90 ticks (~6 seconds check interval)
        if isTacticEnabled(.harassment) && world.tickCount % 90 == 0 {
            applyHarass(decideHarass(house: house, houseState: state, world: world),
                        houseState: state, world: world)
        }

        // Flanking follow-up — check every 15 ticks for delayed flank engagement
        if isTacticEnabled(.flanking) && world.tickCount % 15 == 0 {
            if decideFlankFollowUp(houseState: state, world: world) {
                applyFlankFollowUp(house: house, houseState: state, world: world)
            }
        }
    }
}

// MARK: - Enemy Memory

/// Record a spotted enemy position in AI memory
func recordEnemyPosition(houseState: HouseState, enemy: GameObject, tick: Int) {
    // Avoid duplicate entries for the same unit within 150 ticks
    let dominated = houseState.aiKnownEnemyPositions.contains {
        abs($0.x - enemy.worldX) < 48 && abs($0.y - enemy.worldY) < 48 &&
        $0.typeName == enemy.typeName && (tick - $0.tick) < 150
    }
    if !dominated {
        houseState.aiKnownEnemyPositions.append(
            (x: enemy.worldX, y: enemy.worldY, typeName: enemy.typeName, tick: tick)
        )
    }
}

/// Remove enemy positions older than 2700 ticks (3 minutes)
private func expireEnemyMemory(houseState: HouseState, currentTick: Int) {
    houseState.aiKnownEnemyPositions.removeAll { currentTick - $0.tick > 2700 }
}

// MARK: - 1. Recon / Scouting

/// What recon wants to do this tick (pure decision; see decideRecon).
enum ReconAction {
    case none
    case tickExisting(GameObject)                              // active scout: run its behavior
    case dispatch(scout: GameObject, biasX: Double, biasY: Double)  // send a new scout
}

/// PURE (B3-P4): decide the recon action. No RNG, no mutation. Called every 90
/// ticks but only dispatches a new scout every 1350 ticks (90 seconds).
func decideRecon(house: House, houseState: HouseState, world: GameWorld) -> ReconAction {
    // Only send a new scout every 1350 ticks (90 seconds)
    let ticksSinceLastScout = world.tickCount - houseState.aiLastScoutTick
    guard ticksSinceLastScout >= 1350 else { return .none }

    // Check if current scout is still alive and active
    if let scoutId = houseState.aiScoutUnitId,
       let scout = world.findObject(id: scoutId),
       scout.strength > 0 && scout.aiTacticalRole == .scout {
        return .tickExisting(scout)
    }

    // No active scout — find the fastest idle unit to send
    var bestUnit: GameObject? = nil
    var bestSpeed: Double = 0

    for obj in world.objects {
        guard obj.house == house && obj.strength > 0 else { continue }
        guard obj.kind == .unit else { continue }
        let upper = obj.typeName.uppercased()
        guard fastUnitTypes.contains(upper) else { continue }
        guard obj.mission == .guard_ || obj.mission == .stop else { continue }
        guard obj.aiTacticalRole == .none else { continue }
        if obj.speed > bestSpeed {
            bestSpeed = obj.speed
            bestUnit = obj
        }
    }

    guard let scout = bestUnit else { return .none }

    // Pick a scout target: cell biased toward map center from AI base
    guard let aiBase = findHouseBase(house: house, world: world) else { return .none }
    let mapCenterX = 32.0 * 24.0
    let mapCenterY = 32.0 * 24.0
    let biasX = (aiBase.x + mapCenterX) / 2.0
    let biasY = (aiBase.y + mapCenterY) / 2.0
    return .dispatch(scout: scout, biasX: biasX, biasY: biasY)
}

/// EFFECTFUL (B3-P4): execute the recon action. The scout-target ±360px draw is
/// the only RNG in the dispatch path; the active-scout path runs the (RNG-free)
/// scout state machine.
func applyRecon(_ action: ReconAction, houseState: HouseState, world: GameWorld) {
    switch action {
    case .none:
        return
    case .tickExisting(let scout):
        // Scout still active — check if it reached destination or spotted enemies
        tickScoutBehavior(scout: scout, houseState: houseState, world: world)
    case .dispatch(let scout, let biasX, let biasY):
        // Add randomness (up to 15 cells in any direction)
        let targetX = biasX + rndDouble(-360...360)
        let targetY = biasY + rndDouble(-360...360)

        // Clamp to map bounds
        let clampedX = max(72, min(64 * 24 - 72, targetX))
        let clampedY = max(72, min(64 * 24 - 72, targetY))

        // Dispatch the scout
        scout.moveTargetX = clampedX
        scout.moveTargetY = clampedY
        scout.mission = .move
        scout.movePath = []
        scout.aiTacticalRole = .scout
        houseState.aiScoutUnitId = scout.id
        houseState.aiLastScoutTick = world.tickCount
        houseState.aiScoutTargetCell = Int(clampedY / 24) * 64 + Int(clampedX / 24)
    }
}

/// Handle active scout behavior: detect enemies and retreat, or pick new target.
private func tickScoutBehavior(scout: GameObject, houseState: HouseState, world: GameWorld) {
    let sightPixels = Double(scout.sightRange) * 24.0

    // Check for nearby enemies
    var foundEnemy = false
    for obj in world.objects {
        guard obj.strength > 0 else { continue }
        guard isEnemy(scout, obj) else { continue }
        let dx = obj.worldX - scout.worldX
        let dy = obj.worldY - scout.worldY
        let dist = sqrt(dx * dx + dy * dy)
        if dist <= sightPixels {
            // Record enemy position in AI memory
            recordEnemyPosition(houseState: houseState, enemy: obj, tick: world.tickCount)
            foundEnemy = true
        }
    }

    if foundEnemy {
        // Retreat to base
        retreatToBase(unit: scout, house: scout.house, world: world)
        scout.aiTacticalRole = .none
        houseState.aiScoutUnitId = nil
        return
    }

    // Check if scout reached destination (no move target and idle)
    if scout.moveTargetX == nil && (scout.mission == .guard_ || scout.mission == .stop) {
        // Reached destination with no enemies — clear scout role
        scout.aiTacticalRole = .none
        houseState.aiScoutUnitId = nil
    }

    // If scout gets into combat while scouting, release it
    if scout.mission == .attack {
        scout.aiTacticalRole = .none
        houseState.aiScoutUnitId = nil
    }
}

// MARK: - 2. Hit-and-Run Tactics

/// A decided hit-and-run engagement (B3-P4). `target` is the management-
/// independent enemy pick; `nil` means "no new engagement, just manage existing".
struct HitRunDecision { let target: GameObject? }

/// PURE (B3-P4): decide hit-and-run. Returns nil if the 900-tick cooldown hasn't
/// elapsed (apply is skipped entirely). Otherwise selects the priority enemy
/// target — a read-only enemy scan, independent of the management mutations apply
/// performs. No RNG, no mutation. Attacker selection is deliberately NOT here:
/// it depends on units the management phase may release to idle, so it lives in
/// apply, after management.
func decideHitAndRun(house: House, houseState: HouseState, world: GameWorld) -> HitRunDecision? {
    // Only initiate every 900 ticks (60 seconds)
    let ticksSinceLast = world.tickCount - houseState.aiLastHitAndRunTick
    guard ticksSinceLast >= 900 else { return nil }

    // Find a target: enemy harvesters are priority, then isolated slow units
    var target: GameObject? = nil
    var targetPriority = 0

    for obj in world.objects {
        guard obj.strength > 0 else { continue }
        guard obj.house != house && obj.house != .neutral else { continue }
        guard obj.kind == .unit || obj.kind == .infantry else { continue }

        if obj.isHarvester {
            // Harvesters are highest priority
            if targetPriority < 3 {
                target = obj
                targetPriority = 3
            }
        } else if obj.speed <= 1.5 && obj.isArmed {
            // Slow combat units are secondary targets
            if targetPriority < 2 {
                target = obj
                targetPriority = 2
            }
        } else if !obj.isArmed {
            // Unarmed units (MCVs, etc.) are tertiary
            if targetPriority < 1 {
                target = obj
                targetPriority = 1
            }
        }
    }

    return HitRunDecision(target: target)
}

/// EFFECTFUL (B3-P4): run hit-and-run. Manages existing hit-run units (RNG via
/// retreatToBase), then — if a target was decided — selects 1-2 fast idle
/// attackers (post-management state) and sends them in.
func applyHitAndRun(_ decision: HitRunDecision, house: House, houseState: HouseState, world: GameWorld) {
    // First, manage existing hit-and-run units
    for obj in world.objects {
        guard obj.house == house && obj.strength > 0 else { continue }
        guard obj.aiTacticalRole == .hitAndRun else { continue }

        // Abort if health drops below 40%
        if obj.healthFraction < 0.4 {
            retreatToBase(unit: obj, house: house, world: world)
            obj.aiTacticalRole = .none
            obj.aiHitAndRunTick = nil
            continue
        }

        // Check engagement duration
        if let engageTick = obj.aiHitAndRunTick {
            let ticksEngaged = world.tickCount - engageTick

            if obj.mission == .attack && ticksEngaged >= 60 {
                // Disengage after 60 ticks of combat — retreat 10 cells away from target
                if let targetId = obj.attackTarget,
                   let target = world.findObject(id: targetId) {
                    let dx = obj.worldX - target.worldX
                    let dy = obj.worldY - target.worldY
                    let dist = max(1.0, sqrt(dx * dx + dy * dy))
                    let retreatX = obj.worldX + (dx / dist) * 240.0  // 10 cells
                    let retreatY = obj.worldY + (dy / dist) * 240.0
                    obj.attackTarget = nil
                    obj.moveTargetX = max(12, min(64 * 24 - 12, retreatX))
                    obj.moveTargetY = max(12, min(64 * 24 - 12, retreatY))
                    obj.mission = .move
                    obj.movePath = []
                    obj.aiHitAndRunTick = world.tickCount  // Track retreat start
                } else {
                    // Target gone — release
                    obj.aiTacticalRole = .none
                    obj.aiHitAndRunTick = nil
                }
            } else if obj.mission == .move && ticksEngaged >= 45 {
                // Finished retreating (45 ticks) — re-engage if target alive
                if let targetId = obj.attackTarget,
                   let target = world.findObject(id: targetId),
                   target.strength > 0 {
                    obj.attackTarget = target.id
                    obj.mission = .attack
                    obj.movePath = []
                    obj.aiHitAndRunTick = world.tickCount
                } else {
                    // Target dead — release
                    obj.aiTacticalRole = .none
                    obj.aiHitAndRunTick = nil
                    obj.mission = .guard_
                }
            } else if obj.mission == .guard_ || obj.mission == .stop {
                // Somehow became idle — release
                obj.aiTacticalRole = .none
                obj.aiHitAndRunTick = nil
            }
        }
    }

    guard let hitTarget = decision.target else { return }

    // Find 1-2 fast idle units that are faster than the target
    var attackers: [GameObject] = []
    for obj in world.objects {
        guard obj.house == house && obj.strength > 0 else { continue }
        guard obj.kind == .unit else { continue }
        let upper = obj.typeName.uppercased()
        guard hitAndRunTypes.contains(upper) else { continue }
        guard obj.mission == .guard_ || obj.mission == .stop else { continue }
        guard obj.aiTacticalRole == .none else { continue }
        guard obj.speed > hitTarget.speed else { continue }  // Must be faster
        attackers.append(obj)
        if attackers.count >= 2 { break }
    }

    guard !attackers.isEmpty else { return }

    // Send attackers to engage
    for attacker in attackers {
        attacker.attackTarget = hitTarget.id
        attacker.mission = .attack
        attacker.movePath = []
        attacker.aiTacticalRole = .hitAndRun
        attacker.aiHitAndRunTick = world.tickCount
    }

    houseState.aiLastHitAndRunTick = world.tickCount
}

// MARK: - 3. Flanking Attacks

/// Modify attack wave to split into main + flank groups.
/// Called from tickAIAttackWaves when launching a wave with 6+ units.
func applyFlankingTactics(units: [GameObject], target: GameObject,
                          house: House, houseState: HouseState, world: GameWorld) {
    guard isTacticEnabled(.flanking) else {
        // No flanking — send all units directly
        for unit in units {
            unit.attackTarget = target.id
            unit.mission = .attack
            unit.movePath = []
            let offsetX = rndDouble(-36...36)
            let offsetY = rndDouble(-36...36)
            unit.moveTargetX = target.worldX + offsetX
            unit.moveTargetY = target.worldY + offsetY
        }
        return
    }

    guard units.count >= 6 else {
        // Not enough units for flanking — send all directly
        for unit in units {
            unit.attackTarget = target.id
            unit.mission = .attack
            unit.movePath = []
            let offsetX = rndDouble(-36...36)
            let offsetY = rndDouble(-36...36)
            unit.moveTargetX = target.worldX + offsetX
            unit.moveTargetY = target.worldY + offsetY
        }
        return
    }

    // Split: 70% main, 30% flank
    let flankCount = max(2, units.count * 3 / 10)
    let mainUnits = Array(units.dropLast(flankCount))
    let flankUnits = Array(units.suffix(flankCount))

    // Calculate flank position
    guard let aiBase = findHouseBase(house: house, world: world) else { return }
    let vecX = target.worldX - aiBase.x
    let vecY = target.worldY - aiBase.y
    let vecLen = max(1.0, sqrt(vecX * vecX + vecY * vecY))

    // Perpendicular vector (rotated 90 degrees)
    let perpX = -vecY / vecLen
    let perpY = vecX / vecLen

    // Flank waypoint: target + perpendicular * 8 cells (192 pixels)
    // Randomly pick left or right flank
    let flankSide = rndBool() ? 1.0 : -1.0
    let flankWaypointX = max(72, min(64 * 24 - 72, target.worldX + perpX * 192.0 * flankSide))
    let flankWaypointY = max(72, min(64 * 24 - 72, target.worldY + perpY * 192.0 * flankSide))

    // Main group attacks directly
    for unit in mainUnits {
        unit.attackTarget = target.id
        unit.mission = .attack
        unit.movePath = []
        let offsetX = rndDouble(-36...36)
        let offsetY = rndDouble(-36...36)
        unit.moveTargetX = target.worldX + offsetX
        unit.moveTargetY = target.worldY + offsetY
    }

    // Flank group moves to flank waypoint first, then attacks after 30 tick delay
    for unit in flankUnits {
        unit.moveTargetX = flankWaypointX + rndDouble(-24...24)
        unit.moveTargetY = flankWaypointY + rndDouble(-24...24)
        unit.mission = .move
        unit.movePath = []
        unit.aiTacticalRole = .flank
    }

    // Store flank state for delayed engagement
    houseState.aiFlankDelayTick = world.tickCount + 30
    houseState.aiFlankUnitIds = flankUnits.map { $0.id }
    houseState.aiFlankTargetX = target.worldX
    houseState.aiFlankTargetY = target.worldY
    houseState.aiFlankAttackTargetId = target.id
}

/// PURE (B3-P4): true once the 30-tick flank delay has elapsed and a flank group
/// is pending. No RNG, no mutation.
func decideFlankFollowUp(houseState: HouseState, world: GameWorld) -> Bool {
    guard let delayTick = houseState.aiFlankDelayTick else { return false }
    return world.tickCount >= delayTick
}

/// EFFECTFUL (B3-P4): send the pending flank group to attack (±36px target
/// jitter RNG per unit), then clear the flank state.
func applyFlankFollowUp(house: House, houseState: HouseState, world: GameWorld) {
    // Time to engage — send flank group to attack
    for unitId in houseState.aiFlankUnitIds {
        guard let unit = world.findObject(id: unitId),
              unit.strength > 0,
              unit.house == house else { continue }

        if let targetId = houseState.aiFlankAttackTargetId,
           let target = world.findObject(id: targetId),
           target.strength > 0 {
            unit.attackTarget = target.id
            unit.mission = .attack
            unit.movePath = []
            unit.moveTargetX = target.worldX + rndDouble(-36...36)
            unit.moveTargetY = target.worldY + rndDouble(-36...36)
        } else if let tx = houseState.aiFlankTargetX, let ty = houseState.aiFlankTargetY {
            // Original target dead — attack-move to its position
            unit.moveTargetX = tx
            unit.moveTargetY = ty
            unit.mission = .move
            unit.movePath = []
        }
        unit.aiTacticalRole = .none
    }

    // Clear flank state
    houseState.aiFlankDelayTick = nil
    houseState.aiFlankUnitIds = []
    houseState.aiFlankTargetX = nil
    houseState.aiFlankTargetY = nil
    houseState.aiFlankAttackTargetId = nil
}

// MARK: - 4. Harvester Harassment

/// What harassment wants to do this tick (pure decision; see decideHarass).
enum HarassAction {
    case none
    case tickExisting(GameObject)                              // active harasser: run its behavior
    case scan(harasser: GameObject?, target: GameObject?)      // no active harasser: clear id, maybe dispatch
}

/// PURE (B3-P4): decide harassment. No RNG, no mutation. Called every 90 ticks
/// but only dispatches every 1800 ticks (2 minutes). When no harasser is active,
/// returns the (target, harasser) selection for apply to act on; the active path
/// early-returns so selection and the existing-harasser tick never interleave.
func decideHarass(house: House, houseState: HouseState, world: GameWorld) -> HarassAction {
    let ticksSinceLast = world.tickCount - houseState.aiLastHarassTick
    guard ticksSinceLast >= 1800 else { return .none }

    // Check if current harasser is still active
    if let harassId = houseState.aiHarassUnitId,
       let harasser = world.findObject(id: harassId),
       harasser.strength > 0 && harasser.aiTacticalRole == .harasser {
        return .tickExisting(harasser)
    }

    // Find a player harvester that is far from player buildings (>8 cells)
    var bestHarv: GameObject? = nil
    var bestIsolation = 0.0

    for obj in world.objects {
        guard obj.strength > 0 else { continue }
        guard obj.house != house && obj.house != .neutral else { continue }
        guard obj.isHarvester else { continue }

        // Measure distance to nearest player building
        var nearestBuildingDist = Double.infinity
        for bld in world.objects {
            guard bld.kind == .structure && bld.house == obj.house && bld.strength > 0 else { continue }
            let dx = bld.worldX - obj.worldX
            let dy = bld.worldY - obj.worldY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < nearestBuildingDist { nearestBuildingDist = dist }
        }

        // Must be >8 cells (192 pixels) from nearest building
        if nearestBuildingDist > 192.0 && nearestBuildingDist > bestIsolation {
            bestHarv = obj
            bestIsolation = nearestBuildingDist
        }
    }

    // Find a fast idle unit to send
    var bestUnit: GameObject? = nil
    var bestSpeed: Double = 0

    for obj in world.objects {
        guard obj.house == house && obj.strength > 0 else { continue }
        guard obj.kind == .unit && obj.isArmed else { continue }
        let upper = obj.typeName.uppercased()
        guard hitAndRunTypes.contains(upper) else { continue }
        guard obj.mission == .guard_ || obj.mission == .stop else { continue }
        guard obj.aiTacticalRole == .none else { continue }
        if obj.speed > bestSpeed {
            bestSpeed = obj.speed
            bestUnit = obj
        }
    }

    return .scan(harasser: bestUnit, target: bestHarv)
}

/// EFFECTFUL (B3-P4): execute the harass action. RNG appears only in the
/// existing-harasser retreat path (via retreatToBase); dispatch itself is
/// RNG-free.
func applyHarass(_ action: HarassAction, houseState: HouseState, world: GameWorld) {
    switch action {
    case .none:
        return
    case .tickExisting(let harasser):
        // Check if player sent defenders — retreat if combat units within 6 cells
        tickHarasserBehavior(harasser: harasser, houseState: houseState, world: world)
    case .scan(let harasser, let target):
        houseState.aiHarassUnitId = nil
        guard let targetHarv = target, let harasserUnit = harasser else { return }

        // Send to attack the harvester
        harasserUnit.attackTarget = targetHarv.id
        harasserUnit.mission = .attack
        harasserUnit.movePath = []
        harasserUnit.aiTacticalRole = .harasser
        houseState.aiHarassUnitId = harasserUnit.id
        houseState.aiLastHarassTick = world.tickCount
    }
}

/// Check if harasser should retreat due to approaching defenders.
private func tickHarasserBehavior(harasser: GameObject, houseState: HouseState, world: GameWorld) {
    // Check for enemy combat units approaching within 6 cells (144 pixels)
    var defenderCount = 0
    for obj in world.objects {
        guard obj.strength > 0 else { continue }
        guard isEnemy(harasser, obj) else { continue }
        guard obj.kind == .unit || obj.kind == .infantry else { continue }
        guard obj.isArmed else { continue }
        guard obj.typeName.uppercased() != "HARV" else { continue }

        let dx = obj.worldX - harasser.worldX
        let dy = obj.worldY - harasser.worldY
        let dist = sqrt(dx * dx + dy * dy)
        if dist <= 144.0 {
            defenderCount += 1
        }
    }

    // Retreat if 2+ defenders closing in, or health below 40%
    if defenderCount >= 2 || harasser.healthFraction < 0.4 {
        retreatToBase(unit: harasser, house: harasser.house, world: world)
        harasser.aiTacticalRole = .none
        harasser.aiHitAndRunTick = nil
        houseState.aiHarassUnitId = nil
    }

    // Release if harasser went idle (target destroyed)
    if harasser.mission == .guard_ || harasser.mission == .stop {
        harasser.aiTacticalRole = .none
        houseState.aiHarassUnitId = nil
    }
}

// MARK: - Helpers

/// Order a unit to retreat to its nearest friendly building.
private func retreatToBase(unit: GameObject, house: House, world: GameWorld) {
    var bestDist = Double.infinity
    var bestX = unit.worldX
    var bestY = unit.worldY

    for bld in world.objects {
        guard bld.kind == .structure && bld.house == house && bld.strength > 0 else { continue }
        let dx = bld.worldX - unit.worldX
        let dy = bld.worldY - unit.worldY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < bestDist {
            bestDist = dist
            bestX = bld.worldX
            bestY = bld.worldY
        }
    }

    unit.attackTarget = nil
    unit.moveTargetX = bestX + rndDouble(-24...24)
    unit.moveTargetY = bestY + rndDouble(-24...24)
    unit.mission = .move
    unit.movePath = []
}
