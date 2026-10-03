import CSDL2
import Foundation

// MARK: - Classic (1995) Sidebar
//
// The original hi-res sidebar drawn from its own art in UPDATEC.MIX (HSIDE1/2,
// HSTRIP, HCLOCK, HPWRBAR, HTABS, the button shapes, HRADAR.GDI/NOD) and the
// per-theater build cameos (<NAME>ICNH.TEM|DES|WIN). Layout numbers are the
// 640x400 hi-res ones from SIDEBAR.CPP / RADAR.CPP / POWER.CPP / TAB.CPP,
// expressed relative to the sidebar column (the original's x=480), and drawn
// at a whole-number scale so the 400-line layout fills the window height.
//
// Presentation over the existing production model: the structure and unit
// ProductionQueues, superweapons, repair/sell modes and the minimap.

/// Logical (hi-res) width of the sidebar column.
let classicSidebarLogicalWidth: Int32 = 160

/// Whole-number scale for the classic sidebar: the chosen size (Options), reduced
/// when the window can't fit the original 400-line layout at that scale or the
/// column would take more than a third of the width.
var classicSidebarScale: Int32 {
    let byHeight = max(1, renderState.windowHeight / 400)
    let byWidth = max(1, renderState.windowWidth / (classicSidebarLogicalWidth * 3))
    return max(1, min(UserSettings.sidebarSize.scale, byHeight, byWidth))
}

/// The classic sidebar is in use: chosen in Options and its art is installed.
var classicSidebarActive: Bool {
    UserSettings.sidebarStyle == .classic && ClassicSidebarArt.shared.isAvailable
}

// MARK: - Layout (hi-res coordinates relative to the sidebar column)

private enum ClassicLayout {
    static let side1Y: Int32 = 158, side2Y: Int32 = 276
    static let radarY: Int32 = 15
    static let radarInnerX: Int32 = 16, radarInnerY: Int32 = 21, radarInnerSize: Int32 = 128
    static let repairX: Int32 = 4, sellX: Int32 = 57, mapX: Int32 = 110, buttonY: Int32 = 160
    static let buttonW: Int32 = 49, buttonH: Int32 = 16
    static let stripX: [Int32] = [17, 87], stripY: Int32 = 182
    static let cameoW: Int32 = 64, cameoH: Int32 = 48, cameoInset: Int32 = 3
    static let clipTop: Int32 = 182
    static let scrollW: Int32 = 32, scrollH: Int32 = 27
    static let powerX: Int32 = 0, powerY: Int32 = 180

    // Autolayout: the column is as tall as the window (in hi-res rows), and the
    // strips take every whole cameo row that fits above the scroll buttons. At
    // 400 rows these reproduce the original exactly: 4 rows, strip window
    // 182..372 (WINDOW_SIDEBAR h=191), scroll buttons at 373, power bar bottom
    // 399 with a 218px gauge.

    /// Hi-res rows available in the window.
    static var height: Int32 { max(400, renderState.windowHeight / classicSidebarScale) }
    /// Visible cameo rows per strip (MAX_VISIBLE = 4 at 400 rows).
    static var visibleRows: Int { max(4, Int((height - stripY + 1 - scrollH) / cameoH)) }
    /// End (exclusive) of the strip window, which is also where the scroll buttons sit.
    static var scrollY: Int32 { stripY + Int32(visibleRows) * cameoH - 1 }
    static var clipBottom: Int32 { scrollY }
    /// The power bar runs down beside the strips to the bottom of the scroll buttons.
    static var powerBottom: Int32 { scrollY + scrollH - 1 }
    static var powerMax: Int32 { powerBottom - powerY - 1 }
}

// MARK: - Art

/// Lazily loaded sidebar shapes. Textures are cached per theater, since the
/// hi-res art is drawn with the theater palette ("theater dependant").
final class ClassicSidebarArt {
    static let shared = ClassicSidebarArt()

    private var shapes: [String: SHPFile] = [:]
    private var missing: Set<String> = []
    private var textures: [String: OpaquePointer] = [:]
    private var textureTheater: TheaterType? = nil
    private var checked = false
    private var available = false

    /// UPDATEC.MIX's art is installed (checked once, on first use).
    var isAvailable: Bool {
        checkAvailability()
        return available
    }

    /// Files the layout can't do without; cameos and radar fall back gracefully.
    private static let required = ["HSIDE1.SHP", "HSIDE2.SHP", "HSTRIP.SHP", "HCLOCK.SHP", "HTABS.SHP",
                                   "HREPAIR.SHP", "HSELL.SHP", "HMAP.SHP", "HPWRBAR.SHP", "HPOWER.SHP",
                                   "HSTRIPUP.SHP", "HSTRIPDN.SHP", "HPIPS.SHP"]

    /// Check once whether UPDATEC.MIX's art is installed.
    func checkAvailability() {
        guard !checked else { return }
        checked = true
        available = Self.required.allSatisfy { shape($0) != nil }
        if !available {
            print("ClassicSidebar: hi-res sidebar art missing (UPDATEC.MIX) — using the modern sidebar")
        }
    }

    func shape(_ name: String) -> SHPFile? {
        if let s = shapes[name] { return s }
        if missing.contains(name) { return nil }
        guard let data = mixManager.retrieve(name), let shp = try? SHPFile(data: data) else {
            missing.insert(name)
            return nil
        }
        shapes[name] = shp
        return shp
    }

    /// Texture for one frame. `ghostClock` renders HCLOCK's palette index 3 as
    /// the ClockTranslucentTable does: the cameo underneath faded toward LTGREY
    /// (index 14) at 180/256.
    func texture(_ renderer: OpaquePointer?, _ name: String, frame: Int, ghostClock: Bool = false)
        -> (texture: OpaquePointer, width: Int32, height: Int32)? {
        let theater = session.world?.theater ?? .temperate
        if textureTheater != theater {
            for tex in textures.values { SDL_DestroyTexture(tex) }
            textures.removeAll()
            textureTheater = theater
        }
        guard let shp = shape(name), frame >= 0, frame < shp.frames.count else { return nil }
        let f = shp.frames[frame]
        let key = "\(name)#\(frame)"
        if let tex = textures[key] { return (tex, Int32(f.width), Int32(f.height)) }

        let tex: OpaquePointer?
        if ghostClock {
            tex = createClockTexture(renderer, frame: f)
        } else {
            tex = createUISpriteTexture(renderer, frame: f)
        }
        guard let t = tex else { return nil }
        textures[key] = t
        return (t, Int32(f.width), Int32(f.height))
    }

    private func createClockTexture(_ renderer: OpaquePointer?, frame: SHPFrame) -> OpaquePointer? {
        let w = frame.width, h = frame.height
        let format: UInt32 = 0x16362004  // SDL_PIXELFORMAT_ARGB8888
        guard w > 0, h > 0, renderState.gamePalette.count > 14,
              let texture = SDL_CreateTexture(renderer, format, Int32(SDL_TEXTUREACCESS_STATIC.rawValue),
                                              Int32(w), Int32(h)) else { return nil }
        let grey = renderState.gamePalette[14]
        var argb = [UInt32](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let idx = Int(frame.pixels[i])
            if idx == 0 { continue }
            let c = idx == 3 ? grey : renderState.gamePalette[idx]
            let alpha: UInt32 = idx == 3 ? 180 : 255
            argb[i] = (alpha << 24) | (UInt32(c.r) << 16) | (UInt32(c.g) << 8) | UInt32(c.b)
        }
        _ = argb.withUnsafeMutableBufferPointer { SDL_UpdateTexture(texture, nil, $0.baseAddress, Int32(w * 4)) }
        SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)
        return texture
    }
}

// MARK: - State

/// Per-session presentation state for the classic sidebar.
private struct ClassicSidebarState {
    var topIndex = [0, 0]          // first visible cameo per column
    var radarFrame = 0             // HRADAR frame currently shown
    var powerHeight: Int32 = 0     // displayed (animated) power-bar height
    var drainHeight: Int32 = 0
    var lastStepTicks: UInt32 = 0  // 15 Hz animation clock
}
private var classicState = ClassicSidebarState()

/// One entry in a production column.
private enum ClassicCameo {
    case structure(BuildableStructure)
    case unit(BuildableItem)
    case superWeapon(SpecialWeaponType)

    var iniName: String {
        switch self {
        case .structure(let s): return s.name
        case .unit(let u): return u.name
        case .superWeapon(let t):
            switch t {
            case .ionCannon: return "ION"
            case .nuclearStrike: return "ATOM"
            case .airStrike: return "BOMB"
            }
        }
    }
}

/// Column 0 = structures; column 1 = units, then superweapons (Which_Column).
private func classicColumns() -> [[ClassicCameo]] {
    var units: [ClassicCameo] = getAvailableUnits().map { .unit($0) }
    for (weapon, type) in [(session.playerIonCannon, SpecialWeaponType.ionCannon),
                           (session.playerNukeStrike, .nuclearStrike),
                           (session.playerAirStrike, .airStrike)] where weapon.isPresent {
        units.append(.superWeapon(type))
    }
    return [getAvailableStructures().map { .structure($0) }, units]
}

private func superWeapon(_ type: SpecialWeaponType) -> SuperWeapon {
    switch type {
    case .ionCannon: return session.playerIonCannon
    case .nuclearStrike: return session.playerNukeStrike
    case .airStrike: return session.playerAirStrike
    }
}

// MARK: - Coordinates

private var sidebarOriginX: Int32 { renderState.windowWidth - sidebarWidth }

/// Screen rect for a hi-res rect inside the sidebar column.
private func screenRect(_ x: Int32, _ y: Int32, _ w: Int32, _ h: Int32) -> SDL_Rect {
    let s = classicSidebarScale
    return SDL_Rect(x: sidebarOriginX + x * s, y: y * s, w: w * s, h: h * s)
}

/// Hi-res point inside the sidebar column for a screen point.
private func logicalPoint(_ x: Int32, _ y: Int32) -> (x: Int32, y: Int32) {
    let s = classicSidebarScale
    return ((x - sidebarOriginX) / s, y / s)
}

/// Draw a shape frame at a hi-res position, optionally clipped to hi-res rows.
private func blit(_ renderer: OpaquePointer?, _ name: String, frame: Int, _ x: Int32, _ y: Int32,
                  clipY: ClosedRange<Int32>? = nil, ghostClock: Bool = false) {
    guard let tex = ClassicSidebarArt.shared.texture(renderer, name, frame: frame, ghostClock: ghostClock) else { return }
    var srcY: Int32 = 0, srcH = tex.height
    if let clip = clipY {
        let top = max(y, clip.lowerBound), bottom = min(y + tex.height, clip.upperBound + 1)
        guard bottom > top else { return }
        srcY = top - y
        srcH = bottom - top
    }
    var src = SDL_Rect(x: 0, y: srcY, w: tex.width, h: srcH)
    var dst = screenRect(x, y + srcY, tex.width, srcH)
    SDL_RenderCopy(renderer, tex.texture, &src, &dst)
}

/// Draw part of a shape frame (hi-res source rect) at a hi-res position.
private func blitRegion(_ renderer: OpaquePointer?, _ name: String, frame: Int,
                        srcX: Int32, srcY: Int32, w: Int32, h: Int32, _ x: Int32, _ y: Int32) {
    guard let tex = ClassicSidebarArt.shared.texture(renderer, name, frame: frame) else { return }
    var src = SDL_Rect(x: srcX, y: srcY, w: min(w, tex.width - srcX), h: min(h, tex.height - srcY))
    var dst = screenRect(x, y, src.w, src.h)
    SDL_RenderCopy(renderer, tex.texture, &src, &dst)
}

/// Build cameo for an object: "%.4sICNH" + theater suffix (UDATA/BDATA/IDATA
/// Init_Theater), with the .SHP fallback One_Time tries.
private func cameoName(_ ini: String) -> String? {
    let base = String(ini.uppercased().prefix(4)) + "ICNH"
    let suffix = (session.world?.theater ?? .temperate).suffix
    if ClassicSidebarArt.shared.shape(base + suffix) != nil { return base + suffix }
    if ClassicSidebarArt.shared.shape(base + ".SHP") != nil { return base + ".SHP" }
    return nil
}

// MARK: - Rendering

func renderClassicSidebar(_ renderer: OpaquePointer?) {
    guard let world = session.world else { return }
    stepClassicAnimations(world)

    let s = classicSidebarScale
    let viewH = renderState.windowHeight / s  // hi-res rows available

    // Column background: black, then the granite shapes (and more granite
    // below 768 on very tall windows).
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
    var bg = SDL_Rect(x: sidebarOriginX, y: 0, w: sidebarWidth, h: renderState.windowHeight)
    SDL_RenderFillRect(renderer, &bg)

    renderClassicRadar(renderer, world: world)
    // Frame 1 is the fully composited granite; frame 0 (what the original
    // draws) has holes for the parts drawn separately. Laying frame 1 down
    // first means a hole the taller layout leaves uncovered — e.g. where the
    // original's scroll buttons sat — shows granite, not black.
    for frame in [1, 0] {
        blit(renderer, "HSIDE1.SHP", frame: frame, 0, ClassicLayout.side1Y)
        var y = ClassicLayout.side2Y
        while y < viewH {
            blit(renderer, "HSIDE2.SHP", frame: frame, 0, y)
            y += 492
        }
    }
    // The art is black between the two scroll-button pairs (rows 373-399):
    // the bottom of the 1995 screen. With a taller strip that gap sits
    // mid-column, so patch it with the same columns of granite from lower down.
    if ClassicLayout.visibleRows > 4 {
        blitRegion(renderer, "HSIDE2.SHP", frame: 1, srcX: 80, srcY: 260, w: 16, h: 27, 80, 373)
    }
    // The bar shows through frame 0's hole on the original 400 lines; below
    // that the opaque granite fill would hide it, so draw it on top.
    renderClassicPowerBar(renderer)
    renderClassicStrips(renderer)
    renderClassicButtons(renderer)
    renderClassicTab(renderer)
}

/// Credits tab (TAB.CPP Draw_Credits_Tab): HTABS over a black strip, the
/// value centered. 12GRNGRD.FNT isn't loaded yet, so the built-in font stands in.
private func renderClassicTab(_ renderer: OpaquePointer?) {
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
    var top = screenRect(0, 0, classicSidebarLogicalWidth, 15)
    SDL_RenderFillRect(renderer, &top)
    blit(renderer, "HTABS.SHP", frame: 0, 0, 0)
    let s = classicSidebarScale
    drawText(renderer, "\(session.displayedCredits)",
             centerX: sidebarOriginX + 80 * s, centerY: 7 * s, color: .green, scale: max(1, s))
}

/// Radar (RADAR.CPP): HRADAR frame 0 = no radar, 1-21 = powering up, 22 =
/// active (the map is drawn inside), 41 = present but offline.
private func renderClassicRadar(_ renderer: OpaquePointer?, world: GameWorld) {
    let house = world.playerHouse == .badGuy ? "NOD" : "GDI"
    let frame = classicState.radarFrame
    blit(renderer, "HRADAR.\(house)", frame: frame, 0, ClassicLayout.radarY)
    if frame == 22 {
        var inner = screenRect(ClassicLayout.radarInnerX, ClassicLayout.radarInnerY,
                               ClassicLayout.radarInnerSize, ClassicLayout.radarInnerSize)
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
        SDL_RenderFillRect(renderer, &inner)
        renderGameMinimap(renderer, world: world)
    }
}

/// Production strips: HSTRIP backdrop when a column has fewer than four
/// entries, the cameos (clipped to the strip window), clock / READY / HOLD,
/// and the scroll buttons (SIDEBAR.CPP StripClass::Draw_It).
private func renderClassicStrips(_ renderer: OpaquePointer?) {
    let columns = classicColumns()
    let clip = ClassicLayout.clipTop...(ClassicLayout.clipBottom - 1)
    for (col, entries) in columns.enumerated() {
        let x = ClassicLayout.stripX[col] + ClassicLayout.cameoInset
        let top = min(classicState.topIndex[col], max(0, entries.count - ClassicLayout.visibleRows))
        classicState.topIndex[col] = top

        if entries.count < ClassicLayout.visibleRows {
            // The empty-slot plates are 4 rows (192px) tall; repeat them down a taller strip.
            var plateY = ClassicLayout.stripY - 1
            while plateY < ClassicLayout.clipBottom {
                blit(renderer, "HSTRIP.SHP", frame: col, x, plateY, clipY: clip)
                plateY += 4 * ClassicLayout.cameoH
            }
        }
        for slot in 0..<ClassicLayout.visibleRows {
            let index = top + slot
            guard index < entries.count else { break }
            let y = ClassicLayout.stripY - 1 + Int32(slot) * ClassicLayout.cameoH
            renderClassicCameo(renderer, entries[index], x: x, y: y, clip: clip)
        }
        blit(renderer, "HSTRIPUP.SHP", frame: 0, x, ClassicLayout.scrollY)
        blit(renderer, "HSTRIPDN.SHP", frame: 0, x + ClassicLayout.scrollW, ClassicLayout.scrollY)
    }
}

private func renderClassicCameo(_ renderer: OpaquePointer?, _ cameo: ClassicCameo, x: Int32, y: Int32,
                                clip: ClosedRange<Int32>) {
    if let name = cameoName(cameo.iniName) {
        blit(renderer, name, frame: 0, x, y, clipY: clip)
    } else {
        // No cameo art for this type: a dark plate with its name.
        var r = screenRect(x, max(y, clip.lowerBound), ClassicLayout.cameoW, ClassicLayout.cameoH - 1)
        SDL_SetRenderDrawColor(renderer, 24, 24, 24, 255)
        SDL_RenderFillRect(renderer, &r)
        drawText(renderer, cameo.iniName, centerX: r.x + r.w / 2, centerY: r.y + r.h / 2, color: .green, scale: 1)
    }

    // Progress: frame 0 darkens an entry whose factory is busy with something
    // else; frame stage+1 (stage 0..108) is the clock wipe (FACTORY.H STEP_COUNT).
    let pipX = x + ClassicLayout.cameoW / 2, pipY = y + 32
    switch cameo {
    case .structure(let item):
        drawQueueOverlay(renderer, session.structureBuildQueue, item: item.name, x: x, y: y, clip: clip,
                         pipX: pipX, pipY: pipY)
    case .unit(let item):
        drawQueueOverlay(renderer, session.unitBuildQueue, item: item.name, x: x, y: y, clip: clip,
                         pipX: pipX, pipY: pipY)
    case .superWeapon(let type):
        let weapon = superWeapon(type)
        if weapon.isReady {
            drawPip(renderer, 3, x: pipX, y: pipY, clip: clip)  // READY
        } else {
            let stage = Int(weapon.chargeFraction * 108)
            blit(renderer, "HCLOCK.SHP", frame: min(108, stage) + 1, x, y, clipY: clip, ghostClock: true)
        }
    }
}

private func drawQueueOverlay(_ renderer: OpaquePointer?, _ queue: ProductionQueue, item name: String,
                              x: Int32, y: Int32, clip: ClosedRange<Int32>, pipX: Int32, pipY: Int32) {
    guard let current = queue.item else { return }
    guard current.typeName == name else {
        blit(renderer, "HCLOCK.SHP", frame: 0, x, y, clipY: clip, ghostClock: true)  // factory busy
        return
    }
    if queue.isComplete {
        drawPip(renderer, 3, x: pipX, y: pipY, clip: clip)  // READY
        return
    }
    let stage = Int(queue.progressFraction * 108)
    blit(renderer, "HCLOCK.SHP", frame: min(108, stage) + 1, x, y, clipY: clip, ghostClock: true)
    if queue.isOnHold {
        drawPip(renderer, 4, x: pipX, y: pipY, clip: clip)  // HOLD
    }
}

/// HPIPS READY (3) / HOLDING (4), drawn centered.
private func drawPip(_ renderer: OpaquePointer?, _ frame: Int, x: Int32, y: Int32, clip: ClosedRange<Int32>) {
    guard let tex = ClassicSidebarArt.shared.texture(renderer, "HPIPS.SHP", frame: frame) else { return }
    blit(renderer, "HPIPS.SHP", frame: frame, x - tex.width / 2, y - tex.height / 2, clipY: clip)
}

/// Repair / Sell (frame = on) and Map (0 up, 2 disabled without radar).
private func renderClassicButtons(_ renderer: OpaquePointer?) {
    blit(renderer, "HREPAIR.SHP", frame: session.isRepairMode ? 1 : 0, ClassicLayout.repairX, ClassicLayout.buttonY)
    blit(renderer, "HSELL.SHP", frame: session.isSellMode ? 1 : 0, ClassicLayout.sellX, ClassicLayout.buttonY)
    blit(renderer, "HMAP.SHP", frame: classicState.radarFrame == 22 ? 0 : 2, ClassicLayout.mapX, ClassicLayout.buttonY)
}

/// Power bar (POWER.CPP Draw_It): the empty bar above the output level, the
/// green/yellow/red fill below it, and the HPOWER marker at the drain level.
private func renderClassicPowerBar(_ renderer: OpaquePointer?) {
    let bottom = ClassicLayout.powerBottom
    let fillTop = bottom - classicState.powerHeight
    guard let world = session.world else { return }
    let state = getHouseState(world.playerHouse)
    let fill = state.powerDrain > state.powerOutput * 2 ? 6 : (state.powerDrain > state.powerOutput ? 4 : 2)

    let empty = ClassicLayout.powerY...(fillTop - 1)
    let full = fillTop...bottom
    // Frame pairs: the cap (0/2/4/6) at the top, then the long run (1/3/5/7,
    // 492 rows) — repeated if a very tall column outruns it.
    var pieces: [(frame: Int, y: Int32)] = [(0, ClassicLayout.powerY)]
    var runY = ClassicLayout.powerY + 100
    while runY <= bottom {
        pieces.append((1, runY))
        runY += 492
    }
    for (frame, y) in pieces {
        if !empty.isEmpty { blit(renderer, "HPWRBAR.SHP", frame: frame, ClassicLayout.powerX, y, clipY: empty) }
        blit(renderer, "HPWRBAR.SHP", frame: frame + fill, ClassicLayout.powerX, y, clipY: full)
    }
    blit(renderer, "HPOWER.SHP", frame: 0, ClassicLayout.powerX, bottom - classicState.drainHeight + 1)
}

/// Power_Height (POWER.CPP): each full 100 units closes 1/6 of the remaining
/// gap to 218; the remainder adds its proportional share. A taller gauge
/// (autolayout) scales the same curve to its height.
private func classicPowerHeight(_ value: Int) -> Int32 {
    var h = 0
    var v = max(0, value)
    while v >= 100 {
        h += (218 - h) / 6
        v -= 100
    }
    h += ((218 - h) / 6) * v / 100
    h = min(218, max(0, h))
    return Int32(h * Int(ClassicLayout.powerMax) / 218)
}

/// 15 Hz: radar power-up/down frames, and the power bar sliding 1px a step.
private func stepClassicAnimations(_ world: GameWorld) {
    let now = SDL_GetTicks()
    guard now - classicState.lastStepTicks >= 66 else { return }
    classicState.lastStepTicks = now

    // Radar
    var frame = classicState.radarFrame
    if !playerHasCommsCenter(world) {
        frame = 0
    } else if playerRadarOnline(world) {
        if frame < 22 { frame += 1 } else if frame > 22 { frame -= 1 }
        if frame == 22 && classicState.radarFrame != 22 { audioManager.play(.radarOn) }
    } else {
        if frame == 22 { audioManager.play(.radarOff) }
        if frame < 22 && frame > 0 { frame += 1 }  // finish powering up, then shut down
        if frame >= 22 && frame < 41 { frame += 1 }
        if frame == 0 { frame = 41 }
    }
    classicState.radarFrame = frame

    // Power bar
    let state = getHouseState(world.playerHouse)
    let target = classicPowerHeight(state.powerOutput)
    let drainTarget = classicPowerHeight(state.powerDrain)
    classicState.powerHeight += (target > classicState.powerHeight ? 1 : (target < classicState.powerHeight ? -1 : 0))
    classicState.drainHeight += (drainTarget > classicState.drainHeight ? 1 : (drainTarget < classicState.drainHeight ? -1 : 0))
}

/// Forget scroll positions and animation state (new mission).
func resetClassicSidebarState() {
    classicState = ClassicSidebarState()
}

// MARK: - Minimap placement

/// Where the minimap sits: inside the classic radar's 128x128 well, or the
/// modern overlay at the bottom-right of the battlefield. `x/y/size` is the
/// well; `originX/Y` is where cell (0,0) lands. The classic radar fits the
/// playable area — min(128/width, 128/height) px per cell, centered
/// (RADAR.CPP Zoom_Mode) — while the modern overlay shows all 64x64 cells.
func minimapLayout() -> (x: Int32, y: Int32, size: Int32, cellSize: Int32, originX: Int32, originY: Int32) {
    if classicSidebarActive {
        let s = classicSidebarScale
        let r = screenRect(ClassicLayout.radarInnerX, ClassicLayout.radarInnerY, 0, 0)
        let well = ClassicLayout.radarInnerSize
        let bounds = session.world?.mapBounds ?? MapBounds(x: 0, y: 0, width: 64, height: 64)
        let perCell = max(1, well / Int32(max(bounds.width, bounds.height, 1)))
        let offX = (well - Int32(bounds.width) * perCell) / 2 * s
        let offY = (well - Int32(bounds.height) * perCell) / 2 * s
        let cell = perCell * s
        return (r.x, r.y, well * s, cell,
                r.x + offX - Int32(bounds.x) * cell, r.y + offY - Int32(bounds.y) * cell)
    }
    let cellSize: Int32 = 2
    let size: Int32 = 64 * cellSize
    let pad: Int32 = 10
    let x = renderState.windowWidth - sidebarWidth - size - pad, y = renderState.windowHeight - size - pad
    return (x, y, size, cellSize, x, y)
}

// MARK: - Input

/// Mouse down inside the classic sidebar. Left: build / resume / place /
/// fire; right: hold, then cancel (SelectClass::Action). Returns true if used.
@discardableResult
func handleClassicSidebarMouseDown(_ sx: Int32, _ sy: Int32, button: UInt8) -> Bool {
    let p = logicalPoint(sx, sy)
    let left = button == UInt8(SDL_BUTTON_LEFT)

    // Repair / Sell / Map
    if p.y >= ClassicLayout.buttonY && p.y < ClassicLayout.buttonY + ClassicLayout.buttonH && left {
        if p.x >= ClassicLayout.repairX && p.x < ClassicLayout.repairX + ClassicLayout.buttonW {
            session.isRepairMode.toggle()
            session.isSellMode = false
            return true
        }
        if p.x >= ClassicLayout.sellX && p.x < ClassicLayout.sellX + ClassicLayout.buttonW {
            session.isSellMode.toggle()
            session.isRepairMode = false
            return true
        }
        return p.x >= ClassicLayout.mapX  // Map: radar zoom isn't implemented yet
    }

    let columns = classicColumns()
    for col in 0..<2 {
        let stripX = ClassicLayout.stripX[col]

        // Scroll buttons (up = earlier entries)
        if left && p.y >= ClassicLayout.scrollY && p.y < ClassicLayout.scrollY + ClassicLayout.scrollH {
            let upX = stripX + ClassicLayout.cameoInset
            if p.x >= upX && p.x < upX + ClassicLayout.scrollW {
                classicState.topIndex[col] = max(0, classicState.topIndex[col] - 1)
                return true
            }
            if p.x >= upX + ClassicLayout.scrollW && p.x < upX + 2 * ClassicLayout.scrollW {
                let maxTop = max(0, columns[col].count - ClassicLayout.visibleRows)
                classicState.topIndex[col] = min(maxTop, classicState.topIndex[col] + 1)
                return true
            }
        }

        // Cameo slots — the hit box starts 3px left of the art (SelectButton at X)
        guard p.x >= stripX && p.x < stripX + ClassicLayout.cameoW,
              p.y >= ClassicLayout.clipTop && p.y < ClassicLayout.clipBottom else { continue }
        let slot = Int((p.y - ClassicLayout.stripY) / ClassicLayout.cameoH)
        let index = classicState.topIndex[col] + slot
        guard slot >= 0, index < columns[col].count else { return true }
        classicCameoAction(columns[col][index], left: left)
        return true
    }
    return false
}

private func classicCameoAction(_ cameo: ClassicCameo, left: Bool) {
    switch cameo {
    case .structure(let item):
        classicQueueAction(session.structureBuildQueue, name: item.name, cost: item.cost,
                           buildTicks: item.buildTicks, isStructure: true, left: left)
    case .unit(let item):
        classicQueueAction(session.unitBuildQueue, name: item.name, cost: item.cost,
                           buildTicks: item.buildTicks, isStructure: false, left: left)
    case .superWeapon(let type):
        if left {
            if superWeapon(type).isReady {
                startSuperWeaponTargeting(type)
            } else {
                audioManager.speak(.notReady)
            }
        } else if session.superWeaponTargeting == type {
            session.superWeaponTargeting = nil
        }
    }
}

private func classicQueueAction(_ queue: ProductionQueue, name: String, cost: Int, buildTicks: Int,
                                isStructure: Bool, left: Bool) {
    let isThis = queue.item?.typeName == name

    if !left {
        // Right: cancel a pending placement; hold a running build; cancel a held or finished one.
        guard isThis else { return }
        if isStructure && session.isPlacingStructure {
            session.isPlacingStructure = false
            session.placementType = nil
        }
        if !queue.isComplete && !queue.isOnHold {
            queue.isOnHold = true
            audioManager.speak(.suspended)
        } else {
            session.sidebarCredits += queue.cancel()  // full cost was paid up front
            audioManager.speak(.canceled)
        }
        return
    }

    if isThis {
        if queue.isComplete && isStructure {
            session.isPlacingStructure = true
            session.placementType = name
        } else if queue.isOnHold {
            queue.isOnHold = false
            audioManager.speak(.building)
        }
        return
    }
    if queue.item != nil {
        audioManager.speak(.unableToBuild)  // this factory is busy with something else
        return
    }
    guard session.sidebarCredits >= cost else {
        audioManager.speak(.noCash)
        return
    }
    queue.start(typeName: name, cost: cost, buildTime: buildTicks)
    session.sidebarCredits -= cost
    audioManager.speak(.building)
}
