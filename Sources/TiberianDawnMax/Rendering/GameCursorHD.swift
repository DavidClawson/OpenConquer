import CSDL2
import Foundation

// MARK: - Remastered HD Mouse Cursors
//
// Draws the animated HD cursors extracted from the C&C Remastered Collection
// (`tools/extract_remastered_sprites.py --category ui` →
// sprites_remastered/ui/cursors/). Each of the procedural `CursorDef`s in
// GameCursor.swift maps to a remastered texture "family" (a folder of animation
// frames) plus a hotspot read from the cursors.json manifest. When the HD art
// is present we blit it; otherwise the caller falls back to the procedural
// drawing. This is render-only and has no effect on the simulation.

/// On-screen size (px) for a centered 48px HD cursor. The remastered frames are
/// 48×48 (2× the old ~20px procedural cursors); scaling to ~28px keeps them
/// close to the classic on-screen footprint while using the crisp HD source.
private let hdCursorTargetSize: Double = 28.0
private let hdCursorSourceSize: Double = 48.0
private let hdCursorScale: Double = hdCursorTargetSize / hdCursorSourceSize

private struct HDCursorFamily {
    let frameCount: Int
    let w: Int
    let h: Int
    let hotX: Int
    let hotY: Int
}

private var hdCursorsChecked = false
private var hdCursorsAvailable = false
private var hdCursorFamilies: [String: HDCursorFamily] = [:]
private var hdCursorDir: String = ""
private var hdCursorTextureCache: [String: OpaquePointer] = [:]  // "FAMILY-frame" -> texture

/// Lazily load the cursor manifest on first use.
private func ensureHDCursorsLoaded() {
    guard !hdCursorsChecked else { return }
    hdCursorsChecked = true

    let cursorsDir = assetManager.extractedPath
        .appendingPathComponent("sprites_remastered")
        .appendingPathComponent("ui")
        .appendingPathComponent("cursors")
    let manifestURL = cursorsDir.appendingPathComponent("cursors.json")

    guard let data = try? Data(contentsOf: manifestURL),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let families = root["families"] as? [String: Any] else {
        return
    }

    // Hotspots live under "pointers" (POINTER_* -> {family, hotX, hotY}); collapse
    // them to a per-family hotspot (first pointer that references the family wins).
    var famHot: [String: (Int, Int)] = [:]
    if let pointers = root["pointers"] as? [String: Any] {
        for (_, v) in pointers {
            guard let p = v as? [String: Any],
                  let fam = p["family"] as? String else { continue }
            if famHot[fam] == nil {
                let hx = (p["hotX"] as? Int) ?? 0
                let hy = (p["hotY"] as? Int) ?? 0
                famHot[fam] = (hx, hy)
            }
        }
    }

    for (fam, v) in families {
        guard let info = v as? [String: Any],
              let frames = info["frames"] as? Int, frames > 0,
              let w = info["w"] as? Int, let h = info["h"] as? Int else { continue }
        // Default hotspot: centered for square 48px cursors, tip-anchored otherwise.
        let hot = famHot[fam] ?? (w >= 48 ? (w / 2, h / 2) : (0, 0))
        hdCursorFamilies[fam] = HDCursorFamily(frameCount: frames, w: w, h: h,
                                               hotX: hot.0, hotY: hot.1)
    }

    hdCursorDir = cursorsDir.path
    hdCursorsAvailable = !hdCursorFamilies.isEmpty
}

/// Map a procedural `CursorDef` (plus super-weapon context) to an HD family name.
private func hdCursorFamilyName(for cursor: CursorDef) -> String? {
    switch cursor.startFrame {
    case cursorNormal.startFrame:     return "ICON_POINTER"
    case cursorCanMove.startFrame:    return "ICON_MOVEMENT_COMMAND"
    case cursorNoMove.startFrame:     return "ICON_MOVEMENT_UNAVAILABLE"
    case cursorCanSelect.startFrame:  return "ICON_SELECT_FRIENDLY"
    case cursorCanAttack.startFrame:  return "ICON_TARGET_ENEMY"
    case cursorDeploy.startFrame:     return "ICON_DEPLOY"
    case cursorAttackMove.startFrame: return "ICON_MOVEMENT_FORCE"
    case cursorEnter.startFrame:      return "ICON_MOUNT_UNIT"
    case cursorAreaGuard.startFrame:  return "ICON_MOVEMENT_ESCORT"
    case cursorRepair.startFrame:     return "ICON_REPAIR"
    case cursorReturn.startFrame:     return "ICON_MOVEMENT_COMMAND"
    case cursorSell.startFrame:       return "ICON_SELL_STRUCTURE"
    case cursorNuke.startFrame:
        // Super-weapon targeting reticle depends on which weapon is armed.
        switch session.superWeaponTargeting {
        case .nuclearStrike: return "ICON_TARGET_NUKE"
        case .ionCannon:     return "ICON_IONCANNON"
        default:             return "ICON_TARGET_SUPER"
        }
    default: return nil
    }
}

private func hdCursorTexture(_ renderer: OpaquePointer?, family: String, frame: Int) -> OpaquePointer? {
    let key = "\(family)-\(frame)"
    if let cached = hdCursorTextureCache[key] { return cached }
    let path = "\(hdCursorDir)/\(family)/\(family)-\(String(format: "%04d", frame)).png"
    guard let tex = loadPNGTexture(renderer, path: path) else { return nil }
    hdCursorTextureCache[key] = tex
    return tex
}

/// Try to draw the HD cursor for `cursor`. Returns true if it drew (so the
/// procedural fallback should be skipped), false if HD art is unavailable.
func drawHDCursor(_ renderer: OpaquePointer?, cursor: CursorDef, mx: Int32, my: Int32) -> Bool {
    ensureHDCursorsLoaded()
    guard hdCursorsAvailable,
          let familyName = hdCursorFamilyName(for: cursor),
          let fam = hdCursorFamilies[familyName], fam.frameCount > 0 else {
        return false
    }

    let frame = fam.frameCount > 1 ? (renderState.cursorAnimFrame % fam.frameCount) : 0
    guard let tex = hdCursorTexture(renderer, family: familyName, frame: frame) else {
        return false
    }

    let dstW = Int32((Double(fam.w) * hdCursorScale).rounded())
    let dstH = Int32((Double(fam.h) * hdCursorScale).rounded())
    let hotX = Int32((Double(fam.hotX) * hdCursorScale).rounded())
    let hotY = Int32((Double(fam.hotY) * hdCursorScale).rounded())
    var dst = SDL_Rect(x: mx - hotX, y: my - hotY, w: dstW, h: dstH)
    SDL_RenderCopy(renderer, tex, nil, &dst)
    return true
}
