import CSDL2
import Foundation

// MARK: - Building Hit Test

/// Test if a world position is within a building's clickable area.
/// Building sprites are taller than their footprint (anchored at the bottom),
/// so the hit area extends upward beyond the footprint center to cover the
/// visible sprite region that users naturally click on.
func isWorldPosOnBuilding(worldX: Double, worldY: Double, building: GameObject) -> Bool {
    let size = buildingSize(building.typeName)
    let halfW = Double(size.w * 24) / 2.0
    let halfH = Double(size.h * 24) / 2.0
    // Horizontal: match footprint width
    guard abs(worldX - building.worldX) <= halfW else { return false }
    // Vertical: building sprite is bottom-anchored — it can extend above the footprint.
    // Accept clicks within the footprint (±halfH) plus extra above for the visible sprite.
    let dy = worldY - building.worldY
    return dy >= -halfH - 24.0 && dy <= halfH
}

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
        if dx > 8 || dy > 8 {
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

        var selectedAny = false
        for obj in world.objects {
            if obj.kind == .structure { continue }
            if obj.house != world.playerHouse { continue }  // Only select friendly units
            if obj.strength <= 0 { continue }
            if obj.worldX >= topLeft.worldX && obj.worldX <= bottomRight.worldX &&
               obj.worldY >= topLeft.worldY && obj.worldY <= bottomRight.worldY {
                obj.isSelected = true
                selectedAny = true
            }
        }

        // If the drag box was small and caught no units, treat as a single click
        // This lets players select buildings even with slight mouse movement
        let dragW = maxSX - minSX
        let dragH = maxSY - minSY
        if !selectedAny && dragW < 24 && dragH < 24 {
            let clickWorldPos = gameScreenToWorld(x, y)
            for obj in world.objects {
                if obj.kind != .structure { continue }
                if obj.house != world.playerHouse { continue }
                if obj.strength <= 0 { continue }
                if isWorldPosOnBuilding(worldX: clickWorldPos.worldX, worldY: clickWorldPos.worldY, building: obj) {
                    if session.isRepairMode {
                        if obj.strength < obj.maxStrength {
                            if obj.isRepairing {
                                obj.isRepairing = false
                                obj.mission = .guard_
                            } else {
                                obj.isRepairing = true
                                obj.mission = .repair
                            }
                        }
                        session.isRepairMode = false
                    } else {
                        obj.isSelected = true
                    }
                    break
                }
            }
        }
    } else {
        // Single click: find nearest unit/infantry within hit radius
        let worldPos = gameScreenToWorld(x, y)
        let hitRadius = 14.0 / renderState.gameZoomLevel

        // Check if clicking on a friendly building → select it (or toggle repair in repair mode)
        var clickedBuilding: GameObject? = nil
        for obj in world.objects {
            if obj.kind != .structure { continue }
            if obj.house != world.playerHouse { continue }
            if obj.strength <= 0 { continue }
            if isWorldPosOnBuilding(worldX: worldPos.worldX, worldY: worldPos.worldY, building: obj) {
                clickedBuilding = obj
                break
            }
        }

        if let building = clickedBuilding {
            if session.isRepairMode {
                // Repair mode: toggle repair on damaged buildings
                if building.strength < building.maxStrength {
                    if building.isRepairing {
                        building.isRepairing = false
                        building.mission = .guard_
                    } else {
                        building.isRepairing = true
                        building.mission = .repair
                    }
                }
                session.isRepairMode = false
            } else {
                // Normal click: select the building
                if !shiftHeld { world.deselectAll() }
                building.isSelected = true
            }
            input.selectionBoxStartX = nil
            input.selectionBoxStartY = nil
            input.selectionBoxEndX = nil
            input.selectionBoxEndY = nil
            input.isDragging = false
            return
        }

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

        // MCV deploy: if a selected MCV is clicked on, deploy it
        if let clicked = nearest,
           clicked.isSelected,
           clicked.isMCV,
           clicked.house == world.playerHouse,
           clicked.mission != .unload {
            clicked.mission = .unload
            audioManager.play(audioManager.unitAcknowledgeSound())
            // Clear selection state
            input.selectionBoxStartX = nil
            input.selectionBoxStartY = nil
            input.selectionBoxEndX = nil
            input.selectionBoxEndY = nil
            input.isDragging = false
            return
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

/// Check if a building type is a production structure (can have rally points)
func isProductionStructure(_ typeName: String) -> Bool {
    let upper = typeName.uppercased()
    return ["PYLE", "HAND", "WEAP", "AFLD", "HPAD"].contains(upper)
}

func handleGameRightClick(_ x: Int32, _ y: Int32, shiftHeld: Bool = false) {
    guard let world = session.world else { return }
    let worldPos = gameScreenToWorld(x, y)

    // Cancel patrol mode on right-click
    if session.isPatrolMode {
        // If we have waypoints, commit them to selected units
        if !session.patrolModeWaypoints.isEmpty {
            for obj in world.selectedObjects() {
                if obj.kind == .structure { continue }
                if obj.house != world.playerHouse { continue }
                obj.patrolWaypoints = session.patrolModeWaypoints
                obj.patrolIndex = 0
                obj.mission = .patrol
                obj.moveTargetX = nil
                obj.moveTargetY = nil
                obj.movePath = []
                obj.attackTarget = nil
                obj.isAttackMoving = false
                obj.moveWaypoints = []
            }
            audioManager.play(audioManager.unitAcknowledgeSound())
        }
        session.isPatrolMode = false
        session.patrolModeWaypoints = []
        return
    }

    let selected = world.selectedObjects()
    if selected.isEmpty { return }

    // Check if all selected objects are production structures -> set rally point
    let playerSelected = selected.filter { $0.house == world.playerHouse }
    let allProductionBuildings = !playerSelected.isEmpty && playerSelected.allSatisfy {
        $0.kind == .structure && isProductionStructure($0.typeName)
    }
    if allProductionBuildings {
        for obj in playerSelected {
            obj.rallyPointX = worldPos.worldX
            obj.rallyPointY = worldPos.worldY
        }
        audioManager.play(audioManager.unitAcknowledgeSound())
        return
    }

    // Check if right-clicking on an enemy → attack order
    if let enemy = findEnemyAtWorldPos(worldX: worldPos.worldX, worldY: worldPos.worldY) {
        for obj in selected {
            if obj.kind == .structure { continue }
            obj.attackTarget = enemy.id
            obj.movePath = []
            obj.isAttackMoving = false
            obj.moveWaypoints = []
            obj.groupMoveSpeed = nil
            // Special missions when targeting a building
            if enemy.kind == .structure {
                if obj.isCommando {
                    // Commando targeting a building → sabotage mission (C4)
                    obj.mission = .sabotage
                } else if obj.kind == .infantry,
                          let data = getInfantryTypeDataByName(obj.typeName.uppercased()),
                          data.canCapture {
                    // Engineer targeting an enemy building → capture mission
                    obj.mission = .capture
                } else {
                    obj.mission = .attack
                }
            } else {
                obj.mission = .attack
            }
        }
        audioManager.play(audioManager.unitAcknowledgeSound())
        return
    }

    // Formation spread: arrange targets in a grid so units don't pile up
    let movable = selected.filter { $0.kind != .structure }
    let count = movable.count

    // Squad speed matching: compute minimum speed for mixed groups
    let groupSpeed: Double?
    if count >= 2 {
        let speeds = movable.map { $0.effectiveSpeed }
        let minSpeed = speeds.min() ?? 0
        let maxSpeed = speeds.max() ?? 0
        groupSpeed = (minSpeed < maxSpeed) ? minSpeed : nil
    } else {
        groupSpeed = nil
    }
    // Single unit: clear any previous group speed
    if count == 1 {
        movable[0].groupMoveSpeed = nil
    }

    let cols = max(1, Int(ceil(sqrt(Double(count)))))
    let spacing = 36.0  // 1.5 cells apart to avoid stacking

    for (i, obj) in movable.enumerated() {
        let row = i / cols
        let col = i % cols
        let offsetX = (Double(col) - Double(cols - 1) / 2.0) * spacing
        let offsetY = (Double(row) - Double(max(0, (count - 1) / cols)) / 2.0) * spacing
        // Add small random jitter (±6px) so units don't converge to exact grid points
        let jitterX = Double.random(in: -6.0...6.0)
        let jitterY = Double.random(in: -6.0...6.0)

        var tgtX = worldPos.worldX + offsetX + jitterX
        var tgtY = worldPos.worldY + offsetY + jitterY

        // Clamp targets to world bounds
        tgtX = max(12, min(64 * 24 - 12, tgtX))
        tgtY = max(12, min(64 * 24 - 12, tgtY))

        // Validate target cell is passable for this unit's speed type
        let tgtCellX = Int(tgtX) / 24
        let tgtCellY = Int(tgtY) / 24
        if !isCellPassable(cellX: tgtCellX, cellY: tgtCellY, ignoring: obj, speedType: obj.cachedSpeedType) {
            // Find nearest passable cell
            var bestX = tgtCellX, bestY = tgtCellY
            var bestDist = Double.infinity
            for dy in -3...3 {
                for dx in -3...3 {
                    let nx = tgtCellX + dx
                    let ny = tgtCellY + dy
                    if nx >= 0 && nx < 64 && ny >= 0 && ny < 64 {
                        let passMap = passabilityMap(for: obj.cachedSpeedType)
                        if passMap[ny * 64 + nx] {
                            let dist = sqrt(Double(dx * dx + dy * dy))
                            if dist < bestDist {
                                bestDist = dist
                                bestX = nx
                                bestY = ny
                            }
                        }
                    }
                }
            }
            if bestDist == Double.infinity {
                continue  // No passable cell nearby, skip this unit
            }
            tgtX = Double(bestX * 24) + 12.0
            tgtY = Double(bestY * 24) + 12.0
        }

        if shiftHeld {
            // Waypoint queuing: append to waypoint list
            if obj.mission == .move && obj.moveTargetX != nil {
                // Already moving — queue this as a waypoint
                obj.moveWaypoints.append((x: tgtX, y: tgtY))
            } else {
                // Not moving yet — start moving to first point
                obj.moveTargetX = tgtX
                obj.moveTargetY = tgtY
                obj.attackTarget = nil
                obj.isAttackMoving = false
                obj.mission = .move
                obj.movePath = []
            }
            obj.groupMoveSpeed = groupSpeed
        } else {
            // Normal move: clear waypoints and set target directly
            obj.moveTargetX = tgtX
            obj.moveTargetY = tgtY
            obj.attackTarget = nil
            obj.isAttackMoving = false
            obj.mission = .move
            obj.movePath = []
            obj.moveWaypoints = []
            obj.groupMoveSpeed = groupSpeed
        }
    }
    audioManager.play(audioManager.unitAcknowledgeSound())
}
