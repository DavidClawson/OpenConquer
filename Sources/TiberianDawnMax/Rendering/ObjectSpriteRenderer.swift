import CSDL2
import Foundation
import OpenConquerCore

// MARK: - Object Sprite Helpers
// Per-object sprite selection and overlays used by renderGame: building frames, LST deck cargo, aircraft rotors.

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

// MARK: - Hovercraft Deck Cargo

/// Draw the units riding an LST on its deck, facing north, at the
/// StoppingCoordAbs spots they'll step off from — the "piggy back" draw in
/// UnitClass::Draw_It. They stay limboed (and unselectable) until unloaded.
func renderHovercraftDeck(_ renderer: OpaquePointer?, _ lst: GameObject, x: Int32, y: Int32) {
    guard let world = session.world else { return }
    for (i, id) in lst.passengers.enumerated() {
        guard let unit = world.findObject(id: id), unit.strength > 0 else { continue }
        let deck = hovercraftDeckOffsets[i % hovercraftDeckOffsets.count]
        let cx = x + Int32(deck.dx), cy = y + Int32(deck.dy)
        // Frame 0 = facing north: infantry's standing pose, a vehicle's body;
        // a turreted vehicle's north turret follows its 32 body frames.
        var frames = [0]
        if unit.kind == .unit && unit.hasTurret { frames.append(32) }
        for frame in frames {
            guard let info = getObjectTexture(renderer, typeName: unit.typeName, frame: frame, house: unit.house) else { continue }
            var dst = SDL_Rect(x: cx - Int32(info.width) / 2, y: cy - Int32(info.height) / 2,
                               w: Int32(info.width), h: Int32(info.height))
            SDL_RenderCopy(renderer, info.texture, nil, &dst)
        }
    }
}

// MARK: - Aircraft Rotors

/// Classic hover bob for helicopters holding at flight level
/// (AircraftClass::Draw_It `_jitter`). Cosmetic — draw-time only.
func aircraftHoverJitter(_ obj: GameObject) -> Int32 {
    guard obj.altitude == flightLevel, !obj.isFixedWing else { return 0 }
    let table: [Int32] = [0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, -1, -1, -1, 0]
    return table[(Int(SDL_GetTicks() / 66) + obj.id) % 16]
}

/// Draw LROTOR/RROTOR.SHP over a rotor-equipped aircraft, mirroring
/// AircraftClass::Draw_It: airborne blades spin fast (frames 0-3, see-through);
/// parked blades idle (frames 4-11). The Chinook has two rotors placed fore and
/// aft along its heading, 8-10px out by facing (`_stretch`); others get one,
/// centered. `y` is the drawn (altitude-adjusted) body center.
func renderAircraftRotors(_ renderer: OpaquePointer?, _ obj: GameObject, x: Int32, y: Int32) {
    guard let at = AircraftType.from(iniName: obj.typeName.uppercased()),
          let data = aircraftTypeDataTable[at], data.isRotorEquipped else { return }

    let stage = Int(SDL_GetTicks() / 66) + obj.id
    let airborne = obj.altitude > 0
    let frame = airborne ? stage % 4 : (stage % 8) + 4
    let alpha: UInt8 = airborne ? 140 : 200

    func blit(_ name: String, _ cx: Double, _ cy: Double) {
        guard let info = getObjectTexture(renderer, typeName: name, frame: frame, house: obj.house) else { return }
        SDL_SetTextureAlphaMod(info.texture, alpha)
        var dst = SDL_Rect(x: Int32(cx.rounded()) - Int32(info.width) / 2,
                           y: Int32(cy.rounded()) - 2 - Int32(info.height) / 2,
                           w: Int32(info.width), h: Int32(info.height))
        SDL_RenderCopy(renderer, info.texture, nil, &dst)
        SDL_SetTextureAlphaMod(info.texture, 255)  // textures are cached and shared
    }

    if at == .transport {
        let stretch: [Double] = [8, 9, 10, 9, 8, 9, 10, 9]
        let d = stretch[((obj.facing + 16) & 0xFF) / 32]
        let rad = Double(obj.facing) / 256.0 * 2.0 * .pi
        let ux = sin(rad), uy = -cos(rad)  // 0 = north, clockwise
        blit("RROTOR", Double(x) + ux * d, Double(y) + uy * d)  // front
        blit("LROTOR", Double(x) - ux * d, Double(y) - uy * d)  // rear
    } else {
        blit("RROTOR", Double(x), Double(y))
    }
}
