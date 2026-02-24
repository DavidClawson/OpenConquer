import Foundation

// MARK: - Combat Weapon Resolution
// Uses authentic weapon/warhead data from WeaponData.swift type tables

struct ResolvedWeapon {
    let range: Double       // pixels
    let damage: Int
    let reloadTicks: Int
    let weaponType: WeaponType
    let warhead: WarheadType
}

/// Resolve the weapon stats for a game object using the type data system
func resolveWeapon(for obj: GameObject) -> ResolvedWeapon? {
    guard let weapon = obj.primaryWeapon,
          let wData = weaponTypeData[weapon] else { return nil }

    let warhead = bulletTypeData[wData.fires]?.warhead ?? .sa

    return ResolvedWeapon(
        range: wData.rangeInPixels,
        damage: wData.damage,
        reloadTicks: wData.rof,
        weaponType: weapon,
        warhead: warhead
    )
}

/// Resolve secondary weapon stats
func resolveSecondaryWeapon(for obj: GameObject) -> ResolvedWeapon? {
    guard let weapon = obj.secondaryWeapon,
          let wData = weaponTypeData[weapon] else { return nil }

    let warhead = bulletTypeData[wData.fires]?.warhead ?? .sa

    return ResolvedWeapon(
        range: wData.rangeInPixels,
        damage: wData.damage,
        reloadTicks: wData.rof,
        weaponType: weapon,
        warhead: warhead
    )
}

// MARK: - Combat Functions

/// Check if two objects are enemies (different houses, neither neutral)
func isEnemy(_ a: GameObject, _ b: GameObject) -> Bool {
    if a.house == b.house { return false }
    if a.house == .neutral || b.house == .neutral { return false }
    return true
}

/// Find the nearest enemy within range of an object
func findNearestEnemy(_ obj: GameObject, range: Double) -> GameObject? {
    guard let world = session.world else { return nil }
    var nearest: GameObject? = nil
    var nearestDist = Double.infinity

    for other in world.objects {
        if other.id == obj.id { continue }
        if other.strength <= 0 { continue }
        if !isEnemy(obj, other) { continue }

        let dx = other.worldX - obj.worldX
        let dy = other.worldY - obj.worldY
        let dist = sqrt(dx * dx + dy * dy)
        if dist <= range && dist < nearestDist {
            nearest = other
            nearestDist = dist
        }
    }
    return nearest
}

/// Find a game object by ID
func findObjectById(_ id: Int) -> GameObject? {
    guard let world = session.world else { return nil }
    return world.objects.first { $0.id == id }
}

/// Apply damage to a target using authentic warhead/armor calculation.
/// Returns true if target dies.
@discardableResult
func applyDamage(_ target: GameObject, amount: Int, warhead: WarheadType? = nil) -> Bool {
    let finalDamage: Int
    if let wh = warhead {
        // Use authentic damage model: warhead modifier vs armor type
        finalDamage = modifyDamage(amount, warhead: wh, armor: target.armorType)
    } else {
        finalDamage = max(1, amount)
    }

    target.strength -= finalDamage
    if let world = session.world {
        target.lastDamagedTick = world.tickCount
        target.lastWhoHurtMe = nil  // Could set to attacker's house
    }
    if target.strength <= 0 {
        target.strength = 0
        return true
    }

    // Infantry fear: taking damage increases fear
    if target.kind == .infantry {
        let fearIncrease = min(255 - Int(target.fear), finalDamage * 3)
        target.fear = UInt8(min(255, Int(target.fear) + fearIncrease))
    }

    // Spring "attacked" trigger if attached
    if let trigName = target.triggerName {
        springTrigger(named: trigName, event: .attacked)
    }

    return false
}

// MARK: - Turret Rotation

/// Rotate turret facing toward a target facing, returning true when aligned.
/// Uses VC's approach: rotate at most N steps per tick toward desired facing.
func rotateTurretToward(_ obj: GameObject, targetFacing: Int, rotateSpeed: Int = 8) -> Bool {
    guard obj.hasTurret else {
        obj.turretFacing = obj.facing
        return true
    }

    let diff = ((targetFacing - obj.turretFacing) + 256) % 256
    if diff == 0 { return true }

    // Rotate the shorter way
    if diff <= 128 {
        // Rotate clockwise
        let step = min(diff, rotateSpeed)
        obj.turretFacing = (obj.turretFacing + step) % 256
    } else {
        // Rotate counter-clockwise
        let step = min(256 - diff, rotateSpeed)
        obj.turretFacing = (obj.turretFacing - step + 256) % 256
    }

    // Check if close enough
    let newDiff = ((targetFacing - obj.turretFacing) + 256) % 256
    return newDiff < rotateSpeed || newDiff > (256 - rotateSpeed)
}

// MARK: - Attack Logic

/// Tick the attack mission for an object
func tickAttack(_ obj: GameObject) {
    guard let world = session.world else { return }

    // Decrement reload timer
    if obj.reloadTimer > 0 {
        obj.reloadTimer -= 1
    }

    // Find our target
    guard let targetId = obj.attackTarget,
          let target = findObjectById(targetId),
          target.strength > 0 else {
        // Target gone or dead — return to previous mission
        obj.attackTarget = nil
        if let suspended = obj.suspendedMission {
            obj.mission = suspended
            obj.suspendedMission = nil
            obj.missionStatus = 0
        } else {
            obj.mission = .guard_
        }
        obj.moveTargetX = nil
        obj.moveTargetY = nil
        return
    }

    let resolved = resolveWeapon(for: obj)
    let range = resolved?.range ?? 96.0

    let dx = target.worldX - obj.worldX
    let dy = target.worldY - obj.worldY
    let dist = sqrt(dx * dx + dy * dy)

    // Face the target — turret or body depending on unit type
    let targetFacing = directionToFacing(dx: dx, dy: dy)
    if dist > 0.5 {
        if obj.hasTurret {
            // Body faces movement direction, turret faces target
            let turretAligned = rotateTurretToward(obj, targetFacing: targetFacing)
            if dist <= range && !turretAligned {
                // In range but turret not aligned — wait for rotation
                obj.moveTargetX = nil
                obj.moveTargetY = nil
                obj.movePath = []
                return
            }
        } else {
            obj.facing = targetFacing
        }
    }

    if dist <= range {
        // In range — stop moving and fire if reloaded
        obj.moveTargetX = nil
        obj.moveTargetY = nil
        obj.movePath = []

        if obj.reloadTimer <= 0, let resolved = resolved {
            obj.reloadTimer = resolved.reloadTicks
            obj.lastFireTick = world.tickCount

            // Decrement ammo if limited
            if obj.ammo > 0 {
                obj.ammo -= 1
            }

            // Play weapon fire sound
            if let weapon = obj.cachedPrimaryWeapon {
                soundEffect(weaponFireSound(weapon), worldX: obj.worldX, worldY: obj.worldY)
            }

            // Spawn projectile — the projectile system handles damage on impact.
            // Invisible bullets (sniper, rifle, laser) apply damage immediately
            // inside spawnProjectile; visible ones (missiles, shells) fly first.
            let bulletType = weaponTypeData[resolved.weaponType]?.fires ?? .bullet
            spawnProjectile(bulletType: bulletType, from: obj, to: target,
                           damage: resolved.damage, warhead: resolved.warhead)
        }
    } else {
        // Out of range — move closer (without touching mission)
        if obj.kind != .structure {
            obj.moveTargetX = target.worldX
            obj.moveTargetY = target.worldY
            if obj.movePath.isEmpty {
                let path = findPath(
                    fromX: obj.cellX, fromY: obj.cellY,
                    toX: target.cellX, toY: target.cellY,
                    ignoring: obj,
                    speedType: obj.cachedSpeedType
                )
                obj.movePath = path
            }
            let _ = moveOneStep(obj)
        } else {
            // Structure out of range — give up on this target
            obj.attackTarget = nil
            obj.mission = .guard_
        }
    }
}

/// Auto-target enemies that enter guard range
func tickGuardScan(_ obj: GameObject) {
    let resolved = resolveWeapon(for: obj)
    // Guard range is slightly larger than weapon range
    let guardRange = (resolved?.range ?? 96.0) * 1.5

    if let enemy = findNearestEnemy(obj, range: guardRange) {
        obj.attackTarget = enemy.id
        obj.mission = .attack
    }
}

// MARK: - Infantry Fear System

/// Fear thresholds matching VC defines
let fearAnxious: UInt8 = 10
let fearScared: UInt8 = 100
let fearPanic: UInt8 = 200
let fearMaximum: UInt8 = 255

/// Tick fear reduction for infantry — fear decays slowly when not taking damage
func tickFear(_ obj: GameObject) {
    guard obj.kind == .infantry else { return }
    guard let world = session.world else { return }

    // Fear decays by 1 every 8 ticks when not recently damaged
    let ticksSinceDamage = world.tickCount - obj.lastDamagedTick
    if ticksSinceDamage > 15 && world.tickCount % 8 == 0 {
        if obj.fear > 0 {
            obj.fear -= 1
        }
        if obj.isProne && obj.fear < fearAnxious {
            obj.isProne = false
        }
    }

    // Go prone when scared
    if obj.fear >= fearScared && !obj.isProne {
        obj.isProne = true
    }

    // Panic scatter when fear is extreme
    if obj.fear >= fearPanic && obj.mission != .attack {
        if obj.moveTargetX == nil {
            // Scatter: move to a random nearby cell
            let scatterDist = 3
            let nx = obj.cellX + Int.random(in: -scatterDist...scatterDist)
            let ny = obj.cellY + Int.random(in: -scatterDist...scatterDist)
            let clampedX = max(0, min(63, nx))
            let clampedY = max(0, min(63, ny))
            if isCellPassable(cellX: clampedX, cellY: clampedY, speedType: obj.cachedSpeedType) {
                obj.moveTargetX = Double(clampedX * 24) + 12.0
                obj.moveTargetY = Double(clampedY * 24) + 12.0
                obj.movePath = []
                obj.mission = .retreat
            }
        }
    }
}

// MARK: - Cleanup

/// Remove dead objects from the world
func removeDeadObjects() {
    guard let world = session.world else { return }
    world.objects.removeAll { $0.strength <= 0 }
}

/// Check if an object at a screen position is an enemy of the current player
func findEnemyAtWorldPos(worldX: Double, worldY: Double) -> GameObject? {
    guard let world = session.world else { return nil }
    let hitRadius = 14.0

    for obj in world.objects {
        if obj.strength <= 0 { continue }
        if obj.house == world.playerHouse { continue }
        if obj.house == .neutral { continue }

        let dx = obj.worldX - worldX
        let dy = obj.worldY - worldY
        let dist = sqrt(dx * dx + dy * dy)

        // For structures, use a larger hit area
        if obj.kind == .structure {
            let size = buildingSize(obj.typeName)
            let halfW = Double(size.w * 24) / 2.0
            let halfH = Double(size.h * 24) / 2.0
            if abs(dx) <= halfW && abs(dy) <= halfH {
                return obj
            }
        } else if dist < hitRadius {
            return obj
        }
    }
    return nil
}

/// Find the nearest friendly object of a given type
func findNearestFriendly(_ obj: GameObject, typeName: String, maxRange: Double = Double.infinity) -> GameObject? {
    guard let world = session.world else { return nil }
    var nearest: GameObject? = nil
    var nearestDist = Double.infinity

    for other in world.objects {
        if other.id == obj.id { continue }
        if other.strength <= 0 { continue }
        if other.house != obj.house { continue }
        if other.typeName.uppercased() != typeName.uppercased() { continue }

        let dx = other.worldX - obj.worldX
        let dy = other.worldY - obj.worldY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < nearestDist && dist <= maxRange {
            nearest = other
            nearestDist = dist
        }
    }
    return nearest
}
