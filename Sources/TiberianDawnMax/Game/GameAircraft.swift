import Foundation

// MARK: - Aircraft System
// Ported from Vanilla Conquer aircraft.h/aircraft.cpp, fly.h/fly.cpp

// MARK: - Constants

/// Flight altitude in pixels (VC FLIGHT_LEVEL = 24)
let flightLevel: Int = 24

// MARK: - Aircraft State (stored on GameObject via extension fields)

/// Aircraft-specific state tracked on GameObjects with kind == .unit
/// We use existing fields plus new ones added to GameObject.
/// Aircraft are stored as kind == .unit but with the isAircraft flag set.

// MARK: - Aircraft Initialization

/// Create an aircraft game object
func createAircraft(
    world: GameWorld,
    type: AircraftType,
    house: House,
    worldX: Double,
    worldY: Double,
    facing: Int,
    strength: Int? = nil,
    mission: Mission = .guard_
) -> GameObject {
    guard let data = aircraftTypeDataTable[type] else {
        fatalError("Unknown aircraft type: \(type)")
    }

    let hp = strength ?? data.strength
    let speed = Double(data.maxSpeed.rawValue) * 0.16

    let obj = GameObject(
        id: world.allocateId(),
        typeName: data.iniName,
        house: house,
        kind: .unit,
        worldX: worldX,
        worldY: worldY,
        facing: facing,
        strength: hp,
        mission: mission,
        speed: speed
    )

    // Mark as aircraft
    obj.isAircraft = true
    obj.altitude = flightLevel  // Start airborne
    obj.ammo = data.maxAmmo

    return obj
}

// MARK: - Return to Base

/// Send aircraft back to nearest available (unoccupied) helipad/airstrip
func returnToBase(_ obj: GameObject) {
    guard let world = session.world else { return }

    // Release any previously reserved pad
    if let oldPad = obj.landingPadId {
        world.occupiedPads.remove(oldPad)
        obj.landingPadId = nil
    }

    var bestDist = Double.infinity
    var bestTarget: GameObject? = nil

    for other in world.objects {
        guard other.kind == .structure && other.house == obj.house && other.strength > 0 else { continue }
        guard other.isAircraftPad else { continue }

        // Skip pads already occupied by another aircraft
        if world.occupiedPads.contains(other.id) { continue }

        let dx = other.worldX - obj.worldX
        let dy = other.worldY - obj.worldY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < bestDist {
            bestDist = dist
            bestTarget = other
        }
    }

    if let base = bestTarget {
        // Reserve the pad so other aircraft won't target it
        world.occupiedPads.insert(base.id)
        obj.landingPadId = base.id
        obj.moveTargetX = base.worldX
        obj.moveTargetY = base.worldY
        obj.movePath = []
        obj.mission = .return_
    } else {
        // No available pad — just guard (will retry when a pad frees up)
        obj.mission = .guard_
    }
}

// MARK: - Helpers

/// Check if an object is an aircraft
func isAircraftType(_ typeName: String) -> Bool {
    return AircraftType.from(iniName: typeName.uppercased()) != nil
}

// MARK: - Aircraft Extension Methods

extension GameObject {

    // MARK: - Aircraft Tick

    /// Tick aircraft-specific behavior: altitude changes, flight movement
    func tickAircraft() {
        guard isAircraft else { return }

        // Handle takeoff
        if isTakingOff {
            if altitude < flightLevel {
                altitude += 1
            }
            if altitude >= flightLevel {
                altitude = flightLevel
                isTakingOff = false
                // Release the landing pad when fully airborne
                if let padId = landingPadId {
                    session.world?.occupiedPads.remove(padId)
                    landingPadId = nil
                }
            }
            return
        }

        // Handle landing
        if isLanding {
            if altitude > 0 {
                altitude -= 1
            }
            if altitude <= 0 {
                altitude = 0
                isLanding = false

                // When landed, check for rearm at helipad/airstrip
                if let world = session.world {
                    let landedCell = cell
                    for other in world.objects {
                        guard other.kind == .structure && other.house == house && other.strength > 0 else { continue }
                        if other.isAircraftPad && other.cell == landedCell {
                            // Rearm at this pad
                            rearmAircraft()
                            break
                        }
                    }
                }
            }
            return
        }

        // Normal flight: apply movement toward move target if flying
        if altitude >= flightLevel && moveTargetX != nil {
            let _ = flyToward()
        }
    }

    /// Rearm aircraft to full ammo
    func rearmAircraft() {
        guard isAircraft else { return }
        if let at = AircraftType.from(iniName: typeName.uppercased()),
           let data = aircraftTypeDataTable[at] {
            ammo = data.maxAmmo
        }
    }

    // MARK: - Aircraft Attack Mission

    /// Tick attack for aircraft — fly to target, fire, return to rearm when out of ammo
    func tickAircraftAttack() {
        guard let world = session.world else { return }
        guard isAircraft else { return }

        // Decrement reload timer
        if reloadTimer > 0 {
            reloadTimer -= 1
        }

        // Ensure airborne
        if altitude < flightLevel {
            isTakingOff = true
            return
        }

        // Find target
        guard let targetId = attackTarget,
              let target = findObjectById(targetId),
              target.strength > 0 else {
            // Target gone — return to base or guard
            attackTarget = nil
            if ammo == 0 {
                returnToBase(self)
            } else {
                mission = .guard_
            }
            return
        }

        // Check ammo
        if ammo == 0 {
            attackTarget = nil
            returnToBase(self)
            return
        }

        let resolved = resolveWeapon()
        let range = resolved?.range ?? 96.0

        let dx = target.worldX - worldX
        let dy = target.worldY - worldY
        let dist = sqrt(dx * dx + dy * dy)

        // Face target
        if dist > 0.5 {
            let tgtFacing = directionToFacing(dx: dx, dy: dy)
            facing = tgtFacing
        }

        if dist <= range {
            // In range — fire if reloaded
            if reloadTimer <= 0, let resolved = resolved {
                reloadTimer = resolved.reloadTicks

                if ammo > 0 {
                    ammo -= 1
                }

                lastFireTick = world.tickCount

                // Spawn muzzle flash at aircraft position
                spawnAnimation(.muzzleFlash, worldX: worldX, worldY: worldY)

                let died = target.applyDamage(amount: resolved.damage, warhead: resolved.warhead, attackerHouse: house)

                spawnImpactEffect(at: target.worldX, worldY: target.worldY, warhead: resolved.warhead)

                if died {
                    target.spawnDeathEffects()
                    let attackerState = getHouseState(house)
                    let victimState = getHouseState(target.house)
                    if target.kind == .structure {
                        attackerState.buildingsKilled += 1
                        victimState.buildingsLost += 1
                    } else {
                        attackerState.unitsKilled += 1
                        victimState.unitsLost += 1
                    }

                    attackTarget = nil
                    if ammo == 0 {
                        returnToBase(self)
                    } else {
                        // Look for another target
                        if let newEnemy = findNearestEnemy(self, range: range * 2.0) {
                            attackTarget = newEnemy.id
                        } else {
                            mission = .guard_
                        }
                    }
                }
            }

            // For fixed-wing: keep flying past target
            if isFixedWing {
                let faceRad = Double(facing) / 256.0 * 2.0 * .pi
                worldX += sin(faceRad) * speed
                worldY -= cos(faceRad) * speed
            }
        } else {
            // Out of range — fly toward target
            moveTargetX = target.worldX
            moveTargetY = target.worldY
            movePath = []
            let _ = flyToward()
        }
    }

    // MARK: - Aircraft Guard

    /// Aircraft guard: hover in place, scan for enemies
    func tickAircraftGuard() {
        guard isAircraft && isArmed else { return }

        // Ensure airborne
        if altitude < flightLevel && altitude > 0 {
            isTakingOff = true
            return
        }

        // Check ammo — return to rearm if empty
        if ammo == 0 {
            returnToBase(self)
            return
        }

        // Scan for enemies
        let resolved = resolveWeapon()
        let scanRange = (resolved?.range ?? 96.0) * 1.5

        if let enemy = findNearestEnemy(self, range: scanRange) {
            attackTarget = enemy.id
            mission = .attack
        }
    }

    // MARK: - Aircraft Return

    /// Tick aircraft return mission — fly to base, land, rearm
    func tickAircraftReturn() {
        guard isAircraft else { return }

        // Ensure airborne for flight
        if altitude < flightLevel && altitude > 0 && !isLanding {
            isTakingOff = true
            return
        }

        // If we're landed and at base, rearm
        if altitude == 0 {
            rearmAircraft()
            mission = .guard_
            return
        }

        // Fly toward base
        if moveTargetX != nil {
            let arrived = !flyToward()
            if arrived {
                // Start landing
                isLanding = true
            }
        } else {
            // No target — just hover
            mission = .guard_
        }
    }

    // MARK: - Aircraft Direct Flight Movement

    /// Move aircraft directly toward target (no A* pathfinding — aircraft fly over everything)
    /// Returns true if still moving, false if arrived.
    @discardableResult
    func flyToward() -> Bool {
        guard let targetX = moveTargetX, let targetY = moveTargetY else {
            return false
        }

        let dx = targetX - worldX
        let dy = targetY - worldY
        let dist = sqrt(dx * dx + dy * dy)

        // Update facing
        if dist > 0.5 {
            facing = directionToFacing(dx: dx, dy: dy)
        }

        if dist <= speed {
            worldX = targetX
            worldY = targetY
            moveTargetX = nil
            moveTargetY = nil
            return false
        } else {
            worldX += (dx / dist) * speed
            worldY += (dy / dist) * speed
            return true
        }
    }

    /// Whether this aircraft is a fixed-wing type (A10, C17)
    var isFixedWing: Bool {
        guard let at = AircraftType.from(iniName: typeName.uppercased()),
              let data = aircraftTypeDataTable[at] else { return false }
        return data.isFixedWing
    }

    /// MISSION_RETREAT for aircraft: fly to the nearest map edge and leave.
    /// Once off the map, passengers are checked for the civ-evac condition —
    /// a civilian aboard sets the owning house's `isCivEvacuated` flag
    /// (AIRCRAFT.CPP:831-855) — then transport and passengers are removed.
    /// Removal is a classic `delete`, NOT a kill: it must not spring Destroyed
    /// triggers or the must-survive loss (the evacuee leaving is the win).
    func tickAircraftRetreat() {
        guard let world = session.world else { return }
        let bounds = world.mapBounds ?? MapBounds(x: 0, y: 0, width: 64, height: 64)

        if moveTargetX == nil {
            // Head for the nearest edge, exiting a few cells beyond it
            let left   = worldX - Double(bounds.x * 24)
            let right  = Double((bounds.x + bounds.width) * 24) - worldX
            let top    = worldY - Double(bounds.y * 24)
            let bottom = Double((bounds.y + bounds.height) * 24) - worldY
            let nearest = min(left, right, top, bottom)
            if nearest == left {
                moveTargetX = Double(bounds.x * 24) - 96.0
                moveTargetY = worldY
            } else if nearest == right {
                moveTargetX = Double((bounds.x + bounds.width) * 24) + 96.0
                moveTargetY = worldY
            } else if nearest == top {
                moveTargetX = worldX
                moveTargetY = Double(bounds.y * 24) - 96.0
            } else {
                moveTargetX = worldX
                moveTargetY = Double((bounds.y + bounds.height) * 24) + 96.0
            }
        }
        _ = flyToward()

        // Off the map (past the one-cell fringe)?
        if cellX < bounds.x - 1 || cellX > bounds.x + bounds.width ||
           cellY < bounds.y - 1 || cellY > bounds.y + bounds.height {
            for pid in passengers {
                guard let p = world.findObject(id: pid), p.strength > 0 else { continue }
                if p.kind == .infantry,
                   let data = getInfantryTypeDataByName(p.typeName.uppercased()),
                   data.isCivilian {
                    getHouseState(house).isCivEvacuated = true
                }
                p.triggerName = nil
                p.mustSurvive = false
                p.strength = 0
            }
            passengers.removeAll()
            triggerName = nil
            mustSurvive = false
            strength = 0
        }
    }
}
