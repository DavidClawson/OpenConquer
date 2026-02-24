import Foundation

// MARK: - Mission State Machine Implementations
// Ported from Vanilla Conquer foot.cpp, unit.cpp, infantry.cpp, building.cpp

// MARK: - Guard Area (Patrol with Return-to-Base)

/// Guard area: patrol around initial position, return if strayed too far
func tickGuardArea(_ obj: GameObject) {
    guard let world = session.world else { return }

    // Save home position on first tick of this mission
    if obj.missionStatus == 0 {
        obj.missionStatus = 1
        obj.suspendedTarget = obj.cell  // Remember home cell as Int
    }

    // Only process periodically (every ~1 second)
    guard world.tickCount % 15 == 0 else { return }

    let guardHomeCell = obj.suspendedTarget ?? obj.cell
    let homeCellX = guardHomeCell % 64
    let homeCellY = guardHomeCell / 64
    let homeX = Double(homeCellX * 24) + 12.0
    let homeY = Double(homeCellY * 24) + 12.0

    let resolved = resolveWeapon(for: obj)
    let weaponRange = resolved?.range ?? 96.0
    let maxPatrolDist = weaponRange + 256.0  // Weapon range + ~10 cells

    let distFromHome = sqrt(pow(obj.worldX - homeX, 2) + pow(obj.worldY - homeY, 2))

    // If too far from home, return
    if distFromHome > maxPatrolDist {
        obj.moveTargetX = homeX
        obj.moveTargetY = homeY
        obj.movePath = []
        let _ = moveOneStep(obj)
        return
    }

    // When near home, scan for enemies
    if obj.isArmed {
        let scanRange = weaponRange * 1.5
        if let enemy = findNearestEnemy(obj, range: scanRange) {
            obj.attackTarget = enemy.id
            obj.mission = .attack
            // Save guard area mission to return after combat
            obj.suspendedMission = .guardArea
            return
        }
    }

    // If idle near home and no enemies, do random patrol
    if obj.moveTargetX == nil && obj.kind != .structure {
        let patrolRadius = 5  // cells
        let nx = homeCellX + Int.random(in: -patrolRadius...patrolRadius)
        let ny = homeCellY + Int.random(in: -patrolRadius...patrolRadius)
        let clampedX = max(0, min(63, nx))
        let clampedY = max(0, min(63, ny))
        if isCellPassable(cellX: clampedX, cellY: clampedY, speedType: obj.cachedSpeedType) {
            obj.moveTargetX = Double(clampedX * 24) + 12.0
            obj.moveTargetY = Double(clampedY * 24) + 12.0
            obj.movePath = []
        }
    }

    // Keep moving if we have a target
    if obj.moveTargetX != nil {
        let _ = moveOneStep(obj)
    }
}

// MARK: - Hunt (Aggressive Search & Attack)

/// Hunt: actively seek and destroy enemies across the map
func tickHunt(_ obj: GameObject) {
    // Armed units: scan for enemies in full weapon range
    if obj.isArmed {
        tickGuardScan(obj)
    }

    // If we got a target from guard scan, we're now in attack mode
    if obj.mission == .attack { return }

    // If no target acquired, seek enemies across entire map
    if obj.attackTarget == nil && obj.moveTargetX == nil {
        if let enemy = findNearestEnemy(obj, range: 64.0 * 24.0) {
            obj.attackTarget = enemy.id
            obj.mission = .attack
            return
        }
    }

    // If we have a move target (heading toward enemy base), keep moving
    if obj.moveTargetX != nil {
        let _ = moveOneStep(obj)
    }
}

// MARK: - Retreat (Flee to Safety)

/// Retreat: flee to nearest friendly building
func tickRetreat(_ obj: GameObject) {
    guard let world = session.world else { return }

    // If we have a move target, keep moving
    if obj.moveTargetX != nil {
        let arrived = !moveOneStep(obj)
        if arrived {
            // Arrived at retreat destination — switch to guard
            obj.mission = .guard_
            obj.fear = 0
            obj.isProne = false
        }
        return
    }

    // Find nearest friendly building to flee toward
    var bestDist = Double.infinity
    var bestX = obj.worldX
    var bestY = obj.worldY

    for other in world.objects {
        if other.kind != .structure { continue }
        if other.house != obj.house { continue }
        if other.strength <= 0 { continue }

        let dx = other.worldX - obj.worldX
        let dy = other.worldY - obj.worldY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < bestDist {
            bestDist = dist
            bestX = other.worldX
            bestY = other.worldY
        }
    }

    if bestDist < Double.infinity {
        obj.moveTargetX = bestX
        obj.moveTargetY = bestY
        obj.movePath = []
    } else {
        // No friendly buildings — just run away from nearest enemy
        if let enemy = findNearestEnemy(obj, range: 64.0 * 24.0) {
            let dx = obj.worldX - enemy.worldX
            let dy = obj.worldY - enemy.worldY
            let dist = max(1.0, sqrt(dx * dx + dy * dy))
            obj.moveTargetX = max(12, min(64 * 24 - 12, obj.worldX + dx / dist * 120))
            obj.moveTargetY = max(12, min(64 * 24 - 12, obj.worldY + dy / dist * 120))
            obj.movePath = []
        } else {
            obj.mission = .guard_
        }
    }
}

// MARK: - Return (Return to friendly building)

/// Return: navigate to nearest friendly building for docking/repair
func tickReturn(_ obj: GameObject) {
    // If we have a move target, keep moving
    if obj.moveTargetX != nil {
        let arrived = !moveOneStep(obj)
        if arrived {
            // Check if we're a harvester at a refinery
            if obj.typeName.uppercased() == "HARV" {
                obj.mission = .harvest
                obj.missionStatus = 0
            } else {
                // Return to guard
                obj.mission = .guard_
            }
        }
        return
    }

    // Find appropriate building to return to
    let upper = obj.typeName.uppercased()
    if upper == "HARV" {
        // Harvester: find refinery
        if let refinery = findNearestRefinery(obj) {
            obj.moveTargetX = refinery.worldX
            obj.moveTargetY = refinery.worldY
            obj.movePath = findPath(
                fromX: obj.cellX, fromY: obj.cellY,
                toX: refinery.cellX, toY: refinery.cellY,
                ignoring: obj,
                speedType: .harvester
            )
        } else {
            obj.mission = .guard_
        }
    } else {
        // Other units: find nearest friendly building
        obj.mission = .retreat
    }
}

// MARK: - Capture (Engineer enters building)

/// Capture: engineer moves to and captures enemy building
func tickCapture(_ obj: GameObject) {
    guard session.world != nil else { return }

    // Only infantry can capture
    guard obj.kind == .infantry else {
        obj.mission = .guard_
        return
    }

    // Check if we have an attack target (the building to capture)
    guard let targetId = obj.attackTarget,
          let target = findObjectById(targetId),
          target.strength > 0,
          target.kind == .structure else {
        // No valid target — go back to guard
        obj.attackTarget = nil
        obj.mission = .guard_
        return
    }

    let dx = target.worldX - obj.worldX
    let dy = target.worldY - obj.worldY
    let dist = sqrt(dx * dx + dy * dy)

    // Face the target
    if dist > 0.5 {
        obj.facing = directionToFacing(dx: dx, dy: dy)
    }

    // Check if adjacent to building (within ~36px, roughly 1.5 cells)
    if dist < 36.0 {
        // Check if this infantry type can capture
        let upper = obj.typeName.uppercased()
        if let it = InfantryType.from(iniName: upper), let data = infantryTypeDataTable[it] {
            if data.canCapture {
                // Capture the building: change ownership
                target.house = obj.house

                // Recalculate power for both houses
                recalculateAllHousePower()

                // Remove the engineer (consumed)
                obj.strength = 0

                print("Capture: \(obj.house.rawValue) captured \(target.typeName)")
                return
            }
        }

        // Not an engineer — can't capture, go to guard
        obj.mission = .guard_
        obj.attackTarget = nil
    } else {
        // Move toward the building
        obj.moveTargetX = target.worldX
        obj.moveTargetY = target.worldY
        if obj.movePath.isEmpty {
            obj.movePath = findPath(
                fromX: obj.cellX, fromY: obj.cellY,
                toX: target.cellX, toY: target.cellY,
                ignoring: obj,
                speedType: .foot
            )
        }
        let _ = moveOneStep(obj)
    }
}

// MARK: - Unload (Transport disembark / MCV deploy)

/// Unload: MCV deploys into construction yard, APC disembarks passengers
func tickUnload(_ obj: GameObject) {
    let upper = obj.typeName.uppercased()

    if upper == "MCV" {
        tickMCVDeploy(obj)
    } else if upper == "APC" {
        tickAPCUnload(obj)
    } else {
        obj.mission = .guard_
    }
}

/// MCV deployment: transform into a Construction Yard
func tickMCVDeploy(_ obj: GameObject) {
    guard let world = session.world else { return }

    // Check if the 3x3 area is clear for the construction yard
    let centerCellX = obj.cellX
    let centerCellY = obj.cellY
    let factSize = buildingSize("FACT")  // Construction yard size

    // Check if area is clear
    let startX = centerCellX - factSize.w / 2
    let startY = centerCellY - factSize.h / 2
    var canDeploy = true

    for dy in 0..<factSize.h {
        for dx in 0..<factSize.w {
            let cx = startX + dx
            let cy = startY + dy
            if cx < 0 || cx >= 64 || cy < 0 || cy >= 64 {
                canDeploy = false
                break
            }
            let cell = cy * 64 + cx
            if !staticPassability[cell] && cell != obj.cell {
                canDeploy = false
                break
            }
        }
        if !canDeploy { break }
    }

    if canDeploy {
        // Deploy: remove MCV, create Construction Yard
        let cell = startY * 64 + startX
        let pos = cellToPixel(cell)
        let cx = Double(pos.px) + Double(factSize.w * 24) / 2.0
        let cy = Double(pos.py) + Double(factSize.h * 24) / 2.0

        let building = GameObject(
            id: world.allocateId(),
            typeName: "FACT",
            house: obj.house,
            kind: .structure,
            worldX: cx, worldY: cy,
            facing: 0,
            strength: resolveStrength(typeName: "FACT", kind: .structure, scenarioStrength: 256),
            mission: .guard_,
            speed: 0.0
        )
        world.addObject(building)

        // Mark footprint as impassable
        for dy in 0..<factSize.h {
            for dx in 0..<factSize.w {
                let c = (startY + dy) * 64 + (startX + dx)
                staticPassability[c] = false
            }
        }

        // Remove MCV
        obj.strength = 0

        // Recalculate power
        recalculateAllHousePower()

        print("MCV deployed into Construction Yard at (\(startX), \(startY))")
    } else {
        // Can't deploy here — go back to guard
        obj.mission = .guard_
    }
}

/// APC unloading: eject passengers (stub — transport system not yet implemented)
func tickAPCUnload(_ obj: GameObject) {
    // For now, just switch to guard since we don't have cargo system yet
    obj.mission = .guard_
}

// MARK: - Building Repair

/// Repair a building: spend credits to restore HP over time
func tickBuildingRepair(_ obj: GameObject) {
    guard obj.kind == .structure else {
        obj.mission = .guard_
        return
    }

    // Only repair if building is damaged
    guard obj.strength < obj.maxStrength else {
        obj.isRepairing = false
        obj.mission = .guard_
        return
    }

    // Only process every 4 ticks
    guard let world = session.world else { return }
    guard world.tickCount % 4 == 0 else { return }

    // Cost per repair step: proportional to building cost
    let repairStep = max(1, obj.maxStrength / 50)  // ~50 repair ticks to full
    let repairCost = max(1, obj.cost / 50)

    // Check if house can afford repair
    let houseState = getHouseState(obj.house)

    // Low power slows repair (VC behavior)
    let powerMultiplier = houseState.hasPower ? 1 : 2
    if world.tickCount % (4 * powerMultiplier) != 0 { return }

    if houseState.spendCredits(repairCost) {
        obj.strength = min(obj.maxStrength, obj.strength + repairStep)

        // Deduct from sidebar credits if player building
        if obj.house == session.world?.playerHouse {
            session.sidebarCredits = houseState.credits
        }
    } else {
        // Can't afford — stop repairing
        obj.isRepairing = false
        obj.mission = .guard_
    }
}

// MARK: - Building Sell

/// Sell a building: deconstruct and refund partial cost
func tickBuildingSell(_ obj: GameObject) {
    guard obj.kind == .structure else {
        obj.mission = .guard_
        return
    }

    // Sell sequence: refund credits, spawn crew, destroy building
    let refundAmount = obj.cost / 2  // 50% refund

    let houseState = getHouseState(obj.house)
    houseState.addCredits(refundAmount)

    // Update sidebar credits if player
    if obj.house == session.world?.playerHouse {
        session.sidebarCredits += refundAmount
    }

    // Spawn crew (1-5 minigunners based on building cost)
    if let world = session.world {
        let crewCount = min(5, max(1, obj.cost / 400))
        for i in 0..<crewCount {
            let offset = Double(i) * 12.0 - Double(crewCount - 1) * 6.0
            let crewType = obj.house == .goodGuy ? "E1" : "E1"  // Both sides get minigunners
            let crew = GameObject(
                id: world.allocateId(),
                typeName: crewType,
                house: obj.house,
                kind: .infantry,
                worldX: obj.worldX + offset, worldY: obj.worldY + 24.0,
                facing: 128,
                strength: resolveStrength(typeName: crewType, kind: .infantry, scenarioStrength: 256),
                mission: .guardArea,
                speed: resolveSpeed(typeName: crewType, kind: .infantry)
            )
            world.addObject(crew)
        }
    }

    // Clear building footprint from passability
    let size = buildingSize(obj.typeName)
    let topLeftX = Int(obj.worldX - Double(size.w * 24) / 2.0) / 24
    let topLeftY = Int(obj.worldY - Double(size.h * 24) / 2.0) / 24
    for dy in 0..<size.h {
        for dx in 0..<size.w {
            let c = (topLeftY + dy) * 64 + (topLeftX + dx)
            if c >= 0 && c < 4096 {
                staticPassability[c] = true
            }
        }
    }

    // Spawn destruction effects
    spawnDeathEffects(obj)

    // Destroy the building
    obj.strength = 0

    // Recalculate power
    recalculateAllHousePower()

    print("Building sold: \(obj.typeName) for $\(refundAmount)")
}
