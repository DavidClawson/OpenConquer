import CSDL2
import OpenConquerCore

// MARK: - Animation Rendering
// Explosion/fire/smoke animations, ground smudges, and the ion cannon beam.

// MARK: - Animation Rendering

/// Render active animations (explosions, fires, smoke)
func renderAnimations(_ renderer: OpaquePointer?, camX: Int, camY: Int, vw: Int32, vh: Int32) {
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)

    for anim in session.activeAnimations {
        if anim.isFinished { continue }

        let screenX = Int32(anim.worldX) - Int32(camX)
        let screenY = Int32(anim.worldY) - Int32(camY)

        // Cull off-screen animations
        let maxSize = Int32(anim.data.size)
        if screenX + maxSize < 0 || screenY + maxSize < 0 ||
           screenX - maxSize > vw || screenY - maxSize > vh { continue }

        // Try to render from SHP sprite (animations are plain .SHP, not theater-specific)
        if let info = getObjectTexture(renderer, typeName: anim.data.name,
                                       frame: anim.currentFrame, house: .neutral,
                                       theater: nil) {
            let drawX = screenX - Int32(info.width) / 2
            let drawY = screenY - Int32(info.height) / 2
            var dstRect = SDL_Rect(x: drawX, y: drawY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        } else {
            // Check if SHP exists but the current frame exceeds its frame count
            // (animation is done — don't show ugly procedural rectangles)
            let animSpriteName = spriteNameOverrides[anim.data.name.uppercased()] ?? anim.data.name.uppercased()
            if let shp = renderState.objectSHPCache[animSpriteName],
               anim.currentFrame >= shp.frames.count {
                anim.isFinished = true
            } else {
                // SHP not loaded yet or truly missing — use procedural fallback
                renderProceduralExplosion(renderer, anim: anim, screenX: screenX, screenY: screenY)
            }
        }
    }

}

/// Render smudges (scorch marks and craters). These are ground decals, so they
/// must be drawn BEFORE buildings and units — otherwise a crater created before
/// a building/vehicle moved onto the cell paints over it. Called from an early
/// pass, right after terrain.
func renderSmudges(_ renderer: OpaquePointer?, camX: Int, camY: Int, vw: Int32, vh: Int32) {
    for smudge in (session.world?.map.smudges ?? []) {
        let cellX = smudge.cell % 64
        let cellY = smudge.cell / 64
        let screenX = Int32(cellX * 24 - camX)
        let screenY = Int32(cellY * 24 - camY)
        if screenX > vw || screenY > vh || screenX + 24 < 0 || screenY + 24 < 0 { continue }

        // Try SHP first
        let theater = session.world?.theater ?? .temperate
        if let info = getObjectTexture(renderer, typeName: smudge.type.rawValue,
                                       frame: 0, house: .neutral, theater: theater) {
            var dstRect = SDL_Rect(x: screenX, y: screenY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        } else {
            // Procedural fallback: dark circle for craters, dark oval for scorch
            SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
            SDL_SetRenderDrawColor(renderer, 20, 15, 10,
                                   smudge.type.isCrater ? 140 : 80)
            let size: Int32 = smudge.type.isCrater ? 16 : 20
            var rect = SDL_Rect(x: screenX + (24 - size) / 2, y: screenY + (24 - size) / 2,
                               w: size, h: size)
            SDL_RenderFillRect(renderer, &rect)
        }
    }
}

/// Procedural explosion effect when SHP not available
func renderProceduralExplosion(_ renderer: OpaquePointer?, anim: GameAnimation, screenX: Int32, screenY: Int32) {
    let maxFrames = anim.data.stages > 0 ? anim.data.stages : 30
    let progress = Double(anim.currentFrame) / Double(max(1, maxFrames))
    let halfSize = Int32(anim.data.size) / 2

    // Explosion: expanding circle that fades
    let radius = Int32(Double(halfSize) * min(1.0, progress * 2.0))
    let alpha = UInt8(max(0, min(255, Int(255.0 * (1.0 - progress)))))

    // Color and shape based on type
    let r: UInt8, g: UInt8, b: UInt8
    switch anim.type {
    case .muzzleFlash:
        // Small bright white-yellow flash, fades fast
        SDL_SetRenderDrawColor(renderer, 255, 255, 200, UInt8(max(0, min(255, 255 - Int(progress * 400)))))
        var flash = SDL_Rect(x: screenX - 3, y: screenY - 3, w: 6, h: 6)
        SDL_RenderFillRect(renderer, &flash)
        return
    case .burnSmall, .burnMed, .burnBig,
         .onFireSmall, .onFireMed, .onFireBig, .fireSmall, .fireMed, .fireMed2, .fireTiny:
        // Persistent fire/smoke effects — render as thin grey smoke puff so a
        // missing SHP doesn't dominate the screen with a glowing red square.
        SDL_SetRenderDrawColor(renderer, 70, 65, 60, alpha / 4)
        let puff = Int32(max(2, Double(halfSize) * 0.4))
        var puffRect = SDL_Rect(x: screenX - puff / 2, y: screenY - puff / 2, w: puff, h: puff)
        SDL_RenderFillRect(renderer, &puffRect)
        return
    case .napalm1, .napalm2, .napalm3:
        r = 255; g = UInt8(max(0, 160 - Int(progress * 160))); b = 0
    case .piff, .piffpiff:
        r = 255; g = 255; b = 200
    case .smokeM, .smokePuff:
        r = 80; g = 80; b = 80
    case .ionCannon:
        r = 100; g = 150; b = 255
    default:
        r = 255; g = UInt8(max(0, 200 - Int(progress * 200))); b = 0
    }

    SDL_SetRenderDrawColor(renderer, r, g, b, alpha)

    // Core
    var coreRect = SDL_Rect(x: screenX - radius, y: screenY - radius,
                           w: radius * 2, h: radius * 2)
    SDL_RenderFillRect(renderer, &coreRect)

    // Outer glow (larger, more transparent)
    if radius > 2 {
        SDL_SetRenderDrawColor(renderer, r, g / 2, 0, alpha / 3)
        var glowRect = SDL_Rect(x: screenX - radius - 2, y: screenY - radius - 2,
                               w: radius * 2 + 4, h: radius * 2 + 4)
        SDL_RenderDrawRect(renderer, &glowRect)
    }
}

// MARK: - Ion Cannon Beam Effect

/// Render procedural ion cannon beam from top of screen to target
func renderIonBeam(_ renderer: OpaquePointer?, camX: Int, camY: Int) {
    guard renderState.ionBeamTimer > 0 else { return }

    let screenX = Int32(renderState.ionBeamWorldX) - Int32(camX)
    let screenY = Int32(renderState.ionBeamWorldY) - Int32(camY)

    // Beam fades over time
    let progress = Double(renderState.ionBeamTimer) / 30.0
    let alpha = UInt8(max(0, min(255, Int(255.0 * progress))))

    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)

    // Wide outer glow
    let outerWidth: Int32 = Int32(12.0 * progress)
    SDL_SetRenderDrawColor(renderer, 80, 120, 255, alpha / 4)
    for dx in -outerWidth...outerWidth {
        SDL_RenderDrawLine(renderer, screenX + dx, -100, screenX + dx, screenY)
    }

    // Medium blue beam
    let midWidth: Int32 = Int32(6.0 * progress)
    SDL_SetRenderDrawColor(renderer, 120, 180, 255, alpha / 2)
    for dx in -midWidth...midWidth {
        SDL_RenderDrawLine(renderer, screenX + dx, -100, screenX + dx, screenY)
    }

    // Inner bright white-blue core
    let coreWidth: Int32 = Int32(2.0 * progress)
    SDL_SetRenderDrawColor(renderer, 200, 230, 255, alpha)
    for dx in -coreWidth...coreWidth {
        SDL_RenderDrawLine(renderer, screenX + dx, -100, screenX + dx, screenY)
    }

    // Impact glow at target
    let glowRadius = Int32(20.0 * progress)
    SDL_SetRenderDrawColor(renderer, 180, 220, 255, alpha / 3)
    var glowRect = SDL_Rect(x: screenX - glowRadius, y: screenY - glowRadius,
                           w: glowRadius * 2, h: glowRadius * 2)
    SDL_RenderFillRect(renderer, &glowRect)

    // Bright center flash at impact
    let flashR = Int32(8.0 * progress)
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, alpha)
    var flashRect = SDL_Rect(x: screenX - flashR, y: screenY - flashR,
                            w: flashR * 2, h: flashR * 2)
    SDL_RenderFillRect(renderer, &flashRect)
}
