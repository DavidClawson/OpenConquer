import CSDL2
import Foundation

// MARK: - In-Flight Projectile System
// Tracks visible projectiles in flight between attacker and target.
// Invisible/instant bullets (rifles, machine guns, lasers) skip this system
// and apply damage immediately. Visible projectiles (missiles, tank shells,
// grenades) fly toward their target over multiple ticks.

// MARK: - Projectile Instance

class Projectile {
    let id: Int
    let bulletType: BulletType
    let bulletData: BulletTypeData
    var worldX: Double
    var worldY: Double
    var targetX: Double
    var targetY: Double
    let targetId: Int?              // Track moving targets
    var facing: Int                 // 0-255 facing for sprite rendering
    let damage: Int
    let warhead: WarheadType
    let sourceHouse: House
    var age: Int = 0                // Ticks since launch
    var isFinished: Bool = false
    let speed: Double               // Pixels per tick

    init(id: Int, bulletType: BulletType, data: BulletTypeData,
         startX: Double, startY: Double, targetX: Double, targetY: Double,
         targetId: Int?, facing: Int, damage: Int, warhead: WarheadType,
         sourceHouse: House) {
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
        // Convert MPH speed to pixels/tick (same as unit speed)
        self.speed = Double(data.maxSpeed.rawValue) * 0.08
    }
}

// MARK: - Projectile Manager


/// Spawn a visible projectile from attacker toward target
func spawnProjectile(bulletType: BulletType, from attacker: GameObject,
                     to target: GameObject, damage: Int, warhead: WarheadType) {
    guard let bData = bulletTypeData[bulletType] else { return }

    // Invisible projectiles (sniper, bullets, laser) apply damage immediately
    if bData.isInvisible {
        let died = target.applyDamage(amount: damage, warhead: warhead)
        spawnImpactEffect(at: target.worldX, worldY: target.worldY, warhead: warhead)
        if died {
            target.spawnDeathEffects()
            if target.kind == .infantry {
                audioManager.play(audioManager.infantryDeathScream(), worldX: target.worldX, worldY: target.worldY)
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
        return
    }

    // Calculate launch offset (toward facing direction)
    let faceRad = Double(attacker.facing) / 256.0 * 2.0 * .pi
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
        sourceHouse: attacker.house
    )
    session.nextProjectileId += 1
    session.activeProjectiles.append(proj)
}

/// Tick all active projectiles
func tickProjectiles() {
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
                target.lastWhoHurtMe = proj.sourceHouse
                let died = target.applyDamage(amount: proj.damage, warhead: proj.warhead)
                spawnImpactEffect(at: target.worldX, worldY: target.worldY, warhead: proj.warhead)

                if died {
                    target.spawnDeathEffects()
                    if target.kind == .infantry {
                        audioManager.play(audioManager.infantryDeathScream(), worldX: target.worldX, worldY: target.worldY)
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
            } else {
                // Target gone — explode at last known position
                spawnImpactEffect(at: proj.targetX, worldY: proj.targetY, warhead: proj.warhead)
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

// MARK: - Projectile Rendering

func renderProjectiles(_ renderer: OpaquePointer?, camX: Int, camY: Int, vw: Int32, vh: Int32) {
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)

    for proj in session.activeProjectiles {
        if proj.isFinished { continue }

        let screenX = Int32(proj.worldX) - Int32(camX)
        let screenY = Int32(proj.worldY) - Int32(camY)

        // Cull off-screen
        if screenX < -20 || screenY < -20 || screenX > vw + 20 || screenY > vh + 20 { continue }

        // Try to render from remastered/SHP sprite
        let spriteName = proj.bulletData.iniName
        let theater = session.world?.theater ?? .temperate

        // For facing-based projectiles (missiles), compute the sprite frame
        let spriteFrame: Int
        if !proj.bulletData.isFaceless {
            let facingIdx = facing32[min(255, max(0, proj.facing))]
            spriteFrame = bodyShape[facingIdx]
        } else {
            spriteFrame = 0
        }

        if let info = getObjectTexture(renderer, typeName: spriteName, frame: spriteFrame,
                                        house: .neutral, theater: theater) {
            let drawX = screenX - Int32(info.width) / 2
            let drawY = screenY - Int32(info.height) / 2
            var dstRect = SDL_Rect(x: drawX, y: drawY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        } else {
            // Procedural fallback based on bullet type
            renderProceduralProjectile(renderer, proj: proj, screenX: screenX, screenY: screenY)
        }

        // Smoke trail for fueled projectiles (missiles)
        if proj.bulletData.isFueled && proj.age > 1 {
            SDL_SetRenderDrawColor(renderer, 180, 180, 180, UInt8(max(40, 120 - proj.age * 5)))
            let trailRad = Double(proj.facing) / 256.0 * 2.0 * .pi
            let tx = screenX - Int32(sin(trailRad) * 6.0)
            let ty = screenY + Int32(cos(trailRad) * 6.0)
            var trailRect = SDL_Rect(x: tx - 2, y: ty - 2, w: 4, h: 4)
            SDL_RenderFillRect(renderer, &trailRect)
        }
    }
}

/// Procedural projectile rendering when no sprite is available
private func renderProceduralProjectile(_ renderer: OpaquePointer?, proj: Projectile, screenX: Int32, screenY: Int32) {
    switch proj.bulletType {
    case .apds, .he:
        // Tank shell: bright yellow line in direction of travel
        let faceRad = Double(proj.facing) / 256.0 * 2.0 * .pi
        let len = 4.0
        let x1 = screenX - Int32(sin(faceRad) * len)
        let y1 = screenY + Int32(cos(faceRad) * len)
        let x2 = screenX + Int32(sin(faceRad) * len)
        let y2 = screenY - Int32(cos(faceRad) * len)
        SDL_SetRenderDrawColor(renderer, 255, 255, 150, 255)
        SDL_RenderDrawLine(renderer, x1, y1, x2, y2)

    case .ssm, .ssm2, .sam, .tow, .honestJohn:
        // Missile: white core with orange trail
        SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
        var core = SDL_Rect(x: screenX - 2, y: screenY - 2, w: 4, h: 4)
        SDL_RenderFillRect(renderer, &core)
        // Exhaust glow
        SDL_SetRenderDrawColor(renderer, 255, 160, 40, 180)
        let faceRad = Double(proj.facing) / 256.0 * 2.0 * .pi
        let ex = screenX - Int32(sin(faceRad) * 5.0)
        let ey = screenY + Int32(cos(faceRad) * 5.0)
        var exhaust = SDL_Rect(x: ex - 2, y: ey - 2, w: 3, h: 3)
        SDL_RenderFillRect(renderer, &exhaust)

    case .flame, .chemspray:
        // Flame: flickering orange/yellow blob
        let flicker = UInt8.random(in: 200...255)
        SDL_SetRenderDrawColor(renderer, 255, flicker, 0, 200)
        let sz: Int32 = Int32(3 + proj.age % 3)
        var blob = SDL_Rect(x: screenX - sz / 2, y: screenY - sz / 2, w: sz, h: sz)
        SDL_RenderFillRect(renderer, &blob)

    case .grenade:
        // Grenade: small dark circle with arc trajectory
        SDL_SetRenderDrawColor(renderer, 60, 60, 60, 255)
        var dot = SDL_Rect(x: screenX - 2, y: screenY - 2, w: 4, h: 4)
        SDL_RenderFillRect(renderer, &dot)
        SDL_SetRenderDrawColor(renderer, 120, 120, 120, 255)
        SDL_RenderDrawRect(renderer, &dot)

    case .napalm:
        // Napalm bomb: dark dropping shape
        SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255)
        var bomb = SDL_Rect(x: screenX - 2, y: screenY - 3, w: 4, h: 6)
        SDL_RenderFillRect(renderer, &bomb)

    case .nukeUp, .nukeDown:
        // Nuke: bright white streak
        SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
        let faceRad = Double(proj.facing) / 256.0 * 2.0 * .pi
        let len = 8.0
        let x1 = screenX - Int32(sin(faceRad) * len)
        let y1 = screenY + Int32(cos(faceRad) * len)
        SDL_RenderDrawLine(renderer, x1, y1, screenX, screenY)
        // Glow
        SDL_SetRenderDrawColor(renderer, 255, 200, 100, 120)
        var glow = SDL_Rect(x: screenX - 4, y: screenY - 4, w: 8, h: 8)
        SDL_RenderFillRect(renderer, &glow)

    default:
        // Generic small dot
        SDL_SetRenderDrawColor(renderer, 255, 255, 200, 255)
        var dot = SDL_Rect(x: screenX - 1, y: screenY - 1, w: 3, h: 3)
        SDL_RenderFillRect(renderer, &dot)
    }
}
