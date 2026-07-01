import CSDL2
import Foundation

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

// MARK: - Building Damage Frames
// Mirrors Vanilla-Conquer building.cpp:560-634. Buildings encode damaged
// graphics in trailing SHP frames: simple buildings put the damaged version at
// frameCount-2 and rubble at frameCount-1; turreted buildings (GUN, SAM)
// shift the entire body+turret set by 64 to reach the damaged variants.
/// If a harvester is currently docked at this refinery, return the PROC.SHP
/// animation frame to play; otherwise nil. The whole unload sequence lives in
/// the building sprite (frames 6-29): the harvester itself is hidden while
/// docked. Mirrors the original's building-driven dock animation.
///   6-11  flashing "busy" lights (approach / holding)
///   12-18 docking, 19-23 siphoning (loops), 24-29 undocking
func procDockAnimFrame(_ proc: GameObject) -> Int? {
    guard proc.typeName.uppercased() == "PROC" else { return nil }
    guard let world = session.world else { return nil }
    let bayX = proc.cellX
    let bayY = proc.cellY + 2   // harvester bay is one cell south of the footprint
    for h in world.objects where h.isHarvesterDocked && h.house == proc.house {
        guard h.cellX == bayX && abs(h.cellY - bayY) <= 1 else { continue }
        let slide = Double(max(1, harvesterDockSlideTicks))
        switch h.missionStatus {
        case dockUnloading:
            if h.dockTimer < harvesterDockSlideTicks {
                // Sliding in: play the docking frames 12..18.
                let frac = Double(h.dockTimer) / slide
                return min(18, 12 + Int(frac * 6.0))
            }
            // Seated & siphoning: loop the 19..23 frames (dockTimer ticks up
            // every sim frame while unloading, so this animates on its own).
            return 19 + ((h.dockTimer - harvesterDockSlideTicks) / 2) % 5
        case dockBackingOut:
            // Undocking: play the 24..29 frames as it backs out.
            let frac = min(1.0, Double(h.dockTimer) / slide)
            return min(29, 24 + Int(frac * 5.0))
        default:
            break
        }
    }
    return nil
}

/// If a harvester is parked on tiberium actively scooping, return its HARV
/// gather-animation frame (32..63 = 8 facings × 4 scoop frames); otherwise nil.
/// Mirrors VC unit.cpp:2126-2129 (the IsHarvesting draw branch). Cosmetic: the
/// scoop phase is derived from world.tickCount, so no simulation state is added
/// and the determinism baselines are unaffected.
func harvGatherAnimFrame(_ obj: GameObject) -> Int? {
    guard obj.isHarvester, obj.mission == .harvest else { return nil }
    // dockApproaching (==0) is the "out harvesting" sub-state (not unloading/backing out).
    guard obj.missionStatus == dockApproaching, !obj.harvesterForceDock else { return nil }
    guard obj.tiberiumLoad < maxTiberiumLoad else { return nil }
    guard let world = session.world, world.map.tiberiumCells.contains(obj.cell) else { return nil }
    // Only while stationary — the render analog of VC's !IsDriving; a harvester
    // merely crossing a tiberium cell en route shouldn't flick into the scoop pose.
    guard obj.worldX == obj.prevWorldX, obj.worldY == obj.prevWorldY else { return nil }

    let bodyFrame = bodyShape[facing32[min(255, max(0, obj.facing))]]  // 0..31
    let dir8 = ((bodyFrame + 2) / 4) & 7                               // 0..7 (wrap 30/31 → 0)
    let hstage = [0, 1, 2, 3, 2, 1]                                    // ping-pong scoop
    let stage = hstage[(world.tickCount / 2) % hstage.count]           // ~Set_Rate(2) cadence
    return 32 + dir8 * 4 + stage                                       // 32..63
}

func pickStructureFrame(_ obj: GameObject) -> Int {
    if obj.buildUpFrame >= 0 { return obj.buildUpFrame }

    let upper = obj.typeName.uppercased()
    let healthFrac = obj.healthFraction
    let isCritical = obj.strength <= 1
    let isDamaged = healthFrac < 0.5

    // Resolve total frame count. Prefer the remastered manifest (preloaded at
    // startup) since HD buildings are drawn from PNGs and never populate the
    // classic SHP cache; fall back to the classic SHP cache otherwise. The
    // caller is responsible for warming the classic cache before this runs.
    let frameCount = remasteredFrameCount(upper)
        ?? renderState.objectSHPCache[upper]?.frames.count
        ?? 0

    // Tiberium silo: the sprite has 5 healthy fill stages (0=empty … 4=full)
    // chosen from the OWNING HOUSE's stored tiberium vs total capacity, plus a
    // parallel set of 5 damaged variants at +5. Mirrors VC building.cpp:594-605
    // (Draw_It's STRUCT_STORAGE special case). Fill is house-wide, not per-silo.
    if upper == "SILO" {
        let hs = getHouseState(obj.house)
        var level = 0
        if hs.capacity > 0 {
            level = (hs.tiberium * 5) / hs.capacity
        }
        level = min(4, max(0, level))
        return isDamaged ? level + 5 : level
    }

    // Refinery playing its harvester dock/unload animation (healthy only — the
    // 12-29 frames are the intact building's animation set).
    if upper == "PROC", !isDamaged, !isCritical, let f = procDockAnimFrame(obj) {
        return f
    }

    if obj.hasTurret {
        var base: Int
        if upper == "SAM" {
            base = obj.samDeployState
        } else {
            let facingIdx = facing32[min(255, max(0, obj.turretFacing))]
            base = bodyShape[facingIdx]
        }
        // Damaged set lives at +64 (32 body + 32 turret = "fresh"; next 64 = "damaged").
        if isDamaged && frameCount >= base + 64 + 1 {
            base += 64
        }
        return base
    }

    if isCritical && frameCount >= 1 {
        return frameCount - 1  // rubble
    }
    if isDamaged {
        // Special cases mirror VC building.cpp:582-630.
        if upper == "WEAP" { return frameCount >= 2 ? 1 : 0 }
        // Most simple buildings: second-to-last frame is the damaged variant.
        if frameCount >= 2 { return frameCount - 2 }
    }
    return 0
}

// MARK: - Game Renderer

func renderGame(_ renderer: OpaquePointer?) {
    guard let world = session.world else { return }
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
        } else {
            mobileObjects.append(obj)
        }
    }

    // Sort mobile objects by Y for proper depth ordering
    mobileObjects.sort { $0.worldY < $1.worldY }

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
    let interp = session.renderInterpolation
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

                // Draw aircraft elevated
                let elevatedY = screenY - altOffset
                if let info = getObjectTexture(renderer, typeName: obj.typeName, frame: frameIdx, house: obj.house) {
                    let drawX = screenX - Int32(info.width) / 2
                    let drawY = elevatedY - Int32(info.height) / 2
                    var dstRect = SDL_Rect(x: drawX, y: drawY, w: Int32(info.width), h: Int32(info.height))
                    SDL_RenderCopyEx(renderer, info.texture, nil, &dstRect, 0, nil, bodyFlip)
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
    }

    // Placement preview (rendered in world space with zoom)
    if session.isPlacingStructure {
        renderPlacementPreview(renderer, mouseScreenX: input.mouseX, mouseScreenY: input.mouseY)
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
    let gameViewportCenter = (renderState.windowWidth - sidebarWidth) / 2
    let selectedCount = world.selectedObjects().count
    // Show the mission ACTUALLY being played (not the menu browser index, which
    // stayed at SCG01EA). Derive the mission number + faction from the current
    // scenario name so the friendly title can't drift out of sync.
    let scenarioCode = (session.currentScenarioName ?? session.scenarioList[session.scenarioIndex]).uppercased()
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

    drawText(renderer, "RClick: Move/Attack  F3: Perf  F5: Save  F9: Load  Esc: Menu",
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

// MARK: - UI Sprite Cache (SELECT.SHP, PIPS.SHP, MOUSE.SHP)


func loadUISprites(_ renderer: OpaquePointer?) {
    guard !renderState.uiSpritesLoaded else { return }
    renderState.uiSpritesLoaded = true

    // SELECT.SHP — selection brackets
    if let data = mixManager.retrieve("SELECT.SHP") {
        do {
            renderState.selectSHP = try SHPFile(data: data)
            print("Loaded SELECT.SHP: \(renderState.selectSHP!.frames.count) frames")
            for (i, f) in renderState.selectSHP!.frames.enumerated() {
                let nonZero = f.pixels.filter { $0 != 0 }.count
                print("  SELECT.SHP frame \(i): \(f.width)x\(f.height), \(nonZero) visible pixels")
            }
        } catch {
            print("Failed to parse SELECT.SHP: \(error)")
        }
    }

    // PIPS.SHP — health pips
    if let data = mixManager.retrieve("PIPS.SHP") {
        do {
            renderState.pipsSHP = try SHPFile(data: data)
            print("Loaded PIPS.SHP: \(renderState.pipsSHP!.frames.count) frames")
        } catch {
            print("Failed to parse PIPS.SHP: \(error)")
        }
    }

    // MOUSE.SHP — cursor shapes
    if let data = mixManager.retrieve("MOUSE.SHP") {
        do {
            renderState.mouseSHP = try SHPFile(data: data)
            let shp = renderState.mouseSHP!
            let f0 = shp.frames[0]
            let nonZero = f0.pixels.filter { $0 != 0 }.count
            let paletteLoaded = !renderState.gamePalette.isEmpty
            print("Loaded MOUSE.SHP: \(shp.frames.count) frames, frame 0: \(f0.width)x\(f0.height), \(nonZero) visible, palette loaded: \(paletteLoaded)")
            // Dump unique palette indices used by frame 0
            let usedIndices = Set(f0.pixels.filter { $0 != 0 }).sorted()
            print("  Frame 0 palette indices: \(usedIndices.map { String($0) }.joined(separator: ","))")
            // Dump ASCII art of frame 0
            for y in 0..<min(f0.height, 24) {
                var row = "  "
                for x in 0..<f0.width {
                    let p = f0.pixels[y * f0.width + x]
                    row += p == 0 ? "." : "#"
                }
                print(row)
            }
        } catch {
            print("Failed to parse MOUSE.SHP: \(error)")
        }
    }
}

func getUITexture(_ renderer: OpaquePointer?, shp: SHPFile, frame: Int, cache: inout [Int: OpaquePointer]) -> (texture: OpaquePointer, width: Int, height: Int)? {
    guard frame >= 0 && frame < shp.frames.count else { return nil }
    if let cached = cache[frame] {
        let f = shp.frames[frame]
        return (texture: cached, width: f.width, height: f.height)
    }
    let f = shp.frames[frame]
    // Use UI sprite texture (no shadow on index 4)
    if let texture = createUISpriteTexture(renderer, frame: f) {
        cache[frame] = texture
        return (texture: texture, width: f.width, height: f.height)
    }
    return nil
}

// MARK: - Selection Box Rendering

func renderSelectionBox(_ renderer: OpaquePointer?, x: Int32, y: Int32, w: Int32, h: Int32, healthFraction: Double, cargoPips: Int = 0, maxCargoPips: Int = 0) {
    renderProceduralBrackets(renderer, x: x, y: y, w: w, h: h)
    renderHealthPips(renderer, x: x, y: y, w: w, healthFraction: healthFraction)
    if maxCargoPips > 0 {
        renderCargoPips(renderer, x: x, y: y + h + 2, w: w, cargo: cargoPips, maxCargo: maxCargoPips)
    }
}

/// Fallback procedural white corner brackets
func renderProceduralBrackets(_ renderer: OpaquePointer?, x: Int32, y: Int32, w: Int32, h: Int32) {
    let cornerLen: Int32 = max(4, min(w, h) / 3)
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)

    // Top-left
    SDL_RenderDrawLine(renderer, x, y, x + cornerLen, y)
    SDL_RenderDrawLine(renderer, x, y, x, y + cornerLen)
    // Top-right
    SDL_RenderDrawLine(renderer, x + w, y, x + w - cornerLen, y)
    SDL_RenderDrawLine(renderer, x + w, y, x + w, y + cornerLen)
    // Bottom-left
    SDL_RenderDrawLine(renderer, x, y + h, x + cornerLen, y + h)
    SDL_RenderDrawLine(renderer, x, y + h, x, y + h - cornerLen)
    // Bottom-right
    SDL_RenderDrawLine(renderer, x + w, y + h, x + w - cornerLen, y + h)
    SDL_RenderDrawLine(renderer, x + w, y + h, x + w, y + h - cornerLen)
}

/// Render health bar above selected unit
func renderHealthPips(_ renderer: OpaquePointer?, x: Int32, y: Int32, w: Int32, healthFraction: Double) {
    let healthFrac = max(0.0, min(1.0, healthFraction))

    let barW = w
    let barH: Int32 = 3
    let barX = x
    let barY = y - barH - 2

    SDL_SetRenderDrawColor(renderer, 40, 40, 40, 200)
    var bgRect = SDL_Rect(x: barX, y: barY, w: barW, h: barH)
    SDL_RenderFillRect(renderer, &bgRect)

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

/// Render cargo pips below selected harvesters showing tiberium load
func renderCargoPips(_ renderer: OpaquePointer?, x: Int32, y: Int32, w: Int32, cargo: Int, maxCargo: Int) {
    guard maxCargo > 0 else { return }
    let pipCount = min(maxCargo, 7)  // Show up to 7 pips
    let pipW: Int32 = max(2, w / Int32(pipCount + 1))
    let pipH: Int32 = 2
    let spacing: Int32 = 1
    let totalW = Int32(pipCount) * (pipW + spacing) - spacing
    let startX = x + (w - totalW) / 2

    let filledPips = Int(Double(cargo) / Double(maxCargo) * Double(pipCount))

    for i in 0..<pipCount {
        let px = startX + Int32(i) * (pipW + spacing)
        if i < filledPips {
            // Filled pip: bright green (tiberium)
            SDL_SetRenderDrawColor(renderer, 0, 220, 0, 255)
        } else {
            // Empty pip: dark gray
            SDL_SetRenderDrawColor(renderer, 40, 40, 40, 180)
        }
        var pipRect = SDL_Rect(x: px, y: y, w: pipW, h: pipH)
        SDL_RenderFillRect(renderer, &pipRect)
    }
}

// MARK: - Animation Rendering

/// Render active animations (explosions, fires, smoke)
func renderAnimations(_ renderer: OpaquePointer?, camX: Int, camY: Int, vw: Int32, vh: Int32) {
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)

    for anim in session.activeAnimations {
        if anim.isFinished { continue }

        let screenX = Int32(anim.worldX) - Int32(camX)
        let screenY = Int32(anim.worldY) - Int32(camY)

        // Cull off-screen animations
        let maxSize = Int32(anim.data.size)
        if screenX + maxSize < 0 || screenY + maxSize < 0 ||
           screenX - maxSize > vw || screenY - maxSize > vh { continue }

        // Try to render from SHP sprite (animations are plain .SHP, not theater-specific)
        if let info = getObjectTexture(renderer, typeName: anim.data.name,
                                       frame: anim.currentFrame, house: .neutral,
                                       theater: nil) {
            let drawX = screenX - Int32(info.width) / 2
            let drawY = screenY - Int32(info.height) / 2
            var dstRect = SDL_Rect(x: drawX, y: drawY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        } else {
            // Check if SHP exists but the current frame exceeds its frame count
            // (animation is done — don't show ugly procedural rectangles)
            let animSpriteName = spriteNameOverrides[anim.data.name.uppercased()] ?? anim.data.name.uppercased()
            if let shp = renderState.objectSHPCache[animSpriteName],
               anim.currentFrame >= shp.frames.count {
                anim.isFinished = true
            } else {
                // SHP not loaded yet or truly missing — use procedural fallback
                renderProceduralExplosion(renderer, anim: anim, screenX: screenX, screenY: screenY)
            }
        }
    }

}

/// Render smudges (scorch marks and craters). These are ground decals, so they
/// must be drawn BEFORE buildings and units — otherwise a crater created before
/// a building/vehicle moved onto the cell paints over it. Called from an early
/// pass, right after terrain.
func renderSmudges(_ renderer: OpaquePointer?, camX: Int, camY: Int, vw: Int32, vh: Int32) {
    for smudge in (session.world?.map.smudges ?? []) {
        let cellX = smudge.cell % 64
        let cellY = smudge.cell / 64
        let screenX = Int32(cellX * 24 - camX)
        let screenY = Int32(cellY * 24 - camY)
        if screenX > vw || screenY > vh || screenX + 24 < 0 || screenY + 24 < 0 { continue }

        // Try SHP first
        let theater = session.world?.theater ?? .temperate
        if let info = getObjectTexture(renderer, typeName: smudge.type.rawValue,
                                       frame: 0, house: .neutral, theater: theater) {
            var dstRect = SDL_Rect(x: screenX, y: screenY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        } else {
            // Procedural fallback: dark circle for craters, dark oval for scorch
            SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
            SDL_SetRenderDrawColor(renderer, 20, 15, 10,
                                   smudge.type.isCrater ? 140 : 80)
            let size: Int32 = smudge.type.isCrater ? 16 : 20
            var rect = SDL_Rect(x: screenX + (24 - size) / 2, y: screenY + (24 - size) / 2,
                               w: size, h: size)
            SDL_RenderFillRect(renderer, &rect)
        }
    }
}

/// Procedural explosion effect when SHP not available
func renderProceduralExplosion(_ renderer: OpaquePointer?, anim: GameAnimation, screenX: Int32, screenY: Int32) {
    let maxFrames = anim.data.stages > 0 ? anim.data.stages : 30
    let progress = Double(anim.currentFrame) / Double(max(1, maxFrames))
    let halfSize = Int32(anim.data.size) / 2

    // Explosion: expanding circle that fades
    let radius = Int32(Double(halfSize) * min(1.0, progress * 2.0))
    let alpha = UInt8(max(0, min(255, Int(255.0 * (1.0 - progress)))))

    // Color and shape based on type
    let r: UInt8, g: UInt8, b: UInt8
    switch anim.type {
    case .muzzleFlash:
        // Small bright white-yellow flash, fades fast
        SDL_SetRenderDrawColor(renderer, 255, 255, 200, UInt8(max(0, min(255, 255 - Int(progress * 400)))))
        var flash = SDL_Rect(x: screenX - 3, y: screenY - 3, w: 6, h: 6)
        SDL_RenderFillRect(renderer, &flash)
        return
    case .burnSmall, .burnMed, .burnBig,
         .onFireSmall, .onFireMed, .onFireBig, .fireSmall, .fireMed, .fireMed2, .fireTiny:
        // Persistent fire/smoke effects — render as thin grey smoke puff so a
        // missing SHP doesn't dominate the screen with a glowing red square.
        SDL_SetRenderDrawColor(renderer, 70, 65, 60, alpha / 4)
        let puff = Int32(max(2, Double(halfSize) * 0.4))
        var puffRect = SDL_Rect(x: screenX - puff / 2, y: screenY - puff / 2, w: puff, h: puff)
        SDL_RenderFillRect(renderer, &puffRect)
        return
    case .napalm1, .napalm2, .napalm3:
        r = 255; g = UInt8(max(0, 160 - Int(progress * 160))); b = 0
    case .piff, .piffpiff:
        r = 255; g = 255; b = 200
    case .smokeM, .smokePuff:
        r = 80; g = 80; b = 80
    case .ionCannon:
        r = 100; g = 150; b = 255
    default:
        r = 255; g = UInt8(max(0, 200 - Int(progress * 200))); b = 0
    }

    SDL_SetRenderDrawColor(renderer, r, g, b, alpha)

    // Core
    var coreRect = SDL_Rect(x: screenX - radius, y: screenY - radius,
                           w: radius * 2, h: radius * 2)
    SDL_RenderFillRect(renderer, &coreRect)

    // Outer glow (larger, more transparent)
    if radius > 2 {
        SDL_SetRenderDrawColor(renderer, r, g / 2, 0, alpha / 3)
        var glowRect = SDL_Rect(x: screenX - radius - 2, y: screenY - radius - 2,
                               w: radius * 2 + 4, h: radius * 2 + 4)
        SDL_RenderDrawRect(renderer, &glowRect)
    }
}

// MARK: - Ion Cannon Beam Effect

/// Render procedural ion cannon beam from top of screen to target
func renderIonBeam(_ renderer: OpaquePointer?, camX: Int, camY: Int) {
    guard renderState.ionBeamTimer > 0 else { return }

    let screenX = Int32(renderState.ionBeamWorldX) - Int32(camX)
    let screenY = Int32(renderState.ionBeamWorldY) - Int32(camY)

    // Beam fades over time
    let progress = Double(renderState.ionBeamTimer) / 30.0
    let alpha = UInt8(max(0, min(255, Int(255.0 * progress))))

    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)

    // Wide outer glow
    let outerWidth: Int32 = Int32(12.0 * progress)
    SDL_SetRenderDrawColor(renderer, 80, 120, 255, alpha / 4)
    for dx in -outerWidth...outerWidth {
        SDL_RenderDrawLine(renderer, screenX + dx, -100, screenX + dx, screenY)
    }

    // Medium blue beam
    let midWidth: Int32 = Int32(6.0 * progress)
    SDL_SetRenderDrawColor(renderer, 120, 180, 255, alpha / 2)
    for dx in -midWidth...midWidth {
        SDL_RenderDrawLine(renderer, screenX + dx, -100, screenX + dx, screenY)
    }

    // Inner bright white-blue core
    let coreWidth: Int32 = Int32(2.0 * progress)
    SDL_SetRenderDrawColor(renderer, 200, 230, 255, alpha)
    for dx in -coreWidth...coreWidth {
        SDL_RenderDrawLine(renderer, screenX + dx, -100, screenX + dx, screenY)
    }

    // Impact glow at target
    let glowRadius = Int32(20.0 * progress)
    SDL_SetRenderDrawColor(renderer, 180, 220, 255, alpha / 3)
    var glowRect = SDL_Rect(x: screenX - glowRadius, y: screenY - glowRadius,
                           w: glowRadius * 2, h: glowRadius * 2)
    SDL_RenderFillRect(renderer, &glowRect)

    // Bright center flash at impact
    let flashR = Int32(8.0 * progress)
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, alpha)
    var flashRect = SDL_Rect(x: screenX - flashR, y: screenY - flashR,
                            w: flashR * 2, h: flashR * 2)
    SDL_RenderFillRect(renderer, &flashRect)
}

// MARK: - Game Minimap

func renderGameMinimap(_ renderer: OpaquePointer?, world: GameWorld) {
    let minimapCellSize: Int32 = 2
    let minimapSize: Int32 = 64 * minimapCellSize
    let minimapPad: Int32 = 10
    let minimapX = renderState.windowWidth - sidebarWidth - minimapSize - minimapPad
    let minimapY = renderState.windowHeight - minimapSize - minimapPad
    let mapSize = 64
    let tileSize = 24

    guard let scenario = scenarioData else { return }

    // Power gating: disable minimap when player has no Communications Center or low power
    let playerHouse = world.playerHouse
    let playerState = getHouseState(playerHouse)
    let hasCommsCenter = world.hasBuilding(type: "HQ", house: playerHouse) ||
                         world.hasBuilding(type: "EYE", house: playerHouse)

    if !hasCommsCenter || playerState.isLowPower {
        // Render disabled minimap: dark background with static noise
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 180)
        var minimapBg = SDL_Rect(x: minimapX - 2, y: minimapY - 2, w: minimapSize + 4, h: minimapSize + 4)
        SDL_RenderFillRect(renderer, &minimapBg)

        // Static noise dots
        SDL_SetRenderDrawColor(renderer, 30, 30, 30, 255)
        var fillRect = SDL_Rect(x: minimapX, y: minimapY, w: minimapSize, h: minimapSize)
        SDL_RenderFillRect(renderer, &fillRect)

        // Random static dots for visual noise effect (use tick count as seed variation)
        let tick = world.tickCount
        for i in stride(from: 0, to: Int(minimapSize * minimapSize) / 8, by: 1) {
            let hash = (i &* 2654435761 &+ tick &* 31) & 0x7FFFFFFF
            let px = minimapX + Int32(hash % Int(minimapSize))
            let py = minimapY + Int32((hash / Int(minimapSize)) % Int(minimapSize))
            let brightness = UInt8(40 + (hash / Int(minimapSize * minimapSize)) % 40)
            SDL_SetRenderDrawColor(renderer, brightness, brightness, brightness, 255)
            var dot = SDL_Rect(x: px, y: py, w: 1, h: 1)
            SDL_RenderFillRect(renderer, &dot)
        }

        // "LOW POWER" or "NO RADAR" text overlay
        let label = playerState.isLowPower ? "LOW POWER" : "NO RADAR"
        drawText(renderer, label,
                 centerX: minimapX + minimapSize / 2,
                 centerY: minimapY + minimapSize / 2,
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
    let vpX = minimapX + Int32(renderState.gameCameraX / Double(tileSize)) * minimapCellSize
    let vpY = minimapY + Int32(renderState.gameCameraY / Double(tileSize)) * minimapCellSize
    let vpW = Int32(Double(renderState.windowWidth - sidebarWidth) / renderState.gameZoomLevel / Double(tileSize)) * minimapCellSize
    let vpH = Int32(Double(renderState.windowHeight) / renderState.gameZoomLevel / Double(tileSize)) * minimapCellSize
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
    var vpRect = SDL_Rect(x: vpX, y: vpY, w: vpW, h: vpH)
    SDL_RenderDrawRect(renderer, &vpRect)
}
