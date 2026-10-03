import CSDL2
import Foundation
import OpenConquerCore

// Drawing for in-world sim objects that aren't GameObjects: crates and
// in-flight projectiles.

// MARK: - Crate Rendering

/// Render all active crates in the game world.
/// Called between terrain and unit passes in GameRenderer.swift.
func renderCrates(_ renderer: OpaquePointer?, camX: Int, camY: Int, vw: Int32, vh: Int32) {
    guard let world = session.world else { return }

    for crate in world.crateState.crates {
        guard !crate.isCollected else { continue }

        // Don't render crates in unexplored fog
        if world.map.fogState[crate.cell] == .unexplored { continue }

        let screenX = Int32(crate.worldX) - Int32(camX)
        let screenY = Int32(crate.worldY) - Int32(camY)

        // Cull off-screen
        if screenX + 12 < 0 || screenY + 12 < 0 || screenX - 12 > vw || screenY - 12 > vh { continue }

        // Apply fog dimming for explored-but-not-visible cells
        let isVisible = world.map.fogState[crate.cell] == .visible
        let dimFactor: UInt8 = isVisible ? 255 : 140

        // Draw procedural crate: brown box with lighter top
        let crateW: Int32 = 10
        let crateH: Int32 = 10
        let cx = screenX - crateW / 2
        let cy = screenY - crateH / 2

        // Shadow
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 60)
        var shadowRect = SDL_Rect(x: cx + 2, y: cy + 2, w: crateW, h: crateH)
        SDL_RenderFillRect(renderer, &shadowRect)

        // Main box body (brown)
        let bodyR = UInt8(min(255, Int(140) * Int(dimFactor) / 255))
        let bodyG = UInt8(min(255, Int(90) * Int(dimFactor) / 255))
        let bodyB = UInt8(min(255, Int(40) * Int(dimFactor) / 255))
        SDL_SetRenderDrawColor(renderer, bodyR, bodyG, bodyB, 255)
        var bodyRect = SDL_Rect(x: cx, y: cy, w: crateW, h: crateH)
        SDL_RenderFillRect(renderer, &bodyRect)

        // Highlight top strip (lighter brown)
        let topR = UInt8(min(255, Int(180) * Int(dimFactor) / 255))
        let topG = UInt8(min(255, Int(130) * Int(dimFactor) / 255))
        let topB = UInt8(min(255, Int(60) * Int(dimFactor) / 255))
        SDL_SetRenderDrawColor(renderer, topR, topG, topB, 255)
        var topRect = SDL_Rect(x: cx, y: cy, w: crateW, h: 3)
        SDL_RenderFillRect(renderer, &topRect)

        // Cross detail on crate face
        let crossR = UInt8(min(255, Int(100) * Int(dimFactor) / 255))
        let crossG = UInt8(min(255, Int(60) * Int(dimFactor) / 255))
        let crossB = UInt8(min(255, Int(20) * Int(dimFactor) / 255))
        SDL_SetRenderDrawColor(renderer, crossR, crossG, crossB, 255)
        // Horizontal line
        SDL_RenderDrawLine(renderer, cx + 1, cy + crateH / 2, cx + crateW - 2, cy + crateH / 2)
        // Vertical line
        SDL_RenderDrawLine(renderer, cx + crateW / 2, cy + 3, cx + crateW / 2, cy + crateH - 2)

        // Border
        SDL_SetRenderDrawColor(renderer, 60, 40, 20, dimFactor)
        SDL_RenderDrawRect(renderer, &bodyRect)
    }
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
            let trailRad = Double(proj.facing) / 256.0 * 2.0 * .pi
            let sinF = sin(trailRad)
            let cosF = cos(trailRad)
            // Draw multiple puffs behind the missile for a continuous trail
            for i in 1...4 {
                let dist = Double(i) * 5.0
                let alpha = UInt8(max(20, 160 - i * 35))
                let size: Int32 = Int32(max(2, 5 - i))
                SDL_SetRenderDrawColor(renderer, 180, 180, 180, alpha)
                let tx = screenX - Int32(sinF * dist)
                let ty = screenY + Int32(cosF * dist)
                var trailRect = SDL_Rect(x: tx - size / 2, y: ty - size / 2, w: size, h: size)
                SDL_RenderFillRect(renderer, &trailRect)
            }
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
