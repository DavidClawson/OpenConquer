import CSDL2
import Foundation

// MARK: - Coordinate Conversion

func gameScreenToWorld(_ screenX: Int32, _ screenY: Int32) -> (worldX: Double, worldY: Double) {
    let wx = renderState.gameCameraX + Double(screenX) / renderState.gameZoomLevel
    let wy = renderState.gameCameraY + Double(screenY) / renderState.gameZoomLevel
    return (wx, wy)
}

func gameWorldToScreen(_ worldX: Double, _ worldY: Double) -> (screenX: Int32, screenY: Int32) {
    let sx = Int32((worldX - renderState.gameCameraX) * renderState.gameZoomLevel)
    let sy = Int32((worldY - renderState.gameCameraY) * renderState.gameZoomLevel)
    return (sx, sy)
}

// MARK: - Input Handling

func handleGameLeftDown(_ x: Int32, _ y: Int32, shiftHeld: Bool) {
    input.selectionBoxStartX = x
    input.selectionBoxStartY = y
    input.selectionBoxEndX = x
    input.selectionBoxEndY = y
    input.isDragging = false
}

func handleGameLeftDrag(_ x: Int32, _ y: Int32) {
    input.selectionBoxEndX = x
    input.selectionBoxEndY = y
    if let sx = input.selectionBoxStartX, let sy = input.selectionBoxStartY {
        let dx = abs(Int(x) - Int(sx))
        let dy = abs(Int(y) - Int(sy))
        if dx > 4 || dy > 4 {
            input.isDragging = true
        }
    }
}

func handleGameLeftUp(_ x: Int32, _ y: Int32, shiftHeld: Bool) {
    guard let world = session.world else { return }

    if input.isDragging, let sx = input.selectionBoxStartX, let sy = input.selectionBoxStartY {
        // Box select: find all units/infantry within the screen-space rectangle
        let minSX = min(Int(sx), Int(x))
        let maxSX = max(Int(sx), Int(x))
        let minSY = min(Int(sy), Int(y))
        let maxSY = max(Int(sy), Int(y))

        let topLeft = gameScreenToWorld(Int32(minSX), Int32(minSY))
        let bottomRight = gameScreenToWorld(Int32(maxSX), Int32(maxSY))

        if !shiftHeld {
            world.deselectAll()
        }

        for obj in world.objects {
            if obj.kind == .structure { continue }
            if obj.worldX >= topLeft.worldX && obj.worldX <= bottomRight.worldX &&
               obj.worldY >= topLeft.worldY && obj.worldY <= bottomRight.worldY {
                obj.isSelected = true
            }
        }
    } else {
        // Single click: find nearest unit/infantry within hit radius
        let worldPos = gameScreenToWorld(x, y)
        let hitRadius = 14.0 / renderState.gameZoomLevel

        var nearest: GameObject? = nil
        var nearestDist = Double.infinity

        for obj in world.objects {
            if obj.kind == .structure { continue }
            let dx = obj.worldX - worldPos.worldX
            let dy = obj.worldY - worldPos.worldY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < hitRadius && dist < nearestDist {
                nearest = obj
                nearestDist = dist
            }
        }

        if !shiftHeld {
            world.deselectAll()
        }

        if let obj = nearest {
            obj.isSelected = !obj.isSelected || !shiftHeld
            if obj.isSelected && obj.house == world.playerHouse {
                audioManager.play(audioManager.unitReportSound())
            }
        }
    }

    // Clear drag state
    input.selectionBoxStartX = nil
    input.selectionBoxStartY = nil
    input.selectionBoxEndX = nil
    input.selectionBoxEndY = nil
    input.isDragging = false
}

func handleGameRightClick(_ x: Int32, _ y: Int32) {
    guard let world = session.world else { return }
    let worldPos = gameScreenToWorld(x, y)

    let selected = world.selectedObjects()
    if selected.isEmpty { return }

    // Check if right-clicking on an enemy → attack order
    if let enemy = findEnemyAtWorldPos(worldX: worldPos.worldX, worldY: worldPos.worldY) {
        for obj in selected {
            if obj.kind == .structure { continue }
            obj.attackTarget = enemy.id
            obj.mission = .attack
            obj.movePath = []
        }
        audioManager.play(audioManager.unitAcknowledgeSound())
        return
    }

    // Formation spread: arrange targets in a grid so units don't pile up
    let count = selected.count
    let cols = Int(ceil(sqrt(Double(count))))
    let spacing = 26.0  // Slightly larger than cell size

    for (i, obj) in selected.enumerated() {
        if obj.kind == .structure { continue }
        let row = i / cols
        let col = i % cols
        let offsetX = (Double(col) - Double(cols - 1) / 2.0) * spacing
        let offsetY = (Double(row) - Double((count - 1) / cols) / 2.0) * spacing

        obj.moveTargetX = worldPos.worldX + offsetX
        obj.moveTargetY = worldPos.worldY + offsetY

        // Clamp targets to world bounds
        obj.moveTargetX = max(12, min(64 * 24 - 12, obj.moveTargetX!))
        obj.moveTargetY = max(12, min(64 * 24 - 12, obj.moveTargetY!))

        obj.attackTarget = nil
        obj.mission = .move
        obj.movePath = []  // Clear old path so A* recalculates
    }
    audioManager.play(audioManager.unitAcknowledgeSound())
}
