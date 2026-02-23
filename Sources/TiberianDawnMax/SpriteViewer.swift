import CSDL2
import Foundation

// MARK: - Sprite Viewer

let viewableShapes = [
    "MOUSE.SHP", "OPTIONS.SHP",
    "HTNK.SHP", "MTNK.SHP", "LTNK.SHP", "MLRS.SHP",  // tanks
    "E1.SHP", "E2.SHP", "E3.SHP", "E4.SHP",            // infantry
    "HARV.SHP", "MCV.SHP", "APC.SHP", "MSAM.SHP",      // vehicles
    "ORCA.SHP", "A10.SHP", "HELI.SHP", "TRAN.SHP",     // aircraft
    "WEAP.SHP", "FACT.SHP", "PROC.SHP", "NUKE.SHP",    // buildings
    "GUN.SHP", "GTWR.SHP", "ATWR.SHP", "SAM.SHP",      // defenses
    "ICON.SHP",
]

var spriteViewerIndex = 0
var spriteViewerFrame = 0
var currentSHP: SHPFile? = nil
var spriteViewerAnimating = true
var spriteViewerFrameTimer: UInt32 = 0

func loadCurrentSprite() {
    let name = viewableShapes[spriteViewerIndex]
    spriteViewerFrame = 0
    if let data = mixManager.retrieve(name) {
        do {
            currentSHP = try SHPFile(data: Data(data))
        } catch {
            print("Failed to parse \(name): \(error)")
            currentSHP = nil
        }
    } else {
        currentSHP = nil
    }
}

func renderSHPFrame(_ renderer: OpaquePointer?, frame: SHPFrame, atX: Int32, atY: Int32, scale: Int32) {
    for row in 0..<frame.height {
        for col in 0..<frame.width {
            let pixel = frame.pixels[row * frame.width + col]
            if pixel == 0 { continue }  // transparent
            let color = gamePalette[Int(pixel)]
            SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, 255)
            var rect = SDL_Rect(x: atX + Int32(col) * scale, y: atY + Int32(row) * scale, w: scale, h: scale)
            SDL_RenderFillRect(renderer, &rect)
        }
    }
}
