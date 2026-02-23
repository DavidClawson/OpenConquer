import CSDL2
import Foundation

// MARK: - Game Camera

var gameCameraX: Double = 0.0
var gameCameraY: Double = 0.0
var gameZoomLevel: Double = 1.0

// MARK: - Selection State

var selectionBoxStartX: Int32? = nil
var selectionBoxStartY: Int32? = nil
var selectionBoxEndX: Int32? = nil
var selectionBoxEndY: Int32? = nil
var isDragging = false

// MARK: - Coordinate Conversion

func gameScreenToWorld(_ screenX: Int32, _ screenY: Int32) -> (worldX: Double, worldY: Double) {
    let wx = gameCameraX + Double(screenX) / gameZoomLevel
    let wy = gameCameraY + Double(screenY) / gameZoomLevel
    return (wx, wy)
}

func gameWorldToScreen(_ worldX: Double, _ worldY: Double) -> (screenX: Int32, screenY: Int32) {
    let sx = Int32((worldX - gameCameraX) * gameZoomLevel)
    let sy = Int32((worldY - gameCameraY) * gameZoomLevel)
    return (sx, sy)
}

// MARK: - Input Handling

func handleGameLeftDown(_ x: Int32, _ y: Int32, shiftHeld: Bool) {
    selectionBoxStartX = x
    selectionBoxStartY = y
    selectionBoxEndX = x
    selectionBoxEndY = y
    isDragging = false
}

func handleGameLeftDrag(_ x: Int32, _ y: Int32) {
    selectionBoxEndX = x
    selectionBoxEndY = y
    if let sx = selectionBoxStartX, let sy = selectionBoxStartY {
        let dx = abs(Int(x) - Int(sx))
        let dy = abs(Int(y) - Int(sy))
        if dx > 4 || dy > 4 {
            isDragging = true
        }
    }
}

func handleGameLeftUp(_ x: Int32, _ y: Int32, shiftHeld: Bool) {
    guard let world = gameWorld else { return }

    if isDragging, let sx = selectionBoxStartX, let sy = selectionBoxStartY {
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
        let hitRadius = 14.0 / gameZoomLevel

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
        }
    }

    // Clear drag state
    selectionBoxStartX = nil
    selectionBoxStartY = nil
    selectionBoxEndX = nil
    selectionBoxEndY = nil
    isDragging = false
}

func handleGameRightClick(_ x: Int32, _ y: Int32) {
    guard let world = gameWorld else { return }
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
}

// MARK: - Game Renderer

func renderGame(_ renderer: OpaquePointer?) {
    guard let world = gameWorld else { return }
    let tileSize = 24
    let mapSize = 64
    let theater = world.theater

    // Clip game rendering to viewport area (left of sidebar)
    let gameViewportWidth = windowWidth - sidebarWidth
    var clipRect = SDL_Rect(x: 0, y: 0, w: gameViewportWidth, h: windowHeight)
    SDL_RenderSetClipRect(renderer, &clipRect)

    // Apply zoom scaling
    SDL_RenderSetScale(renderer, Float(gameZoomLevel), Float(gameZoomLevel))

    let visibleWidth = Int(Double(gameViewportWidth) / gameZoomLevel)
    let visibleHeight = Int(Double(windowHeight) / gameZoomLevel)
    let camX = Int(gameCameraX)
    let camY = Int(gameCameraY)

    let startCellX = max(0, camX / tileSize)
    let startCellY = max(0, camY / tileSize)
    let endCellX = min(mapSize - 1, (camX + visibleWidth) / tileSize)
    let endCellY = min(mapSize - 1, (camY + visibleHeight) / tileSize)

    let vw = Int32(visibleWidth)
    let vh = Int32(visibleHeight)

    // === Pass 1: Terrain tiles ===
    for cellY in startCellY...endCellY {
        for cellX in startCellX...endCellX {
            let cellIndex = cellY * mapSize + cellX
            let cell = mapCells[cellIndex]

            let templateType = Int(cell.templateType)
            let iconIndex = Int(cell.iconIndex)

            let icnName: String
            let actualIconIndex: Int
            if templateType == 0xFF || templateType >= templateTable.count {
                icnName = "CLEAR1"
                actualIconIndex = 0
            } else {
                icnName = templateTable[templateType].icnName
                actualIconIndex = iconIndex
            }

            if let texture = getTileTexture(renderer, icnName: icnName, iconIndex: actualIconIndex, theater: theater) {
                let screenX = Int32(cellX * tileSize - camX)
                let screenY = Int32(cellY * tileSize - camY)
                var dstRect = SDL_Rect(x: screenX, y: screenY, w: Int32(tileSize), h: Int32(tileSize))
                SDL_RenderCopy(renderer, texture, nil, &dstRect)
            } else {
                let screenX = Int32(cellX * tileSize - camX)
                let screenY = Int32(cellY * tileSize - camY)
                SDL_SetRenderDrawColor(renderer, 0, 100, 0, 255)
                var rect = SDL_Rect(x: screenX, y: screenY, w: Int32(tileSize), h: Int32(tileSize))
                SDL_RenderFillRect(renderer, &rect)
            }
        }
    }

    guard let scenario = scenarioData else {
        SDL_RenderSetScale(renderer, 1.0, 1.0)
        return
    }

    // === Pass 2: Overlays ===
    let wallTypes: Set<String> = ["SBAG", "CYCL", "BRIK", "BARB", "WOOD"]
    var wallCells: [Int: String] = [:]
    for overlay in scenario.overlays {
        let upper = overlay.typeName.uppercased()
        if wallTypes.contains(upper) {
            wallCells[overlay.cell] = upper
        }
    }

    for overlay in scenario.overlays {
        let pos = cellToPixel(overlay.cell)
        let screenX = Int32(pos.px - camX)
        let screenY = Int32(pos.py - camY)
        if screenX > vw || screenY > vh || screenX + 24 < 0 || screenY + 24 < 0 { continue }

        let upper = overlay.typeName.uppercased()
        var frameIdx = 0
        if wallTypes.contains(upper) {
            let cell = overlay.cell
            if cell >= 64 && wallCells[cell - 64] == upper { frameIdx |= 1 }
            if (cell % 64) < 63 && wallCells[cell + 1] == upper { frameIdx |= 2 }
            if cell + 64 < 64 * 64 && wallCells[cell + 64] == upper { frameIdx |= 4 }
            if (cell % 64) > 0 && wallCells[cell - 1] == upper { frameIdx |= 8 }
        }

        if let info = getObjectTexture(renderer, typeName: overlay.typeName, frame: frameIdx, house: .neutral, theater: theater) {
            var dstRect = SDL_Rect(x: screenX, y: screenY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        }
    }

    // === Pass 3: Terrain objects ===
    for terrainObj in scenario.terrain {
        let pos = cellToPixel(terrainObj.cell)
        if let info = getTerrainTexture(renderer, typeName: terrainObj.typeName, theater: theater, animFrame: 0) {
            let screenX = Int32(pos.px - camX)
            let screenY = Int32(pos.py + 24 - info.height - camY)
            if screenX > vw || screenY > vh ||
               screenX + Int32(info.width) < 0 || screenY + Int32(info.height) < 0 { continue }
            var dstRect = SDL_Rect(x: screenX, y: screenY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        }
    }

    // === Pass 3.5: Fog of War Overlay ===
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
    for cellY in startCellY...endCellY {
        for cellX in startCellX...endCellX {
            let cellIndex = cellY * mapSize + cellX
            let fog = fogState[cellIndex]
            if fog == .visible { continue }
            let screenX = Int32(cellX * tileSize - camX)
            let screenY = Int32(cellY * tileSize - camY)
            var rect = SDL_Rect(x: screenX, y: screenY, w: Int32(tileSize), h: Int32(tileSize))
            if fog == .unexplored {
                SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
            } else {
                SDL_SetRenderDrawColor(renderer, 0, 0, 0, 128)
            }
            SDL_RenderFillRect(renderer, &rect)
        }
    }

    // === Pass 4: Game objects sorted by Y (structures first, then units/infantry by Y) ===
    // Separate structures from mobile units for proper draw order
    var structures: [GameObject] = []
    var mobileObjects: [GameObject] = []

    for obj in world.objects {
        if obj.kind == .structure {
            structures.append(obj)
        } else {
            mobileObjects.append(obj)
        }
    }

    // Sort mobile objects by Y for proper depth ordering
    mobileObjects.sort { $0.worldY < $1.worldY }

    // Draw structures (using scenario data for proper bib/anchor rendering)
    for structure in scenario.structures {
        let pos = cellToPixel(structure.cell)
        let size = buildingSize(structure.typeName)
        let pixW = Int32(size.w * 24)
        let pixH = Int32(size.h * 24)
        let screenX = Int32(pos.px - camX)
        let screenY = Int32(pos.py - camY)

        if screenX > vw || screenY > vh ||
           screenX + pixW < 0 || screenY + pixH < 0 { continue }

        // Render bib
        if let bib = buildingBibInfo(structure.typeName) {
            let bibOriginCell = structure.cell + (size.h - 1) * 64
            for bibRow in 0..<bib.bibH {
                for bibCol in 0..<bib.bibW {
                    let bibCell = bibOriginCell + bibRow * 64 + bibCol
                    let bibPos = cellToPixel(bibCell)
                    let bibScreenX = Int32(bibPos.px - camX)
                    let bibScreenY = Int32(bibPos.py - camY)
                    let bibFrame = bibCol + bibRow * bib.bibW
                    if let bibInfo = getObjectTexture(renderer, typeName: bib.bibName, frame: bibFrame, house: .neutral, theater: theater) {
                        var bibRect = SDL_Rect(x: bibScreenX, y: bibScreenY, w: Int32(bibInfo.width), h: Int32(bibInfo.height))
                        SDL_RenderCopy(renderer, bibInfo.texture, nil, &bibRect)
                    }
                }
            }
        }

        if let info = getObjectTexture(renderer, typeName: structure.typeName, frame: 0, house: structure.house, theater: theater) {
            let spriteX = screenX
            let spriteY = screenY + pixH - Int32(info.height)
            var dstRect = SDL_Rect(x: spriteX, y: spriteY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        } else {
            let hc = structure.house.displayColor
            SDL_SetRenderDrawColor(renderer, hc.r, hc.g, hc.b, 160)
            var rect = SDL_Rect(x: screenX + 1, y: screenY + 1, w: pixW - 2, h: pixH - 2)
            SDL_RenderFillRect(renderer, &rect)
            SDL_SetRenderDrawColor(renderer, hc.r, hc.g, hc.b, 255)
            var border = SDL_Rect(x: screenX, y: screenY, w: pixW, h: pixH)
            SDL_RenderDrawRect(renderer, &border)
        }
    }

    // Draw mobile game objects (units and infantry) from their live positions
    for obj in mobileObjects {
        // Skip enemy objects on non-visible cells (fog of war)
        if obj.house != world.playerHouse && !isCellVisible(obj.cell) { continue }

        let screenX = Int32(obj.worldX - Double(camX))
        let screenY = Int32(obj.worldY - Double(camY))

        if obj.kind == .unit {
            let facingIdx = facing32[min(255, max(0, obj.facing))]
            let frameIdx = bodyShape[facingIdx]

            if let info = getObjectTexture(renderer, typeName: obj.typeName, frame: frameIdx, house: obj.house) {
                let drawX = screenX - Int32(info.width) / 2
                let drawY = screenY - Int32(info.height) / 2
                if drawX > vw || drawY > vh ||
                   drawX + Int32(info.width) < 0 || drawY + Int32(info.height) < 0 { continue }
                var dstRect = SDL_Rect(x: drawX, y: drawY, w: Int32(info.width), h: Int32(info.height))
                SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
            } else {
                let unitSize: Int32 = 16
                let hc = obj.house.displayColor
                SDL_SetRenderDrawColor(renderer, hc.r, hc.g, hc.b, 200)
                var rect = SDL_Rect(x: screenX - unitSize / 2, y: screenY - unitSize / 2, w: unitSize, h: unitSize)
                SDL_RenderFillRect(renderer, &rect)
                SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
                SDL_RenderDrawRect(renderer, &rect)
            }
        } else if obj.kind == .infantry {
            let facingIdx = facing32[min(255, max(0, obj.facing))]
            let frameIdx = humanShape[facingIdx]

            if let info = getObjectTexture(renderer, typeName: obj.typeName, frame: frameIdx, house: obj.house) {
                let drawX = screenX - Int32(info.width) / 2
                let drawY = screenY - Int32(info.height) / 2
                if drawX > vw || drawY > vh ||
                   drawX + Int32(info.width) < 0 || drawY + Int32(info.height) < 0 { continue }
                var dstRect = SDL_Rect(x: drawX, y: drawY, w: Int32(info.width), h: Int32(info.height))
                SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
            } else {
                let dotSize: Int32 = 6
                let hc = obj.house.displayColor
                SDL_SetRenderDrawColor(renderer, hc.r, hc.g, hc.b, 255)
                var rect = SDL_Rect(x: screenX - dotSize / 2, y: screenY - dotSize / 2, w: dotSize, h: dotSize)
                SDL_RenderFillRect(renderer, &rect)
            }
        }
    }

    // === Pass 5: Selection highlights ===
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
    for obj in world.objects {
        if !obj.isSelected { continue }

        let screenX = Int32(obj.worldX - Double(camX))
        let screenY = Int32(obj.worldY - Double(camY))

        if obj.kind == .structure {
            // Find matching scenario structure for size
            if let sStruct = scenario.structures.first(where: {
                let pos = cellToPixel($0.cell)
                let size = buildingSize($0.typeName)
                let cx = Double(pos.px) + Double(size.w * 24) / 2.0
                let cy = Double(pos.py) + Double(size.h * 24) / 2.0
                return abs(cx - obj.worldX) < 1 && abs(cy - obj.worldY) < 1
            }) {
                let pos = cellToPixel(sStruct.cell)
                let size = buildingSize(sStruct.typeName)
                let sx = Int32(pos.px - camX)
                let sy = Int32(pos.py - camY)
                let sw = Int32(size.w * 24)
                let sh = Int32(size.h * 24)
                renderSelectionBox(renderer, x: sx, y: sy, w: sw, h: sh, strength: obj.strength)
            }
        } else {
            let boxSize: Int32 = obj.kind == .unit ? 20 : 12
            let sx = screenX - boxSize / 2
            let sy = screenY - boxSize / 2
            renderSelectionBox(renderer, x: sx, y: sy, w: boxSize, h: boxSize, strength: obj.strength)
        }
    }

    // === Pass 6: Drag-select rectangle (in world space since we have zoom scaling active) ===
    if isDragging, let sx = selectionBoxStartX, let sy = selectionBoxStartY,
       let ex = selectionBoxEndX, let ey = selectionBoxEndY {
        // Convert screen coords to world coords for drawing
        let startWorld = gameScreenToWorld(sx, sy)
        let endWorld = gameScreenToWorld(ex, ey)
        let rx = Int32(startWorld.worldX - Double(camX))
        let ry = Int32(startWorld.worldY - Double(camY))
        let rw = Int32(endWorld.worldX - startWorld.worldX)
        let rh = Int32(endWorld.worldY - startWorld.worldY)

        SDL_SetRenderDrawColor(renderer, 0, 255, 0, 100)
        var fillRect = SDL_Rect(x: min(rx, rx + rw), y: min(ry, ry + rh), w: abs(rw), h: abs(rh))
        SDL_RenderFillRect(renderer, &fillRect)
        SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255)
        SDL_RenderDrawRect(renderer, &fillRect)
    }

    // === Pass 7: Shroud ===
    if let bounds = world.mapBounds {
        let bx = Int32(bounds.x * tileSize - camX)
        let by = Int32(bounds.y * tileSize - camY)
        let bw = Int32(bounds.width * tileSize)
        let bh = Int32(bounds.height * tileSize)

        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 160)

        if by > 0 {
            var r = SDL_Rect(x: 0, y: 0, w: vw, h: by)
            SDL_RenderFillRect(renderer, &r)
        }
        let bottomY = by + bh
        if bottomY < vh {
            var r = SDL_Rect(x: 0, y: bottomY, w: vw, h: vh - bottomY)
            SDL_RenderFillRect(renderer, &r)
        }
        let stripTop = max(0, by)
        let stripBottom = min(vh, bottomY)
        let stripH = stripBottom - stripTop
        if bx > 0 && stripH > 0 {
            var r = SDL_Rect(x: 0, y: stripTop, w: bx, h: stripH)
            SDL_RenderFillRect(renderer, &r)
        }
        let rightX = bx + bw
        if rightX < vw && stripH > 0 {
            var r = SDL_Rect(x: rightX, y: stripTop, w: vw - rightX, h: stripH)
            SDL_RenderFillRect(renderer, &r)
        }
    }

    // Placement preview (rendered in world space with zoom)
    if isPlacingStructure {
        renderPlacementPreview(renderer, mouseScreenX: mouseX, mouseScreenY: mouseY)
    }

    // Reset scale for HUD and minimap
    SDL_RenderSetScale(renderer, 1.0, 1.0)

    // Remove clip rect for minimap and sidebar
    SDL_RenderSetClipRect(renderer, nil)

    // === Minimap === (position adjusted for sidebar)
    renderGameMinimap(renderer, world: world)

    // === Sidebar ===
    renderSidebar(renderer)

    // === HUD ===
    let gameViewportCenter = (windowWidth - sidebarWidth) / 2
    let selectedCount = world.selectedObjects().count
    let scenarioLabel = scenarioList[scenarioIndex]
    drawText(renderer, "PLAYING - \(scenarioLabel)", centerX: gameViewportCenter, centerY: 15, color: .amber, scale: 2)

    if selectedCount > 0 {
        drawText(renderer, "\(selectedCount) SELECTED", centerX: gameViewportCenter, centerY: 35, color: .green, scale: 1)
    }

    drawText(renderer, "Select  Drag  Right Click: Move/Attack  Esc: Menu",
             centerX: gameViewportCenter, centerY: windowHeight - 15, color: .gray, scale: 1)
}

// MARK: - Selection Box Rendering

func renderSelectionBox(_ renderer: OpaquePointer?, x: Int32, y: Int32, w: Int32, h: Int32, strength: Int) {
    // Green selection border
    SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255)
    var border = SDL_Rect(x: x, y: y, w: w, h: h)
    SDL_RenderDrawRect(renderer, &border)

    // Health bar above selection
    let barW = w
    let barH: Int32 = 3
    let barX = x
    let barY = y - barH - 2
    let healthFrac = Double(strength) / 256.0

    // Background (dark)
    SDL_SetRenderDrawColor(renderer, 40, 40, 40, 200)
    var bgRect = SDL_Rect(x: barX, y: barY, w: barW, h: barH)
    SDL_RenderFillRect(renderer, &bgRect)

    // Health fill (green → yellow → red based on health)
    let fillW = Int32(Double(barW) * healthFrac)
    let r: UInt8, g: UInt8
    if healthFrac > 0.5 {
        r = UInt8(min(255, Int((1.0 - healthFrac) * 2.0 * 255.0)))
        g = 255
    } else {
        r = 255
        g = UInt8(min(255, Int(healthFrac * 2.0 * 255.0)))
    }
    SDL_SetRenderDrawColor(renderer, r, g, 0, 255)
    var healthRect = SDL_Rect(x: barX, y: barY, w: fillW, h: barH)
    SDL_RenderFillRect(renderer, &healthRect)
}

// MARK: - Game Minimap

func renderGameMinimap(_ renderer: OpaquePointer?, world: GameWorld) {
    let minimapCellSize: Int32 = 2
    let minimapSize: Int32 = 64 * minimapCellSize
    let minimapPad: Int32 = 10
    let minimapX = windowWidth - sidebarWidth - minimapSize - minimapPad
    let minimapY = windowHeight - minimapSize - minimapPad
    let mapSize = 64
    let tileSize = 24

    guard let scenario = scenarioData else { return }

    // Build structure cell lookup
    var structureCells: [Int: House] = [:]
    for structure in scenario.structures {
        let size = buildingSize(structure.typeName)
        let baseXY = cellToXY(structure.cell)
        for dy in 0..<size.h {
            for dx in 0..<size.w {
                let cell = (baseXY.y + dy) * mapSize + (baseXY.x + dx)
                structureCells[cell] = structure.house
            }
        }
    }

    // Background
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 180)
    var minimapBg = SDL_Rect(x: minimapX - 2, y: minimapY - 2, w: minimapSize + 4, h: minimapSize + 4)
    SDL_RenderFillRect(renderer, &minimapBg)

    // Draw terrain cells
    for cellY in 0..<mapSize {
        for cellX in 0..<mapSize {
            let cellIndex = cellY * mapSize + cellX
            let px = minimapX + Int32(cellX) * minimapCellSize
            let py = minimapY + Int32(cellY) * minimapCellSize

            var r: UInt8 = 20, g: UInt8 = 60, b: UInt8 = 20

            if let house = structureCells[cellIndex] {
                let hc = house.displayColor
                r = hc.r; g = hc.g; b = hc.b
            } else {
                let cell = mapCells[cellIndex]
                let templateType = Int(cell.templateType)
                if templateType != 0xFF && templateType < templateTable.count {
                    let name = templateTable[templateType].icnName.uppercased()
                    if name.hasPrefix("W") || name.contains("WATER") || name.hasPrefix("SH") || name.hasPrefix("FALLS") || name.hasPrefix("RIVER") || name.hasPrefix("FORD") || name.hasPrefix("BRIDGE") {
                        r = 20; g = 30; b = 80
                    }
                }
            }

            // Apply fog to minimap colors
            let fog = fogState[cellIndex]
            if fog == .unexplored {
                r = 0; g = 0; b = 0
            } else if fog == .explored {
                r = r / 2; g = g / 2; b = b / 2
            }

            SDL_SetRenderDrawColor(renderer, r, g, b, 255)
            var dot = SDL_Rect(x: px, y: py, w: minimapCellSize, h: minimapCellSize)
            SDL_RenderFillRect(renderer, &dot)
        }
    }

    // Draw mobile units on minimap as bright dots (only if visible)
    for obj in world.objects {
        if obj.kind == .structure { continue }
        // Skip enemies on non-visible cells
        if obj.house != world.playerHouse && !isCellVisible(obj.cell) { continue }
        let px = minimapX + Int32(obj.worldX / Double(tileSize)) * minimapCellSize
        let py = minimapY + Int32(obj.worldY / Double(tileSize)) * minimapCellSize
        let hc = obj.house.displayColor
        SDL_SetRenderDrawColor(renderer, UInt8(min(255, UInt16(hc.r) + 50)), UInt8(min(255, UInt16(hc.g) + 50)), UInt8(min(255, UInt16(hc.b) + 50)), 255)
        var dot = SDL_Rect(x: px, y: py, w: minimapCellSize, h: minimapCellSize)
        SDL_RenderFillRect(renderer, &dot)
    }

    // Darken outside map bounds
    if let bounds = world.mapBounds {
        let mbx = minimapX + Int32(bounds.x) * minimapCellSize
        let mby = minimapY + Int32(bounds.y) * minimapCellSize
        let mbw = Int32(bounds.width) * minimapCellSize
        let mbh = Int32(bounds.height) * minimapCellSize

        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 140)

        if mby > minimapY {
            var r = SDL_Rect(x: minimapX, y: minimapY, w: minimapSize, h: mby - minimapY)
            SDL_RenderFillRect(renderer, &r)
        }
        let mmBottom = mby + mbh
        let mmEnd = minimapY + minimapSize
        if mmBottom < mmEnd {
            var r = SDL_Rect(x: minimapX, y: mmBottom, w: minimapSize, h: mmEnd - mmBottom)
            SDL_RenderFillRect(renderer, &r)
        }
        let sTop = max(minimapY, mby)
        let sBot = min(mmEnd, mmBottom)
        let sH = sBot - sTop
        if mbx > minimapX && sH > 0 {
            var r = SDL_Rect(x: minimapX, y: sTop, w: mbx - minimapX, h: sH)
            SDL_RenderFillRect(renderer, &r)
        }
        let mmRight = mbx + mbw
        let mmXEnd = minimapX + minimapSize
        if mmRight < mmXEnd && sH > 0 {
            var r = SDL_Rect(x: mmRight, y: sTop, w: mmXEnd - mmRight, h: sH)
            SDL_RenderFillRect(renderer, &r)
        }
    }

    // Camera viewport indicator
    let vpX = minimapX + Int32(gameCameraX / Double(tileSize)) * minimapCellSize
    let vpY = minimapY + Int32(gameCameraY / Double(tileSize)) * minimapCellSize
    let vpW = Int32(Double(windowWidth - sidebarWidth) / gameZoomLevel / Double(tileSize)) * minimapCellSize
    let vpH = Int32(Double(windowHeight) / gameZoomLevel / Double(tileSize)) * minimapCellSize
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
    var vpRect = SDL_Rect(x: vpX, y: vpY, w: vpW, h: vpH)
    SDL_RenderDrawRect(renderer, &vpRect)
}
