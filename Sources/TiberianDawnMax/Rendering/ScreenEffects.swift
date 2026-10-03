import Foundation
import OpenConquerCore

// MARK: - Screen Effects
// Superweapon flash, shake and ion beam. The sim announces the strike on the
// event bus; this sets up and fades the visuals.

func subscribeScreenEffects() {
    eventBus.subscribe(id: "screen-effects") { event in
        switch event {
        case .ionCannonStrike(let x, let y):
            renderState.screenFlashAlpha = 200
            renderState.screenFlashR = 180
            renderState.screenFlashG = 220
            renderState.screenFlashB = 255
            renderState.ionBeamWorldX = x
            renderState.ionBeamWorldY = y
            renderState.ionBeamTimer = 30  // ~2 seconds at 15 FPS
        case .nuclearDetonation:
            renderState.screenFlashAlpha = 255
            renderState.screenFlashR = 255
            renderState.screenFlashG = 255
            renderState.screenFlashB = 240
            renderState.screenShakeDuration = 45  // ~3 seconds
            renderState.screenShakeIntensity = 8.0
        default:
            break
        }
    }
}

// MARK: - Screen Effects Tick

/// Fade the flash, shake and beam once per sim tick. Cosmetic, so the shake
/// uses the system RNG rather than the seeded sim RNG.
func tickScreenEffects() {
    // Fade screen flash
    if renderState.screenFlashAlpha > 0 {
        let decay: UInt8 = 12
        if renderState.screenFlashAlpha > decay {
            renderState.screenFlashAlpha -= decay
        } else {
            renderState.screenFlashAlpha = 0
        }
    }

    // Tick screen shake
    if renderState.screenShakeDuration > 0 {
        renderState.screenShakeDuration -= 1
        let progress = Double(renderState.screenShakeDuration) / 45.0
        let intensity = renderState.screenShakeIntensity * progress
        renderState.screenShakeOffsetX = Int32(Double.random(in: -intensity...intensity))
        renderState.screenShakeOffsetY = Int32(Double.random(in: -intensity...intensity))
    } else {
        renderState.screenShakeOffsetX = 0
        renderState.screenShakeOffsetY = 0
    }

    // Tick ion beam visual
    if renderState.ionBeamTimer > 0 {
        renderState.ionBeamTimer -= 1
    }
}
