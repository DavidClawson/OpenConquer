import Foundation

// MARK: - Mission State Machine Implementations
// Ported from Vanilla Conquer foot.cpp, unit.cpp, infantry.cpp, building.cpp

extension GameObject {

    // MARK: - Guard Area (Patrol with Return-to-Base)

    /// Guard area: patrol around initial position, return if strayed too far
    func tickGuardArea() {
        guard let world = session.world else { return }

        // Save home position on first tick of this mission
        if missionStatus == 0 {
            missionStatus = 1
            suspendedTarget = cell  // Remember home cell as Int
        }

        // Only process periodically (every ~1 second)
        guard world.tickCount % 15 == 0 else { return }

        let guardHomeCell = suspendedTarget ?? cell
        let homeCellX = guardHomeCell % 64
        let homeCellY = guardHomeCell / 64
        let homeX = Double(homeCellX * 24) + 12.0
        let homeY = Double(homeCellY * 24) + 12.0

        let resolved = resolveWeapon()
        let weaponRange = resolved?.range ?? 96.0
        let maxPatrolDist = weaponRange + 256.0  // Weapon range + ~10 cells

        let distFromHome = sqrt(pow(worldX - homeX, 2) + pow(worldY - homeY, 2))

        // If too far from home, return
        if distFromHome > maxPatrolDist {
            moveTargetX = homeX
            moveTargetY = homeY
            movePath = []
            moveOneStep()
            return
        }

        // When near home, scan for enemies
        if isArmed {
            let scanRange = weaponRange * 1.5
            if let enemy = findNearestEnemy(self, range: scanRange) {
                attackTarget = enemy.id
                mission = .attack
                // Save guard area mission to return after combat
                suspendedMission = .guardArea
                return
            }
        }

        // If idle near home and no enemies, do random patrol
        if moveTargetX == nil && kind != .structure {
            let patrolRadius = 5  // cells
            let nx = homeCellX + Int.random(in: -patrolRadius...patrolRadius)
            let ny = homeCellY + Int.random(in: -patrolRadius...patrolRadius)
            let clampedX = max(0, min(63, nx))
            let clampedY = max(0, min(63, ny))
            if isCellPassable(cellX: clampedX, cellY: clampedY, speedType: cachedSpeedType) {
                moveTargetX = Double(clampedX * 24) + 12.0
                moveTargetY = Double(clampedY * 24) + 12.0
                movePath = []
            }
        }

        // Keep moving if we have a target
        if moveTargetX != nil {
            moveOneStep()
        }
    }

    // MARK: - Hunt (Aggressive Search & Attack)

    /// Hunt: actively seek and destroy enemies across the map
    func tickHunt() {
        // Armed units: scan for enemies in full weapon range
        if isArmed {
            tickGuardScan()
        }

        // If we got a target from guard scan, we're now in attack mode
        if mission == .attack { return }

        // If no target acquired, seek enemies across entire map
        if attackTarget == nil && moveTargetX == nil {
            if let enemy = findNearestEnemy(self, range: 64.0 * 24.0) {
                attackTarget = enemy.id
                mission = .attack
                return
            }
        }

        // If we have a move target (heading toward enemy base), keep moving
        if moveTargetX != nil {
            moveOneStep()
        }
    }

    // MARK: - Retreat (Flee to Safety)

    /// Retreat: flee to nearest friendly building
    func tickRetreat() {
        guard let world = session.world else { return }

        // If we have a move target, keep moving
        if moveTargetX != nil {
            let arrived = !moveOneStep()
            if arrived {
                // Arrived at retreat destination — switch to guard
                mission = .guard_
                fear = 0
                isProne = false
            }
            return
        }

        // Find nearest friendly building to flee toward
        var bestDist = Double.infinity
        var bestX = worldX
        var bestY = worldY

        for other in world.objects {
            if other.kind != .structure { continue }
            if other.house != house { continue }
            if other.strength <= 0 { continue }

            let dx = other.worldX - worldX
            let dy = other.worldY - worldY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                bestX = other.worldX
                bestY = other.worldY
            }
        }

        if bestDist < Double.infinity {
            moveTargetX = bestX
            moveTargetY = bestY
            movePath = []
        } else {
            // No friendly buildings — just run away from nearest enemy
            if let enemy = findNearestEnemy(self, range: 64.0 * 24.0) {
                let dx = worldX - enemy.worldX
                let dy = worldY - enemy.worldY
                let dist = max(1.0, sqrt(dx * dx + dy * dy))
                moveTargetX = max(12, min(64 * 24 - 12, worldX + dx / dist * 120))
                moveTargetY = max(12, min(64 * 24 - 12, worldY + dy / dist * 120))
                movePath = []
            } else {
                mission = .guard_
            }
        }
    }

    // MARK: - Return (Return to friendly building)

    /// Return: navigate to nearest friendly building for docking/repair
    func tickReturn() {
        // If we have a move target, keep moving
        if moveTargetX != nil {
            let arrived = !moveOneStep()
            if arrived {
                // Check if we're a harvester at a refinery
                if typeName.uppercased() == "HARV" {
                    mission = .harvest
                    missionStatus = 0
                } else {
                    // Return to guard
                    mission = .guard_
                }
            }
            return
        }

        // Find appropriate building to return to
        let upper = typeName.uppercased()
        if upper == "HARV" {
            // Harvester: find refinery
            if let refinery = findNearestRefinery() {
                moveTargetX = refinery.worldX
                moveTargetY = refinery.worldY
                movePath = findPath(
                    fromX: cellX, fromY: cellY,
                    toX: refinery.cellX, toY: refinery.cellY,
                    ignoring: self,
                    speedType: .harvester
                )
            } else {
                mission = .guard_
            }
        } else {
            // Other units: find nearest friendly building
            mission = .retreat
        }
    }

    // MARK: - Capture (Engineer enters building)

    /// Capture: engineer moves to and captures enemy building
    func tickCapture() {
        guard session.world != nil else { return }

        // Only infantry can capture
        guard kind == .infantry else {
            mission = .guard_
            return
        }

        // Check if we have an attack target (the building to capture)
        guard let targetId = attackTarget,
              let target = findObjectById(targetId),
              target.strength > 0,
              target.kind == .structure else {
            // No valid target — go back to guard
            attackTarget = nil
            mission = .guard_
            return
        }

        let dx = target.worldX - worldX
        let dy = target.worldY - worldY
        let dist = sqrt(dx * dx + dy * dy)

        // Face the target
        if dist > 0.5 {
            facing = directionToFacing(dx: dx, dy: dy)
        }

        // Check if adjacent to building (within ~36px, roughly 1.5 cells)
        if dist < 36.0 {
            // Check if this infantry type can capture
            let upper = typeName.uppercased()
            if let it = InfantryType.from(iniName: upper), let data = infantryTypeDataTable[it] {
                if data.canCapture {
                    // Capture the building: change ownership
                    target.house = house

                    // Recalculate power for both houses
                    recalculateAllHousePower()

                    // Remove the engineer (consumed)
                    strength = 0

                    print("Capture: \(house.rawValue) captured \(target.typeName)")
                    return
                }
            }

            // Not an engineer — can't capture, go to guard
            mission = .guard_
            attackTarget = nil
        } else {
            // Move toward the building
            moveTargetX = target.worldX
            moveTargetY = target.worldY
            if movePath.isEmpty {
                movePath = findPath(
                    fromX: cellX, fromY: cellY,
                    toX: target.cellX, toY: target.cellY,
                    ignoring: self,
                    speedType: .foot
                )
            }
            moveOneStep()
        }
    }

    // MARK: - Unload (Transport disembark / MCV deploy)

    /// Unload: MCV deploys into construction yard, transports disembark passengers
    func tickUnload() {
        let upper = typeName.uppercased()

        if upper == "MCV" {
            tickMCVDeploy()
        } else if isTransporter {
            tickAPCUnload()
        } else {
            mission = .guard_
        }
    }

    /// MCV deployment: transform into a Construction Yard
    func tickMCVDeploy() {
        guard let world = session.world else { return }

        // Check if the 3x3 area is clear for the construction yard
        let centerCellX = cellX
        let centerCellY = cellY
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
                let cellIdx = cy * 64 + cx
                if !staticPassability[cellIdx] && cellIdx != cell {
                    canDeploy = false
                    break
                }
            }
            if !canDeploy { break }
        }

        if canDeploy {
            // Deploy: remove MCV, create Construction Yard
            let deployCell = startY * 64 + startX
            let pos = cellToPixel(deployCell)
            let cx = Double(pos.px) + Double(factSize.w * 24) / 2.0
            let cy = Double(pos.py) + Double(factSize.h * 24) / 2.0

            let building = GameObject(
                id: world.allocateId(),
                typeName: "FACT",
                house: house,
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
            strength = 0

            // Recalculate power
            recalculateAllHousePower()

            print("MCV deployed into Construction Yard at (\(startX), \(startY))")
        } else {
            // Can't deploy here — go back to guard
            mission = .guard_
        }
    }

    // tickAPCUnload is defined in GameReinforcements.swift with full cargo support

    // MARK: - Building Repair

    /// Repair a building: spend credits to restore HP over time
    func tickBuildingRepair() {
        guard kind == .structure else {
            mission = .guard_
            return
        }

        // Only repair if building is damaged
        guard strength < maxStrength else {
            isRepairing = false
            mission = .guard_
            return
        }

        // Only process every 4 ticks
        guard let world = session.world else { return }
        guard world.tickCount % 4 == 0 else { return }

        // Cost per repair step: proportional to building cost
        let repairStep = max(1, maxStrength / 50)  // ~50 repair ticks to full
        let repairCost = max(1, cost / 50)

        // Check if house can afford repair
        let houseState = getHouseState(house)

        // Low power slows repair (VC behavior)
        let powerMultiplier = houseState.hasPower ? 1 : 2
        if world.tickCount % (4 * powerMultiplier) != 0 { return }

        if houseState.spendCredits(repairCost) {
            strength = min(maxStrength, strength + repairStep)

            // Deduct from sidebar credits if player building
            if house == session.world?.playerHouse {
                session.sidebarCredits = houseState.credits
            }
        } else {
            // Can't afford — stop repairing
            isRepairing = false
            mission = .guard_
        }
    }

    // MARK: - Building Sell

    /// Sell a building: deconstruct and refund partial cost
    func tickBuildingSell() {
        guard kind == .structure else {
            mission = .guard_
            return
        }

        // Sell sequence: refund credits, spawn crew, destroy building
        let refundAmount = cost / 2  // 50% refund

        let houseState = getHouseState(house)
        houseState.addCredits(refundAmount)

        // Update sidebar credits if player
        if house == session.world?.playerHouse {
            session.sidebarCredits += refundAmount
        }

        // Spawn crew (1-5 minigunners based on building cost)
        if let world = session.world {
            let crewCount = min(5, max(1, cost / 400))
            for i in 0..<crewCount {
                let offset = Double(i) * 12.0 - Double(crewCount - 1) * 6.0
                let crewType = house == .goodGuy ? "E1" : "E1"  // Both sides get minigunners
                let crew = GameObject(
                    id: world.allocateId(),
                    typeName: crewType,
                    house: house,
                    kind: .infantry,
                    worldX: worldX + offset, worldY: worldY + 24.0,
                    facing: 128,
                    strength: resolveStrength(typeName: crewType, kind: .infantry, scenarioStrength: 256),
                    mission: .guardArea,
                    speed: resolveSpeed(typeName: crewType, kind: .infantry)
                )
                world.addObject(crew)
            }
        }

        // Clear building footprint from passability
        let size = buildingSize(typeName)
        let topLeftX = Int(worldX - Double(size.w * 24) / 2.0) / 24
        let topLeftY = Int(worldY - Double(size.h * 24) / 2.0) / 24
        for dy in 0..<size.h {
            for dx in 0..<size.w {
                let c = (topLeftY + dy) * 64 + (topLeftX + dx)
                if c >= 0 && c < 4096 {
                    staticPassability[c] = true
                }
            }
        }

        // Spawn destruction effects
        spawnDeathEffects()

        // Destroy the building
        strength = 0

        // Recalculate power
        recalculateAllHousePower()

        print("Building sold: \(typeName) for $\(refundAmount)")
    }
}
