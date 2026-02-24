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
    let speed = Double(data.maxSpeed.rawValue) * 0.08

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

// MARK: - Aircraft Tick

/// Tick aircraft-specific behavior: altitude changes, flight movement
func tickAircraft(_ obj: GameObject) {
    guard obj.isAircraft else { return }

    // Handle takeoff
    if obj.isTakingOff {
        if obj.altitude < flightLevel {
            obj.altitude += 1
        }
        if obj.altitude >= flightLevel {
            obj.altitude = flightLevel
            obj.isTakingOff = false
        }
        return
    }

    // Handle landing
    if obj.isLanding {
        if obj.altitude > 0 {
            obj.altitude -= 1
        }
        if obj.altitude <= 0 {
            obj.altitude = 0
            obj.isLanding = false

            // When landed, check for rearm at helipad/airstrip
            if let world = session.world {
                let landedCell = obj.cell
                for other in world.objects {
                    guard other.kind == .structure && other.house == obj.house && other.strength > 0 else { continue }
                    let upper = other.typeName.uppercased()
                    if (upper == "HPAD" || upper == "AFLD") && other.cell == landedCell {
                        // Rearm at this pad
                        rearmAircraft(obj)
                        break
                    }
                }
            }
        }
        return
    }

    // Normal flight: apply movement toward move target if flying
    if obj.altitude >= flightLevel && obj.moveTargetX != nil {
        let _ = flyToward(obj)
    }
}

/// Rearm aircraft to full ammo
func rearmAircraft(_ obj: GameObject) {
    guard obj.isAircraft else { return }
    if let at = AircraftType.from(iniName: obj.typeName.uppercased()),
       let data = aircraftTypeDataTable[at] {
        obj.ammo = data.maxAmmo
    }
}

// MARK: - Aircraft Attack Mission

/// Tick attack for aircraft — fly to target, fire, return to rearm when out of ammo
func tickAircraftAttack(_ obj: GameObject) {
    guard let world = session.world else { return }
    guard obj.isAircraft else { return }

    // Decrement reload timer
    if obj.reloadTimer > 0 {
        obj.reloadTimer -= 1
    }

    // Ensure airborne
    if obj.altitude < flightLevel {
        obj.isTakingOff = true
        return
    }

    // Find target
    guard let targetId = obj.attackTarget,
          let target = findObjectById(targetId),
          target.strength > 0 else {
        // Target gone — return to base or guard
        obj.attackTarget = nil
        if obj.ammo == 0 {
            returnToBase(obj)
        } else {
            obj.mission = .guard_
        }
        return
    }

    // Check ammo
    if obj.ammo == 0 {
        obj.attackTarget = nil
        returnToBase(obj)
        return
    }

    let resolved = resolveWeapon(for: obj)
    let range = resolved?.range ?? 96.0

    let dx = target.worldX - obj.worldX
    let dy = target.worldY - obj.worldY
    let dist = sqrt(dx * dx + dy * dy)

    // Face target
    if dist > 0.5 {
        let targetFacing = directionToFacing(dx: dx, dy: dy)
        obj.facing = targetFacing
    }

    if dist <= range {
        // In range — fire if reloaded
        if obj.reloadTimer <= 0, let resolved = resolved {
            obj.reloadTimer = resolved.reloadTicks

            if obj.ammo > 0 {
                obj.ammo -= 1
            }

            obj.lastFireTick = world.tickCount
            let died = applyDamage(target, amount: resolved.damage, warhead: resolved.warhead)
            target.lastWhoHurtMe = obj.house

            spawnImpactEffect(at: target.worldX, worldY: target.worldY, warhead: resolved.warhead)

            if died {
                spawnDeathEffects(target)
                let attackerState = getHouseState(obj.house)
                let victimState = getHouseState(target.house)
                if target.kind == .structure {
                    attackerState.buildingsKilled += 1
                    victimState.buildingsLost += 1
                } else {
                    attackerState.unitsKilled += 1
                    victimState.unitsLost += 1
                }

                obj.attackTarget = nil
                if obj.ammo == 0 {
                    returnToBase(obj)
                } else {
                    // Look for another target
                    if let newEnemy = findNearestEnemy(obj, range: range * 2.0) {
                        obj.attackTarget = newEnemy.id
                    } else {
                        obj.mission = .guard_
                    }
                }
            }
        }

        // For fixed-wing: keep flying past target
        if isFixedWing(obj) {
            let faceRad = Double(obj.facing) / 256.0 * 2.0 * .pi
            obj.worldX += sin(faceRad) * obj.speed
            obj.worldY -= cos(faceRad) * obj.speed
        }
    } else {
        // Out of range — fly toward target
        obj.moveTargetX = target.worldX
        obj.moveTargetY = target.worldY
        obj.movePath = []
        let _ = flyToward(obj)
    }
}

// MARK: - Aircraft Guard

/// Aircraft guard: hover in place, scan for enemies
func tickAircraftGuard(_ obj: GameObject) {
    guard obj.isAircraft && obj.isArmed else { return }

    // Ensure airborne
    if obj.altitude < flightLevel && obj.altitude > 0 {
        obj.isTakingOff = true
        return
    }

    // Check ammo — return to rearm if empty
    if obj.ammo == 0 {
        returnToBase(obj)
        return
    }

    // Scan for enemies
    let resolved = resolveWeapon(for: obj)
    let scanRange = (resolved?.range ?? 96.0) * 1.5

    if let enemy = findNearestEnemy(obj, range: scanRange) {
        obj.attackTarget = enemy.id
        obj.mission = .attack
    }
}

// MARK: - Return to Base

/// Send aircraft back to nearest helipad/airstrip
func returnToBase(_ obj: GameObject) {
    guard let world = session.world else { return }

    var bestDist = Double.infinity
    var bestTarget: GameObject? = nil

    for other in world.objects {
        guard other.kind == .structure && other.house == obj.house && other.strength > 0 else { continue }
        let upper = other.typeName.uppercased()
        guard upper == "HPAD" || upper == "AFLD" else { continue }

        let dx = other.worldX - obj.worldX
        let dy = other.worldY - obj.worldY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < bestDist {
            bestDist = dist
            bestTarget = other
        }
    }

    if let base = bestTarget {
        obj.moveTargetX = base.worldX
        obj.moveTargetY = base.worldY
        obj.movePath = []
        obj.mission = .return_
    } else {
        // No base to return to — just guard
        obj.mission = .guard_
    }
}

/// Tick aircraft return mission — fly to base, land, rearm
func tickAircraftReturn(_ obj: GameObject) {
    guard obj.isAircraft else { return }

    // Ensure airborne for flight
    if obj.altitude < flightLevel && obj.altitude > 0 && !obj.isLanding {
        obj.isTakingOff = true
        return
    }

    // If we're landed and at base, rearm
    if obj.altitude == 0 {
        rearmAircraft(obj)
        obj.mission = .guard_
        return
    }

    // Fly toward base
    if obj.moveTargetX != nil {
        let arrived = !flyToward(obj)
        if arrived {
            // Start landing
            obj.isLanding = true
        }
    } else {
        // No target — just hover
        obj.mission = .guard_
    }
}

// MARK: - Aircraft Direct Flight Movement

/// Move aircraft directly toward target (no A* pathfinding — aircraft fly over everything)
/// Returns true if still moving, false if arrived.
func flyToward(_ obj: GameObject) -> Bool {
    guard let targetX = obj.moveTargetX, let targetY = obj.moveTargetY else {
        return false
    }

    let dx = targetX - obj.worldX
    let dy = targetY - obj.worldY
    let dist = sqrt(dx * dx + dy * dy)

    // Update facing
    if dist > 0.5 {
        obj.facing = directionToFacing(dx: dx, dy: dy)
    }

    if dist <= obj.speed {
        obj.worldX = targetX
        obj.worldY = targetY
        obj.moveTargetX = nil
        obj.moveTargetY = nil
        return false
    } else {
        obj.worldX += (dx / dist) * obj.speed
        obj.worldY += (dy / dist) * obj.speed
        return true
    }
}

// MARK: - Helpers

/// Check if an aircraft is fixed-wing type
func isFixedWing(_ obj: GameObject) -> Bool {
    guard let at = AircraftType.from(iniName: obj.typeName.uppercased()),
          let data = aircraftTypeDataTable[at] else { return false }
    return data.isFixedWing
}

/// Check if an object is an aircraft
func isAircraftType(_ typeName: String) -> Bool {
    return AircraftType.from(iniName: typeName.uppercased()) != nil
}
