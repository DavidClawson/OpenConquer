import CSDL2
import Foundation

// MARK: - Game Tick Timing

let ticksPerSecond = 15
let tickDurationMs: UInt32 = 66  // ~15 FPS (1000/15)

/// Interpolation factor 0.0-1.0 between game ticks for smooth rendering.
/// 0.0 = at previous tick position, 1.0 = at current tick position.

// MARK: - Game Update

func updateGame() {
    let now = SDL_GetTicks()
    if session.lastTickTime == 0 {
        session.lastTickTime = now
        return
    }

    let elapsed = now - session.lastTickTime
    session.lastTickTime = now
    session.tickAccumulator += elapsed

    // Run game ticks at fixed 15 FPS rate
    while session.tickAccumulator >= tickDurationMs {
        session.tickAccumulator -= tickDurationMs
        gameTick()
    }

    // Compute interpolation factor for smooth rendering between ticks
    session.renderInterpolation = Double(session.tickAccumulator) / Double(tickDurationMs)
}

// MARK: - Game Tick

/// One-shot flag to initialize event bus debug logging on first tick
private var _eventBusInitialized = false

func gameTick() {
    guard let world = session.world else { return }

    // Initialize event bus debug logging once on the first tick
    if !_eventBusInitialized {
        _eventBusInitialized = true
        setupEventBusDebugLogging()
    }

    world.tickCount += 1

    // Save previous positions for render interpolation
    for obj in world.objects {
        obj.prevWorldX = obj.worldX
        obj.prevWorldY = obj.worldY
    }

    // Update occupancy at start of tick
    updateOccupancy()

    // Resolve any pre-stacked units (idle units sharing a cell with another
    // unit). Picks one to scatter to the nearest free neighbor; affected
    // units fall through their normal mission tick once moving.
    if world.tickCount % 30 == 0 {
        resolveStackedUnits()
    }

    // Update fog of war
    updateFog()

    // Tick credits display animation
    session.tickCreditsDisplay()

    // Tick production
    tickProduction()

    // Tick super weapons
    tickSuperWeapons()

    // Tick screen effects (flash, shake, beam)
    tickScreenEffects()

    // Tick AI
    tickAI()
    tickAISuperWeapons()

    // Tick team AI (coordinated squads)
    tickTeams()

    // Tick reinforcement deliveries (C17 fly-in)
    tickReinforcements()

    // Tick triggers (win/lose conditions, timed events)
    tickTriggers()
    // Tier-1: region enter/leave events (inert when the scenario has no regions)
    tickRegionTriggers()

    // Tick tiberium growth and spread
    world.map.tickTiberiumGrowth()

    // Tick crate spawning and pickup
    tickCrates()

    // Update each object by mission
    for obj in world.objects {
        // Aircraft-specific handling
        if obj.isAircraft {
            obj.tickAircraft()
            switch obj.mission {
            case .attack:
                obj.tickAircraftAttack()
            case .guard_:
                obj.tickAircraftGuard()
            case .return_:
                obj.tickAircraftReturn()
            case .move:
                if obj.altitude >= flightLevel {
                    let arrived = !obj.flyToward()
                    if arrived {
                        obj.mission = .guard_
                    }
                }
            case .hunt, .timedHunt:
                obj.tickAircraftGuard()
                if obj.mission == .guard_ { obj.mission = .hunt }
            case .unload:
                // Aircraft transport unloading (C17/TRAN) — handled by tickReinforcements
                // for pending deliveries; direct unload for already-arrived transports
                if obj.hasCargo && obj.moveTargetX == nil {
                    obj.tickAPCUnload()
                } else if obj.moveTargetX != nil {
                    // Still flying to drop zone
                    let arrived = !obj.flyToward()
                    if arrived {
                        obj.tickAPCUnload()
                    }
                } else {
                    obj.mission = .guard_
                }
            default:
                break
            }
            continue
        }

        // VC special case: Gunboat always hunts regardless of assigned mission
        if obj.isGunboat && obj.cachedSpeedType == .float_ {
            obj.mission = .hunt
            obj.tickGunboatHunt()
            continue
        }

        switch obj.mission {
        case .move:
            obj.tickMove()
        case .attack:
            obj.tickAttack()
        case .harvest:
            obj.tickHarvest()
        case .guard_:
            // Auto-target enemies for armed units/structures
            if obj.isArmed {
                obj.tickGuardScan()
            }
        case .guardArea:
            obj.tickGuardArea()
        case .hunt, .timedHunt:
            obj.tickHunt()
        case .ambush:
            // Ambush: like sleep but switches to hunt when discovered
            // Becomes hunt when any player unit is in sight range
            if let _ = findNearestEnemy(obj, range: Double(obj.sightRange) * 24.0) {
                obj.mission = .hunt
            }
        case .stop, .sleep, .sticky:
            break
        case .retreat:
            obj.tickRetreat()
        case .return_:
            obj.tickReturn()
        case .enter:
            // Move toward nav target (transport/building)
            if obj.moveTargetX != nil {
                obj.moveOneStep()
            } else {
                obj.mission = .guard_
            }
        case .capture:
            obj.tickCapture()
        case .unload:
            obj.tickUnload()
        case .repair:
            obj.tickBuildingRepair()
        case .selling:
            obj.tickBuildingSell()
        case .construction:
            obj.tickBuildUp()
        case .deconstruction:
            obj.tickDeconstruction()
        case .sabotage:
            obj.tickSabotage()
        case .missile:
            break  // Future: superweapon launch
        case .patrol:
            obj.tickPatrol()
        }
    }

    // Tick infantry fear system
    for obj in world.objects {
        if obj.kind == .infantry {
            obj.tickFear()
        }
    }

    // Tick animation state (walk cycles, fire animations)
    for obj in world.objects {
        guard obj.strength > 0 else { continue }

        // Fire animation countdown
        if obj.isFiringAnim {
            obj.fireAnimTicks -= 1
            if obj.fireAnimTicks <= 0 {
                obj.isFiringAnim = false
                obj.fireAnimTicks = 0
            }
        }

        // Infantry walk cycle advancement
        if obj.kind == .infantry {
            let isMoving = obj.moveTargetX != nil
            if isMoving {
                obj.animTickCounter += 1
                if obj.animTickCounter >= 4 {
                    obj.animTickCounter = 0
                    obj.animFrame += 1
                    if obj.animFrame > 5 { obj.animFrame = 0 }
                }
            } else {
                obj.animFrame = 0
                obj.animTickCounter = 0
            }
        }
    }

    // Tick elite self-heal (1 HP per 30 ticks for elite units)
    for obj in world.objects {
        if obj.veteranLevel >= 2 && obj.strength > 0 {
            obj.tickEliteHeal()
        }
    }

    // Tick SAM site deploy/retract animation
    for obj in world.objects {
        if obj.kind == .structure && obj.hasTurret {
            obj.tickSAMDeploy()
        }
    }

    // Spawn fire/smoke on damaged objects (original C&C behavior).
    // Only check periodically to avoid spamming animations.
    if world.tickCount % 30 == 0 {
        for obj in world.objects {
            guard obj.strength > 0 else { continue }
            // Infantry don't smoke — only buildings and vehicles.
            guard obj.kind == .structure || obj.kind == .unit else { continue }
            // Aircraft in flight don't trail smoke (the explosion fires on impact).
            if obj.isAircraft && obj.altitude > 0 { continue }

            let health = obj.healthFraction
            // One persistent damage anim per object — wait for it to clear before respawning
            let hasFireAnim = session.activeAnimations.contains { $0.attachedToId == obj.id }

            if obj.kind == .structure {
                if health <= 0.25 && !hasFireAnim {
                    // Heavy damage: building-sized fire across the footprint.
                    let size = buildingSize(obj.typeName)
                    let halfW = Double(size.w * 24) / 2.0
                    let halfH = Double(size.h * 24) / 2.0
                    let ox = Double.random(in: -halfW * 0.5...halfW * 0.5)
                    let oy = Double.random(in: -halfH * 0.5...halfH * 0.5)
                    let anim = GameAnimation(type: .onFireBig, worldX: obj.worldX + ox, worldY: obj.worldY + oy)
                    anim.attachedToId = obj.id
                    session.activeAnimations.append(anim)
                } else if health <= 0.5 && health > 0.25 && !hasFireAnim {
                    let anim = GameAnimation(type: .smokeM, worldX: obj.worldX, worldY: obj.worldY)
                    anim.attachedToId = obj.id
                    session.activeAnimations.append(anim)
                }
            } else {
                // Vehicles: smaller smoke at half health, bigger fire at quarter health.
                if health <= 0.25 && !hasFireAnim {
                    let anim = GameAnimation(type: .onFireSmall, worldX: obj.worldX, worldY: obj.worldY)
                    anim.attachedToId = obj.id
                    session.activeAnimations.append(anim)
                } else if health <= 0.5 && health > 0.25 && !hasFireAnim {
                    let anim = GameAnimation(type: .smokeM, worldX: obj.worldX, worldY: obj.worldY)
                    anim.attachedToId = obj.id
                    session.activeAnimations.append(anim)
                }
            }
        }
    }

    // Check cell triggers for units that may have moved
    for obj in world.objects {
        if obj.strength > 0 && !obj.isInLimbo && (obj.kind == .unit || obj.kind == .infantry) {
            checkCellTriggers(cell: obj.cell, enteringObject: obj)
        }
    }

    // Check discovered triggers (objects becoming visible to the player)
    // Only check every 15 ticks (~1 second) for performance
    if world.tickCount % 15 == 0 {
        checkDiscoveredTriggers()
    }

    // Tick projectiles in flight
    tickProjectiles()

    // Tick animations
    tickAnimations()

    // Remove dead objects — spring "destroyed" triggers first, spawn death effects
    for obj in world.objects {
        if obj.strength <= 0 {
            if let trigName = obj.triggerName {
                springTrigger(named: trigName, event: .destroyed)
            }
            // Tier-1 mission flag: a "must-survive" object dying = mission lost.
            if obj.mustSurvive && session.triggerWinState == .playing {
                session.triggerWinState = .lost
            }
            // Death effects are spawned by tickAttack when it kills;
            // also catch any other deaths (e.g., fire damage, triggers)
            if obj.lastDamagedTick == world.tickCount {
                // Already handled by combat this tick
            } else if obj.kind == .structure {
                obj.spawnDeathEffects()
            }
        }
    }
    // Remove loaner units (reinforcement transports) that have exited the map
    if let bounds = world.mapBounds {
        for obj in world.objects {
            guard obj.isALoaner && obj.strength > 0 && !obj.hasCargo else { continue }
            let cx = obj.cellX
            let cy = obj.cellY
            if cx < bounds.x - 1 || cx > bounds.x + bounds.width ||
               cy < bounds.y - 1 || cy > bounds.y + bounds.height {
                // Gunboat: bounce at edges (handled by tickGunboatHunt), don't remove
                if obj.isGunboat { continue }
                obj.strength = 0
            }
        }
    }

    removeDeadObjects()

    // Recalculate power when buildings die or are built
    if world.tickCount % 30 == 0 {
        recalculateAllHousePower()
    }

    // Sync sidebar credits with HouseState
    let playerState = getHouseState(world.playerHouse)
    playerState.credits = session.sidebarCredits

    // Flush all queued game events to subscribers
    eventBus.flush()
}

// MARK: - Movement Extensions

/// Result of a single movement step attempt.
enum MovementStepResult {
    case noTarget          // No move target set
    case noPath            // Pathfinding failed
    case blocked           // Waiting for repath (cell impassable or enemy blocking)
    case moving            // Still moving toward waypoint
    case arrivedWaypoint   // Reached intermediate waypoint, more path remains
    case arrivedFinal      // Reached final destination
}

extension GameObject {

    /// Core movement step logic shared by tickMove() and moveOneStep().
    /// Handles pathfinding, path revalidation, occupancy checks, infantry crushing,
    /// and per-tick position advancement. Returns a result the caller uses to decide
    /// mission transitions.
    func executeMovementStep() -> MovementStepResult {
        guard let targetX = moveTargetX, let targetY = moveTargetY else {
            return .noTarget
        }

        // If we have no path, compute one via A*
        if movePath.isEmpty {
            let fromCellX = cellX
            let fromCellY = cellY
            let toCellX = Int(targetX) / 24
            let toCellY = Int(targetY) / 24

            // Only pathfind if we're not already at the target cell
            if fromCellX != toCellX || fromCellY != toCellY {
                let path = findPath(
                    fromX: fromCellX, fromY: fromCellY,
                    toX: toCellX, toY: toCellY,
                    ignoring: self,
                    speedType: cachedSpeedType
                )
                if path.isEmpty {
                    return .noPath
                }
                movePath = path
            }
        }

        // Determine the next waypoint to move toward
        let nextX: Double
        let nextY: Double

        if !movePath.isEmpty {
            let nextCell = movePath[0]
            let nextCellIdx = nextCell.cellY * 64 + nextCell.cellX

            // Revalidate: if next path cell became impassable (new structure, etc.), repath
            let passMap = passabilityMap(for: cachedSpeedType)
            if nextCellIdx >= 0 && nextCellIdx < 4096 && !passMap[nextCellIdx] {
                movePath = []  // Invalidate stale path, will repath next tick
                return .blocked
            }

            // Inspect whoever's currently in the next path cell.
            //   - friendlies: transit through them (squad movement);
            //   - crushable enemies if we're a crusher: run them over;
            //   - any other enemy: wait and re-path.
            // Final-cell occupancy (not stacking on a friend at rest) is
            // enforced by `findPath` rerouting around full destinations.
            if let world = session.world, let ids = world.occupancy[nextCellIdx] {
                let isFinalCell = movePath.count == 1
                var blocked = false
                for occupantId in ids where occupantId != id {
                    guard let occupant = world.findObject(id: occupantId) else { continue }
                    if isCrusher && occupant.isCrushable && isEnemy(self, occupant) {
                        occupant.applyDamage(amount: occupant.strength + 1, attackerHouse: house)
                        occupant.spawnDeathEffects()
                        audioManager.play(audioManager.infantryDeathScream(), worldX: occupant.worldX, worldY: occupant.worldY)
                        session.campaign.trackKill(victimHouse: occupant.house, victimKind: occupant.kind)
                        getHouseState(occupant.house).unitsLost += 1
                        getHouseState(house).unitsKilled += 1
                        continue
                    }
                    if occupant.house == house {
                        // Friendly: never crush. If this is the final cell
                        // and entering would violate stacking, repath so we
                        // don't stop on top of them.
                        if isFinalCell &&
                           !isCellEnterableAsDestination(cell: nextCellIdx, mover: self) {
                            blocked = true
                            break
                        }
                        continue
                    }
                    // Enemy non-crushable: blocked.
                    blocked = true
                    break
                }
                if blocked {
                    movePath = []
                    return .blocked
                }
            }

            nextX = Double(nextCell.cellX * 24) + 12.0
            nextY = Double(nextCell.cellY * 24) + 12.0
        } else {
            // We're in the target cell, move to exact target position
            nextX = targetX
            nextY = targetY
        }

        let dx = nextX - worldX
        let dy = nextY - worldY
        let dist = sqrt(dx * dx + dy * dy)

        // Update facing to point toward movement direction
        if dist > 0.5 {
            facing = directionToFacing(dx: dx, dy: dy)
        }

        let baseSpeed = effectiveSpeed
        let moveSpeed = groupMoveSpeed != nil ? min(baseSpeed, groupMoveSpeed!) : baseSpeed
        if dist <= moveSpeed {
            // Arrived at waypoint
            worldX = nextX
            worldY = nextY

            if !movePath.isEmpty {
                movePath.removeFirst()

                // If we've consumed all waypoints, check if we're at final target
                if movePath.isEmpty {
                    let finalDx = targetX - worldX
                    let finalDy = targetY - worldY
                    let finalDist = sqrt(finalDx * finalDx + finalDy * finalDy)
                    if finalDist < 2.0 {
                        moveTargetX = nil
                        moveTargetY = nil
                        return .arrivedFinal
                    }
                }
                return .arrivedWaypoint
            } else {
                // Arrived at final target
                moveTargetX = nil
                moveTargetY = nil
                return .arrivedFinal
            }
        } else {
            // Move toward waypoint
            let moveX = (dx / dist) * moveSpeed
            let moveY = (dy / dist) * moveSpeed
            worldX += moveX
            worldY += moveY
            return .moving
        }
    }

    /// Tick the move mission (follow path to target).
    /// Transitions to .guard_ on arrival or path failure.
    /// Supports attack-move (scan for enemies while moving) and waypoint queuing.
    func tickMove() {
        // Attack-move: periodically scan for enemies while moving
        if isAttackMoving && isArmed {
            if let world = session.world, world.tickCount % 8 == 0 {
                let resolved = resolveWeapon()
                let weaponRange = resolved?.range ?? 96.0
                let sightPixels = Double(sightRange) * 24.0
                let scanRange = max(sightPixels, weaponRange)
                if let enemy = findNearestEnemy(self, range: scanRange) {
                    // Suspend current move and engage enemy
                    suspendedMission = .move
                    attackTarget = enemy.id
                    mission = .attack
                    return
                }
            }
        }

        let result = executeMovementStep()
        switch result {
        case .noTarget, .noPath, .arrivedFinal:
            // Check for queued waypoints before going idle
            if !moveWaypoints.isEmpty {
                let next = moveWaypoints.removeFirst()
                moveTargetX = next.x
                moveTargetY = next.y
                movePath = []  // Recalculate A* for new segment
            } else {
                isAttackMoving = false
                groupMoveSpeed = nil
                mission = .guard_
                moveTargetX = nil
                moveTargetY = nil
            }
        case .blocked, .moving, .arrivedWaypoint:
            break
        }
    }

    /// Move one step toward current target without changing mission.
    /// Returns true if still moving.
    @discardableResult
    func moveOneStep() -> Bool {
        let result = executeMovementStep()
        switch result {
        case .noTarget, .noPath, .arrivedFinal:
            moveTargetX = nil
            moveTargetY = nil
            groupMoveSpeed = nil
            return false
        case .blocked, .moving, .arrivedWaypoint:
            return true
        }
    }

}

// MARK: - Facing Calculation

/// Convert movement direction to C&C 0-255 facing
/// C&C convention: 0=North, 64=East, 128=South, 192=West
func directionToFacing(dx: Double, dy: Double) -> Int {
    // atan2 gives angle from positive X axis, counterclockwise
    // We need: 0=N (up, -Y), 64=E (+X), 128=S (+Y), 192=W (-X)
    let angle = atan2(dx, -dy)  // Note: (dx, -dy) maps to N=0
    var facing = Int(angle / (2.0 * .pi) * 256.0)
    if facing < 0 { facing += 256 }
    return facing & 0xFF
}
