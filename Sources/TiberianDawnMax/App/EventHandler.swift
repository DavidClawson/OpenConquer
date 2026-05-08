import CSDL2
import Foundation

// MARK: - Event Handling (thin dispatchers to MenuScreen)

func handleKeyDown(_ key: Int32) {
    // Global: F3 toggles performance overlay
    if key == Int32(SDLK_F3.rawValue) {
        renderState.perfShowOverlay.toggle()
    }
    session.currentScreen.handleKeyDown(key)
}

func handleMouseMotion(_ event: SDL_Event) {
    input.mouseX = event.motion.x
    input.mouseY = event.motion.y
    session.currentScreen.handleMouseMotion(
        event.motion.x, event.motion.y,
        xrel: event.motion.xrel, yrel: event.motion.yrel
    )
}

func handleMouseButtonDown(_ event: SDL_Event) {
    session.currentScreen.handleMouseDown(
        event.button.x, event.button.y,
        button: event.button.button
    )
}

func handleMouseButtonUp(_ event: SDL_Event) {
    input.isPanning = false
    session.currentScreen.handleMouseUp(
        event.button.x, event.button.y,
        button: event.button.button
    )
}

func handleMouseWheel(_ event: SDL_Event) {
    // SDL gives integer y deltas (+1 per "click" on most mice; some trackpads
    // emit fractions but SDL clamps to 1 minimum on a meaningful scroll).
    let dy = event.wheel.y
    if dy == 0 { return }
    session.currentScreen.handleMouseWheel(
        Int32(dy),
        atX: input.mouseX, atY: input.mouseY
    )
}

func handleWindowEvent(_ event: SDL_Event) {
    let evt = event.window.event
    // SIZE_CHANGED fires for both user-driven and programmatic resizes
    // (and for moves between displays with different DPI). RESIZED is a
    // subset of SIZE_CHANGED — handling SIZE_CHANGED covers both.
    if evt == UInt8(SDL_WINDOWEVENT_SIZE_CHANGED.rawValue) ||
       evt == UInt8(SDL_WINDOWEVENT_RESIZED.rawValue) {
        let w = event.window.data1
        let h = event.window.data2
        if w > 0 && h > 0 {
            renderState.windowWidth = w
            renderState.windowHeight = h
            if let ren = renderState.sdlRenderer {
                SDL_RenderSetLogicalSize(ren, w, h)
                // HiDPI scale can change when the window crosses displays.
                var drawW: Int32 = 0, drawH: Int32 = 0
                SDL_GetRendererOutputSize(ren, &drawW, &drawH)
                if w > 0 {
                    renderState.displayScale = Double(drawW) / Double(w)
                }
            }
            applyWindowResizeSideEffects()
            WindowConfig.save(width: w, height: h)
        }
    }
}

/// Re-fit the in-game camera and zoom after the window changes size.
/// Only applies while a mission is playing — menus already lay out from
/// `renderState.windowWidth/Height` each frame so they're already responsive.
private func applyWindowResizeSideEffects() {
    guard session.isPlaying else { return }
    // Empty space outside the map is allowed (matches the original game's
    // look on bounded missions). Just clamp the camera so it doesn't drift
    // into negative coords when a resize widens the viewport.
    clampGameCamera()
}

func handleContinuousInput() {
    session.currentScreen.handleContinuousInput()
}
