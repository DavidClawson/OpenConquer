import CSDL2
import Foundation

// MARK: - Frame Clock
// Drives the simulation from real time: fixed 15 Hz ticks out of a variable
// frame rate, plus the interpolation factor the renderer uses between ticks.

func updateGame() {
    syncPresentationWithWorld()
    let now = SDL_GetTicks()
    if app.lastTickTime == 0 {
        app.lastTickTime = now
        return
    }

    let elapsed = now - app.lastTickTime
    app.lastTickTime = now
    app.tickAccumulator += elapsed

    // Run game ticks at fixed 15 FPS rate
    while app.tickAccumulator >= tickDurationMs {
        app.tickAccumulator -= tickDurationMs
        gameTick()
        tickScreenEffects()
    }

    tickCommandoQuips()

    // Compute interpolation factor for smooth rendering between ticks
    app.renderInterpolation = Double(app.tickAccumulator) / Double(tickDurationMs)
}

/// When a mission starts, restarts or loads, the simulation builds a new
/// world; set the presentation up for it: the theater palette, fresh sprite
/// caches, a fresh classic sidebar, and a reset clock so the loop doesn't try to catch up.
func syncPresentationWithWorld() {
    guard let world = session.world, world !== app.presentedWorld else { return }
    app.presentedWorld = world
    let palName: String
    switch world.theater {
    case .temperate: palName = "TEMPERAT.PAL"
    case .desert: palName = "DESERT.PAL"
    case .winter: palName = "WINTER.PAL"
    }
    renderState.gamePalette = loadPalette(palName)
    renderState.objectFailedSHPs.removeAll()
    renderState.terrainFailedSHPs.removeAll()
    resetClassicSidebarState()
    app.lastTickTime = 0
    app.tickAccumulator = 0
}
