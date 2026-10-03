import CSDL2
import OpenConquerAssets

// MARK: - Selection Rendering
// UI sprite cache (SELECT/PIPS/MOUSE.SHP) plus selection brackets, health and cargo pips.

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
