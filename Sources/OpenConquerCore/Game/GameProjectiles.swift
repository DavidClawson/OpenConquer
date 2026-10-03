import Foundation

// MARK: - In-Flight Projectile System
// Tracks visible projectiles in flight between attacker and target.
// Invisible/instant bullets (rifles, machine guns, lasers) skip this system
// and apply damage immediately. Visible projectiles (missiles, tank shells,
// grenades) fly toward their target over multiple ticks.

// MARK: - Projectile Instance

package class Projectile {
    package let id: Int
    package let bulletType: BulletType
    package let bulletData: BulletTypeData
    package var worldX: Double
    package var worldY: Double
    package var targetX: Double
    package var targetY: Double
    package let targetId: Int?              // Track moving targets
    package var facing: Int                 // 0-255 facing for sprite rendering
    package let damage: Int
    package let warhead: WarheadType
    package let sourceHouse: House
    package let sourceObjectId: Int?        // Attacker's object ID (for kill credit)
    package let sourceX: Double             // Attacker's position at fire time (for fog reveal)
    package let sourceY: Double
    package var age: Int = 0                // Ticks since launch
    package var isFinished: Bool = false
    package let speed: Double               // Pixels per tick

    package init(id: Int, bulletType: BulletType, data: BulletTypeData,
         startX: Double, startY: Double, targetX: Double, targetY: Double,
         targetId: Int?, facing: Int, damage: Int, warhead: WarheadType,
         sourceHouse: House, sourceObjectId: Int? = nil) {
        self.id = id
        self.bulletType = bulletType
        self.bulletData = data
        self.worldX = startX
        self.worldY = startY
        self.targetX = targetX
        self.targetY = targetY
        self.targetId = targetId
        self.facing = facing
        self.damage = damage
        self.warhead = warhead
        self.sourceHouse = sourceHouse
        self.sourceObjectId = sourceObjectId
        self.sourceX = startX
        self.sourceY = startY
        // Convert MPH speed to pixels/tick
        // Projectiles should fly noticeably faster than ground units
        // Unit speed factor is 0.16; projectiles use 0.40 for snappy feel
        self.speed = Double(data.maxSpeed.rawValue) * 0.40
    }
}

// MARK: - Projectile Manager


/// Spawn a visible projectile from attacker toward target
package func spawnProjectile(bulletType: BulletType, from attacker: GameObject,
                     to target: GameObject, damage: Int, warhead: WarheadType) {
    guard let bData = bulletTypeData[bulletType] else { return }

    // Invisible projectiles (sniper, bullets, laser) apply damage immediately
    if bData.isInvisible {
        // Reveal attacker's position in fog if target is a player unit
        if let world = session.world, target.house == world.playerHouse {
            revealFogAroundPosition(worldX: attacker.worldX, worldY: attacker.worldY)
        }
        let died = target.applyDamage(amount: damage, warhead: warhead,
                                       attackerHouse: attacker.house, attackerId: attacker.id)
        spawnImpactEffect(at: target.worldX, worldY: target.worldY, warhead: warhead)
        if died {
            target.spawnDeathEffects()
            if target.kind == .infantry {
                audioManager.play(audioManager.deathScream(for: target), worldX: target.worldX, worldY: target.worldY)
            } else {
                audioManager.play(audioManager.explosionSound(warhead), worldX: target.worldX, worldY: target.worldY)
            }
            session.campaign.trackKill(victimHouse: target.house, victimKind: target.kind)
            let attackerState = getHouseState(attacker.house)
            let victimState = getHouseState(target.house)
            if target.kind == .structure {
                attackerState.buildingsKilled += 1
                victimState.buildingsLost += 1
            } else {
                attackerState.unitsKilled += 1
                victimState.unitsLost += 1
            }
        }
        // Splash damage for instant-hit weapons (only for explosive warheads)
        applySplashDamage(at: target.worldX, worldY: target.worldY, warhead: warhead,
                          baseDamage: damage, attackerHouse: attacker.house,
                          attackerId: attacker.id, primaryTargetId: target.id)
        return
    }

    // Calculate launch offset (toward facing direction — use turret for turreted units)
    let fireFacing = attacker.hasTurret ? attacker.turretFacing : attacker.facing
    let faceRad = Double(fireFacing) / 256.0 * 2.0 * .pi
    let launchDist = (attacker.kind == .infantry) ? 6.0 : 10.0
    let startX = attacker.worldX + sin(faceRad) * launchDist
    let startY = attacker.worldY - cos(faceRad) * launchDist

    let dx = target.worldX - startX
    let dy = target.worldY - startY
    let facing = directionToFacing(dx: dx, dy: dy)

    let proj = Projectile(
        id: session.nextProjectileId,
        bulletType: bulletType,
        data: bData,
        startX: startX, startY: startY,
        targetX: target.worldX, targetY: target.worldY,
        targetId: target.id,
        facing: facing,
        damage: damage,
        warhead: warhead,
        sourceHouse: attacker.house,
        sourceObjectId: attacker.id
    )
    session.nextProjectileId += 1
    session.activeProjectiles.append(proj)
}

/// Tick all active projectiles
package func tickProjectiles() {
    guard let world = session.world else { return }

    for proj in session.activeProjectiles {
        guard !proj.isFinished else { continue }
        proj.age += 1

        // Update target position for homing missiles
        if proj.bulletData.isHoming, let tid = proj.targetId,
           let target = world.findObject(id: tid), target.strength > 0 {
            proj.targetX = target.worldX
            proj.targetY = target.worldY
        }

        let dx = proj.targetX - proj.worldX
        let dy = proj.targetY - proj.worldY
        let dist = sqrt(dx * dx + dy * dy)

        // Update facing for non-faceless projectiles
        if !proj.bulletData.isFaceless && dist > 0.5 {
            let desiredFacing = directionToFacing(dx: dx, dy: dy)
            if proj.bulletData.rot > 0 {
                // Gradual turning (homing missiles)
                let diff = ((desiredFacing - proj.facing) + 256) % 256
                if diff != 0 {
                    if diff <= 128 {
                        proj.facing = (proj.facing + min(diff, proj.bulletData.rot)) % 256
                    } else {
                        proj.facing = (proj.facing - min(256 - diff, proj.bulletData.rot) + 256) % 256
                    }
                }
            } else {
                proj.facing = desiredFacing
            }
        }

        // Move toward target
        let moveSpeed = max(proj.speed, 2.0)  // Minimum 2px/tick so projectiles don't crawl
        if dist <= moveSpeed || proj.age > 120 {
            // Arrived at target or timed out — apply damage
            proj.isFinished = true

            if let tid = proj.targetId,
               let target = world.findObject(id: tid), target.strength > 0 {
                // Reveal attacker's position in fog if target is a player unit
                if target.house == world.playerHouse {
                    revealFogAroundPosition(worldX: proj.sourceX, worldY: proj.sourceY)
                }
                let died = target.applyDamage(amount: proj.damage, warhead: proj.warhead,
                                               attackerHouse: proj.sourceHouse,
                                               attackerId: proj.sourceObjectId)
                spawnImpactEffect(at: target.worldX, worldY: target.worldY, warhead: proj.warhead)

                if died {
                    target.spawnDeathEffects()
                    if target.kind == .infantry {
                        audioManager.play(audioManager.deathScream(for: target), worldX: target.worldX, worldY: target.worldY)
                    } else {
                        audioManager.play(audioManager.explosionSound(proj.warhead), worldX: target.worldX, worldY: target.worldY)
                    }
                    session.campaign.trackKill(victimHouse: target.house, victimKind: target.kind)
                    let attackerState = getHouseState(proj.sourceHouse)
                    let victimState = getHouseState(target.house)
                    if target.kind == .structure {
                        attackerState.buildingsKilled += 1
                        victimState.buildingsLost += 1
                    } else {
                        attackerState.unitsKilled += 1
                        victimState.unitsLost += 1
                    }
                }
                // Splash damage around impact point
                applySplashDamage(at: target.worldX, worldY: target.worldY,
                                  warhead: proj.warhead, baseDamage: proj.damage,
                                  attackerHouse: proj.sourceHouse,
                                  attackerId: proj.sourceObjectId,
                                  primaryTargetId: tid)
            } else {
                // Target gone — explode at last known position
                spawnImpactEffect(at: proj.targetX, worldY: proj.targetY, warhead: proj.warhead)
                // Still apply splash damage at impact point even if primary target is gone
                applySplashDamage(at: proj.targetX, worldY: proj.targetY,
                                  warhead: proj.warhead, baseDamage: proj.damage,
                                  attackerHouse: proj.sourceHouse,
                                  attackerId: proj.sourceObjectId)
            }
        } else {
            // Fly toward target
            let moveX: Double
            let moveY: Double
            if proj.bulletData.isHoming && proj.bulletData.rot > 0 {
                // Homing: move in current facing direction
                let faceRad = Double(proj.facing) / 256.0 * 2.0 * .pi
                moveX = sin(faceRad) * moveSpeed
                moveY = -cos(faceRad) * moveSpeed
            } else {
                // Straight line to target
                moveX = (dx / dist) * moveSpeed
                moveY = (dy / dist) * moveSpeed
            }
            proj.worldX += moveX
            proj.worldY += moveY
        }
    }

    // Remove finished projectiles
    session.activeProjectiles.removeAll { $0.isFinished }
}
