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

func gameTick() {
    guard let world = session.world else { return }
    world.tickCount += 1

    // Save previous positions for render interpolation
    for obj in world.objects {
        obj.prevWorldX = obj.worldX
        obj.prevWorldY = obj.worldY
    }

    // Update occupancy at start of tick
    updateOccupancy()

    // Update fog of war
    updateFog()

    // Tick production
    tickProduction()

    // Tick super weapons
    tickSuperWeapons()

    // Tick AI
    tickAI()
    tickAISuperWeapons()

    // Tick team AI (coordinated squads)
    tickTeams()

    // Tick triggers (win/lose conditions, timed events)
    tickTriggers()

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
            default:
                break
            }
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
        case .construction, .deconstruction:
            break  // Handled by production system
        case .missile:
            break  // Future: superweapon launch
        }
    }

    // Tick infantry fear system
    for obj in world.objects {
        if obj.kind == .infantry {
            obj.tickFear()
        }
    }

    // Check cell triggers for player units that may have moved
    for obj in world.objects {
        if obj.house == world.playerHouse && obj.strength > 0 {
            checkCellTriggers(cell: obj.cell, enteringObject: obj)
        }
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
            // Death effects are spawned by tickAttack when it kills;
            // also catch any other deaths (e.g., fire damage, triggers)
            if obj.lastDamagedTick == world.tickCount {
                // Already handled by combat this tick
            } else if obj.kind == .structure {
                obj.spawnDeathEffects()
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
}

// MARK: - Movement Extensions

extension GameObject {
    /// Tick the move mission (follow path to target)
    func tickMove() {
        guard let targetX = moveTargetX, let targetY = moveTargetY else {
            mission = .guard_
            return
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
                    // No path found, stop
                    mission = .guard_
                    moveTargetX = nil
                    moveTargetY = nil
                    return
                }
                movePath = path
            }
        }

        // Determine the next waypoint to move toward
        let nextX: Double
        let nextY: Double

        if !movePath.isEmpty {
            // Move toward the center of the next path cell
            let nextCell = movePath[0]
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

        if dist <= speed {
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
                        mission = .guard_
                        moveTargetX = nil
                        moveTargetY = nil
                    }
                }
            } else {
                // Arrived at final target
                mission = .guard_
                moveTargetX = nil
                moveTargetY = nil
            }
        } else {
            // Move toward waypoint
            let moveX = (dx / dist) * speed
            let moveY = (dy / dist) * speed
            worldX += moveX
            worldY += moveY
        }
    }

    /// Move one step toward current target without changing mission.
    /// Returns true if still moving.
    @discardableResult
    func moveOneStep() -> Bool {
        guard let targetX = moveTargetX, let targetY = moveTargetY else {
            return false
        }

        // If we have no path, compute one via A*
        if movePath.isEmpty {
            let fromCellX = cellX
            let fromCellY = cellY
            let toCellX = Int(targetX) / 24
            let toCellY = Int(targetY) / 24

            if fromCellX != toCellX || fromCellY != toCellY {
                let path = findPath(
                    fromX: fromCellX, fromY: fromCellY,
                    toX: toCellX, toY: toCellY,
                    ignoring: self,
                    speedType: cachedSpeedType
                )
                if path.isEmpty {
                    moveTargetX = nil
                    moveTargetY = nil
                    return false
                }
                movePath = path
            }
        }

        // Determine the next waypoint
        let nextX: Double
        let nextY: Double

        if !movePath.isEmpty {
            let nextCell = movePath[0]
            nextX = Double(nextCell.cellX * 24) + 12.0
            nextY = Double(nextCell.cellY * 24) + 12.0
        } else {
            nextX = targetX
            nextY = targetY
        }

        let dx = nextX - worldX
        let dy = nextY - worldY
        let dist = sqrt(dx * dx + dy * dy)

        if dist > 0.5 {
            facing = directionToFacing(dx: dx, dy: dy)
        }

        if dist <= speed {
            worldX = nextX
            worldY = nextY

            if !movePath.isEmpty {
                movePath.removeFirst()
                if movePath.isEmpty {
                    let finalDx = targetX - worldX
                    let finalDy = targetY - worldY
                    let finalDist = sqrt(finalDx * finalDx + finalDy * finalDy)
                    if finalDist < 2.0 {
                        moveTargetX = nil
                        moveTargetY = nil
                        return false
                    }
                }
            } else {
                moveTargetX = nil
                moveTargetY = nil
                return false
            }
        } else {
            let moveX = (dx / dist) * speed
            let moveY = (dy / dist) * speed
            worldX += moveX
            worldY += moveY
        }
        return true
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
