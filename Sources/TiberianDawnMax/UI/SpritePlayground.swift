import CSDL2
import Foundation

// MARK: - Sprite Playground
// Interactive sprite browser for debugging rendering issues.
// Browse all game assets (units, structures, VFX, raw SHP) with
// facing control, house color cycling, animation, zoom, and sounds.

// MARK: - Playground Item

struct PlaygroundItem {
    let name: String       // INI/asset name (e.g. "MTNK", "E1")
    let fullName: String   // Display name (e.g. "Medium Tank", "Minigunner")
    let frameCount: Int    // Total frames (0 = unknown/dynamic)
}

// MARK: - Sprite Playground State

class SpritePlaygroundState {
    var category: Int = 0              // 0=units, 1=structures, 2=vfx, 3=shp
    var selectedIndex: Int = 0
    var scrollOffset: Int = 0
    var facing: Int = 0                // 0-255
    var currentFrame: Int = 0
    var house: House = .goodGuy
    var isAnimating: Bool = false
    var animTimer: UInt32 = 0
    var zoom: Int = 4                  // Display scale multiplier
    var showRemastered: Bool = true

    // Cached item lists per category
    var unitItems: [PlaygroundItem] = []
    var structItems: [PlaygroundItem] = []
    var vfxItems: [PlaygroundItem] = []
    var shpItems: [PlaygroundItem] = []

    private let maxVisible: Int = 20
    private let categoryNames = ["UNITS", "STRUCTURES", "VFX", "SHP"]

    // Houses to cycle through
    private let houseOrder: [House] = [
        .goodGuy, .badGuy, .neutral, .special,
        .multi1, .multi2, .multi3, .multi4, .multi5, .multi6
    ]

    func initialize() {
        // Ensure palette is loaded for classic SHP rendering
        if renderState.gamePalette.isEmpty {
            renderState.gamePalette = loadPalette("TEMPERAT.PAL")
        }
        buildItemLists()
        category = 0
        selectedIndex = 0
        scrollOffset = 0
        facing = 0
        currentFrame = 0
        house = .goodGuy
        isAnimating = false
        zoom = 4
    }

    // MARK: - Item List Building

    private func buildItemLists() {
        // Units: vehicles + infantry + aircraft
        var units: [PlaygroundItem] = []
        for (_, data) in unitTypeDataTable {
            units.append(PlaygroundItem(name: data.iniName, fullName: data.fullName, frameCount: 0))
        }
        for (_, data) in infantryTypeDataTable {
            units.append(PlaygroundItem(name: data.iniName, fullName: data.fullName, frameCount: 0))
        }
        for (_, data) in aircraftTypeDataTable {
            units.append(PlaygroundItem(name: data.iniName, fullName: data.fullName, frameCount: 0))
        }
        unitItems = units.sorted { $0.name < $1.name }

        // Structures
        var structs: [PlaygroundItem] = []
        for (_, data) in buildingTypeDataTable {
            structs.append(PlaygroundItem(name: data.iniName, fullName: data.fullName, frameCount: 0))
        }
        structItems = structs.sorted { $0.name < $1.name }

        // VFX from remastered manifests
        let vfxManifests = getRemasteredManifests(category: "vfx")
        vfxItems = vfxManifests.map {
            PlaygroundItem(name: $0.name, fullName: $0.name, frameCount: $0.frameCount)
        }

        // SHP: classic shapes from SpriteViewer
        shpItems = viewableShapes.map {
            let name = $0.replacingOccurrences(of: ".SHP", with: "")
            return PlaygroundItem(name: name, fullName: $0, frameCount: 0)
        }
    }

    // MARK: - Current Items

    var currentItems: [PlaygroundItem] {
        switch category {
        case 0: return unitItems
        case 1: return structItems
        case 2: return vfxItems
        case 3: return shpItems
        default: return []
        }
    }

    var currentCategoryName: String {
        categoryNames[category]
    }

    var selectedItem: PlaygroundItem? {
        let items = currentItems
        guard selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    // MARK: - Input Handling

    func handleKey(_ key: Int32) {
        let items = currentItems

        if key == Int32(SDLK_TAB.rawValue) {
            category = (category + 1) % categoryNames.count
            selectedIndex = 0
            scrollOffset = 0
            currentFrame = 0
            facing = 0
            isAnimating = category == 2 // Auto-animate VFX
        } else if key == Int32(SDLK_DOWN.rawValue) {
            if selectedIndex < items.count - 1 {
                selectedIndex += 1
                if selectedIndex >= scrollOffset + maxVisible {
                    scrollOffset = selectedIndex - maxVisible + 1
                }
                currentFrame = 0
            }
        } else if key == Int32(SDLK_UP.rawValue) {
            if selectedIndex > 0 {
                selectedIndex -= 1
                if selectedIndex < scrollOffset {
                    scrollOffset = selectedIndex
                }
                currentFrame = 0
            }
        } else if key == Int32(SDLK_PAGEDOWN.rawValue) {
            selectedIndex = min(items.count - 1, selectedIndex + 10)
            if selectedIndex >= scrollOffset + maxVisible {
                scrollOffset = selectedIndex - maxVisible + 1
            }
            currentFrame = 0
        } else if key == Int32(SDLK_PAGEUP.rawValue) {
            selectedIndex = max(0, selectedIndex - 10)
            if selectedIndex < scrollOffset {
                scrollOffset = selectedIndex
            }
            currentFrame = 0
        } else if key == Int32(SDLK_RIGHT.rawValue) {
            facing = (facing + 8) & 0xFF
        } else if key == Int32(SDLK_LEFT.rawValue) {
            facing = (facing - 8 + 256) & 0xFF
        } else if key == Int32(SDLK_SPACE.rawValue) {
            isAnimating = !isAnimating
        } else if key == Int32(SDLK_RIGHTBRACKET.rawValue) {
            stepFrame(forward: true)
        } else if key == Int32(SDLK_LEFTBRACKET.rawValue) {
            stepFrame(forward: false)
        } else if key == Int32(SDLK_h.rawValue) {
            cycleHouse()
        } else if key == Int32(SDLK_f.rawValue) {
            playWeaponSound()
        } else if key == Int32(SDLK_s.rawValue) {
            playAcknowledgeSound()
        } else if key == Int32(SDLK_r.rawValue) {
            playReportSound()
        } else if key == Int32(SDLK_EQUALS.rawValue) {
            zoom = min(12, zoom + 1)
        } else if key == Int32(SDLK_MINUS.rawValue) {
            zoom = max(1, zoom - 1)
        } else if key == Int32(SDLK_t.rawValue) {
            showRemastered = !showRemastered
        }
    }

    private func stepFrame(forward: Bool) {
        if category == 0 || category == 3 {
            // Units/SHP: step facing by one frame (8 = one facing step)
            if forward {
                facing = (facing + 8) & 0xFF
            } else {
                facing = (facing - 8 + 256) & 0xFF
            }
        } else {
            // Structures/VFX: step through raw frames
            let totalFrames = getFrameCount()
            guard totalFrames > 0 else { return }
            if forward {
                currentFrame = (currentFrame + 1) % totalFrames
            } else {
                currentFrame = (currentFrame - 1 + totalFrames) % totalFrames
            }
        }
    }

    private func cycleHouse() {
        if let idx = houseOrder.firstIndex(of: house) {
            house = houseOrder[(idx + 1) % houseOrder.count]
        } else {
            house = .goodGuy
        }
    }

    // MARK: - Sound Playback

    private func playWeaponSound() {
        guard let item = selectedItem else { return }
        let weapon = findPrimaryWeapon(item.name)
        guard let weapon = weapon else { return }
        let voc = audioManager.weaponFireSound(weapon)
        audioManager.playSoundEffect(voc)
    }

    private func playAcknowledgeSound() {
        let voc = audioManager.unitAcknowledgeSound()
        audioManager.playSoundEffect(voc)
    }

    private func playReportSound() {
        let voc = audioManager.unitReportSound()
        audioManager.playSoundEffect(voc)
    }

    // MARK: - Data Lookups

    func findUnitData(_ name: String) -> UnitTypeData? {
        return unitTypeDataTable.values.first { $0.iniName == name }
    }

    func findInfantryData(_ name: String) -> InfantryTypeData? {
        return infantryTypeDataTable.values.first { $0.iniName == name }
    }

    func findAircraftData(_ name: String) -> AircraftTypeData? {
        return aircraftTypeDataTable.values.first { $0.iniName == name }
    }

    func findBuildingData(_ name: String) -> BuildingTypeData? {
        return buildingTypeDataTable.values.first { $0.iniName == name }
    }

    func findPrimaryWeapon(_ name: String) -> WeaponType? {
        if let u = findUnitData(name) { return u.primaryWeapon }
        if let i = findInfantryData(name) { return i.primaryWeapon }
        if let a = findAircraftData(name) { return a.primaryWeapon }
        if let b = findBuildingData(name) { return b.primaryWeapon }
        return nil
    }

    // MARK: - Frame Calculations

    /// Get the frame index for current facing (for units with 32 facing frames)
    func facingFrameIndex() -> Int {
        // C&C uses 32 facings: facing 0-255 maps to frames 0-31
        // Frame 0 = north (facing 0), clockwise
        return (facing / 8) % 32
    }

    /// Get total frame count for current item
    func getFrameCount() -> Int {
        guard let item = selectedItem else { return 0 }
        let baseName = item.name.replacingOccurrences(of: ".SHP", with: "").uppercased()
        let spriteName = spriteNameOverrides[baseName] ?? baseName

        // Check remastered manifest first (try both names)
        if let manifest = getRemasteredManifest(name: baseName) {
            return manifest.frameCount
        }
        if spriteName != baseName, let manifest = getRemasteredManifest(name: spriteName) {
            return manifest.frameCount
        }

        // Check SHP cache
        if let shp = renderState.objectSHPCache[spriteName] {
            return shp.frames.count
        }

        // Try to load the SHP to get frame count
        if let data = mixManager.retrieve(spriteName + ".SHP") {
            if let shp = try? SHPFile(data: Data(data)) {
                renderState.objectSHPCache[spriteName] = shp
                return shp.frames.count
            }
        }

        return item.frameCount
    }

    /// Compute the actual frame to display based on facing and category
    func displayFrame() -> Int {
        switch category {
        case 0:
            // Units: facing selects body direction (0-31)
            return facingFrameIndex()
        case 1:
            // Structures: sequential frame (damage states, build anim)
            return currentFrame
        case 2:
            // VFX: sequential animation frame
            return currentFrame
        case 3:
            // SHP: facing-based like units (most SHPs in this list are unit sprites)
            return facingFrameIndex()
        default:
            return currentFrame
        }
    }

    // MARK: - Rendering

    func render(_ renderer: OpaquePointer?) {
        let winW = renderState.windowWidth
        let winH = renderState.windowHeight

        // Title bar
        drawText(renderer, "SPRITE PLAYGROUND", centerX: winW / 2, centerY: 25, color: .amber, scale: 3)

        // Category tabs
        renderCategoryTabs(renderer)

        // Split layout
        let listW: Int32 = 220
        let listX: Int32 = 10
        let listY: Int32 = 75
        let listH = winH - 90

        // Left panel: item list
        renderItemList(renderer, x: listX, y: listY, w: listW, h: listH)

        // Right panel: sprite display + info
        let displayX = listX + listW + 10
        let displayW = winW - displayX - 10
        renderSpriteDisplay(renderer, x: displayX, y: listY, w: displayW, h: listH)

        // Controls help at bottom
        let ctrlY = winH - 15
        drawText(renderer, "Tab:Cat  Arrows:Browse/Face  Space:Anim  []:Frame  H:House  F:Fire  S:Ack  R:Rpt  +/-:Zoom  T:Toggle  Esc:Back",
                 centerX: winW / 2, centerY: ctrlY, color: .gray, scale: 1)

        // Auto-animate
        if isAnimating {
            let now = SDL_GetTicks()
            if now - animTimer > 100 {
                animTimer = now
                if category == 0 || category == 3 {
                    // Units/SHP: rotate through facings
                    facing = (facing + 8) & 0xFF
                } else {
                    // Structures/VFX: cycle through frames
                    let total = getFrameCount()
                    if total > 0 {
                        currentFrame = (currentFrame + 1) % total
                    }
                }
            }
        }
    }

    private func renderCategoryTabs(_ renderer: OpaquePointer?) {
        let tabW: Int32 = 120
        let tabH: Int32 = 22
        let totalW = tabW * Int32(categoryNames.count)
        let startX = renderState.windowWidth / 2 - totalW / 2
        let tabY: Int32 = 52

        for (i, name) in categoryNames.enumerated() {
            let x = startX + Int32(i) * tabW
            let isSelected = (i == category)

            if isSelected {
                SDL_SetRenderDrawColor(renderer, 0, 80, 0, 255)
                var rect = SDL_Rect(x: x, y: tabY, w: tabW - 2, h: tabH)
                SDL_RenderFillRect(renderer, &rect)
            }

            SDL_SetRenderDrawColor(renderer, 0, 150, 0, 255)
            var border = SDL_Rect(x: x, y: tabY, w: tabW - 2, h: tabH)
            SDL_RenderDrawRect(renderer, &border)

            let color: Color = isSelected ? .brightGreen : .green
            drawText(renderer, name, centerX: x + (tabW - 2) / 2, centerY: tabY + tabH / 2, color: color, scale: 1)
        }
    }

    private func renderItemList(_ renderer: OpaquePointer?, x: Int32, y: Int32, w: Int32, h: Int32) {
        let items = currentItems

        // Background
        SDL_SetRenderDrawColor(renderer, 10, 10, 10, 255)
        var bg = SDL_Rect(x: x, y: y, w: w, h: h)
        SDL_RenderFillRect(renderer, &bg)

        // Border
        SDL_SetRenderDrawColor(renderer, 0, 80, 0, 255)
        SDL_RenderDrawRect(renderer, &bg)

        let rowH: Int32 = 20
        let visibleCount = min(maxVisible, Int((h - 10) / rowH))
        let endIdx = min(items.count, scrollOffset + visibleCount)

        for i in scrollOffset..<endIdx {
            let item = items[i]
            let rowY = y + 5 + Int32(i - scrollOffset) * rowH
            let isSelected = (i == selectedIndex)

            if isSelected {
                SDL_SetRenderDrawColor(renderer, 0, 50, 0, 255)
                var selRect = SDL_Rect(x: x + 2, y: rowY - 1, w: w - 4, h: rowH)
                SDL_RenderFillRect(renderer, &selRect)
            }

            let cursor = isSelected ? "> " : "  "
            let color: Color = isSelected ? .brightGreen : .green
            let label = "\(cursor)\(item.name)"
            drawTextLeft(renderer, label, x: x + 5, y: rowY + 2, color: color, scale: 1)
        }

        // Scroll indicators
        if scrollOffset > 0 {
            drawText(renderer, "^ \(scrollOffset) above", centerX: x + w / 2, centerY: y - 8, color: .gray, scale: 1)
        }
        if endIdx < items.count {
            drawText(renderer, "v \(items.count - endIdx) below", centerX: x + w / 2, centerY: y + h + 8, color: .gray, scale: 1)
        }
    }

    private func renderSpriteDisplay(_ renderer: OpaquePointer?, x: Int32, y: Int32, w: Int32, h: Int32) {
        guard let item = selectedItem else {
            drawText(renderer, "No item selected", centerX: x + w / 2, centerY: y + h / 2, color: .gray, scale: 2)
            return
        }

        // Background
        SDL_SetRenderDrawColor(renderer, 15, 15, 15, 255)
        var bg = SDL_Rect(x: x, y: y, w: w, h: h)
        SDL_RenderFillRect(renderer, &bg)
        SDL_SetRenderDrawColor(renderer, 0, 80, 0, 255)
        SDL_RenderDrawRect(renderer, &bg)

        // Item name at top
        drawText(renderer, "\(item.name) - \(item.fullName)", centerX: x + w / 2, centerY: y + 15, color: .amber, scale: 2)

        // Sprite display area
        let spriteAreaY = y + 35
        let spriteAreaH = h - 200
        let spriteCenterX = x + w / 2
        let spriteCenterY = spriteAreaY + spriteAreaH / 2

        renderSprite(renderer, item: item, centerX: spriteCenterX, centerY: spriteCenterY)

        // Facing compass below sprite
        let compassY = spriteAreaY + spriteAreaH + 5
        renderFacingCompass(renderer, centerX: spriteCenterX, centerY: compassY)

        // Info panel
        let infoY = compassY + 35
        renderInfoPanel(renderer, item: item, x: x + 10, y: infoY, w: w - 20)
    }

    private func renderSprite(_ renderer: OpaquePointer?, item: PlaygroundItem, centerX: Int32, centerY: Int32) {
        let frame = displayFrame()
        let lookupName = item.name.replacingOccurrences(of: ".SHP", with: "").uppercased()

        // Try remastered first if enabled (all categories)
        if showRemastered {
            // Try original name, then sprite name override
            let overrideName = spriteNameOverrides[lookupName]
            let namesToTry = [lookupName] + (overrideName.map { [$0] } ?? [])
            for tryName in namesToTry {
                if let info = getRemasteredTextureWithHouse(renderer, typeName: tryName, frame: frame, house: house) {
                    let scale = Int32(zoom)
                    let drawW = Int32(info.width) * scale
                    let drawH = Int32(info.height) * scale
                    var dstRect = SDL_Rect(x: centerX - drawW / 2, y: centerY - drawH / 2, w: drawW, h: drawH)
                    SDL_RenderCopy(renderer, info.texture, nil, &dstRect)

                    // Render turret overlay for turreted units (turret frames start at 32)
                    if let unit = findUnitData(lookupName), unit.hasTurret {
                        let turretFrame = 32 + facingFrameIndex()
                        if let turretInfo = getRemasteredTextureWithHouse(renderer, typeName: tryName, frame: turretFrame, house: house) {
                            let tDrawW = Int32(turretInfo.width) * scale
                            let tDrawH = Int32(turretInfo.height) * scale
                            var tRect = SDL_Rect(x: centerX - tDrawW / 2, y: centerY - tDrawH / 2, w: tDrawW, h: tDrawH)
                            SDL_RenderCopy(renderer, turretInfo.texture, nil, &tRect)
                        }
                    }

                    drawText(renderer, "Remastered", centerX: centerX, centerY: centerY + drawH / 2 + 12, color: .cyan, scale: 1)
                    return
                }
            }
        }

        // Classic SHP with house color remapping + turret overlay
        renderClassicWithHouse(renderer, name: lookupName, frame: frame, centerX: centerX, centerY: centerY)
    }

    /// Render a classic SHP sprite with house color remapping via createRemappedSpriteTexture.
    /// This bypasses getObjectTexture() so we can show house colors even when remastered exists.
    /// For turreted units, renders body + turret overlay.
    private func renderClassicWithHouse(_ renderer: OpaquePointer?, name: String, frame: Int, centerX: Int32, centerY: Int32) {
        guard !renderState.gamePalette.isEmpty else {
            drawText(renderer, "Palette not loaded", centerX: centerX, centerY: centerY, color: .red, scale: 1)
            return
        }

        // Resolve sprite name overrides (e.g. HMMV -> JEEP)
        let spriteName = spriteNameOverrides[name] ?? name

        // Load SHP if not cached
        if renderState.objectSHPCache[spriteName] == nil {
            if let data = mixManager.retrieve(spriteName + ".SHP") {
                renderState.objectSHPCache[spriteName] = try? SHPFile(data: Data(data))
            }
        }

        guard let shp = renderState.objectSHPCache[spriteName],
              !shp.frames.isEmpty else {
            drawText(renderer, "SHP not found", centerX: centerX, centerY: centerY, color: .red, scale: 1)
            return
        }

        let frameIdx = frame % shp.frames.count
        let f = shp.frames[frameIdx]
        let scale = Int32(zoom)

        // Render body frame
        renderSHPFrameAsTexture(renderer, shp: shp, frameIdx: frameIdx, spriteName: spriteName,
                                centerX: centerX, centerY: centerY, scale: scale)

        // Render turret overlay for turreted units (turret frames start at 32)
        if let unit = findUnitData(name), unit.hasTurret {
            let turretFrameIdx = 32 + facingFrameIndex()
            if turretFrameIdx < shp.frames.count {
                renderSHPFrameAsTexture(renderer, shp: shp, frameIdx: turretFrameIdx, spriteName: spriteName,
                                        centerX: centerX, centerY: centerY, scale: scale)
            }
        }

        drawText(renderer, "Classic (\(house.rawValue))", centerX: centerX, centerY: centerY + Int32(f.height) * scale / 2 + 12, color: .green, scale: 1)
    }

    /// Render a single SHP frame as a house-remapped texture at the given center position.
    private func renderSHPFrameAsTexture(_ renderer: OpaquePointer?, shp: SHPFile, frameIdx: Int,
                                          spriteName: String, centerX: Int32, centerY: Int32, scale: Int32) {
        let f = shp.frames[frameIdx]
        let cacheKey = "PG_\(spriteName)_\(frameIdx)_\(house.rawValue)"
        let texture: OpaquePointer?
        if let cached = renderState.objectTextureCache[cacheKey] {
            texture = cached
        } else if let created = createRemappedSpriteTexture(renderer, frame: f, house: house) {
            renderState.objectTextureCache[cacheKey] = created
            texture = created
        } else {
            return
        }

        let drawW = Int32(f.width) * scale
        let drawH = Int32(f.height) * scale
        var dstRect = SDL_Rect(x: centerX - drawW / 2, y: centerY - drawH / 2, w: drawW, h: drawH)
        SDL_RenderCopy(renderer, texture, nil, &dstRect)
    }

    private func renderFacingCompass(_ renderer: OpaquePointer?, centerX: Int32, centerY: Int32) {
        let radius: Int32 = 15

        // Draw circle outline
        SDL_SetRenderDrawColor(renderer, 0, 100, 0, 255)
        for angle in stride(from: 0.0, to: 360.0, by: 15.0) {
            let rad = angle * .pi / 180.0
            let px = centerX + Int32(Double(radius) * sin(rad))
            let py = centerY - Int32(Double(radius) * cos(rad))
            var dot = SDL_Rect(x: px, y: py, w: 1, h: 1)
            SDL_RenderFillRect(renderer, &dot)
        }

        // Draw facing arrow
        let facingAngle = Double(facing) / 256.0 * 2.0 * .pi
        let tipX = centerX + Int32(Double(radius) * sin(facingAngle))
        let tipY = centerY - Int32(Double(radius) * cos(facingAngle))

        SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255)
        SDL_RenderDrawLine(renderer, centerX, centerY, tipX, tipY)

        // Facing label
        let facingLabel = "Facing: \(facing)"
        drawText(renderer, facingLabel, centerX: centerX, centerY: centerY + radius + 10, color: .green, scale: 1)
    }

    private func renderInfoPanel(_ renderer: OpaquePointer?, item: PlaygroundItem, x: Int32, y: Int32, w: Int32) {
        var cy = y
        let lineH: Int32 = 16

        // Frame info
        let totalFrames = getFrameCount()
        let frameInfo = "Frame: \(displayFrame())/\(totalFrames)  Zoom: \(zoom)x"
        drawTextLeft(renderer, frameInfo, x: x, y: cy, color: .green, scale: 1)
        cy += lineH

        // House info
        let houseColor = house.displayColor
        let houseLabel = "House: \(house.rawValue)"
        drawTextLeft(renderer, houseLabel, x: x, y: cy, color: .green, scale: 1)
        // Draw house color swatch
        SDL_SetRenderDrawColor(renderer, houseColor.r, houseColor.g, houseColor.b, 255)
        var swatch = SDL_Rect(x: x + 200, y: cy, w: 16, h: 12)
        SDL_RenderFillRect(renderer, &swatch)
        cy += lineH

        // Animation state
        let animLabel = isAnimating ? "Animating" : "Paused"
        let srcLabel = showRemastered ? "Remastered" : "Classic"
        drawTextLeft(renderer, "Anim: \(animLabel)  Source: \(srcLabel)", x: x, y: cy, color: .green, scale: 1)
        cy += lineH + 4

        // Category-specific info
        switch category {
        case 0:
            renderUnitInfo(renderer, name: item.name, x: x, y: cy, w: w)
        case 1:
            renderBuildingInfo(renderer, name: item.name, x: x, y: cy, w: w)
        case 2:
            renderVFXInfo(renderer, name: item.name, x: x, y: cy, w: w)
        case 3:
            renderSHPInfo(renderer, name: item.fullName, x: x, y: cy, w: w)
        default:
            break
        }
    }

    private func renderUnitInfo(_ renderer: OpaquePointer?, name: String, x: Int32, y: Int32, w: Int32) {
        var cy = y
        let lineH: Int32 = 14

        if let u = findUnitData(name) {
            drawTextLeft(renderer, "HP: \(u.strength)  Armor: \(u.armor)  Cost: \(u.cost)", x: x, y: cy, color: .green, scale: 1)
            cy += lineH
            drawTextLeft(renderer, "Speed: \(u.maxSpeed)  Sight: \(u.sightRange)  ROT: \(u.rot)", x: x, y: cy, color: .green, scale: 1)
            cy += lineH
            if let pw = u.primaryWeapon {
                let wInfo = weaponDescription(pw)
                drawTextLeft(renderer, "Wpn1: \(pw) \(wInfo)", x: x, y: cy, color: .amber, scale: 1)
                cy += lineH
            }
            if let sw = u.secondaryWeapon {
                let wInfo = weaponDescription(sw)
                drawTextLeft(renderer, "Wpn2: \(sw) \(wInfo)", x: x, y: cy, color: .amber, scale: 1)
                cy += lineH
            }
            var flags: [String] = []
            if u.hasTurret { flags.append("Turret") }
            if u.isTransporter { flags.append("Transport") }
            if u.isCloakable { flags.append("Cloak") }
            if u.isHarvester { flags.append("Harvester") }
            if u.isCrusher { flags.append("Crusher") }
            if u.isGigundo { flags.append("Large") }
            if !flags.isEmpty {
                drawTextLeft(renderer, "Flags: \(flags.joined(separator: " "))", x: x, y: cy, color: .cyan, scale: 1)
                cy += lineH
            }
        } else if let i = findInfantryData(name) {
            drawTextLeft(renderer, "HP: \(i.strength)  Armor: \(i.armor)  Cost: \(i.cost)", x: x, y: cy, color: .green, scale: 1)
            cy += lineH
            drawTextLeft(renderer, "Speed: \(i.maxSpeed)  Sight: \(i.sightRange)", x: x, y: cy, color: .green, scale: 1)
            cy += lineH
            if let pw = i.primaryWeapon {
                let wInfo = weaponDescription(pw)
                drawTextLeft(renderer, "Wpn: \(pw) \(wInfo)", x: x, y: cy, color: .amber, scale: 1)
                cy += lineH
            }
            var flags: [String] = []
            if i.canCapture { flags.append("Capture") }
            if i.hasCrawl { flags.append("Crawl") }
            if i.isCivilian { flags.append("Civilian") }
            if !flags.isEmpty {
                drawTextLeft(renderer, "Flags: \(flags.joined(separator: " "))", x: x, y: cy, color: .cyan, scale: 1)
                cy += lineH
            }
        } else if let a = findAircraftData(name) {
            drawTextLeft(renderer, "HP: \(a.strength)  Armor: \(a.armor)  Cost: \(a.cost)", x: x, y: cy, color: .green, scale: 1)
            cy += lineH
            drawTextLeft(renderer, "Speed: \(a.maxSpeed)  Sight: \(a.sightRange)  Ammo: \(a.maxAmmo)", x: x, y: cy, color: .green, scale: 1)
            cy += lineH
            if let pw = a.primaryWeapon {
                let wInfo = weaponDescription(pw)
                drawTextLeft(renderer, "Wpn: \(pw) \(wInfo)", x: x, y: cy, color: .amber, scale: 1)
                cy += lineH
            }
            var flags: [String] = []
            if a.isFixedWing { flags.append("FixedWing") }
            if a.isRotorEquipped { flags.append("Rotor") }
            if a.isTransporter { flags.append("Transport") }
            if !flags.isEmpty {
                drawTextLeft(renderer, "Flags: \(flags.joined(separator: " "))", x: x, y: cy, color: .cyan, scale: 1)
            }
        } else {
            drawTextLeft(renderer, "No unit data found", x: x, y: cy, color: .red, scale: 1)
        }
    }

    private func renderBuildingInfo(_ renderer: OpaquePointer?, name: String, x: Int32, y: Int32, w: Int32) {
        var cy = y
        let lineH: Int32 = 14

        if let b = findBuildingData(name) {
            drawTextLeft(renderer, "HP: \(b.strength)  Armor: \(b.armor)  Cost: \(b.cost)", x: x, y: cy, color: .green, scale: 1)
            cy += lineH
            drawTextLeft(renderer, "Size: \(b.sizeW)x\(b.sizeH)  Sight: \(b.sightRange)", x: x, y: cy, color: .green, scale: 1)
            cy += lineH
            if b.powerProduction > 0 || b.powerDrain > 0 {
                drawTextLeft(renderer, "Power: +\(b.powerProduction) -\(b.powerDrain)", x: x, y: cy, color: .amber, scale: 1)
                cy += lineH
            }
            if b.tiberiumCapacity > 0 {
                drawTextLeft(renderer, "Tib Capacity: \(b.tiberiumCapacity)", x: x, y: cy, color: .amber, scale: 1)
                cy += lineH
            }
            if let pw = b.primaryWeapon {
                let wInfo = weaponDescription(pw)
                drawTextLeft(renderer, "Wpn: \(pw) \(wInfo)", x: x, y: cy, color: .amber, scale: 1)
                cy += lineH
            }
            var flags: [String] = []
            if b.hasTurret { flags.append("Turret") }
            if b.isCapturable { flags.append("Capture") }
            if b.isWall { flags.append("Wall") }
            if b.isCivilian { flags.append("Civilian") }
            if !flags.isEmpty {
                drawTextLeft(renderer, "Flags: \(flags.joined(separator: " "))", x: x, y: cy, color: .cyan, scale: 1)
            }
        } else {
            drawTextLeft(renderer, "No building data found", x: x, y: cy, color: .red, scale: 1)
        }
    }

    private func renderVFXInfo(_ renderer: OpaquePointer?, name: String, x: Int32, y: Int32, w: Int32) {
        var cy = y
        let lineH: Int32 = 14

        if let manifest = getRemasteredManifest(name: name) {
            drawTextLeft(renderer, "Frames: \(manifest.frameCount)", x: x, y: cy, color: .green, scale: 1)
            cy += lineH
            drawTextLeft(renderer, "Canvas: \(manifest.canvasWidth)x\(manifest.canvasHeight)", x: x, y: cy, color: .green, scale: 1)
            cy += lineH
            drawTextLeft(renderer, "Category: \(manifest.category)", x: x, y: cy, color: .green, scale: 1)
        } else {
            drawTextLeft(renderer, "No manifest data", x: x, y: cy, color: .red, scale: 1)
        }
    }

    private func renderSHPInfo(_ renderer: OpaquePointer?, name: String, x: Int32, y: Int32, w: Int32) {
        let baseName = name.replacingOccurrences(of: ".SHP", with: "").uppercased()
        let spriteName = spriteNameOverrides[baseName] ?? baseName
        if let shp = renderState.objectSHPCache[spriteName], !shp.frames.isEmpty {
            let f = shp.frames[currentFrame % shp.frames.count]
            drawTextLeft(renderer, "Frames: \(shp.frames.count)  Size: \(f.width)x\(f.height)", x: x, y: y, color: .green, scale: 1)
        } else {
            drawTextLeft(renderer, "SHP not loaded", x: x, y: y, color: .red, scale: 1)
        }
    }

    private func weaponDescription(_ weapon: WeaponType) -> String {
        guard let wd = weaponTypeData[weapon] else { return "" }
        let bullet = bulletTypeData[wd.fires]
        let warhead = bullet?.warhead
        let whName = warhead.map { "\($0)" } ?? "?"
        return "(\(wd.damage)dmg R:\(wd.rangeInCells) \(whName))"
    }
}

// MARK: - Sprite Playground Screen

class SpritePlaygroundScreen: MenuScreen {
    func render(_ renderer: OpaquePointer?) {
        session.spritePlayground.render(renderer)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = MainMenuScreen()
            return
        }
        session.spritePlayground.handleKey(key)
    }
}
