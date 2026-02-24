import CSDL2
import Foundation

// MARK: - Input Manager
// Consolidates all mouse/input state that was scattered across main.swift,
// GameRenderer.swift, and MapRenderer.swift.

class InputManager {
    // Screen-space mouse position
    var mouseX: Int32 = 0
    var mouseY: Int32 = 0

    // Mouse panning state for map viewer
    var isPanning: Bool = false
    var lastMouseX: Int32 = 0
    var lastMouseY: Int32 = 0

    // World-space mouse position for info panel
    var mouseWorldX: Int = 0
    var mouseWorldY: Int = 0

    // Selection drag state
    var selectionBoxStartX: Int32? = nil
    var selectionBoxStartY: Int32? = nil
    var selectionBoxEndX: Int32? = nil
    var selectionBoxEndY: Int32? = nil
    var isDragging: Bool = false

    // Control group double-tap tracking
    var lastGroupKey: Int = -1
    var lastGroupKeyTick: Int = 0

    // Minimap drag state
    var isDraggingMinimap: Bool = false
}

/// Global input manager instance
var input = InputManager()
