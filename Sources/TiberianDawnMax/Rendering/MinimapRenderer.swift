import CSDL2
import OpenConquerCore

// MARK: - Minimap Rendering
// The in-game radar minimap and the comms-center / radar-online checks that gate it.

// MARK: - Game Minimap

/// Player owns a Communications Center (HQ) or Advanced Comm. Center (EYE).
func playerHasCommsCenter(_ world: GameWorld) -> Bool {
    world.hasBuilding(type: "HQ", house: world.playerHouse) ||
        world.hasBuilding(type: "EYE", house: world.playerHouse)
}

/// Radar is usable: a comms center and enough power.
func playerRadarOnline(_ world: GameWorld) -> Bool {
    playerHasCommsCenter(world) && !getHouseState(world.playerHouse).isLowPower
}

func renderGameMinimap(_ renderer: OpaquePointer?, world: GameWorld) {
    let layout = minimapLayout()
    let minimapCellSize = layout.cellSize
    let minimapSize = layout.size
    let wellX = layout.x
    let wellY = layout.y
    let mapSize = 64
    let tileSize = 24

    guard let scenario = scenarioData else { return }

    // Power gating: no Communications Center → no radar panel at all (it sits
    // over the battlefield, so an empty box would only hide units). Low power
    // with a comms center shows the offline panel.
    let playerHouse = world.playerHouse
    let playerState = getHouseState(playerHouse)
    if !playerHasCommsCenter(world) { return }

    if playerState.isLowPower {
        // Render disabled minimap: dark background with static noise
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 180)
        var minimapBg = SDL_Rect(x: wellX - 2, y: wellY - 2, w: minimapSize + 4, h: minimapSize + 4)
        SDL_RenderFillRect(renderer, &minimapBg)

        // Static noise dots
        SDL_SetRenderDrawColor(renderer, 30, 30, 30, 255)
        var fillRect = SDL_Rect(x: wellX, y: wellY, w: minimapSize, h: minimapSize)
        SDL_RenderFillRect(renderer, &fillRect)

        // Random static dots for visual noise effect (use tick count as seed variation)
        let tick = world.tickCount
        for i in stride(from: 0, to: Int(minimapSize * minimapSize) / 8, by: 1) {
            let hash = (i &* 2654435761 &+ tick &* 31) & 0x7FFFFFFF
            let px = wellX + Int32(hash % Int(minimapSize))
            let py = wellY + Int32((hash / Int(minimapSize)) % Int(minimapSize))
            let brightness = UInt8(40 + (hash / Int(minimapSize * minimapSize)) % 40)
            SDL_SetRenderDrawColor(renderer, brightness, brightness, brightness, 255)
            var dot = SDL_Rect(x: px, y: py, w: 1, h: 1)
            SDL_RenderFillRect(renderer, &dot)
        }

        drawText(renderer, "LOW POWER",
                 centerX: wellX + minimapSize / 2,
                 centerY: wellY + minimapSize / 2,
                 color: .red, scale: 1)
        return
    }

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
    var minimapBg = SDL_Rect(x: wellX - 2, y: wellY - 2, w: minimapSize + 4, h: minimapSize + 4)
    SDL_RenderFillRect(renderer, &minimapBg)

    // Map cells, units and the camera box are placed from the map origin and
    // clipped to the well (the classic radar centers a fitted map in it).
    let minimapX = layout.originX
    let minimapY = layout.originY
    var well = SDL_Rect(x: wellX, y: wellY, w: minimapSize, h: minimapSize)
    SDL_RenderSetClipRect(renderer, &well)
    defer { SDL_RenderSetClipRect(renderer, nil) }

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
            } else if world.map.tiberiumCells.contains(cellIndex) {
                // Tiberium: bright green/yellow
                r = 80; g = 200; b = 40
            } else {
                let cell = mapCells[cellIndex]
                let templateType = Int(cell.templateType)
                if templateType != 0xFF && templateType < templateTable.count {
                    let name = templateTable[templateType].icnName.uppercased()
                    if name == "W1" || name == "W2" {
                        // Deep water: dark blue
                        r = 15; g = 20; b = 80
                    } else if name.hasPrefix("SH") || name.hasPrefix("FALLS") || name.hasPrefix("FORD") {
                        // Shore/falls: medium blue-green
                        r = 20; g = 40; b = 60
                    } else if name.hasPrefix("RV") || name.hasPrefix("RIVER") || name.hasPrefix("BRIDGE") {
                        // River/bridge: medium blue
                        r = 20; g = 30; b = 70
                    } else if name.hasPrefix("D") || name.hasPrefix("ROCK") || name.hasPrefix("CLIFF") {
                        // Rock/desert: dark gray
                        r = 40; g = 40; b = 35
                    }
                }
                // Impassable land (not water): dark gray
                if !landPassability[cellIndex] && r == 20 && g == 60 && b == 20 {
                    r = 35; g = 35; b = 30
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
        if obj.kind == .structure || obj.isInLimbo { continue }
        // Skip enemies on non-visible cells
        if obj.house != world.playerHouse && !isCellVisible(obj.cell) { continue }
        let px = minimapX + Int32(obj.worldX / Double(tileSize)) * minimapCellSize
        let py = minimapY + Int32(obj.worldY / Double(tileSize)) * minimapCellSize
        let hc = obj.house.displayColor
        SDL_SetRenderDrawColor(renderer, UInt8(min(255, UInt16(hc.r) + 50)), UInt8(min(255, UInt16(hc.g) + 50)), UInt8(min(255, UInt16(hc.b) + 50)), 255)
        var dot = SDL_Rect(x: px, y: py, w: minimapCellSize, h: minimapCellSize)
        SDL_RenderFillRect(renderer, &dot)
    }

    // Draw crates on minimap as bright white dots (only if visible)
    for crate in world.crateState.crates {
        guard !crate.isCollected else { continue }
        guard world.map.fogState[crate.cell] != .unexplored else { continue }
        let px = minimapX + Int32(crate.worldX / Double(tileSize)) * minimapCellSize
        let py = minimapY + Int32(crate.worldY / Double(tileSize)) * minimapCellSize
        // Blink effect: alternate brightness
        let bright = (world.tickCount / 8) % 2 == 0
        SDL_SetRenderDrawColor(renderer, bright ? 255 : 180, bright ? 255 : 180, bright ? 255 : 180, 255)
        var cdot = SDL_Rect(x: px, y: py, w: minimapCellSize, h: minimapCellSize)
        SDL_RenderFillRect(renderer, &cdot)
    }

    // Darken outside map bounds
    if !classicSidebarActive, let bounds = world.mapBounds {
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
    let vpX = minimapX + Int32(renderState.gameCameraX / Double(tileSize)) * minimapCellSize
    let vpY = minimapY + Int32(renderState.gameCameraY / Double(tileSize)) * minimapCellSize
    let vpW = Int32(Double(renderState.windowWidth - sidebarWidth) / renderState.gameZoomLevel / Double(tileSize)) * minimapCellSize
    let vpH = Int32(Double(renderState.windowHeight) / renderState.gameZoomLevel / Double(tileSize)) * minimapCellSize
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
    var vpRect = SDL_Rect(x: vpX, y: vpY, w: vpW, h: vpH)
    SDL_RenderDrawRect(renderer, &vpRect)
}
