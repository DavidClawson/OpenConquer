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

/// True if the object's primary weapon can only target aircraft (e.g. SAM site)
func isAntiAirOnly(_ obj: GameObject) -> Bool {
    guard let weapon = obj.primaryWeapon,
          let wData = weaponTypeData[weapon],
          let bData = bulletTypeData[wData.fires] else { return false }
    return bData.isAntiAircraft
}

/// Find the nearest enemy within range of an object
func findNearestEnemy(_ obj: GameObject, range: Double) -> GameObject? {
    guard let world = session.world else { return nil }
    var nearest: GameObject? = nil
    var nearestDist = Double.infinity
    let aaOnly = isAntiAirOnly(obj)

    for other in world.objects {
        if other.id == obj.id { continue }
        if other.strength <= 0 { continue }
        if !isEnemy(obj, other) { continue }
        // Anti-aircraft weapons (SAM) can only target aircraft
        if aaOnly && !other.isAircraft { continue }

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

/// Find a game object by ID — O(1) via indexed lookup
func findObjectById(_ id: Int) -> GameObject? {
    guard let world = session.world else { return nil }
    return world.findObject(id: id)
}

// MARK: - Combat Extensions

extension GameObject {
    /// Apply damage using warhead/armor calculation. Returns true if killed.
    /// `attackerId` is the object ID of the attacker, used for veterancy kill credit.
    @discardableResult
    func applyDamage(amount: Int, warhead: WarheadType? = nil, attackerHouse: House? = nil, attackerId: Int? = nil) -> Bool {
        // Overkill prevention: don't apply damage to already-dead objects
        guard strength > 0 else { return false }

        let finalDamage: Int
        if let wh = warhead {
            // Use authentic damage model: warhead modifier vs armor type
            finalDamage = modifyDamage(amount, warhead: wh, armor: armorType)
        } else {
            finalDamage = max(1, amount)
        }

        // Elite defense bonus: incoming damage reduced by 25% for elite units
        var adjustedDamage = finalDamage
        if veteranLevel >= 2 {
            adjustedDamage = max(1, adjustedDamage * 3 / 4)
        }

        strength -= adjustedDamage
        if let world = session.world {
            lastDamagedTick = world.tickCount
            lastWhoHurtMe = attackerHouse
        }
        if strength <= 0 {
            strength = 0
            // Credit kill to attacker for veterancy
            if let aId = attackerId, let attacker = findObjectById(aId) {
                attacker.killCount += 1
            }
            return true
        }

        // EVA warnings for player objects taking damage
        if let world = session.world, house == world.playerHouse {
            if kind == .structure {
                session.speakEVA(.baseUnderAttack, cooldownTicks: 90)
            } else if typeName.uppercased() == "HARV" {
                session.speakEVA(.baseUnderAttack, cooldownTicks: 90)
            }
        }

        // Infantry fear: taking damage increases fear
        if kind == .infantry {
            let fearIncrease = min(255 - Int(fear), adjustedDamage * 3)
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

    /// True if this object is a defensive structure (turrets, SAMs, guard towers, obelisk)
    var isDefenseStructure: Bool {
        guard kind == .structure else { return false }
        let upper = typeName.uppercased()
        return upper == "GUN" || upper == "GTWR" || upper == "SAM" ||
               upper == "ATWR" || upper == "OBLI"
    }

    /// Tick the attack mission
    func tickAttack() {
        guard let world = session.world else { return }

        // Power gating: defensive structures fire at half rate when house has low power
        if isDefenseStructure {
            let houseState = getHouseState(house)
            if !houseState.hasPower && houseState.powerDrain > 0 {
                // No power: skip every other tick (simulates degraded performance)
                if world.tickCount % 2 == 0 {
                    return
                }
            }
        }

        // Decrement reload timer
        if reloadTimer > 0 {
            reloadTimer -= 1
        }

        // Find our target
        guard let targetId = attackTarget,
              let target = findObjectById(targetId),
              target.strength > 0,
              !(isAntiAirOnly(self) && !target.isAircraft) else {
            // Target gone, dead, or invalid (e.g. SAM vs ground) — find new target or return to guard
            attackTarget = nil
            if let suspended = suspendedMission {
                mission = suspended
                suspendedMission = nil
                missionStatus = 0
                // Recalculate path when resuming suspended move
                movePath = []
            } else {
                // Immediately scan for a new target before going idle
                mission = .guard_
                moveTargetX = nil
                moveTargetY = nil
                if isArmed {
                    tickGuardScan()
                }
            }
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
                reloadTimer = effectiveReloadTicks(resolved.reloadTicks)
                lastFireTick = world.tickCount

                // Trigger fire animation state
                isFiringAnim = true
                fireAnimTicks = 4

                // Spawn muzzle flash animation at barrel position
                // Use weapon-appropriate flash: small piff for small arms, GUNFIRE for cannons
                let fireFacing = hasTurret ? turretFacing : facing
                let faceRad = Double(fireFacing) / 256.0 * 2.0 * Double.pi
                let flashDist = (kind == .infantry) ? 6.0 : 10.0
                let mfx = worldX + sin(faceRad) * flashDist
                let mfy = worldY - cos(faceRad) * flashDist
                if let weapon = cachedPrimaryWeapon {
                    switch weapon {
                    case .m60mg, .m16, .chainGun, .pistol, .rifle:
                        // Small arms: use muzzle flash for structures (more visible), piff for infantry/units
                        if kind == .structure {
                            spawnAnimation(.muzzleFlash, worldX: mfx, worldY: mfy)
                        } else {
                            spawnAnimation(.piff, worldX: mfx, worldY: mfy)
                        }
                    case .flamethrower, .flameTongue, .chemspray:
                        break  // Flame weapons don't need a separate muzzle flash
                    default:
                        // Cannons, rockets, etc: full muzzle flash
                        spawnAnimation(.muzzleFlash, worldX: mfx, worldY: mfy)
                    }
                }

                // Decrement ammo if limited
                if ammo > 0 {
                    ammo -= 1
                }

                // Play weapon fire sound
                if let weapon = cachedPrimaryWeapon {
                    audioManager.play(audioManager.weaponFireSound(weapon), worldX: worldX, worldY: worldY)
                }

                // Spawn projectile — the projectile system handles damage on impact.
                // Invisible bullets (sniper, rifle, laser) apply damage immediately
                // inside spawnProjectile; visible ones (missiles, shells) fly first.
                let bulletType = weaponTypeData[resolved.weaponType]?.fires ?? .bullet
                let effectiveDamage = Int(Double(resolved.damage) * crateBuff.firepowerMultiplier)
                spawnProjectile(bulletType: bulletType, from: self, to: target,
                               damage: effectiveDamage, warhead: resolved.warhead)
            }
        } else {
            // Out of range — move closer (without touching mission)
            if kind != .structure {
                // Add small random offset so multiple units don't all converge on exact same point
                let jitterX = Double.random(in: -12.0...12.0)
                let jitterY = Double.random(in: -12.0...12.0)
                moveTargetX = target.worldX + jitterX
                moveTargetY = target.worldY + jitterY
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
        // Use sight range for detection (includes veterancy bonus)
        let sightPixels = Double(sightRange) * 24.0
        let resolved = resolveWeapon()
        let weaponRange = resolved?.range ?? 96.0
        // Scan at whichever is larger: sight range or weapon range
        let guardRange = max(sightPixels, weaponRange * 1.5)

        if let enemy = findNearestEnemy(self, range: guardRange) {
            attackTarget = enemy.id
            mission = .attack
        }
    }

    /// Tick SAM site deploy/retract animation.
    /// In original C&C, SAM sites retract into their silo when no aircraft target is present.
    /// Frame 0 = retracted, frames 1-31 = deployed turret rotation.
    func tickSAMDeploy() {
        guard kind == .structure else { return }
        guard typeName.uppercased() == "SAM" else { return }

        let hasTarget = attackTarget != nil && mission == .attack

        if hasTarget {
            // Deploying/deployed — animate toward target facing frame
            let targetFacingIdx = facing32[min(255, max(0, turretFacing))]
            let targetFrame = bodyShape[targetFacingIdx]
            if samDeployState == 0 {
                // Start deploying — go to frame 1
                samDeployState = 1
            } else if samDeployState < targetFrame {
                samDeployState = min(samDeployState + 2, targetFrame)
            } else if samDeployState > targetFrame {
                samDeployState = max(samDeployState - 2, targetFrame)
            }
        } else {
            // No target — retract back to frame 0
            if samDeployState > 0 {
                samDeployState = max(0, samDeployState - 2)
            }
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

// MARK: - Splash Damage System

/// Get splash radius in pixels for a warhead type
func splashRadius(for warhead: WarheadType) -> Double {
    switch warhead {
    case .he:
        return 48.0   // 2-cell radius
    case .fire:
        return 36.0   // 1.5-cell radius
    case .ap:
        return 12.0   // 0.5-cell radius (small splash)
    default:
        return 0.0    // No splash (SA, laser, fist, etc.)
    }
}

/// Apply splash damage at a world position. Damages all objects within the warhead's
/// splash radius, with linear falloff from 100% at center to 25% at edge.
/// - Parameters:
///   - worldX/worldY: Impact point
///   - warhead: Warhead type (determines splash radius)
///   - baseDamage: Base damage before armor modifiers
///   - attackerHouse: House of the attacker (to avoid full friendly fire)
///   - attackerId: Object ID of the attacker (for kill credit)
///   - primaryTargetId: The direct target (already took full damage, skip in splash)
func applySplashDamage(at worldX: Double, worldY: Double, warhead: WarheadType,
                       baseDamage: Int, attackerHouse: House, attackerId: Int? = nil,
                       primaryTargetId: Int? = nil) {
    guard let world = session.world else { return }
    let radius = splashRadius(for: warhead)
    guard radius > 0 else { return }

    for obj in world.objects {
        if obj.strength <= 0 { continue }
        // Skip the primary target (already received full damage)
        if let primaryId = primaryTargetId, obj.id == primaryId { continue }

        let dx = obj.worldX - worldX
        let dy = obj.worldY - worldY
        let dist = sqrt(dx * dx + dy * dy)
        guard dist <= radius else { continue }

        // Friendly fire: skip friendly units entirely
        if obj.house == attackerHouse { continue }

        // Linear falloff: 100% at center, 25% at edge
        let falloff = 1.0 - 0.75 * (dist / radius)
        var splashDmg = Int(Double(baseDamage) * falloff)

        // Infantry in the open take 1.5x splash damage
        if obj.kind == .infantry && !obj.isProne {
            splashDmg = splashDmg * 3 / 2
        }

        guard splashDmg > 0 else { continue }

        let died = obj.applyDamage(amount: splashDmg, warhead: warhead,
                                   attackerHouse: attackerHouse, attackerId: attackerId)
        if died {
            obj.spawnDeathEffects()
            if obj.kind == .infantry {
                audioManager.play(audioManager.infantryDeathScream(), worldX: obj.worldX, worldY: obj.worldY)
            } else {
                audioManager.play(audioManager.explosionSound(warhead), worldX: obj.worldX, worldY: obj.worldY)
            }
            session.campaign.trackKill(victimHouse: obj.house, victimKind: obj.kind)
            let attackerState = getHouseState(attackerHouse)
            let victimState = getHouseState(obj.house)
            if obj.kind == .structure {
                attackerState.buildingsKilled += 1
                victimState.buildingsLost += 1
            } else {
                attackerState.unitsKilled += 1
                victimState.unitsLost += 1
            }
        }
    }
}

// MARK: - Veterancy Bonuses

extension GameObject {
    /// Get the effective fire delay, reduced by veterancy
    func effectiveReloadTicks(_ base: Int) -> Int {
        switch veteranLevel {
        case 2: return max(1, base / 2)       // Elite: 50% faster
        case 1: return max(1, base * 3 / 4)   // Veteran: 25% faster
        default: return base
        }
    }

    /// Get the effective sight range, increased by veterancy
    var effectiveSightRange: Int {
        switch veteranLevel {
        case 2: return cachedSightRange + 4   // Elite: +4 cells
        case 1: return cachedSightRange + 2   // Veteran: +2 cells
        default: return cachedSightRange
        }
    }

    /// Tick elite self-heal: 1 HP per 30 ticks (0.5 HP/sec at 15 FPS)
    func tickEliteHeal() {
        guard veteranLevel >= 2 else { return }
        guard strength > 0 && strength < cachedMaxStrength else { return }
        guard let world = session.world else { return }
        if world.tickCount % 30 == 0 {
            strength = min(cachedMaxStrength, strength + 1)
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

/// Remove dead objects from the world using two-phase mark/sweep.
/// Phase 1 (mark): Dead objects already identified by strength <= 0.
/// Phase 2 (sweep): Remove from array + index, log for debugging.
func removeDeadObjects() {
    guard let world = session.world else { return }
    // Release any landing pad reservations held by dying aircraft
    for obj in world.objects where obj.strength <= 0 {
        if let padId = obj.landingPadId {
            world.occupiedPads.remove(padId)
            obj.landingPadId = nil
        }
    }

    // EVA announcements for player losses (before removal)
    for obj in world.objects where obj.strength <= 0 {
        guard obj.house == world.playerHouse else { continue }
        guard obj.mission != .selling && obj.mission != .deconstruction else { continue }  // Selling is voluntary, not a loss
        switch obj.kind {
        case .unit, .infantry:
            session.speakEVA(.unitLost, cooldownTicks: 45)
        case .structure:
            session.speakEVA(.structureLost, cooldownTicks: 45)
        }
    }

    let removed = world.removeDeadAndIndex()
    #if DEBUG
    for obj in removed {
        // Log unexpected removals — objects that died without being damaged this tick
        // (could indicate a bug where strength was set to 0 without proper combat flow)
        if obj.lastDamagedTick != world.tickCount && obj.mission != .selling && obj.mission != .deconstruction {
            print("DEBUG removeDeadObjects: \(obj.typeName)#\(obj.id) (\(obj.kind)) died without combat damage this tick (lastDamaged=\(obj.lastDamagedTick), currentTick=\(world.tickCount))")
        }
    }
    #endif
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

        // For structures, use visual hit area (extends above footprint)
        if obj.kind == .structure {
            if isWorldPosOnBuilding(worldX: worldX, worldY: worldY, building: obj) {
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
