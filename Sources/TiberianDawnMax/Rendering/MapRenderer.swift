import CSDL2
import Foundation

// MARK: - Map Viewer State

/// Standalone map used in map-viewer mode (no GameWorld)
var mapViewerMap = GameMap()

/// Backward-compatible accessor — delegates to world.map when in game, mapViewerMap otherwise
var mapCells: [MapCell] {
    get { session.world?.map.cells ?? mapViewerMap.cells }
    set {
        if let world = session.world {
            world.map.cells = newValue
        } else {
            mapViewerMap.cells = newValue
        }
    }
}

/// Backward-compatible accessor — delegates to world.map when in game, mapViewerMap otherwise
var scenarioData: ScenarioData? {
    get { session.world?.map.scenarioData ?? mapViewerMap.scenarioData }
    set {
        if let world = session.world {
            world.map.scenarioData = newValue
        } else {
            mapViewerMap.scenarioData = newValue
        }
    }
}

// Info panel & overlay toggle state

// MARK: - Facing & Remap Lookup Tables (from Vanilla Conquer tiberiandawn/const.cpp)

/// Maps 0-255 facing value to 32-direction index
let facing32: [Int] = [
    0,0,0,0,0,1,1,1,1,1,1,1,1,1,2,2,
    2,2,2,2,2,2,3,3,3,3,3,3,3,3,3,4,
    4,4,4,4,4,4,4,5,5,5,5,5,5,5,5,5,
    6,6,6,6,6,6,6,6,7,7,7,7,7,7,7,7,
    8,8,8,8,8,8,8,8,8,9,9,9,9,9,9,9,
    9,10,10,10,10,10,10,10,10,10,11,11,11,11,11,11,
    11,11,12,12,12,12,12,12,12,12,12,13,13,13,13,13,
    13,13,13,14,14,14,14,14,14,14,14,14,15,15,15,15,
    15,15,15,15,16,16,16,16,16,16,16,16,16,17,17,17,
    17,17,17,17,17,18,18,18,18,18,18,18,18,18,19,19,
    19,19,19,19,19,19,20,20,20,20,20,20,20,20,20,21,
    21,21,21,21,21,21,21,22,22,22,22,22,22,22,22,22,
    23,23,23,23,23,23,23,23,24,24,24,24,24,24,24,24,
    24,25,25,25,25,25,25,25,25,26,26,26,26,26,26,26,
    26,26,27,27,27,27,27,27,27,27,28,28,28,28,28,28,
    28,28,28,29,29,29,29,29,29,29,29,30,30,30,30,30
]

/// Maps 32-direction index to SHP frame index for vehicle body rotation
let bodyShape: [Int] = [
    0,31,30,29,28,27,26,25,24,23,22,21,20,19,18,17,
    16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1
]

/// Maps 32-direction index to 8-direction index for infantry
let humanShape: [Int] = [
    0,0,7,7,7,7,6,6,6,6,5,5,5,5,5,4,
    4,4,3,3,3,3,2,2,2,2,1,1,1,1,1,0
]

/// House color remap tables — each has 16 entries replacing palette indices 176-191
/// From Vanilla Conquer tiberiandawn/const.cpp
let remapRed: [UInt8] = [
    127,126,125,124,122,46,120,47,125,124,123,122,42,121,120,120
]
let remapBlue: [UInt8] = [
    2,119,118,135,136,138,112,12,118,135,136,137,138,139,114,112
]
let remapOrange: [UInt8] = [
    24,25,26,27,29,31,46,47,26,27,28,29,30,31,43,47
]
let remapGreen: [UInt8] = [
    5,165,166,167,159,142,140,199,166,167,157,3,159,143,142,141
]
let remapLtBlue: [UInt8] = [
    161,200,201,202,204,205,206,12,201,202,203,204,205,115,198,114
]

/// Returns the 16-entry remap table for a given house, or nil for identity (no remap)
func remapTable(for house: House) -> [UInt8]? {
    switch house {
    case .goodGuy:  return nil          // GDI uses default gold (identity)
    case .badGuy:   return remapRed     // Nod = red
    case .neutral:  return nil           // Neutral = identity
    case .special:  return nil           // Special = identity
    case .multi1:   return remapLtBlue  // Multi1 = light blue
    case .multi2:   return remapOrange  // Multi2 = orange
    case .multi3:   return remapGreen   // Multi3 = green
    case .multi4:   return nil          // Multi4 = gold (default)
    case .multi5:   return remapRed     // Multi5 = red (same as Nod)
    case .multi6:   return remapBlue    // Multi6 = blue
    }
}

/// Animation frame counter, incremented each render frame

// MARK: - Loading

func loadMapViewerData(_ scenarioName: String = "SCG01EA") {
    renderState.cameraX = 0
    renderState.cameraY = 0
    renderState.zoomLevel = 1.0

    // Clear texture caches since different theaters use different palettes/art
    for (_, texture) in renderState.objectTextureCache { SDL_DestroyTexture(texture) }
    renderState.objectTextureCache.removeAll()
    renderState.objectSHPCache.removeAll()
    renderState.objectFailedSHPs.removeAll()
    clearRemasteredTextureCache()

    for (_, texture) in renderState.terrainTextureCache { SDL_DestroyTexture(texture) }
    renderState.terrainTextureCache.removeAll()
    renderState.terrainSHPCache.removeAll()
    renderState.terrainFailedSHPs.removeAll()

    for (_, texture) in renderState.tileTextureCache { SDL_DestroyTexture(texture) }
    renderState.tileTextureCache.removeAll()
    renderState.icnCache.removeAll()
    renderState.mapFailedICNs.removeAll()

    let binName = scenarioName + ".BIN"
    let iniName = scenarioName + ".INI"

    if let cells = loadMap(binName, from: mixManager) {
        mapCells = cells
    } else {
        print("MapViewer: Failed to load \(binName)")
        mapCells = (0..<4096).map { _ in MapCell(templateType: 0xFF, iconIndex: 0) }
    }

    scenarioData = loadScenario(iniName, from: mixManager)

    // Reload palette for the scenario's theater (desert/winter/temperate)
    if let theater = scenarioData?.theater {
        renderState.gamePalette = loadPalette(theater.paletteName)
    }

    if let bounds = scenarioData?.mapBounds {
        renderState.cameraX = bounds.x * 24
        renderState.cameraY = bounds.y * 24
    }

}

// MARK: - Texture Creation

func createTileTexture(_ renderer: OpaquePointer?, pixels: [UInt8]) -> OpaquePointer? {
    let format: UInt32 = 0x16362004  // SDL_PIXELFORMAT_ARGB8888
    guard let texture = SDL_CreateTexture(renderer, format, Int32(SDL_TEXTUREACCESS_STATIC.rawValue), 24, 24) else {
        return nil
    }

    var argb = [UInt32](repeating: 0, count: 576)
    for i in 0..<576 {
        let palIdx = Int(pixels[i])
        let c = renderState.gamePalette[palIdx]
        argb[i] = 0xFF000000 | (UInt32(c.r) << 16) | (UInt32(c.g) << 8) | UInt32(c.b)
    }

    _ = argb.withUnsafeMutableBufferPointer { buf in
        SDL_UpdateTexture(texture, nil, buf.baseAddress, 24 * 4)
    }

    return texture
}

func createSpriteTexture(_ renderer: OpaquePointer?, frame: SHPFrame) -> OpaquePointer? {
    let w = frame.width
    let h = frame.height
    guard w > 0 && h > 0 else { return nil }
    let format: UInt32 = 0x16362004  // SDL_PIXELFORMAT_ARGB8888
    guard let texture = SDL_CreateTexture(renderer, format, Int32(SDL_TEXTUREACCESS_STATIC.rawValue), Int32(w), Int32(h)) else {
        return nil
    }

    var argb = [UInt32](repeating: 0, count: w * h)
    for i in 0..<(w * h) {
        let palIdx = Int(frame.pixels[i])
        if palIdx == 0 {
            argb[i] = 0x00000000  // Fully transparent
        } else if palIdx == 4 {
            argb[i] = 0x80000000  // Shadow: 50% transparent black
        } else {
            let c = renderState.gamePalette[palIdx]
            argb[i] = 0xFF000000 | (UInt32(c.r) << 16) | (UInt32(c.g) << 8) | UInt32(c.b)
        }
    }

    _ = argb.withUnsafeMutableBufferPointer { buf in
        SDL_UpdateTexture(texture, nil, buf.baseAddress, Int32(w * 4))
    }
    SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)
    return texture
}

func createRemappedSpriteTexture(_ renderer: OpaquePointer?, frame: SHPFrame, house: House) -> OpaquePointer? {
    let w = frame.width
    let h = frame.height
    guard w > 0 && h > 0 else { return nil }
    let format: UInt32 = 0x16362004  // SDL_PIXELFORMAT_ARGB8888
    guard let texture = SDL_CreateTexture(renderer, format, Int32(SDL_TEXTUREACCESS_STATIC.rawValue), Int32(w), Int32(h)) else {
        return nil
    }

    let remap = remapTable(for: house)
    var argb = [UInt32](repeating: 0, count: w * h)
    for i in 0..<(w * h) {
        var palIdx = Int(frame.pixels[i])
        if palIdx == 0 {
            argb[i] = 0x00000000
        } else if palIdx == 4 {
            argb[i] = 0x80000000  // Shadow: 50% transparent black
        } else {
            if let remap = remap, palIdx >= 176 && palIdx <= 191 {
                palIdx = Int(remap[palIdx - 176])
            }
            let c = renderState.gamePalette[palIdx]
            argb[i] = 0xFF000000 | (UInt32(c.r) << 16) | (UInt32(c.g) << 8) | UInt32(c.b)
        }
    }

    _ = argb.withUnsafeMutableBufferPointer { buf in
        SDL_UpdateTexture(texture, nil, buf.baseAddress, Int32(w * 4))
    }
    SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)
    return texture
}

// MARK: - Texture Caching

func getTerrainTexture(_ renderer: OpaquePointer?, typeName: String, theater: TheaterType, animFrame: Int = 0) -> (texture: OpaquePointer, width: Int, height: Int)? {
    let upperName = typeName.uppercased()

    // Load SHP into cache if needed
    if renderState.terrainSHPCache[upperName] == nil && !renderState.terrainFailedSHPs.contains(upperName) {
        let filename = upperName + theater.suffix
        guard let data = mixManager.retrieve(filename) else {
            renderState.terrainFailedSHPs.insert(upperName)
            return nil
        }
        do {
            let shp = try SHPFile(data: data)
            guard !shp.frames.isEmpty else {
                renderState.terrainFailedSHPs.insert(upperName)
                return nil
            }
            renderState.terrainSHPCache[upperName] = shp
        } catch {
            renderState.terrainFailedSHPs.insert(upperName)
            return nil
        }
    }

    if renderState.terrainFailedSHPs.contains(upperName) { return nil }

    guard let shp = renderState.terrainSHPCache[upperName] else { return nil }

    // Terrain SHPs have normal frames in the first half, shadow frames in the second half
    let normalFrameCount = max(1, shp.frames.count / 2)
    let frameIdx: Int
    if normalFrameCount > 1 {
        frameIdx = (animFrame / 8) % normalFrameCount
    } else {
        frameIdx = 0
    }

    let key = "\(upperName)_\(frameIdx)"
    if let cached = renderState.terrainTextureCache[key] {
        let frame = shp.frames[frameIdx]
        return (texture: cached, width: frame.width, height: frame.height)
    }

    let frame = shp.frames[frameIdx]
    if let texture = createSpriteTexture(renderer, frame: frame) {
        renderState.terrainTextureCache[key] = texture
        return (texture: texture, width: frame.width, height: frame.height)
    }
    return nil
}

func getObjectTexture(_ renderer: OpaquePointer?, typeName: String, frame: Int, house: House, theater: TheaterType? = nil) -> (texture: OpaquePointer, width: Int, height: Int)? {
    let upperName = typeName.uppercased()

    // Try remastered sprite first (hi-res PNG)
    if let remastered = getRemasteredTexture(renderer, typeName: upperName, frame: frame) {
        return remastered
    }

    // Fall back to classic SHP from MIX archives
    let key = "\(upperName)_\(frame)_\(house.rawValue)"

    if let cached = renderState.objectTextureCache[key] {
        let shp = renderState.objectSHPCache[upperName]!
        let f = shp.frames[frame]
        return (texture: cached, width: f.width, height: f.height)
    }

    if renderState.objectFailedSHPs.contains(upperName) { return nil }

    if renderState.objectSHPCache[upperName] == nil {
        var data: Data? = nil
        // Buildings/overlays use theater-specific extensions (.TEM, .DES, .WIN)
        if let theater = theater {
            data = mixManager.retrieve(upperName + theater.suffix)
        }
        // Units/infantry use .SHP; also fallback for buildings
        if data == nil {
            data = mixManager.retrieve(upperName + ".SHP")
        }
        guard let fileData = data else {
            renderState.objectFailedSHPs.insert(upperName)
            return nil
        }
        do {
            renderState.objectSHPCache[upperName] = try SHPFile(data: fileData)
        } catch {
            renderState.objectFailedSHPs.insert(upperName)
            return nil
        }
    }

    guard let shp = renderState.objectSHPCache[upperName],
          frame < shp.frames.count else {
        return nil
    }

    let f = shp.frames[frame]
    if let texture = createRemappedSpriteTexture(renderer, frame: f, house: house) {
        renderState.objectTextureCache[key] = texture
        return (texture: texture, width: f.width, height: f.height)
    }
    return nil
}

func getTileTexture(_ renderer: OpaquePointer?, icnName: String, iconIndex: Int, theater: TheaterType = .temperate) -> OpaquePointer? {
    let key = "\(icnName)_\(iconIndex)"
    if let cached = renderState.tileTextureCache[key] {
        return cached
    }

    if renderState.icnCache[icnName] == nil && !renderState.mapFailedICNs.contains(icnName) {
        let filename = icnName + theater.suffix
        if let data = mixManager.retrieve(filename) {
            do {
                renderState.icnCache[icnName] = try ICNFile(data: data)
            } catch {
                print("MapViewer: Failed to parse \(filename): \(error)")
                renderState.mapFailedICNs.insert(icnName)
            }
        } else {
            renderState.mapFailedICNs.insert(icnName)
        }
    }

    guard let icn = renderState.icnCache[icnName], let pixels = icn.tile(icon: iconIndex) else {
        return nil
    }

    if let texture = createTileTexture(renderer, pixels: pixels) {
        renderState.tileTextureCache[key] = texture
        return texture
    }
    return nil
}

// MARK: - Building Bib Lookup

/// Returns the bib type name and dimensions for a bibbed building, or nil if no bib.
/// Based on Vanilla Conquer tiberiandawn/bdata.cpp Bib_And_Offset logic:
///   - Width 2 buildings use BIB3 (2x2 cells)
///   - Width 3 buildings use BIB2 (3x2 cells)
///   - Width 4 buildings use BIB1 (4x2 cells)
/// The bib is placed at the bottom row of the building footprint.
func buildingBibInfo(_ typeName: String) -> (bibName: String, bibW: Int, bibH: Int)? {
    let upper = typeName.uppercased()

    // Buildings with IsBibbed = true from bdata.cpp
    let bibbedBuildings: Set<String> = [
        "TMPL", "EYE", "WEAP", "FACT", "PROC", "SILO", "HPAD",
        "HQ", "AFLD", "NUKE", "NUK2", "HOSP", "BIO", "PYLE",
        "HAND", "FIX", "MISS",
    ]

    guard bibbedBuildings.contains(upper) else { return nil }

    let size = buildingSize(upper)
    switch size.w {
    case 2:  return (bibName: "BIB3", bibW: 2, bibH: 2)
    case 3:  return (bibName: "BIB2", bibW: 3, bibH: 2)
    case 4:  return (bibName: "BIB1", bibW: 4, bibH: 2)
    default: return nil
    }
}

// MARK: - Multi-Pass Rendering

func renderMapViewer(_ renderer: OpaquePointer?) {
    let tileSize = 24
    let mapSize = 64

    // Apply zoom scaling to all rendering
    SDL_RenderSetScale(renderer, Float(renderState.zoomLevel), Float(renderState.zoomLevel))

    // Visible area shrinks/grows with zoom
    let visibleWidth = Int(Double(renderState.windowWidth) / renderState.zoomLevel)
    let visibleHeight = Int(Double(renderState.windowHeight) / renderState.zoomLevel)

    let startCellX = max(0, renderState.cameraX / tileSize)
    let startCellY = max(0, renderState.cameraY / tileSize)
    let endCellX = min(mapSize - 1, (renderState.cameraX + visibleWidth) / tileSize)
    let endCellY = min(mapSize - 1, (renderState.cameraY + visibleHeight) / tileSize)

    let theater = scenarioData?.theater ?? .temperate

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
                let screenX = Int32(cellX * tileSize - renderState.cameraX)
                let screenY = Int32(cellY * tileSize - renderState.cameraY)
                var dstRect = SDL_Rect(x: screenX, y: screenY, w: Int32(tileSize), h: Int32(tileSize))
                SDL_RenderCopy(renderer, texture, nil, &dstRect)
            } else {
                let screenX = Int32(cellX * tileSize - renderState.cameraX)
                let screenY = Int32(cellY * tileSize - renderState.cameraY)
                SDL_SetRenderDrawColor(renderer, 0, 100, 0, 255)
                var rect = SDL_Rect(x: screenX, y: screenY, w: Int32(tileSize), h: Int32(tileSize))
                SDL_RenderFillRect(renderer, &rect)
            }
        }
    }

    let vw = Int32(visibleWidth)
    let vh = Int32(visibleHeight)

    guard let scenario = scenarioData else {
        SDL_RenderSetScale(renderer, 1.0, 1.0)
        return
    }

    // === Pass 2: Overlays (tiberium, walls, roads) as SHP sprites ===
    // Build wall connectivity lookup so walls pick connected frames
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
        let screenX = Int32(pos.px - renderState.cameraX)
        let screenY = Int32(pos.py - renderState.cameraY)

        if screenX > vw || screenY > vh || screenX + 24 < 0 || screenY + 24 < 0 { continue }

        let upper = overlay.typeName.uppercased()

        // Wall overlays: compute frame from neighbor connectivity (4-bit N/E/S/W mask)
        var frameIdx = 0
        if wallTypes.contains(upper) {
            let cell = overlay.cell
            if cell >= 64 && wallCells[cell - 64] == upper { frameIdx |= 1 }   // North
            if (cell % 64) < 63 && wallCells[cell + 1] == upper { frameIdx |= 2 }  // East
            if cell + 64 < 64 * 64 && wallCells[cell + 64] == upper { frameIdx |= 4 }  // South
            if (cell % 64) > 0 && wallCells[cell - 1] == upper { frameIdx |= 8 }   // West
        }

        if let info = getObjectTexture(renderer, typeName: overlay.typeName, frame: frameIdx, house: .neutral, theater: theater) {
            var dstRect = SDL_Rect(x: screenX, y: screenY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        } else {
            if upper.hasPrefix("TI") {
                SDL_SetRenderDrawColor(renderer, 0, 200, 0, 120)
            } else if wallTypes.contains(upper) {
                SDL_SetRenderDrawColor(renderer, 150, 150, 150, 200)
            } else {
                SDL_SetRenderDrawColor(renderer, 80, 80, 80, 140)
            }
            var rect = SDL_Rect(x: screenX + 2, y: screenY + 2, w: 20, h: 20)
            SDL_RenderFillRect(renderer, &rect)
        }
    }

    // === Pass 3: Terrain objects (trees, rocks) as SHP sprites ===
    for terrainObj in scenario.terrain {
        let pos = cellToPixel(terrainObj.cell)

        if let info = getTerrainTexture(renderer, typeName: terrainObj.typeName, theater: theater, animFrame: renderState.animationFrame) {
            let screenX = Int32(pos.px - renderState.cameraX)
            let screenY = Int32(pos.py + 24 - info.height - renderState.cameraY)

            if screenX > vw || screenY > vh ||
               screenX + Int32(info.width) < 0 || screenY + Int32(info.height) < 0 { continue }

            var dstRect = SDL_Rect(x: screenX, y: screenY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        } else {
            let screenX = Int32(pos.px - renderState.cameraX)
            let screenY = Int32(pos.py - renderState.cameraY)
            if screenX > vw || screenY > vh || screenX + 24 < 0 || screenY + 24 < 0 { continue }
            SDL_SetRenderDrawColor(renderer, 0, 80, 0, 200)
            var rect = SDL_Rect(x: screenX + 4, y: screenY + 4, w: 16, h: 16)
            SDL_RenderFillRect(renderer, &rect)
        }
    }

    // === Pass 4: Structures (bibs + SHP sprites with fallback rectangles) ===
    for structure in scenario.structures {
        let pos = cellToPixel(structure.cell)
        let size = buildingSize(structure.typeName)
        let pixW = Int32(size.w * 24)
        let pixH = Int32(size.h * 24)
        let screenX = Int32(pos.px - renderState.cameraX)
        let screenY = Int32(pos.py - renderState.cameraY)

        if screenX > vw || screenY > vh ||
           screenX + pixW < 0 || screenY + pixH < 0 { continue }

        // Render bib (foundation pad) underneath the building
        if let bib = buildingBibInfo(structure.typeName) {
            // Bib starts at the bottom row of the building footprint
            let bibOriginCell = structure.cell + (size.h - 1) * 64
            for bibRow in 0..<bib.bibH {
                for bibCol in 0..<bib.bibW {
                    let bibCell = bibOriginCell + bibRow * 64 + bibCol
                    let bibPos = cellToPixel(bibCell)
                    let bibScreenX = Int32(bibPos.px - renderState.cameraX)
                    let bibScreenY = Int32(bibPos.py - renderState.cameraY)
                    // SHP frame index = col + row * width
                    let bibFrame = bibCol + bibRow * bib.bibW
                    if let bibInfo = getObjectTexture(renderer, typeName: bib.bibName, frame: bibFrame, house: .neutral, theater: theater) {
                        var bibRect = SDL_Rect(x: bibScreenX, y: bibScreenY, w: Int32(bibInfo.width), h: Int32(bibInfo.height))
                        SDL_RenderCopy(renderer, bibInfo.texture, nil, &bibRect)
                    }
                }
            }
        }

        if let info = getObjectTexture(renderer, typeName: structure.typeName, frame: 0, house: structure.house, theater: theater) {
            // Anchor sprite bottom-left to the building cell area
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

            drawText(renderer, structure.typeName,
                     centerX: screenX + pixW / 2,
                     centerY: screenY + pixH / 2,
                     color: Color.white, scale: 1)
        }
    }

    // === Pass 5: Units (SHP sprites with fallback rectangles) ===
    for unit in scenario.units {
        let pos = cellToPixel(unit.cell)
        let facingIdx = facing32[min(255, max(0, unit.facing))]
        let frameIdx = bodyShape[facingIdx]

        if let info = getObjectTexture(renderer, typeName: unit.typeName, frame: frameIdx, house: unit.house) {
            let screenX = Int32(pos.px - renderState.cameraX) + 12 - Int32(info.width) / 2
            let screenY = Int32(pos.py - renderState.cameraY) + 12 - Int32(info.height) / 2
            if screenX > vw || screenY > vh ||
               screenX + Int32(info.width) < 0 || screenY + Int32(info.height) < 0 { continue }
            var dstRect = SDL_Rect(x: screenX, y: screenY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        } else {
            let screenX = Int32(pos.px - renderState.cameraX) + 4
            let screenY = Int32(pos.py - renderState.cameraY) + 4
            let unitSize: Int32 = 16
            if screenX > vw || screenY > vh ||
               screenX + unitSize < 0 || screenY + unitSize < 0 { continue }
            let hc = unit.house.displayColor
            SDL_SetRenderDrawColor(renderer, hc.r, hc.g, hc.b, 200)
            var rect = SDL_Rect(x: screenX, y: screenY, w: unitSize, h: unitSize)
            SDL_RenderFillRect(renderer, &rect)
            SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
            SDL_RenderDrawRect(renderer, &rect)
        }
    }

    // === Pass 6: Infantry (SHP sprites with fallback dots) ===
    for inf in scenario.infantry {
        let pos = cellToPixel(inf.cell)
        let sub = subCellOffset(inf.subLocation)
        let facingIdx = facing32[min(255, max(0, inf.facing))]
        let frameIdx = humanShape[facingIdx]

        if let info = getObjectTexture(renderer, typeName: inf.typeName, frame: frameIdx, house: inf.house) {
            let screenX = Int32(pos.px + sub.dx - renderState.cameraX) + 3 - Int32(info.width) / 2
            let screenY = Int32(pos.py + sub.dy - renderState.cameraY) + 3 - Int32(info.height) / 2
            if screenX > vw || screenY > vh ||
               screenX + Int32(info.width) < 0 || screenY + Int32(info.height) < 0 { continue }
            var dstRect = SDL_Rect(x: screenX, y: screenY, w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dstRect)
        } else {
            let screenX = Int32(pos.px + sub.dx - renderState.cameraX)
            let screenY = Int32(pos.py + sub.dy - renderState.cameraY)
            let dotSize: Int32 = 6
            if screenX > vw || screenY > vh ||
               screenX + dotSize < 0 || screenY + dotSize < 0 { continue }
            let hc = inf.house.displayColor
            SDL_SetRenderDrawColor(renderer, hc.r, hc.g, hc.b, 255)
            var rect = SDL_Rect(x: screenX, y: screenY, w: dotSize, h: dotSize)
            SDL_RenderFillRect(renderer, &rect)
        }
    }

    // === Pass 7: Waypoint markers ===
    for wp in scenario.waypoints {
        let pos = cellToPixel(wp.cell)
        let cx = Int32(pos.px - renderState.cameraX) + 12  // Center of cell
        let cy = Int32(pos.py - renderState.cameraY) + 12

        if cx < -12 || cy < -12 || cx > vw + 12 || cy > vh + 12 { continue }

        // Choose color and label based on waypoint type
        let color: Color
        let label: String
        if wp.id == 98 {
            color = .magenta
            label = "SP"  // Start Position
        } else if wp.id == 25 {
            color = .amber
            label = "RP"  // Rally Point
        } else {
            color = .cyan
            label = "\(wp.id)"
        }

        // Draw diamond marker (4 lines forming a diamond shape)
        let d: Int32 = 6  // Diamond half-size
        SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, 220)
        SDL_RenderDrawLine(renderer, cx, cy - d, cx + d, cy)  // Top to right
        SDL_RenderDrawLine(renderer, cx + d, cy, cx, cy + d)  // Right to bottom
        SDL_RenderDrawLine(renderer, cx, cy + d, cx - d, cy)  // Bottom to left
        SDL_RenderDrawLine(renderer, cx - d, cy, cx, cy - d)  // Left to top
        // Draw inner diamond for thickness
        let d2: Int32 = 5
        SDL_RenderDrawLine(renderer, cx, cy - d2, cx + d2, cy)
        SDL_RenderDrawLine(renderer, cx + d2, cy, cx, cy + d2)
        SDL_RenderDrawLine(renderer, cx, cy + d2, cx - d2, cy)
        SDL_RenderDrawLine(renderer, cx - d2, cy, cx, cy - d2)

        // Draw waypoint label above the diamond
        drawText(renderer, label, centerX: cx, centerY: cy - d - 6, color: color, scale: 1)
    }

    // === Pass 7b: CellTrigger visualization ===
    if renderState.showCellTriggers {
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
        for ct in scenario.cellTriggers {
            let pos = cellToPixel(ct.cell)
            let screenX = Int32(pos.px - renderState.cameraX)
            let screenY = Int32(pos.py - renderState.cameraY)
            if screenX > vw || screenY > vh || screenX + 24 < 0 || screenY + 24 < 0 { continue }

            // Semi-transparent orange fill
            SDL_SetRenderDrawColor(renderer, 220, 120, 20, 80)
            var rect = SDL_Rect(x: screenX, y: screenY, w: 24, h: 24)
            SDL_RenderFillRect(renderer, &rect)

            // Orange border
            SDL_SetRenderDrawColor(renderer, 220, 120, 20, 200)
            SDL_RenderDrawRect(renderer, &rect)

            // Trigger name as small text
            drawText(renderer, ct.triggerName, centerX: screenX + 12, centerY: screenY + 12, color: .amber, scale: 1)
        }
    }

    // === Pass 7c: Base rebuild list visualization ===
    if renderState.showBaseList {
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
        for base in scenario.baseBuildings {
            let pos = cellToPixel(base.cell)
            let size = buildingSize(base.typeName)
            let pixW = Int32(size.w * 24)
            let pixH = Int32(size.h * 24)
            let screenX = Int32(pos.px - renderState.cameraX)
            let screenY = Int32(pos.py - renderState.cameraY)

            if screenX > vw || screenY > vh || screenX + pixW < 0 || screenY + pixH < 0 { continue }

            // Semi-transparent purple fill
            SDL_SetRenderDrawColor(renderer, 140, 60, 200, 50)
            var rect = SDL_Rect(x: screenX, y: screenY, w: pixW, h: pixH)
            SDL_RenderFillRect(renderer, &rect)

            // Purple border
            SDL_SetRenderDrawColor(renderer, 140, 60, 200, 180)
            SDL_RenderDrawRect(renderer, &rect)
            // Inner border for dashed effect
            var inner = SDL_Rect(x: screenX + 2, y: screenY + 2, w: pixW - 4, h: pixH - 4)
            SDL_RenderDrawRect(renderer, &inner)

            // Building type name centered
            drawText(renderer, base.typeName, centerX: screenX + pixW / 2, centerY: screenY + pixH / 2, color: .magenta, scale: 1)
        }
    }

    // === Pass 7d: Info panel cell highlight ===
    if renderState.showInfoPanel {
        let hovCellX = input.mouseWorldX / 24
        let hovCellY = input.mouseWorldY / 24
        if hovCellX >= 0 && hovCellX < 64 && hovCellY >= 0 && hovCellY < 64 {
            let screenX = Int32(hovCellX * 24 - renderState.cameraX)
            let screenY = Int32(hovCellY * 24 - renderState.cameraY)
            SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
            SDL_SetRenderDrawColor(renderer, 255, 255, 255, 120)
            var rect = SDL_Rect(x: screenX, y: screenY, w: 24, h: 24)
            SDL_RenderFillRect(renderer, &rect)
            SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
            SDL_RenderDrawRect(renderer, &rect)
        }
    }

    // === Pass 8: Cell Grid overlay ===
    if renderState.showGrid {
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
        SDL_SetRenderDrawColor(renderer, 255, 255, 255, 30)
        // Vertical lines at cell boundaries
        for cellX in startCellX...(endCellX + 1) {
            let screenX = Int32(cellX * tileSize - renderState.cameraX)
            let topY = Int32(startCellY * tileSize - renderState.cameraY)
            let botY = Int32((endCellY + 1) * tileSize - renderState.cameraY)
            SDL_RenderDrawLine(renderer, screenX, topY, screenX, botY)
        }
        // Horizontal lines at cell boundaries
        for cellY in startCellY...(endCellY + 1) {
            let screenY = Int32(cellY * tileSize - renderState.cameraY)
            let leftX = Int32(startCellX * tileSize - renderState.cameraX)
            let rightX = Int32((endCellX + 1) * tileSize - renderState.cameraX)
            SDL_RenderDrawLine(renderer, leftX, screenY, rightX, screenY)
        }
    }

    // === Pass 9: Shroud (darken areas outside map bounds) ===
    if let bounds = scenario.mapBounds {
        let bx = Int32(bounds.x * tileSize - renderState.cameraX)
        let by = Int32(bounds.y * tileSize - renderState.cameraY)
        let bw = Int32(bounds.width * tileSize)
        let bh = Int32(bounds.height * tileSize)

        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 160)

        // Top strip (above map bounds, full width)
        if by > 0 {
            var r = SDL_Rect(x: 0, y: 0, w: vw, h: by)
            SDL_RenderFillRect(renderer, &r)
        }
        // Bottom strip (below map bounds, full width)
        let bottomY = by + bh
        if bottomY < vh {
            var r = SDL_Rect(x: 0, y: bottomY, w: vw, h: vh - bottomY)
            SDL_RenderFillRect(renderer, &r)
        }
        // Left strip (between top and bottom strips)
        let stripTop = max(0, by)
        let stripBottom = min(vh, bottomY)
        let stripH = stripBottom - stripTop
        if bx > 0 && stripH > 0 {
            var r = SDL_Rect(x: 0, y: stripTop, w: bx, h: stripH)
            SDL_RenderFillRect(renderer, &r)
        }
        // Right strip (between top and bottom strips)
        let rightX = bx + bw
        if rightX < vw && stripH > 0 {
            var r = SDL_Rect(x: rightX, y: stripTop, w: vw - rightX, h: stripH)
            SDL_RenderFillRect(renderer, &r)
        }
    }

    // Reset scale so HUD text renders at native resolution
    SDL_RenderSetScale(renderer, 1.0, 1.0)

    // === Pass 10: Minimap (128x128 overview in bottom-right corner) ===
    let minimapCellSize: Int32 = 2
    let minimapSize: Int32 = 64 * minimapCellSize  // 128x128
    let minimapPad: Int32 = 10
    let minimapX = renderState.windowWidth - minimapSize - minimapPad
    let minimapY = renderState.windowHeight - minimapSize - minimapPad

    // Build quick lookup sets for structures and overlays by cell
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
    var overlayCells: [Int: String] = [:]
    for overlay in scenario.overlays {
        overlayCells[overlay.cell] = overlay.typeName.uppercased()
    }

    // Semi-transparent dark background
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 180)
    var minimapBg = SDL_Rect(x: minimapX - 2, y: minimapY - 2, w: minimapSize + 4, h: minimapSize + 4)
    SDL_RenderFillRect(renderer, &minimapBg)

    // Draw each cell as a 2x2 pixel block
    for cellY in 0..<mapSize {
        for cellX in 0..<mapSize {
            let cellIndex = cellY * mapSize + cellX
            let px = minimapX + Int32(cellX) * minimapCellSize
            let py = minimapY + Int32(cellY) * minimapCellSize

            var r: UInt8 = 20, g: UInt8 = 60, b: UInt8 = 20  // Default dark green for land

            if let house = structureCells[cellIndex] {
                let hc = house.displayColor
                r = hc.r; g = hc.g; b = hc.b
            } else if let overlayName = overlayCells[cellIndex] {
                if overlayName.hasPrefix("TI") {
                    r = 0; g = 180; b = 0  // Tiberium green
                } else {
                    r = 140; g = 140; b = 140  // Walls/other gray
                }
            } else {
                // Sample from the map cell template to distinguish terrain
                let cell = mapCells[cellIndex]
                let templateType = Int(cell.templateType)
                if templateType != 0xFF && templateType < templateTable.count {
                    let name = templateTable[templateType].icnName.uppercased()
                    if name.hasPrefix("W") || name.contains("WATER") || name.hasPrefix("SH") || name.hasPrefix("FALLS") || name.hasPrefix("RIVER") || name.hasPrefix("FORD") || name.hasPrefix("BRIDGE") {
                        r = 20; g = 30; b = 80  // Water blue
                    } else if name.hasPrefix("S") && !name.hasPrefix("SH") {
                        r = 50; g = 50; b = 30  // Sand/shore
                    } else if name.hasPrefix("D") {
                        r = 40; g = 40; b = 30  // Dirt
                    } else if name.hasPrefix("P") || name.hasPrefix("ROAD") || name.hasPrefix("R") {
                        r = 50; g = 50; b = 50  // Pavement/road gray
                    }
                    // else keep default dark green
                }
            }

            SDL_SetRenderDrawColor(renderer, r, g, b, 255)
            var dot = SDL_Rect(x: px, y: py, w: minimapCellSize, h: minimapCellSize)
            SDL_RenderFillRect(renderer, &dot)
        }
    }

    // Darken areas outside map bounds on the minimap
    if let bounds = scenario.mapBounds {
        let mbx = minimapX + Int32(bounds.x) * minimapCellSize
        let mby = minimapY + Int32(bounds.y) * minimapCellSize
        let mbw = Int32(bounds.width) * minimapCellSize
        let mbh = Int32(bounds.height) * minimapCellSize

        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 140)

        // Top
        if mby > minimapY {
            var r = SDL_Rect(x: minimapX, y: minimapY, w: minimapSize, h: mby - minimapY)
            SDL_RenderFillRect(renderer, &r)
        }
        // Bottom
        let mmBottom = mby + mbh
        let mmEnd = minimapY + minimapSize
        if mmBottom < mmEnd {
            var r = SDL_Rect(x: minimapX, y: mmBottom, w: minimapSize, h: mmEnd - mmBottom)
            SDL_RenderFillRect(renderer, &r)
        }
        // Left
        let sTop = max(minimapY, mby)
        let sBot = min(mmEnd, mmBottom)
        let sH = sBot - sTop
        if mbx > minimapX && sH > 0 {
            var r = SDL_Rect(x: minimapX, y: sTop, w: mbx - minimapX, h: sH)
            SDL_RenderFillRect(renderer, &r)
        }
        // Right
        let mmRight = mbx + mbw
        let mmXEnd = minimapX + minimapSize
        if mmRight < mmXEnd && sH > 0 {
            var r = SDL_Rect(x: mmRight, y: sTop, w: mmXEnd - mmRight, h: sH)
            SDL_RenderFillRect(renderer, &r)
        }
    }

    // Draw white outline showing current camera viewport on minimap
    let vpX = minimapX + Int32(renderState.cameraX / tileSize) * minimapCellSize
    let vpY = minimapY + Int32(renderState.cameraY / tileSize) * minimapCellSize
    let vpW = Int32(Double(renderState.windowWidth) / renderState.zoomLevel / Double(tileSize)) * minimapCellSize
    let vpH = Int32(Double(renderState.windowHeight) / renderState.zoomLevel / Double(tileSize)) * minimapCellSize
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
    var vpRect = SDL_Rect(x: vpX, y: vpY, w: vpW, h: vpH)
    SDL_RenderDrawRect(renderer, &vpRect)

    // === Info Panel (rendered at native resolution after scale reset) ===
    if renderState.showInfoPanel {
        renderInfoPanel(renderer, scenario: scenario, tileSize: tileSize)
    }
}

// MARK: - Info Panel

func renderInfoPanel(_ renderer: OpaquePointer?, scenario: ScenarioData, tileSize: Int) {
    let panelW: Int32 = 210
    let panelX = renderState.windowWidth - panelW
    let panelY: Int32 = 0
    let panelH = renderState.windowHeight

    // Semi-transparent dark background
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 200)
    var bg = SDL_Rect(x: panelX, y: panelY, w: panelW, h: panelH)
    SDL_RenderFillRect(renderer, &bg)

    // Left border
    SDL_SetRenderDrawColor(renderer, 0, 180, 0, 255)
    SDL_RenderDrawLine(renderer, panelX, panelY, panelX, panelY + panelH)

    let hovCellX = input.mouseWorldX / tileSize
    let hovCellY = input.mouseWorldY / tileSize
    let hovCell = hovCellY * 64 + hovCellX

    var lineY: Int32 = 10
    let leftX = panelX + 8

    // Header
    drawTextLeft(renderer, "INFO PANEL", x: leftX, y: lineY, color: .amber, scale: 1)
    lineY += 14

    // Cell coordinates
    drawTextLeft(renderer, "CELL: \(hovCellX) \(hovCellY)", x: leftX, y: lineY, color: .green, scale: 1)
    lineY += 12
    drawTextLeft(renderer, "IDX: \(hovCell)", x: leftX, y: lineY, color: .green, scale: 1)
    lineY += 16

    guard hovCellX >= 0 && hovCellX < 64 && hovCellY >= 0 && hovCellY < 64 else { return }

    // Check structures at this cell
    var foundObject = false
    for structure in scenario.structures {
        let size = buildingSize(structure.typeName)
        let baseXY = cellToXY(structure.cell)
        if hovCellX >= baseXY.x && hovCellX < baseXY.x + size.w &&
           hovCellY >= baseXY.y && hovCellY < baseXY.y + size.h {
            drawTextLeft(renderer, "STRUCTURE", x: leftX, y: lineY, color: .amber, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "TYPE: \(structure.typeName)", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "HOUSE: \(structure.house.rawValue)", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "HP: \(structure.strength)/256", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 12
            if structure.trigger != "None" && structure.trigger != "NONE" {
                drawTextLeft(renderer, "TRIG: \(structure.trigger)", x: leftX, y: lineY, color: .cyan, scale: 1)
                lineY += 12
            }
            lineY += 6
            foundObject = true
        }
    }

    // Check units at this cell
    for unit in scenario.units {
        let unitXY = cellToXY(unit.cell)
        if hovCellX == unitXY.x && hovCellY == unitXY.y {
            drawTextLeft(renderer, "UNIT", x: leftX, y: lineY, color: .amber, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "TYPE: \(unit.typeName)", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "HOUSE: \(unit.house.rawValue)", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "HP: \(unit.strength)/256", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "MISSION: \(unit.mission)", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 12
            if unit.trigger != "None" && unit.trigger != "NONE" {
                drawTextLeft(renderer, "TRIG: \(unit.trigger)", x: leftX, y: lineY, color: .cyan, scale: 1)
                lineY += 12
            }
            lineY += 6
            foundObject = true
        }
    }

    // Check infantry at this cell
    for inf in scenario.infantry {
        let infXY = cellToXY(inf.cell)
        if hovCellX == infXY.x && hovCellY == infXY.y {
            drawTextLeft(renderer, "INFANTRY", x: leftX, y: lineY, color: .amber, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "TYPE: \(inf.typeName)", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "HOUSE: \(inf.house.rawValue)", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "HP: \(inf.strength)/256", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "MISSION: \(inf.mission)", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 12
            if inf.trigger != "None" && inf.trigger != "NONE" {
                drawTextLeft(renderer, "TRIG: \(inf.trigger)", x: leftX, y: lineY, color: .cyan, scale: 1)
                lineY += 12
            }
            lineY += 6
            foundObject = true
        }
    }

    // Check terrain at this cell
    for terrainObj in scenario.terrain {
        let tXY = cellToXY(terrainObj.cell)
        if hovCellX == tXY.x && hovCellY == tXY.y {
            drawTextLeft(renderer, "TERRAIN", x: leftX, y: lineY, color: .amber, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "TYPE: \(terrainObj.typeName)", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 16
            foundObject = true
        }
    }

    // Check overlays at this cell
    for overlay in scenario.overlays {
        if overlay.cell == hovCell {
            drawTextLeft(renderer, "OVERLAY", x: leftX, y: lineY, color: .amber, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "TYPE: \(overlay.typeName)", x: leftX, y: lineY, color: .white, scale: 1)
            lineY += 16
            foundObject = true
        }
    }

    // Check cell triggers at this cell
    for ct in scenario.cellTriggers {
        if ct.cell == hovCell {
            drawTextLeft(renderer, "CELLTRIGGER", x: leftX, y: lineY, color: .amber, scale: 1)
            lineY += 12
            drawTextLeft(renderer, "NAME: \(ct.triggerName)", x: leftX, y: lineY, color: .cyan, scale: 1)
            lineY += 16
            foundObject = true
        }
    }

    if !foundObject {
        drawTextLeft(renderer, "EMPTY", x: leftX, y: lineY, color: .gray, scale: 1)
    }
}
