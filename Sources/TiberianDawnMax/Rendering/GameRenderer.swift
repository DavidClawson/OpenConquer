import CSDL2
import Foundation
import OpenConquerCore

// MARK: - In-Game Renderer
// renderGame and its ordered draw passes; per-object, selection, animation and minimap helpers live in sibling files.

// MARK: - Drawing Utilities

/// Draw a dotted/dashed line between two points using the current render draw color.
func drawDottedLine(_ renderer: OpaquePointer?, x1: Int32, y1: Int32, x2: Int32, y2: Int32, dashLen: Int32, gapLen: Int32) {
    let dx = Double(x2 - x1)
    let dy = Double(y2 - y1)
    let totalLen = sqrt(dx * dx + dy * dy)
    guard totalLen > 0 else { return }
    let ux = dx / totalLen
    let uy = dy / totalLen
    let segLen = Double(dashLen + gapLen)
    var t = 0.0
    while t < totalLen {
        let endT = min(t + Double(dashLen), totalLen)
        let sx = Int32(Double(x1) + ux * t)
        let sy = Int32(Double(y1) + uy * t)
        let ex = Int32(Double(x1) + ux * endT)
        let ey = Int32(Double(y1) + uy * endT)
        SDL_RenderDrawLine(renderer, sx, sy, ex, ey)
        t += segLen
    }
}

// MARK: - Game Renderer

func renderGame(_ renderer: OpaquePointer?) {
    guard let world = session.world else { return }
    syncPresentationWithWorld()  // a world can be drawn before its first tick
    let tileSize = 24
    let mapSize = 64
    let theater = world.theater

    // Load UI sprites on first frame
    loadUISprites(renderer)

    // Clip game rendering to viewport area (left of sidebar)
    let gameViewportWidth = renderState.windowWidth - sidebarWidth
    var clipRect = SDL_Rect(x: 0, y: 0, w: gameViewportWidth, h: renderState.windowHeight)
    SDL_RenderSetClipRect(renderer, &clipRect)

    // Apply zoom scaling
    SDL_RenderSetScale(renderer, Float(renderState.gameZoomLevel), Float(renderState.gameZoomLevel))

    let visibleWidth = Int(Double(gameViewportWidth) / renderState.gameZoomLevel)
    let visibleHeight = Int(Double(renderState.windowHeight) / renderState.gameZoomLevel)
    let camX = Int(renderState.gameCameraX) - Int(renderState.screenShakeOffsetX)
    let camY = Int(renderState.gameCameraY) - Int(renderState.screenShakeOffsetY)

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
        let upper = overlay.typeName.uppercased()
        // Skip tiberium overlays — rendered dynamically from world.map.tiberiumCells below
        if upper.hasPrefix("TI") { continue }

        let pos = cellToPixel(overlay.cell)
        let screenX = Int32(pos.px - camX)
        let screenY = Int32(pos.py - camY)
        if screenX > vw || screenY > vh || screenX + 24 < 0 || screenY + 24 < 0 { continue }

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

    // === Pass 2b: Dynamic tiberium from world.map (grows/spreads, depleted by harvesting) ===
    // VC convention: the SHP (TI1..TI12) is the *visual variant*, the FRAME within
    // that SHP is the maturity 0..11. Each variant SHP has 12 frames going from
    // sparse (frame 0) to fully mature glowing tiberium (frame 11). Drawing
    // frame 0 of every cell flattens that gradient — the "bright green glowing"
    // late-stage frames never appeared.
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
    var tiberiumRendered = 0
    for cell in world.map.tiberiumCells {
        let pos = cellToPixel(cell)
        let screenX = Int32(pos.px - camX)
        let screenY = Int32(pos.py - camY)
        if screenX > vw || screenY > vh || screenX + 24 < 0 || screenY + 24 < 0 { continue }

        let density = world.map.tiberiumDensity[cell] ?? 1
        let variant = world.map.tiberiumVariant[cell] ?? density  // legacy save fallback
        let tiName = "TI\(min(max(variant, 1), 12))"
        let frame = min(max(density - 1, 0), 11)

        if let info = getObjectTexture(renderer, typeName: tiName, frame: frame, house: .neutral, theater: theater) {
            var dstRect = SDL_Rect(x: screenX, y: screenY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
            tiberiumRendered += 1
        } else {
            // Fallback: bright green diamond to show tiberium location
            SDL_SetRenderDrawColor(renderer, 40, 220, 40, 255)
            var rect = SDL_Rect(x: screenX + 4, y: screenY + 4, w: 16, h: 16)
            SDL_RenderFillRect(renderer, &rect)
            // Add crystal-like accent
            SDL_SetRenderDrawColor(renderer, 120, 255, 120, 255)
            SDL_RenderDrawLine(renderer, screenX + 8, screenY + 4, screenX + 12, screenY + 10)
            SDL_RenderDrawLine(renderer, screenX + 14, screenY + 6, screenX + 10, screenY + 14)
            tiberiumRendered += 1
        }
    }
    if world.tickCount <= 2 && !world.map.tiberiumCells.isEmpty {
        if let firstCell = world.map.tiberiumCells.first {
            let density = world.map.tiberiumDensity[firstCell] ?? 1
            let variant = world.map.tiberiumVariant[firstCell] ?? density
            let tiName = "TI\(variant)"
            let frame = min(max(density - 1, 0), 11)
            let hasTex = getObjectTexture(renderer, typeName: tiName, frame: frame, house: .neutral, theater: theater) != nil
            print("Tiberium debug: \(world.map.tiberiumCells.count) cells, \(tiberiumRendered) visible, sample=\(tiName) frame=\(frame) hasTex=\(hasTex)")
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

    // === Pass 3.75: Crates ===
    renderCrates(renderer, camX: camX, camY: camY, vw: vw, vh: vh)

    // === Pass 3.9: Smudges (scorch/craters) — ground decals, under objects ===
    renderSmudges(renderer, camX: camX, camY: camY, vw: vw, vh: vh)

    // === Pass 4: Game objects sorted by Y (structures first, then units/infantry by Y) ===
    // Separate structures from mobile units for proper draw order
    var structures: [GameObject] = []
    var mobileObjects: [GameObject] = []

    for obj in world.objects {
        if obj.kind == .structure {
            structures.append(obj)
        } else if !obj.isInLimbo {
            // Limbo = aboard a transport (or otherwise off the board): not drawn
            // at its own position. Hovercraft cargo is drawn on deck instead.
            mobileObjects.append(obj)
        }
    }

    // Sort mobile objects by Y for proper depth ordering. A hovercraft sorts
    // two cells "higher" so the units stepping off its deck (northward) draw
    // over it, as the original's Sort_Y does for the LST (UNIT.CPP).
    func depthY(_ obj: GameObject) -> Double { obj.isHovercraft ? obj.worldY - 48 : obj.worldY }
    mobileObjects.sort { depthY($0) < depthY($1) }

    // Pass 1: Render all building bibs FIRST so they never overlap building sprites
    for obj in structures {
        let size = buildingSize(obj.typeName)
        let pixW = Int32(size.w * 24)
        let pixH = Int32(size.h * 24)
        let topLeftX = Int32(obj.worldX - Double(size.w * 24) / 2.0)
        let topLeftY = Int32(obj.worldY - Double(size.h * 24) / 2.0)
        let screenX = topLeftX - Int32(camX)
        let screenY = topLeftY - Int32(camY)

        if screenX > vw || screenY > vh ||
           screenX + pixW < 0 || screenY + pixH < 0 { continue }

        if let bib = buildingBibInfo(obj.typeName) {
            let bibStartX = Int(topLeftX) / 24
            let bibStartY = Int(topLeftY) / 24 + size.h - 1
            let bibOriginCell = bibStartY * 64 + bibStartX
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
    }

    // A docked harvester is HIDDEN entirely (see the skip in the mobile pass
    // below) and the refinery plays its own dock/siphon/undock animation via
    // pickStructureFrame — mirroring the original, where the harvester is
    // limboed on attach and the PROC.SHP carries the whole unload animation
    // (UNIT.CPP Per_Cell_Process RADIO_ATTACH → Limbo; BUILDING.CPP
    // Mission_Harvest BSTATE_ACTIVE/AUX1/AUX2). No separate harvester draw.

    // Pass 2: Render building sprites on top of bibs
    for obj in structures {
        let size = buildingSize(obj.typeName)
        let pixW = Int32(size.w * 24)
        let pixH = Int32(size.h * 24)
        let topLeftX = Int32(obj.worldX - Double(size.w * 24) / 2.0)
        let topLeftY = Int32(obj.worldY - Double(size.h * 24) / 2.0)
        let screenX = topLeftX - Int32(camX)
        let screenY = topLeftY - Int32(camY)

        if screenX > vw || screenY > vh ||
           screenX + pixW < 0 || screenY + pixH < 0 { continue }

        // Resolve build-up frame count on first render (SHP data lives in rendering layer)
        if obj.buildUpFrame >= 0 && obj.buildUpTotalFrames == 0 {
            let spriteName = obj.typeName.uppercased()
            if let shp = renderState.objectSHPCache[spriteName] {
                obj.buildUpTotalFrames = max(1, shp.frames.count)
            } else {
                // Try loading the SHP to populate the cache
                if let _ = getObjectTexture(renderer, typeName: spriteName, frame: 0, house: obj.house, theater: theater) {
                    if let shp = renderState.objectSHPCache[spriteName] {
                        obj.buildUpTotalFrames = max(1, shp.frames.count)
                    }
                }
                if obj.buildUpTotalFrames == 0 {
                    obj.buildUpTotalFrames = 1  // Fallback: skip animation
                }
            }
            // For turreted structures, only body frames count for build-up
            if obj.hasTurret && obj.buildUpTotalFrames > 32 {
                obj.buildUpTotalFrames = 32
            }
        }

        // Warm the classic SHP cache before frame selection. pickStructureFrame
        // needs the total frame count to choose damaged/rubble frames; without
        // this, an as-yet-unloaded building reports 0 frames and always renders
        // healthy on its first frame (and forever, if it's already damaged when
        // first seen). Skipped when a remastered manifest supplies the count.
        let structSprite = obj.typeName.uppercased()
        if remasteredFrameCount(structSprite) == nil,
           renderState.objectSHPCache[structSprite] == nil {
            _ = getObjectTexture(renderer, typeName: structSprite, frame: 0, house: obj.house, theater: theater)
        }

        // Determine frame for structures (mirrors Vanilla-Conquer building.cpp:560-634)
        let structFrame: Int = pickStructureFrame(obj)

        if let info = getObjectTexture(renderer, typeName: obj.typeName, frame: structFrame, house: obj.house, theater: theater) {
            let spriteX = screenX
            let spriteY = screenY + pixH - Int32(info.height)
            var dstRect = SDL_Rect(x: spriteX, y: spriteY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)

            // Weapons Factory has a separate roof/door SHP (WEAP2) drawn on
            // top of the body. Vanilla-Conquer building.cpp:508-514 picks
            // frame = Door_Stage() (0=closed, 1-3=opening, etc.) plus +4 for
            // damaged variants. Until production-driven door animation is
            // wired up we draw frame 0 always so the roof at least appears.
            if obj.typeName.uppercased() == "WEAP" {
                let overlayFrame = obj.healthFraction < 0.5 ? 4 : 0
                if let roof = getObjectTexture(renderer, typeName: "WEAP2", frame: overlayFrame, house: obj.house, theater: theater) {
                    let rx = screenX
                    let ry = screenY + pixH - Int32(roof.height)
                    var roofRect = SDL_Rect(x: rx, y: ry, w: Int32(roof.width), h: Int32(roof.height))
                    SDL_RenderCopy(renderer, roof.texture, nil, &roofRect)
                }
            }
        } else {
            let hc = obj.house.displayColor
            SDL_SetRenderDrawColor(renderer, hc.r, hc.g, hc.b, 160)
            var rect = SDL_Rect(x: screenX + 1, y: screenY + 1, w: pixW - 2, h: pixH - 2)
            SDL_RenderFillRect(renderer, &rect)
            SDL_SetRenderDrawColor(renderer, hc.r, hc.g, hc.b, 255)
            var border = SDL_Rect(x: screenX, y: screenY, w: pixW, h: pixH)
            SDL_RenderDrawRect(renderer, &border)
        }
    }

    // Draw mobile game objects (units and infantry) from interpolated positions
    let interp = app.renderInterpolation
    for obj in mobileObjects {
        // Skip enemy objects on non-visible cells (fog of war)
        if obj.house != world.playerHouse && !isCellVisible(obj.cell) { continue }
        // A docked harvester is hidden entirely; the refinery plays its own
        // dock/unload animation (see procDockAnimFrame).
        if obj.isHarvesterDocked { continue }

        // Interpolate between previous and current tick positions for smooth rendering
        let drawX = obj.prevWorldX + (obj.worldX - obj.prevWorldX) * interp
        let drawY = obj.prevWorldY + (obj.worldY - obj.prevWorldY) * interp
        // Render offsets: harvesters can't drive onto the impassable refinery
        // footprint, and vehicles being repaired sit on the FIX pad (the
        // building centre) — both are drawn via a positional offset.
        let dockOffset: (dx: Double, dy: Double)
        if obj.isHarvester {
            dockOffset = obj.harvesterDockOffset()
        } else if obj.repairBuildingID != nil {
            dockOffset = obj.repairPadOffset()
        } else {
            dockOffset = (0.0, 0.0)
        }
        let screenX = Int32(drawX + dockOffset.dx - Double(camX))
        let screenY = Int32(drawY + dockOffset.dy - Double(camY))

        if obj.kind == .unit {
            let facingIdx = facing32[min(255, max(0, obj.facing))]
            var frameIdx = bodyShape[facingIdx]
            var bodyFlip = SDL_FLIP_NONE

            // Handle sprites with fewer than 32 body frames by mirroring
            let unitSpriteName = spriteNameOverrides[obj.typeName.uppercased()] ?? obj.typeName.uppercased()
            let bodyFrameCount: Int
            if let shp = renderState.objectSHPCache[unitSpriteName], shp.frames.count > 0 {
                bodyFrameCount = obj.hasTurret ? min(32, shp.frames.count / 2) : min(32, shp.frames.count)
                if frameIdx >= bodyFrameCount {
                    let mirrorFrame = bodyFrameCount * 2 - frameIdx
                    frameIdx = max(0, min(bodyFrameCount - 1, mirrorFrame))
                    bodyFlip = SDL_FLIP_HORIZONTAL
                }
            } else {
                bodyFrameCount = 32
            }

            // Harvester scooping tiberium: override the body frame with the
            // gather animation (HARV frames 32-63). Pre-drawn per direction, so
            // never mirrored.
            if let hf = harvGatherAnimFrame(obj) {
                frameIdx = hf
                bodyFlip = SDL_FLIP_NONE
            }

            // BOAT special case: the hull sprite only visually differs for east vs west.
            // Use the east-facing body frame and flip horizontally when traveling west.
            let upperType = obj.typeName.uppercased()
            if upperType == "LST" {
                // "Special hovercraft shape is ALWAYS N/S" (UNIT.CPP Draw_It)
                frameIdx = 0
                bodyFlip = SDL_FLIP_NONE
            }
            if upperType == "BOAT" {
                // Always use the east-facing body frame (facingIdx 8 → bodyShape = 24)
                let eastFacingIdx = 8
                frameIdx = bodyShape[eastFacingIdx]
                // Flip horizontally when traveling west (facing 129-255)
                bodyFlip = obj.facing > 128 ? SDL_FLIP_HORIZONTAL : SDL_FLIP_NONE
            }

            // Aircraft: draw shadow at ground level, sprite offset upward by altitude
            if obj.isAircraft && obj.altitude > 0 {
                let altOffset = Int32(obj.altitude)

                // Shadow: dark ellipse on the ground
                SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
                SDL_SetRenderDrawColor(renderer, 0, 0, 0, 80)
                let shadowW: Int32 = 18
                let shadowH: Int32 = 8
                var shadowRect = SDL_Rect(x: screenX - shadowW / 2, y: screenY - shadowH / 2 + altOffset / 2,
                                          w: shadowW, h: shadowH)
                SDL_RenderFillRect(renderer, &shadowRect)

                // Draw aircraft elevated, with the classic hover bob at flight level
                let elevatedY = screenY - altOffset + aircraftHoverJitter(obj)
                if let info = getObjectTexture(renderer, typeName: obj.typeName, frame: frameIdx, house: obj.house) {
                    let drawX = screenX - Int32(info.width) / 2
                    let drawY = elevatedY - Int32(info.height) / 2
                    var dstRect = SDL_Rect(x: drawX, y: drawY, w: Int32(info.width), h: Int32(info.height))
                    SDL_RenderCopyEx(renderer, info.texture, nil, &dstRect, 0, nil, bodyFlip)
                    renderAircraftRotors(renderer, obj, x: screenX, y: elevatedY)
                } else {
                    // Procedural aircraft: diamond shape
                    let hc = obj.house.displayColor
                    SDL_SetRenderDrawColor(renderer, hc.r, hc.g, hc.b, 220)
                    let sz: Int32 = 14
                    // Draw diamond
                    var points: [SDL_Point] = [
                        SDL_Point(x: screenX, y: elevatedY - sz / 2),
                        SDL_Point(x: screenX + sz / 2, y: elevatedY),
                        SDL_Point(x: screenX, y: elevatedY + sz / 2),
                        SDL_Point(x: screenX - sz / 2, y: elevatedY),
                        SDL_Point(x: screenX, y: elevatedY - sz / 2),
                    ]
                    SDL_RenderDrawLines(renderer, &points, Int32(points.count))
                    // Fill center
                    var fillRect = SDL_Rect(x: screenX - 3, y: elevatedY - 3, w: 6, h: 6)
                    SDL_RenderFillRect(renderer, &fillRect)
                }
            } else if let info = getObjectTexture(renderer, typeName: obj.typeName, frame: frameIdx, house: obj.house) {
                let drawX = screenX - Int32(info.width) / 2
                let drawY = screenY - Int32(info.height) / 2
                if drawX > vw || drawY > vh ||
                   drawX + Int32(info.width) < 0 || drawY + Int32(info.height) < 0 { continue }
                var dstRect = SDL_Rect(x: drawX, y: drawY, w: Int32(info.width), h: Int32(info.height))
                SDL_RenderCopyEx(renderer, info.texture, nil, &dstRect, 0, nil, bodyFlip)
                if obj.isAircraft {
                    renderAircraftRotors(renderer, obj, x: screenX, y: screenY)  // parked: idle rotors
                }
                if obj.isHovercraft && obj.hasCargo {
                    renderHovercraftDeck(renderer, obj, x: screenX, y: screenY)
                }

                // Render turret overlay for turreted units (frame 32 + turretFacing)
                if obj.hasTurret {
                    let turretFacingIdx = facing32[min(255, max(0, obj.turretFacing))]
                    var turretFrameIdx = bodyShape[turretFacingIdx]
                    var turretFlip = SDL_FLIP_NONE
                    // Mirror turret too if needed
                    if turretFrameIdx >= bodyFrameCount {
                        let mirrorFrame = bodyFrameCount * 2 - turretFrameIdx
                        turretFrameIdx = max(0, min(bodyFrameCount - 1, mirrorFrame))
                        turretFlip = SDL_FLIP_HORIZONTAL
                    }
                    turretFrameIdx += (obj.hasTurret ? bodyFrameCount : 32)
                    if let turretInfo = getObjectTexture(renderer, typeName: obj.typeName, frame: turretFrameIdx, house: obj.house) {
                        let tDrawX = screenX - Int32(turretInfo.width) / 2
                        let tDrawY = screenY - Int32(turretInfo.height) / 2
                        var tDstRect = SDL_Rect(x: tDrawX, y: tDrawY, w: Int32(turretInfo.width), h: Int32(turretInfo.height))
                        SDL_RenderCopyEx(renderer, turretInfo.texture, nil, &tDstRect, 0, nil, turretFlip)
                    }
                }
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
            let direction = humanShape[facingIdx]  // 0-7 direction index

            // Determine animation frame based on infantry state
            // Uses per-object animFrame for smooth per-unit walk cycles
            var frameIdx: Int
            let isMoving = obj.moveTargetX != nil
            if obj.isProne {
                if isMoving {
                    // DO_CRAWL: Frame=144, Count=4, Jump=4 (minigunner layout)
                    let crawlStart = 144
                    let crawlJump = 4
                    frameIdx = crawlStart + direction * crawlJump + (obj.animFrame % 4)
                } else {
                    // DO_PRONE: Frame=192, Count=1, Jump=8
                    frameIdx = 192 + direction * 8
                }
            } else if obj.isFiringAnim {
                // DO_FIRE_WEAPON: Frame=64, Count=8, Jump=8 (minigunner)
                let fireStart = 64
                let fireJump = 8
                // Use fireAnimTicks as countdown to pick a fire frame
                let fireFrame = max(0, 4 - obj.fireAnimTicks)
                frameIdx = fireStart + direction * fireJump + fireFrame
            } else if isMoving {
                // DO_WALK: Frame=16, Count=6, Jump=6 (all standard infantry)
                let walkStart = 16
                let walkJump = 6
                frameIdx = walkStart + direction * walkJump + (obj.animFrame % 6)
            } else {
                // DO_STAND_READY: Frame=0, Count=1, Jump=1
                frameIdx = direction
            }

            // Clamp frame index to valid range for this SHP
            let infantrySpriteName = spriteNameOverrides[obj.typeName.uppercased()] ?? obj.typeName.uppercased()
            if let shp = renderState.objectSHPCache[infantrySpriteName] {
                if frameIdx >= shp.frames.count {
                    frameIdx = min(shp.frames.count - 1, direction)
                }
            }

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

    // === Pass 4a: Animations (explosions, fires, effects) ===
    renderAnimations(renderer, camX: camX, camY: camY, vw: vw, vh: vh)

    // === Pass 4b: In-flight projectiles (missiles, shells, grenades) ===
    renderProjectiles(renderer, camX: camX, camY: camY, vw: vw, vh: vh)

    // === Pass 4c: Ion Cannon Beam Effect ===
    renderIonBeam(renderer, camX: camX, camY: camY)

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
                renderSelectionBox(renderer, x: sx, y: sy, w: sw, h: sh, healthFraction: obj.healthFraction)
            }
        } else {
            let boxSize: Int32 = obj.kind == .unit ? 20 : 12
            let sx = screenX - boxSize / 2
            let sy = screenY - boxSize / 2
            // Show cargo pips for harvesters
            let isHarv = obj.typeName.uppercased() == "HARV"
            renderSelectionBox(renderer, x: sx, y: sy, w: boxSize, h: boxSize, healthFraction: obj.healthFraction,
                               cargoPips: isHarv ? obj.tiberiumLoad : 0,
                               maxCargoPips: isHarv ? maxTiberiumLoad : 0)
        }
    }

    // === Pass 5a2: Veterancy chevrons above veteran/elite units ===
    for obj in world.objects {
        guard obj.strength > 0 && obj.veteranLevel > 0 else { continue }
        guard obj.kind == .unit || obj.kind == .infantry else { continue }

        let screenX = Int32(obj.worldX - Double(camX))
        let screenY = Int32(obj.worldY - Double(camY))

        // Cull off-screen
        if screenX < -20 || screenY < -20 || screenX > vw + 20 || screenY > vh + 20 { continue }

        let chevronY = screenY - (obj.kind == .unit ? 14 : 10)
        renderVeterancyChevrons(renderer, cx: screenX, cy: chevronY, level: obj.veteranLevel)
    }

    // === Pass 5b: Repair wrench indicator on buildings actively being repaired ===
    for obj in world.objects {
        guard obj.kind == .structure && obj.house == world.playerHouse &&
              obj.strength > 0 && obj.isRepairing else { continue }
        let screenX = Int32(obj.worldX - Double(camX))
        let screenY = Int32(obj.worldY - Double(camY))
        let size = buildingSize(obj.typeName)
        let topY = screenY - Int32(size.h * 24) / 2
        renderRepairWrench(renderer, cx: screenX, cy: topY - 8, tickCount: world.tickCount)
    }

    // === Pass 5c: Rally points for selected production buildings ===
    for obj in world.objects {
        guard obj.isSelected && obj.kind == .structure && obj.house == world.playerHouse else { continue }
        guard obj.strength > 0 else { continue }
        guard let rpX = obj.rallyPointX, let rpY = obj.rallyPointY else { continue }

        let bx = Int32(obj.worldX - Double(camX))
        let by = Int32(obj.worldY - Double(camY))
        let rx = Int32(rpX - Double(camX))
        let ry = Int32(rpY - Double(camY))

        // Draw dotted line from building to rally point (bright green)
        SDL_SetRenderDrawColor(renderer, 0, 255, 0, 200)
        drawDottedLine(renderer, x1: bx, y1: by, x2: rx, y2: ry, dashLen: 4, gapLen: 3)

        // Draw diamond marker at rally point
        SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255)
        let ds: Int32 = 5
        SDL_RenderDrawLine(renderer, rx, ry - ds, rx + ds, ry)
        SDL_RenderDrawLine(renderer, rx + ds, ry, rx, ry + ds)
        SDL_RenderDrawLine(renderer, rx, ry + ds, rx - ds, ry)
        SDL_RenderDrawLine(renderer, rx - ds, ry, rx, ry - ds)
        // Fill the diamond with a small rectangle
        var flagRect = SDL_Rect(x: rx - 2, y: ry - 2, w: 5, h: 5)
        SDL_RenderFillRect(renderer, &flagRect)
    }

    // === Pass 5d: Patrol routes for selected patrolling units ===
    for obj in world.objects {
        guard obj.isSelected && obj.strength > 0 else { continue }
        guard obj.house == world.playerHouse else { continue }
        guard obj.mission == .patrol && !obj.patrolWaypoints.isEmpty else { continue }

        SDL_SetRenderDrawColor(renderer, 255, 255, 0, 200)
        let wps = obj.patrolWaypoints
        // Draw connected line segments
        for i in 0..<wps.count {
            let from = wps[i]
            let to = wps[(i + 1) % wps.count]
            let fx = Int32(from.x - Double(camX))
            let fy = Int32(from.y - Double(camY))
            let tx = Int32(to.x - Double(camX))
            let ty = Int32(to.y - Double(camY))
            SDL_RenderDrawLine(renderer, fx, fy, tx, ty)
        }
        // Draw dots at each waypoint
        for (i, wp) in wps.enumerated() {
            let wx = Int32(wp.x - Double(camX))
            let wy = Int32(wp.y - Double(camY))
            let isCurrent = (i == obj.patrolIndex)
            let dotSize: Int32 = isCurrent ? 4 : 2
            if isCurrent {
                SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
            } else {
                SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255)
            }
            var dotRect = SDL_Rect(x: wx - dotSize, y: wy - dotSize, w: dotSize * 2, h: dotSize * 2)
            SDL_RenderFillRect(renderer, &dotRect)
        }
    }

    // === Pass 5e: Patrol mode waypoint preview (while building route) ===
    if session.isPatrolMode && !session.patrolModeWaypoints.isEmpty {
        SDL_SetRenderDrawColor(renderer, 255, 255, 0, 150)
        let wps = session.patrolModeWaypoints
        for i in 0..<wps.count - 1 {
            let fx = Int32(wps[i].x - Double(camX))
            let fy = Int32(wps[i].y - Double(camY))
            let tx = Int32(wps[i + 1].x - Double(camX))
            let ty = Int32(wps[i + 1].y - Double(camY))
            SDL_RenderDrawLine(renderer, fx, fy, tx, ty)
        }
        // Draw closing segment preview (dashed)
        if wps.count > 1 {
            let lastX = Int32(wps.last!.x - Double(camX))
            let lastY = Int32(wps.last!.y - Double(camY))
            let firstX = Int32(wps[0].x - Double(camX))
            let firstY = Int32(wps[0].y - Double(camY))
            SDL_SetRenderDrawColor(renderer, 255, 255, 0, 100)
            drawDottedLine(renderer, x1: lastX, y1: lastY, x2: firstX, y2: firstY, dashLen: 3, gapLen: 4)
        }
        // Draw dots at placed waypoints
        SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255)
        for wp in wps {
            let wx = Int32(wp.x - Double(camX))
            let wy = Int32(wp.y - Double(camY))
            var dotRect = SDL_Rect(x: wx - 3, y: wy - 3, w: 6, h: 6)
            SDL_RenderFillRect(renderer, &dotRect)
        }
    }

    // === Pass 6: Drag-select rectangle (in world space since we have zoom scaling active) ===
    if input.isDragging, let sx = input.selectionBoxStartX, let sy = input.selectionBoxStartY,
       let ex = input.selectionBoxEndX, let ey = input.selectionBoxEndY {
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

    // === Pass 7: Out-of-bounds mask ===
    // Everything outside the playable map bounds is masked with SOLID black, so
    // small/bounded maps read as "the map, on a black field" instead of showing
    // unreachable terrain + fog you can't actually enter.
    if let bounds = world.mapBounds {
        let bx = Int32(bounds.x * tileSize - camX)
        let by = Int32(bounds.y * tileSize - camY)
        let bw = Int32(bounds.width * tileSize)
        let bh = Int32(bounds.height * tileSize)

        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE)
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)

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

        // A thin steel frame just outside the playable area, so a small map
        // centered in a large window reads as bounded rather than unexplored.
        SDL_SetRenderDrawColor(renderer, 70, 74, 78, 255)
        for inset: Int32 in 1...2 {
            var frame = SDL_Rect(x: bx - inset, y: by - inset, w: bw + inset * 2, h: bh + inset * 2)
            SDL_RenderDrawRect(renderer, &frame)
        }
    }

    // Placement preview (rendered in world space with zoom)
    if session.isPlacingStructure {
        renderPlacementPreview(renderer, mouseScreenX: input.mouseX, mouseScreenY: input.mouseY)
    }

    // Reset scale for HUD and minimap
    SDL_RenderSetScale(renderer, 1.0, 1.0)

    // Remove clip rect for minimap and sidebar
    SDL_RenderSetClipRect(renderer, nil)

    // === Minimap + Sidebar === (the classic sidebar draws the minimap in its radar)
    if classicSidebarActive {
        renderClassicSidebar(renderer)
    } else {
        renderGameMinimap(renderer, world: world)
        renderSidebar(renderer)
    }

    // === HUD ===
    let gameViewportCenter = (renderState.windowWidth - sidebarWidth) / 2
    let selectedCount = world.selectedObjects().count
    // Show the mission ACTUALLY being played (not the menu browser index, which
    // stayed at SCG01EA). Derive the mission number + faction from the current
    // scenario name so the friendly title can't drift out of sync.
    let scenarioCode = (session.currentScenarioName ?? app.scenarioList[app.scenarioIndex]).uppercased()
    let missionNum = Int(scenarioCode.dropFirst(3).prefix(2)) ?? 0
    let nameTable = scenarioCode.hasPrefix("SCB") ? nodMissionNames : gdiMissionNames
    let missionTitle = nameTable[missionNum] ?? scenarioCode
    drawText(renderer, "PLAYING - \(missionTitle)", centerX: gameViewportCenter, centerY: 15, color: .amber, scale: 2)

    if selectedCount > 0 {
        drawText(renderer, "\(selectedCount) SELECTED", centerX: gameViewportCenter, centerY: 35, color: .green, scale: 1)
    }

    // Win/Lose state display
    if session.triggerWinState == .won {
        drawText(renderer, "MISSION ACCOMPLISHED", centerX: gameViewportCenter, centerY: renderState.windowHeight / 2 - 20, color: .green, scale: 3)
        drawText(renderer, "Press Enter for Score", centerX: gameViewportCenter, centerY: renderState.windowHeight / 2 + 20, color: .amber, scale: 2)
    } else if session.triggerWinState == .lost {
        drawText(renderer, "MISSION FAILED", centerX: gameViewportCenter, centerY: renderState.windowHeight / 2 - 20, color: .red, scale: 3)
        drawText(renderer, "Press Enter for Score  R: Restart", centerX: gameViewportCenter, centerY: renderState.windowHeight / 2 + 20, color: .amber, scale: 2)
    }

    let commandHint = UserSettings.controlScheme == .classic ? "Click: Select/Move/Attack" : "RClick: Move/Attack"
    drawText(renderer, "\(commandHint)  F3: Perf  F5: Save  F9: Load  Esc: Menu",
             centerX: gameViewportCenter, centerY: renderState.windowHeight - 15, color: .gray, scale: 1)

    // === Screen Flash Overlay ===
    if renderState.screenFlashAlpha > 0 {
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
        SDL_SetRenderDrawColor(renderer,
                               renderState.screenFlashR,
                               renderState.screenFlashG,
                               renderState.screenFlashB,
                               renderState.screenFlashAlpha)
        var flashRect = SDL_Rect(x: 0, y: 0, w: renderState.windowWidth, h: renderState.windowHeight)
        SDL_RenderFillRect(renderer, &flashRect)
    }

    // === Custom Cursor Rendering ===
    renderGameCursor(renderer, world: world)
}

// Cursor rendering moved to GameCursor.swift

// renderGameCursor() is now in GameCursor.swift
