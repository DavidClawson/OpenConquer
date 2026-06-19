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

        // When near home, scan for enemies (use sight range for wider detection)
        if isArmed {
            let sightPixels = Double(sightRange) * 24.0
            let scanRange = max(sightPixels, weaponRange * 1.5)
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
            if cachedSpeedType == .float_ {
                // Boats: patrol left/right along initial row (matching VC gunboat behavior)
                let patrolDist = 10  // cells left/right
                let targetCellX: Int
                // Alternate direction: go left if we're right of home, go right if left
                if cellX >= homeCellX {
                    targetCellX = max(0, homeCellX - patrolDist)
                } else {
                    targetCellX = min(63, homeCellX + patrolDist)
                }
                let targetCellY = homeCellY
                if isCellPassable(cellX: targetCellX, cellY: targetCellY, speedType: .float_) {
                    moveTargetX = Double(targetCellX * 24) + 12.0
                    moveTargetY = Double(targetCellY * 24) + 12.0
                    movePath = []
                } else {
                    // Find nearest water cell along the row
                    for offset in 1...patrolDist {
                        let leftX = max(0, homeCellX - offset)
                        let rightX = min(63, homeCellX + offset)
                        let tryX = (cellX >= homeCellX) ? leftX : rightX
                        if isCellPassable(cellX: tryX, cellY: targetCellY, speedType: .float_) {
                            moveTargetX = Double(tryX * 24) + 12.0
                            moveTargetY = Double(targetCellY * 24) + 12.0
                            movePath = []
                            break
                        }
                    }
                }
            } else {
                let patrolRadius = 5  // cells
                let nx = homeCellX + rndInt(-patrolRadius...patrolRadius)
                let ny = homeCellY + rndInt(-patrolRadius...patrolRadius)
                let clampedX = max(0, min(63, nx))
                let clampedY = max(0, min(63, ny))
                if isCellPassable(cellX: clampedX, cellY: clampedY, speedType: cachedSpeedType) {
                    moveTargetX = Double(clampedX * 24) + 12.0
                    moveTargetY = Double(clampedY * 24) + 12.0
                    movePath = []
                }
            }
        }

        // Keep moving if we have a target
        if moveTargetX != nil {
            moveOneStep()
        }
    }

    // MARK: - Gunboat Hunt (VC-authentic edge-bounce patrol)

    /// Gunboat hunt: sail back and forth across the map, shooting at enemies in range.
    /// Ported from VC unit.cpp — gunboat always hunts, bounces at map edges,
    /// fires at enemies in range while moving, and cannot be player-controlled.
    func tickGunboatHunt() {
        guard let world = session.world else { return }

        // Ensure gunboat is always a loaner and at full speed
        isALoaner = true

        // If no destination, assign one based on current facing
        if moveTargetX == nil {
            let boatRow = cellY
            if let bounds = world.mapBounds {
                if facing >= 128 {
                    // Facing west — go to west edge (stay within bounds)
                    let westCellX = bounds.x
                    moveTargetX = Double(westCellX * 24) + 12.0
                } else {
                    // Facing east — go to east edge (stay within bounds)
                    let eastCellX = bounds.x + bounds.width - 1
                    moveTargetX = Double(eastCellX * 24) + 12.0
                }
                moveTargetY = Double(boatRow * 24) + 12.0
            }
            movePath = []
        }

        // Edge-bounce: when reaching a map edge, reverse direction
        if let bounds = world.mapBounds {
            let boatRow = cellY
            if cellX <= bounds.x + 1 {
                // At west edge — reverse to east
                facing = 64  // DIR_E
                turretFacing = 64
                let eastCellX = bounds.x + bounds.width - 1
                moveTargetX = Double(eastCellX * 24) + 12.0
                moveTargetY = Double(boatRow * 24) + 12.0
                movePath = []
            } else if cellX >= bounds.x + bounds.width - 2 {
                // At east edge — reverse to west
                facing = 192  // DIR_W
                turretFacing = 192
                let westCellX = bounds.x
                moveTargetX = Double(westCellX * 24) + 12.0
                moveTargetY = Double(boatRow * 24) + 12.0
                movePath = []
            }
        }

        // Scan for enemies in weapon range and fire while moving
        if isArmed {
            let resolved = resolveWeapon()
            let range = resolved?.range ?? 96.0

            // Check current attack target
            if let targetId = attackTarget,
               let target = findObjectById(targetId),
               target.strength > 0 {
                let dx = target.worldX - worldX
                let dy = target.worldY - worldY
                let dist = sqrt(dx * dx + dy * dy)

                if dist <= range {
                    // In range — rotate turret and fire without stopping
                    let tgtFacing = directionToFacing(dx: dx, dy: dy)
                    let aligned = rotateTurretToward(targetFacing: tgtFacing)

                    if aligned && reloadTimer <= 0, let resolved = resolved {
                        reloadTimer = resolved.reloadTicks
                        lastFireTick = world.tickCount

                        let fireFacing = hasTurret ? turretFacing : facing
                        let faceRad = Double(fireFacing) / 256.0 * 2.0 * Double.pi
                        let flashDist = 10.0
                        let mfx = worldX + sin(faceRad) * flashDist
                        let mfy = worldY - cos(faceRad) * flashDist
                        spawnAnimation(.muzzleFlash, worldX: mfx, worldY: mfy)

                        if let weapon = cachedPrimaryWeapon {
                            audioManager.play(audioManager.weaponFireSound(weapon), worldX: worldX, worldY: worldY)
                        }

                        let bulletType = weaponTypeData[resolved.weaponType]?.fires ?? .bullet
                        spawnProjectile(bulletType: bulletType, from: self, to: target,
                                       damage: resolved.damage, warhead: resolved.warhead)
                    }
                } else {
                    // Out of range — drop target
                    attackTarget = nil
                }
            } else {
                // No current target — scan for new one
                attackTarget = nil
                if let enemy = findNearestEnemy(self, range: range) {
                    attackTarget = enemy.id
                } else {
                    // No enemy in range — align turret with body direction
                    turretFacing = facing
                }
            }

            if reloadTimer > 0 {
                reloadTimer -= 1
            }
        }

        // Keep moving toward destination — gunboat moves directly, bypassing A* pathfinding
        // Validate that movement stays on water cells
        if let targetX = moveTargetX, let targetY = moveTargetY {
            let dx = targetX - worldX
            let dy = targetY - worldY
            let dist = sqrt(dx * dx + dy * dy)

            if dist > 0.5 {
                facing = directionToFacing(dx: dx, dy: dy)
            }

            if dist <= speed {
                // Validate target cell is water before moving
                let tCellX = Int(targetX) / 24
                let tCellY = Int(targetY) / 24
                if isCellPassable(cellX: tCellX, cellY: tCellY, ignoring: self, speedType: .float_) {
                    worldX = targetX
                    worldY = targetY
                }
                moveTargetX = nil
                moveTargetY = nil
            } else if dist > 0 {
                let newX = worldX + (dx / dist) * speed
                let newY = worldY + (dy / dist) * speed
                // Check next cell is water before moving
                let nextCellX = Int(newX) / 24
                let nextCellY = Int(newY) / 24
                if isCellPassable(cellX: nextCellX, cellY: nextCellY, ignoring: self, speedType: .float_) {
                    worldX = newX
                    worldY = newY
                } else {
                    // Hit non-water cell — reverse direction
                    moveTargetX = nil
                    moveTargetY = nil
                }
            }
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
                if isHarvester {
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
        if isHarvester {
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

        // Compute distance to nearest edge of the building footprint, not its center
        let edgeDist = distanceToBuilding(target)

        // Face the target
        let dx = target.worldX - worldX
        let dy = target.worldY - worldY
        if dx * dx + dy * dy > 0.25 {
            facing = directionToFacing(dx: dx, dy: dy)
        }

        // Check if adjacent to building (within ~1.5 cells of the footprint edge)
        if edgeDist < 20.0 {
            // Check if this infantry type can capture
            let upper = typeName.uppercased()
            if let it = InfantryType.from(iniName: upper), let data = infantryTypeDataTable[it] {
                if data.canCapture {
                    // Capture the building: change ownership
                    let previousOwner = target.house
                    target.house = house

                    // Recalculate power for both houses
                    recalculateAllHousePower()

                    // EVA announcement
                    if let world = session.world {
                        if house == world.playerHouse {
                            // Player captured an enemy building
                            let vox: VoxType = previousOwner == .badGuy ? .nodCaptured : .gdiCaptured
                            session.speakEVA(vox)
                        } else if previousOwner == world.playerHouse {
                            // Enemy captured player's building
                            session.speakEVA(.structureLost, cooldownTicks: 45)
                        }
                    }

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
            // Move toward the nearest edge of the building
            let nearEdge = nearestBuildingEdgePoint(target)
            moveTargetX = nearEdge.x
            moveTargetY = nearEdge.y
            let edgeCellX = Int(nearEdge.x) / 24
            let edgeCellY = Int(nearEdge.y) / 24
            if movePath.isEmpty {
                movePath = findPath(
                    fromX: cellX, fromY: cellY,
                    toX: edgeCellX, toY: edgeCellY,
                    ignoring: self,
                    speedType: .foot
                )
            }
            moveOneStep()
        }
    }

    // MARK: - Sabotage (Commando C4 on buildings)

    /// Sabotage: commando moves to and destroys enemy building with C4
    func tickSabotage() {
        guard let world = session.world else { return }

        // Only infantry (commando) can sabotage
        guard kind == .infantry else {
            mission = .guard_
            return
        }

        // Check if we have an attack target (the building to sabotage)
        guard let targetId = attackTarget,
              let target = findObjectById(targetId),
              target.strength > 0,
              target.kind == .structure else {
            // No valid target — go back to guard
            attackTarget = nil
            mission = .guard_
            return
        }

        // Compute distance to nearest edge of the building footprint
        let edgeDist = distanceToBuilding(target)

        let dx = target.worldX - worldX
        let dy = target.worldY - worldY

        // Face the target
        if dx * dx + dy * dy > 0.25 {
            facing = directionToFacing(dx: dx, dy: dy)
        }

        // Check if adjacent to building (within ~20px of the footprint edge)
        if edgeDist < 20.0 {
            // Plant C4: destroy the building instantly
            target.strength = 0
            target.lastDamagedTick = world.tickCount
            target.lastWhoHurtMe = house

            // Spawn large explosion
            spawnAnimation(.fball1, worldX: target.worldX, worldY: target.worldY)
            spawnAnimation(.fball1, worldX: target.worldX - 12, worldY: target.worldY - 12)
            spawnAnimation(.fball1, worldX: target.worldX + 12, worldY: target.worldY + 12)

            // Clear building footprint from passability
            let size = buildingSize(target.typeName)
            let topLeftX = Int(target.worldX - Double(size.w * 24) / 2.0) / 24
            let topLeftY = Int(target.worldY - Double(size.h * 24) / 2.0) / 24
            for fdy in 0..<size.h {
                for fdx in 0..<size.w {
                    let c = (topLeftY + fdy) * 64 + (topLeftX + fdx)
                    if c >= 0 && c < 4096 {
                        staticPassability[c] = true
                    }
                }
            }

            // Recalculate power
            recalculateAllHousePower()

            // Track kill
            session.campaign.trackKill(victimHouse: target.house, victimKind: target.kind)
            let attackerState = getHouseState(house)
            let victimState = getHouseState(target.house)
            victimState.buildingsLost += 1
            attackerState.buildingsKilled += 1

            // Commando survives — return to guard
            attackTarget = nil
            mission = .guard_
            return
        } else {
            // Move toward the nearest edge of the building
            let nearEdge = nearestBuildingEdgePoint(target)
            moveTargetX = nearEdge.x
            moveTargetY = nearEdge.y
            let edgeCellX = Int(nearEdge.x) / 24
            let edgeCellY = Int(nearEdge.y) / 24
            if movePath.isEmpty {
                movePath = findPath(
                    fromX: cellX, fromY: cellY,
                    toX: edgeCellX, toY: edgeCellY,
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
        if isMCV {
            tickMCVDeploy()
        } else if isTransporter {
            // If transport still has a move target, move there first before unloading
            if hasCargo && moveTargetX != nil {
                let arrived = !moveOneStep()
                if !arrived {
                    return  // Still moving to drop-off point
                }
            }
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
                mission: .construction,
                speed: 0.0
            )
            // Start build-up animation
            building.buildUpFrame = 0
            building.buildUpDelay = 0
            world.addObject(building)
            audioManager.play(.construction)

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

    // MARK: - Building Build-Up Animation

    /// Animate building construction frame by frame.
    /// buildUpTotalFrames is resolved by the renderer on first draw (since frame count
    /// comes from sprite data which is only available in the rendering layer).
    func tickBuildUp() {
        guard kind == .structure else {
            mission = .guard_
            return
        }

        // Wait until renderer has resolved frame count
        if buildUpTotalFrames == 0 {
            return
        }

        // If only 1 frame, skip animation but still trigger completion bonuses
        if buildUpTotalFrames <= 1 {
            buildUpFrame = -1
            mission = .guard_
            onBuildUpComplete()
            return
        }

        // Advance frame with delay (2 ticks per frame for smooth animation)
        buildUpDelay += 1
        if buildUpDelay >= 2 {
            buildUpDelay = 0
            buildUpFrame += 1

            if buildUpFrame >= buildUpTotalFrames {
                // Animation complete
                buildUpFrame = -1
                mission = .guard_
                onBuildUpComplete()
            }
        }
    }

    /// Called when a building's build-up animation finishes.
    /// Handles bonus units: refineries spawn a free harvester.
    /// Also checks for newly unlocked build options (EVA "new construction options").
    func onBuildUpComplete() {
        guard let world = session.world else { return }
        let upper = typeName.uppercased()

        // Check if this building unlocks new build options for the player
        if house == world.playerHouse {
            let prevCount = session.previousBuildOptionCount
            let newStructs = getAvailableStructures().count
            let newUnits = getAvailableUnits().count
            let newTotal = newStructs + newUnits
            if newTotal > prevCount && prevCount > 0 {
                session.speakEVA(.newConstruct, cooldownTicks: 30)
            }
            session.previousBuildOptionCount = newTotal
        }

        // Refinery: spawn a free harvester at the building exit
        if isRefinery {
            let size = buildingSize("PROC")
            let preferredX = worldX
            let preferredY = worldY + Double(size.h * 24) / 2.0 + 12.0
            // Find an empty cell near the exit so the harvester doesn't
            // land on top of an MCV/unit that's already parked there.
            let spawn = findFreeSpawnCell(nearWorldX: preferredX, nearWorldY: preferredY, kind: .unit)
                ?? (cellX: Int(preferredX) / 24, cellY: Int(preferredY) / 24)
            let exitX = Double(spawn.cellX * 24) + 12.0
            let exitY = Double(spawn.cellY * 24) + 12.0
            let harv = GameObject(
                id: world.allocateId(),
                typeName: "HARV",
                house: house,
                kind: .unit,
                worldX: exitX,
                worldY: exitY,
                facing: 128,  // Facing south
                strength: resolveStrength(typeName: "HARV", kind: .unit, scenarioStrength: 256),
                mission: .harvest,
                speed: resolveSpeed(typeName: "HARV", kind: .unit)
            )
            world.addObject(harv)
        }

        // Helipad: spawn a free Orca (GDI) or Apache (Nod) when the player
        // builds an HPAD specifically (AFLD is the airstrip equivalent and
        // has its own arrival flow via tickAirstripArrival).
        if upper == "HPAD" {
            let aircraft = (house == .badGuy) ? "HELI" : "ORCA"
            let heli = GameObject(
                id: world.allocateId(),
                typeName: aircraft,
                house: house,
                kind: .unit,
                worldX: worldX,
                worldY: worldY,
                facing: 0,
                strength: resolveStrength(typeName: aircraft, kind: .unit, scenarioStrength: 256),
                mission: .guard_,
                speed: resolveSpeed(typeName: aircraft, kind: .unit)
            )
            heli.isAircraft = true
            world.addObject(heli)
        }
    }

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

    /// Sell a building: initiate deconstruction animation (build-up in reverse)
    func tickBuildingSell() {
        guard kind == .structure else {
            mission = .guard_
            return
        }

        // Start deconstruction: play build-up animation in reverse
        // Set buildUpFrame to the last frame; tickDeconstruction will count down
        if buildUpTotalFrames > 1 {
            buildUpFrame = buildUpTotalFrames - 1
            buildUpDelay = 0
            mission = .deconstruction
        } else {
            // No build-up frames available — complete sell immediately
            completeSell()
        }
    }

    // MARK: - Building Deconstruction Animation

    /// Animate building sell: play build-up frames in reverse, then complete the sale
    func tickDeconstruction() {
        guard kind == .structure else {
            mission = .guard_
            return
        }

        // Wait until renderer has resolved frame count
        if buildUpTotalFrames == 0 {
            return
        }

        // If only 1 frame, skip animation and sell immediately
        if buildUpTotalFrames <= 1 {
            completeSell()
            return
        }

        // Decrement frame with delay (2 ticks per frame, matching build-up speed)
        buildUpDelay += 1
        if buildUpDelay >= 2 {
            buildUpDelay = 0
            buildUpFrame -= 1

            if buildUpFrame <= 0 {
                // Animation complete — finalize the sale
                completeSell()
            }
        }
    }

    /// Complete the sell: refund credits, spawn crew, clear footprint, remove building
    private func completeSell() {
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

        // Destroy the building (no death effects — it was sold, not destroyed)
        buildUpFrame = -1
        strength = 0

        // Recalculate power
        recalculateAllHousePower()

        print("Building sold: \(typeName) for $\(refundAmount)")
    }

    // MARK: - Building Distance Helpers

    /// Distance from this object to the nearest edge of a building's footprint.
    func distanceToBuilding(_ building: GameObject) -> Double {
        let size = buildingSize(building.typeName)
        let halfW = Double(size.w * 24) / 2.0
        let halfH = Double(size.h * 24) / 2.0
        // Clamp to the building rect to find the nearest point on the footprint
        let nearestX = max(building.worldX - halfW, min(worldX, building.worldX + halfW))
        let nearestY = max(building.worldY - halfH, min(worldY, building.worldY + halfH))
        let dx = worldX - nearestX
        let dy = worldY - nearestY
        return sqrt(dx * dx + dy * dy)
    }

    /// Returns the point on the building footprint edge closest to this object.
    func nearestBuildingEdgePoint(_ building: GameObject) -> (x: Double, y: Double) {
        let size = buildingSize(building.typeName)
        let halfW = Double(size.w * 24) / 2.0
        let halfH = Double(size.h * 24) / 2.0
        let nearestX = max(building.worldX - halfW, min(worldX, building.worldX + halfW))
        let nearestY = max(building.worldY - halfH, min(worldY, building.worldY + halfH))
        return (x: nearestX, y: nearestY)
    }

    // MARK: - Patrol (Loop through waypoints, engage enemies along the way)

    /// Patrol: move through waypoints in a loop, scanning for enemies along the way.
    /// When an enemy is found, engage it, then resume the patrol route.
    func tickPatrol() {
        guard let world = session.world else { return }

        // Need waypoints to patrol
        guard !patrolWaypoints.isEmpty else {
            mission = .guard_
            return
        }

        // Scan for enemies periodically (reuse guard scan logic)
        if isArmed && world.tickCount % 8 == 0 {
            let sightPixels = Double(sightRange) * 24.0
            let resolved = resolveWeapon()
            let weaponRange = resolved?.range ?? 96.0
            let scanRange = max(sightPixels, weaponRange * 1.5)
            if let enemy = findNearestEnemy(self, range: scanRange) {
                // Engage enemy, save patrol mission for resume
                suspendedMission = .patrol
                attackTarget = enemy.id
                mission = .attack
                return
            }
        }

        // Move toward current waypoint
        let wp = patrolWaypoints[patrolIndex]
        if moveTargetX == nil {
            moveTargetX = wp.x
            moveTargetY = wp.y
            movePath = []
        }

        let result = executeMovementStep()
        switch result {
        case .noTarget, .noPath, .arrivedFinal:
            // Reached waypoint - advance to next
            moveTargetX = nil
            moveTargetY = nil
            patrolIndex = (patrolIndex + 1) % patrolWaypoints.count
        case .blocked, .moving, .arrivedWaypoint:
            break
        }
    }
}
