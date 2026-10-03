import CSDL2
import Foundation
import OpenConquerAssets

// MARK: - Remastered HD sidebar meters
//
// The modern sidebar's power gauge and fill bars drawn from the Remastered
// Collection's UI art (`tools/extract_remastered_sprites.py --category ui` →
// sprites_remastered/ui/sidebar/): the power segments (UI_SIDEBAR_POWERSEGMENT
// _EMPTY / _FILLED, the filled one greyscale so it takes the status colour),
// the build-progress bar (UI_TRAINQUEUEBAR_FILLED) and the greyscale health
// bar. Same lazy-load-and-cache structure as GameCursorHD.swift: each `draw…`
// returns false when the art isn't installed and the caller draws its
// procedural bar instead. Render-only; the classic (UPDATEC.MIX) sidebar
// keeps its own HPWRBAR/HCLOCK art.

private var sidebarHDChecked = false
private var sidebarHDDir = ""
private var sidebarHDNames: Set<String> = []
private var sidebarHDTextures: [String: (texture: OpaquePointer, w: Int32, h: Int32)] = [:]

private func ensureSidebarHDLoaded() {
    guard !sidebarHDChecked else { return }
    sidebarHDChecked = true
    let dir = assetManager.extractedPath
        .appendingPathComponent("sprites_remastered")
        .appendingPathComponent("ui")
        .appendingPathComponent("sidebar")
    guard let data = try? Data(contentsOf: dir.appendingPathComponent("sidebar.json")),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    sidebarHDDir = dir.path
    sidebarHDNames = Set(root.keys)
}

private func sidebarHDTexture(_ renderer: OpaquePointer?, _ name: String) -> (texture: OpaquePointer, w: Int32, h: Int32)? {
    ensureSidebarHDLoaded()
    if let t = sidebarHDTextures[name] { return t }
    guard sidebarHDNames.contains(name),
          let tex = loadPNGTexture(renderer, path: "\(sidebarHDDir)/\(name).png") else { return nil }
    var w: Int32 = 0, h: Int32 = 0
    SDL_QueryTexture(tex, nil, nil, &w, &h)
    SDL_SetTextureBlendMode(tex, SDL_BLENDMODE_BLEND)
    sidebarHDTextures[name] = (tex, w, h)
    return sidebarHDTextures[name]
}

/// The HD power gauge: a row of segments, those up to `outputFraction` lit
/// in `color` (green / yellow / red, the original's Drain-vs-Power test),
/// the rest empty, with a white tick at `drainFraction`. Returns false when
/// the segment art isn't installed.
func drawHDPowerBar(_ renderer: OpaquePointer?, x: Int32, y: Int32, w: Int32, h: Int32,
                    outputFraction: Double, drainFraction: Double,
                    color: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
    guard let empty = sidebarHDTexture(renderer, "UI_SIDEBAR_POWERSEGMENT_EMPTY"),
          let filled = sidebarHDTexture(renderer, "UI_SIDEBAR_POWERSEGMENT_FILLED") else { return false }
    let segW = max(3, Int32((Double(empty.w) * Double(h) / Double(empty.h)).rounded()))
    let count = max(1, w / segW)
    let left = x + (w - count * segW) / 2
    let lit = Int32((outputFraction * Double(count)).rounded())
    SDL_SetTextureColorMod(filled.texture, color.r, color.g, color.b)
    for i in 0..<count {
        var dst = SDL_Rect(x: left + i * segW, y: y, w: segW, h: h)
        SDL_RenderCopy(renderer, (i < lit ? filled : empty).texture, nil, &dst)
    }
    SDL_SetTextureColorMod(filled.texture, 255, 255, 255)

    // Drain marker, like the original's HPOWER threshold arrow.
    let markX = left + Int32(min(1, max(0, drainFraction)) * Double(count * segW))
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
    var mark = SDL_Rect(x: min(markX, left + count * segW - 2), y: y - 2, w: 2, h: h + 4)
    SDL_RenderFillRect(renderer, &mark)
    return true
}

/// A horizontal fill bar from one HD bar texture, cut at `fraction` (the art
/// is clipped, not squashed). `tint` colours greyscale art. Returns false when
/// the texture isn't installed.
func drawHDFillBar(_ renderer: OpaquePointer?, _ name: String, x: Int32, y: Int32, w: Int32, h: Int32,
                   fraction: Double, tint: (r: UInt8, g: UInt8, b: UInt8)? = nil) -> Bool {
    guard let tex = sidebarHDTexture(renderer, name) else { return false }
    let f = min(1, max(0, fraction))
    guard f > 0 else { return true }
    var src = SDL_Rect(x: 0, y: 0, w: max(1, Int32(Double(tex.w) * f)), h: tex.h)
    var dst = SDL_Rect(x: x, y: y, w: max(1, Int32(Double(w) * f)), h: h)
    if let tint { SDL_SetTextureColorMod(tex.texture, tint.r, tint.g, tint.b) }
    SDL_RenderCopy(renderer, tex.texture, &src, &dst)
    if tint != nil { SDL_SetTextureColorMod(tex.texture, 255, 255, 255) }
    return true
}

/// Build progress (unit / structure queue, superweapon charge).
func drawHDProgressBar(_ renderer: OpaquePointer?, x: Int32, y: Int32, w: Int32, h: Int32, fraction: Double) -> Bool {
    drawHDFillBar(renderer, "UI_TRAINQUEUEBAR_FILLED", x: x, y: y, w: w, h: h, fraction: fraction)
}
