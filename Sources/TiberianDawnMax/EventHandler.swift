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

func handleWindowEvent(_ event: SDL_Event) {
    if event.window.event == UInt8(SDL_WINDOWEVENT_RESIZED.rawValue) {
        renderState.windowWidth = event.window.data1
        renderState.windowHeight = event.window.data2
    }
}

func handleContinuousInput() {
    session.currentScreen.handleContinuousInput()
}
