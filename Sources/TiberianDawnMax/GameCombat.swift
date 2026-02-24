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

// MARK: - Weapon Resolution Extensions

extension GameObject {
    /// Resolve primary weapon stats from type data
    func resolveWeapon() -> ResolvedWeapon? {
        guard let weapon = primaryWeapon,
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
    func resolveSecondaryWeapon() -> ResolvedWeapon? {
        guard let weapon = secondaryWeapon,
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

// MARK: - Combat Extensions

extension GameObject {
    /// Apply damage using warhead/armor calculation. Returns true if killed.
    @discardableResult
    func applyDamage(amount: Int, warhead: WarheadType? = nil) -> Bool {
        let finalDamage: Int
        if let wh = warhead {
            // Use authentic damage model: warhead modifier vs armor type
            finalDamage = modifyDamage(amount, warhead: wh, armor: armorType)
        } else {
            finalDamage = max(1, amount)
        }

        strength -= finalDamage
        if let world = session.world {
            lastDamagedTick = world.tickCount
            lastWhoHurtMe = nil  // Could set to attacker's house
        }
        if strength <= 0 {
            strength = 0
            return true
        }

        // Infantry fear: taking damage increases fear
        if kind == .infantry {
            let fearIncrease = min(255 - Int(fear), finalDamage * 3)
            fear = UInt8(min(255, Int(fear) + fearIncrease))
        }

        // Spring "attacked" trigger if attached
        if let trigName = triggerName {
            springTrigger(named: trigName, event: .attacked)
        }

        return false
    }

    /// Rotate turret toward target facing. Returns true when aligned.
    func rotateTurretToward(targetFacing: Int, rotateSpeed: Int = 8) -> Bool {
        guard hasTurret else {
            turretFacing = facing
            return true
        }

        let diff = ((targetFacing - turretFacing) + 256) % 256
        if diff == 0 { return true }

        // Rotate the shorter way
        if diff <= 128 {
            // Rotate clockwise
            let step = min(diff, rotateSpeed)
            turretFacing = (turretFacing + step) % 256
        } else {
            // Rotate counter-clockwise
            let step = min(256 - diff, rotateSpeed)
            turretFacing = (turretFacing - step + 256) % 256
        }

        // Check if close enough
        let newDiff = ((targetFacing - turretFacing) + 256) % 256
        return newDiff < rotateSpeed || newDiff > (256 - rotateSpeed)
    }

    /// Tick the attack mission
    func tickAttack() {
        guard let world = session.world else { return }

        // Decrement reload timer
        if reloadTimer > 0 {
            reloadTimer -= 1
        }

        // Find our target
        guard let targetId = attackTarget,
              let target = findObjectById(targetId),
              target.strength > 0 else {
            // Target gone or dead — return to previous mission
            attackTarget = nil
            if let suspended = suspendedMission {
                mission = suspended
                suspendedMission = nil
                missionStatus = 0
            } else {
                mission = .guard_
            }
            moveTargetX = nil
            moveTargetY = nil
            return
        }

        let resolved = resolveWeapon()
        let range = resolved?.range ?? 96.0

        let dx = target.worldX - worldX
        let dy = target.worldY - worldY
        let dist = sqrt(dx * dx + dy * dy)

        // Face the target — turret or body depending on unit type
        let tgtFacing = directionToFacing(dx: dx, dy: dy)
        if dist > 0.5 {
            if hasTurret {
                // Body faces movement direction, turret faces target
                let turretAligned = rotateTurretToward(targetFacing: tgtFacing)
                if dist <= range && !turretAligned {
                    // In range but turret not aligned — wait for rotation
                    moveTargetX = nil
                    moveTargetY = nil
                    movePath = []
                    return
                }
            } else {
                facing = tgtFacing
            }
        }

        if dist <= range {
            // In range — stop moving and fire if reloaded
            moveTargetX = nil
            moveTargetY = nil
            movePath = []

            if reloadTimer <= 0, let resolved = resolved {
                reloadTimer = resolved.reloadTicks
                lastFireTick = world.tickCount

                // Decrement ammo if limited
                if ammo > 0 {
                    ammo -= 1
                }

                // Play weapon fire sound
                if let weapon = cachedPrimaryWeapon {
                    soundEffect(weaponFireSound(weapon), worldX: worldX, worldY: worldY)
                }

                // Spawn projectile — the projectile system handles damage on impact.
                // Invisible bullets (sniper, rifle, laser) apply damage immediately
                // inside spawnProjectile; visible ones (missiles, shells) fly first.
                let bulletType = weaponTypeData[resolved.weaponType]?.fires ?? .bullet
                spawnProjectile(bulletType: bulletType, from: self, to: target,
                               damage: resolved.damage, warhead: resolved.warhead)
            }
        } else {
            // Out of range — move closer (without touching mission)
            if kind != .structure {
                moveTargetX = target.worldX
                moveTargetY = target.worldY
                if movePath.isEmpty {
                    let path = findPath(
                        fromX: cellX, fromY: cellY,
                        toX: target.cellX, toY: target.cellY,
                        ignoring: self,
                        speedType: cachedSpeedType
                    )
                    movePath = path
                }
                moveOneStep()
            } else {
                // Structure out of range — give up on this target
                attackTarget = nil
                mission = .guard_
            }
        }
    }

    /// Auto-target enemies in guard range
    func tickGuardScan() {
        let resolved = resolveWeapon()
        // Guard range is slightly larger than weapon range
        let guardRange = (resolved?.range ?? 96.0) * 1.5

        if let enemy = findNearestEnemy(self, range: guardRange) {
            attackTarget = enemy.id
            mission = .attack
        }
    }

    /// Tick infantry fear decay and panic behavior
    func tickFear() {
        guard kind == .infantry else { return }
        guard let world = session.world else { return }

        // Fear decays by 1 every 8 ticks when not recently damaged
        let ticksSinceDamage = world.tickCount - lastDamagedTick
        if ticksSinceDamage > 15 && world.tickCount % 8 == 0 {
            if fear > 0 {
                fear -= 1
            }
            if isProne && fear < fearAnxious {
                isProne = false
            }
        }

        // Go prone when scared
        if fear >= fearScared && !isProne {
            isProne = true
        }

        // Panic scatter when fear is extreme
        if fear >= fearPanic && mission != .attack {
            if moveTargetX == nil {
                // Scatter: move to a random nearby cell
                let scatterDist = 3
                let nx = cellX + Int.random(in: -scatterDist...scatterDist)
                let ny = cellY + Int.random(in: -scatterDist...scatterDist)
                let clampedX = max(0, min(63, nx))
                let clampedY = max(0, min(63, ny))
                if isCellPassable(cellX: clampedX, cellY: clampedY, speedType: cachedSpeedType) {
                    moveTargetX = Double(clampedX * 24) + 12.0
                    moveTargetY = Double(clampedY * 24) + 12.0
                    movePath = []
                    mission = .retreat
                }
            }
        }
    }
}

// MARK: - Infantry Fear System

/// Fear thresholds matching VC defines
let fearAnxious: UInt8 = 10
let fearScared: UInt8 = 100
let fearPanic: UInt8 = 200
let fearMaximum: UInt8 = 255

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
