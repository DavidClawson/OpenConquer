import CSDL2
import Foundation
import OpenConquerCore

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
    // Only a release that pairs with handleGameLeftDown is a selection. Mode
    // clicks (repair/sell, attack-move, superweapon) are consumed on mouse-down
    // and never start a box, so their release must not reselect or deselect.
    guard input.selectionBoxStartX != nil else { return }

    if input.isDragging, let sx = input.selectionBoxStartX, let sy = input.selectionBoxStartY {
        // Box select: find all units/infantry within the screen-space rectangle
        let minSX = min(Int(sx), Int(x))
        let maxSX = max(Int(sx), Int(x))
        let minSY = min(Int(sy), Int(y))
        let maxSY = max(Int(sy), Int(y))

        let topLeft = gameScreenToWorld(Int32(minSX), Int32(minSY))
        let bottomRight = gameScreenToWorld(Int32(maxSX), Int32(maxSY))

        // Classic controls: a small drag that boxes none of our units is a
        // shaky click, so it commands the selection rather than clearing it.
        if UserSettings.controlScheme == .classic && maxSX - minSX < 24 && maxSY - minSY < 24 {
            let boxesOwnUnit = world.objects.contains { obj in
                obj.kind != .structure && obj.house == world.playerHouse && obj.strength > 0 &&
                obj.worldX >= topLeft.worldX && obj.worldX <= bottomRight.worldX &&
                obj.worldY >= topLeft.worldY && obj.worldY <= bottomRight.worldY
            }
            let clickPos = gameScreenToWorld(x, y)
            if !boxesOwnUnit &&
               classicClickIsCommand(worldX: clickPos.worldX, worldY: clickPos.worldY, world: world) {
                handleGameRightClick(x, y, shiftHeld: shiftHeld)
                input.selectionBoxStartX = nil
                input.selectionBoxStartY = nil
                input.selectionBoxEndX = nil
                input.selectionBoxEndY = nil
                input.isDragging = false
                return
            }
        }

        if !shiftHeld {
            world.deselectAll()
        }

        var selectedAny = false
        for obj in world.objects {
            if obj.kind == .structure { continue }
            if obj.house != world.playerHouse { continue }  // Only select friendly units
            if obj.strength <= 0 || obj.isInLimbo { continue }  // aboard a transport
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
                    obj.isSelected = true
                    break
                }
            }
        }
    } else {
        // Single click: find nearest unit/infantry within hit radius
        let worldPos = gameScreenToWorld(x, y)
        let hitRadius = 14.0 / renderState.gameZoomLevel

        // Classic controls: with units selected, a plain left-click is the
        // context command (move/attack/enter/dock) that Modern puts on the
        // right button.
        if UserSettings.controlScheme == .classic,
           classicClickIsCommand(worldX: worldPos.worldX, worldY: worldPos.worldY, world: world) {
            handleGameRightClick(x, y, shiftHeld: shiftHeld)
            input.selectionBoxStartX = nil
            input.selectionBoxStartY = nil
            input.selectionBoxEndX = nil
            input.selectionBoxEndY = nil
            input.isDragging = false
            return
        }

        // Check if clicking on a friendly building → select it
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
            if !shiftHeld { world.deselectAll() }
            building.isSelected = true
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
            if obj.kind == .structure || obj.isInLimbo { continue }
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
            issue(.deploy(mcv: clicked.id))
            gameAudio.play(gameAudio.unitAcknowledgeSound())
            // Clear selection state
            input.selectionBoxStartX = nil
            input.selectionBoxStartY = nil
            input.selectionBoxEndX = nil
            input.selectionBoxEndY = nil
            input.isDragging = false
            return
        }

        // Clicking our own selected, loaded transport unloads it (classic
        // ACTION_SELF). A Chinook lands first — see the .unload aircraft case.
        if let transport = ownTransport(atWorldX: worldPos.worldX, worldY: worldPos.worldY, world: world),
           transport.isSelected, transport.hasCargo, transport.mission != .unload {
            issue(.unload(transport: transport.id))
            gameAudio.play(gameAudio.unitAcknowledgeSound())
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
                gameAudio.play(gameAudio.selectResponse(for: obj))
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

/// Our own live transport (APC, Chinook) under a world position. The hit
/// area follows the sprite: the Chinook is ~2 cells long, so its 14px unit
/// radius missed most clicks on its body. Aircraft are drawn `altitude` px
/// above their ground position, so the test is against the drawn spot.
func ownTransport(atWorldX worldX: Double, worldY: Double, world: GameWorld) -> GameObject? {
    world.objects.first { obj in
        guard obj.kind == .unit, obj.house == world.playerHouse, obj.strength > 0,
              !obj.isInLimbo, obj.isTransporter else { return false }
        let radius = obj.isAircraft ? 24.0 : 14.0
        let drawnY = obj.worldY - Double(obj.altitude)
        return abs(obj.worldX - worldX) < radius && abs(drawnY - worldY) < radius
    }
}

/// Classic (1995) controls: does a left-click here command the current
/// selection rather than select something? Mirrors What_Action: with player
/// units selected, enemies, open ground, and service targets (refinery for a
/// harvester, repair bay for a vehicle, transport for infantry) are commands;
/// any other object of ours is ACTION_SELECT. A selected MCV clicked on itself
/// falls through to the deploy path in handleGameLeftUp.
func classicClickIsCommand(worldX: Double, worldY: Double, world: GameWorld) -> Bool {
    let movable = world.selectedObjects().filter {
        $0.kind != .structure && $0.house == world.playerHouse && $0.strength > 0
    }
    if movable.isEmpty { return false }

    if findEnemyAtWorldPos(worldX: worldX, worldY: worldY) != nil { return true }

    if let building = world.objects.first(where: {
        $0.kind == .structure && $0.house == world.playerHouse && $0.strength > 0 &&
        isWorldPosOnBuilding(worldX: worldX, worldY: worldY, building: $0)
    }) {
        switch building.typeName.uppercased() {
        case "PROC": return movable.contains { $0.isHarvester }
        case "FIX":  return movable.contains { $0.kind == .unit && !$0.isAircraft }
        default:     return false
        }
    }

    if let transport = ownTransport(atWorldX: worldX, worldY: worldY, world: world) {
        return !transport.isSelected && movable.contains { $0.kind == .infantry }
    }

    let hitRadius = 14.0 / renderState.gameZoomLevel
    if world.objects.contains(where: { obj in
        obj.kind != .structure && obj.house == world.playerHouse && obj.strength > 0 &&
        !obj.isInLimbo && hypot(obj.worldX - worldX, obj.worldY - worldY) < hitRadius
    }) {
        return false
    }

    return true
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
            issue(.patrol(units: world.selectedObjects().map(\.id),
                          waypoints: session.patrolModeWaypoints.map { MapPoint(x: $0.x, y: $0.y) }))
            gameAudio.play(gameAudio.unitAcknowledgeSound())
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
        issue(.setRallyPoint(buildings: playerSelected.map(\.id),
                             at: MapPoint(x: worldPos.worldX, y: worldPos.worldY)))
        gameAudio.play(gameAudio.unitAcknowledgeSound())
        return
    }

    // Check if right-clicking on an enemy → attack order
    if let enemy = findEnemyAtWorldPos(worldX: worldPos.worldX, worldY: worldPos.worldY) {
        issue(.attack(units: selected.map(\.id), target: enemy.id))
        // A commando ordered onto a building plants C4: "I've got a present for ya"
        // (Vanilla Response_Sabotage). Otherwise the attack reply.
        let attackers = selected.filter { $0.kind != .structure }
        if enemy.kind == .structure && attackers.first?.isCommando == true {
            gameAudio.play(.ramboPresent)
        } else {
            gameAudio.play(gameAudio.attackResponse(for: attackers))
        }
        return
    }

    // Right-clicking one of our own transports (APC/TRAN) with infantry
    // selected orders them aboard (classic ACTION_ENTER). Boarding is what
    // drives the civ-evac missions: a civilian entering a transport aircraft
    // makes it fly off the map (AIRCRAFT.CPP:2530-2542).
    if let transport = ownTransport(atWorldX: worldPos.worldX, worldY: worldPos.worldY, world: world) {
        let boarders = selected.filter { $0.kind == .infantry && $0.house == world.playerHouse }
        if !boarders.isEmpty && transport.passengerCount < transport.maxPassengers {
            issue(.enter(units: boarders.map(\.id), transport: transport.id))
            gameAudio.play(gameAudio.unitAcknowledgeSound())
            return
        }
    }

    // Right-clicking one of our own special-service buildings issues a
    // service order rather than a move:
    //   • refinery (PROC) + harvester(s) → go dock & unload there
    //   • repair bay (FIX) + vehicle(s)  → drive in and get repaired
    // Mirrors the original's context-sensitive deliver / repair cursors.
    if let building = world.objects.first(where: {
        $0.kind == .structure && $0.house == world.playerHouse && $0.strength > 0 &&
        isWorldPosOnBuilding(worldX: worldPos.worldX, worldY: worldPos.worldY, building: $0)
    }) {
        let bType = building.typeName.uppercased()
        if bType == "PROC" {
            let harvesters = selected.filter { $0.isHarvester && $0.house == world.playerHouse }
            if !harvesters.isEmpty {
                issue(.dock(harvesters: harvesters.map(\.id), refinery: building.id))
                gameAudio.play(gameAudio.unitAcknowledgeSound())
                return
            }
        } else if bType == "FIX" {
            let vehicles = selected.filter { $0.kind == .unit && $0.house == world.playerHouse && !$0.isAircraft }
            if !vehicles.isEmpty {
                issue(.repairAt(units: vehicles.map(\.id), bay: building.id))
                gameAudio.play(gameAudio.unitAcknowledgeSound())
                return
            }
        }
    }

    // Move in formation (applied next tick; see applyGroupMove)
    let movable = selected.filter { $0.kind != .structure }
    issue(.move(units: movable.map(\.id), to: MapPoint(x: worldPos.worldX, y: worldPos.worldY),
                queued: shiftHeld, attackMove: false))
    gameAudio.play(gameAudio.moveResponse(for: movable))
}

// MARK: - Structure Placement

/// A placement click: convert the screen point to the cell under it.
func handleStructurePlacement(_ x: Int32, _ y: Int32) {
    guard let type = session.placementType else { return }
    let worldPos = gameScreenToWorld(x, y)
    issue(.placeStructure(type: type, cellX: Int(worldPos.worldX) / 24, cellY: Int(worldPos.worldY) / 24))
}
