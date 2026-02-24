import CSDL2
import Foundation

// MARK: - Button

struct Button {
    let label: String
    let x: Int32
    let y: Int32
    let w: Int32
    let h: Int32
    let action: () -> Void

    func contains(_ px: Int32, _ py: Int32) -> Bool {
        px >= x && px < x + w && py >= y && py < y + h
    }

    func draw(_ renderer: OpaquePointer?, highlighted: Bool) {
        let borderColor = highlighted ? Color.brightGreen : Color.green
        let fillColor = highlighted ? Color.darkGreen : Color.black

        // Fill
        var rect = SDL_Rect(x: x, y: y, w: w, h: h)
        SDL_SetRenderDrawColor(renderer, fillColor.r, fillColor.g, fillColor.b, fillColor.a)
        SDL_RenderFillRect(renderer, &rect)

        // Border
        SDL_SetRenderDrawColor(renderer, borderColor.r, borderColor.g, borderColor.b, borderColor.a)
        SDL_RenderDrawRect(renderer, &rect)

        // Inner border for depth
        var inner = SDL_Rect(x: x + 1, y: y + 1, w: w - 2, h: h - 2)
        SDL_RenderDrawRect(renderer, &inner)

        // Draw label centered (simple character rendering)
        drawText(renderer, label, centerX: x + w / 2, centerY: y + h / 2, color: borderColor)
    }
}

// MARK: - Button Factory Functions

func makeMainButtons() -> [Button] {
    let bw: Int32 = 300
    let bh: Int32 = 44
    let cx = renderState.windowWidth / 2 - bw / 2
    let startY: Int32 = 200

    return [
        Button(label: "Start New Game", x: cx, y: startY, w: bw, h: bh) {
            menuState = .chooseDifficulty
        },
        Button(label: "Sprite Viewer", x: cx, y: startY + 60, w: bw, h: bh) {
            loadCurrentSprite()
            menuState = .spriteViewer
        },
        Button(label: "Sound Test", x: cx, y: startY + 120, w: bw, h: bh) {
            initSoundTest()
            menuState = .soundTest
        },
        Button(label: "Map Viewer", x: cx, y: startY + 180, w: bw, h: bh) {
            loadMapViewerData(scenarioList[scenarioIndex])
            menuState = .mapViewer
        },
        Button(label: "Exit Game", x: cx, y: startY + 240, w: bw, h: bh) {
            running = false
        },
    ]
}

func makeDifficultyButtons() -> [Button] {
    let bw: Int32 = 200
    let bh: Int32 = 44
    let cx = renderState.windowWidth / 2 - bw / 2
    let startY: Int32 = 200

    return Difficulty.allCases.enumerated().map { i, diff in
        Button(label: diff.rawValue, x: cx, y: startY + Int32(i) * 60, w: bw, h: bh) {
            selectedDifficulty = diff
            menuState = .chooseFaction
        }
    }
}

func makeFactionButtons() -> [Button] {
    let bw: Int32 = 200
    let bh: Int32 = 80
    let gap: Int32 = 60
    let totalW = bw * 2 + gap
    let startX = renderState.windowWidth / 2 - totalW / 2
    let cy: Int32 = 250

    return [
        Button(label: "GDI", x: startX, y: cy, w: bw, h: bh) {
            selectedFaction = .gdi
            menuState = .launching(.gdi, selectedDifficulty)
        },
        Button(label: "NOD", x: startX + bw + gap, y: cy, w: bw, h: bh) {
            selectedFaction = .nod
            menuState = .launching(.nod, selectedDifficulty)
        },
    ]
}

// MARK: - Menu State Rendering

func renderMenuState(_ renderer: OpaquePointer?, state: MenuState) {
    switch state {
    case .main:
        drawText(renderer, "Command & Conquer", centerX: renderState.windowWidth / 2, centerY: 80, color: .amber, scale: 4)
        drawText(renderer, "Tiberian Dawn Max", centerX: renderState.windowWidth / 2, centerY: 140, color: .green, scale: 3)

        for btn in makeMainButtons() {
            btn.draw(renderer, highlighted: btn.contains(input.mouseX, input.mouseY))
        }

        drawText(renderer, "R964", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 40, color: .gray, scale: 1)

    case .chooseDifficulty:
        drawText(renderer, "Select Difficulty", centerX: renderState.windowWidth / 2, centerY: 120, color: .amber, scale: 3)

        for btn in makeDifficultyButtons() {
            btn.draw(renderer, highlighted: btn.contains(input.mouseX, input.mouseY))
        }

        drawText(renderer, "Esc: Back", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 40, color: .gray, scale: 1)

    case .chooseFaction:
        drawText(renderer, "Choose Your Side", centerX: renderState.windowWidth / 2, centerY: 100, color: .amber, scale: 3)
        drawText(renderer, "Difficulty: \(selectedDifficulty.rawValue)", centerX: renderState.windowWidth / 2, centerY: 160, color: .green, scale: 2)

        for btn in makeFactionButtons() {
            let isGDI = btn.label == "GDI"
            let highlighted = btn.contains(input.mouseX, input.mouseY)
            btn.draw(renderer, highlighted: highlighted)
            // Subtitle
            let subtitle = isGDI ? "Global Defense Initiative" : "Brotherhood of Nod"
            drawText(renderer, subtitle, centerX: btn.x + btn.w / 2, centerY: btn.y + btn.h + 20, color: isGDI ? .amber : .red, scale: 1)
        }

        drawText(renderer, "Esc: Back", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 40, color: .gray, scale: 1)

    case .launching(let faction, let difficulty):
        drawText(renderer, "Loading...", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight / 2, color: .green, scale: 3)
        SDL_RenderPresent(renderer)

        // Initialize campaign
        session.campaignState.currentFaction = (faction == .gdi) ? "GDI" : "NOD"
        session.campaignState.difficulty = (difficulty == .easy) ? 0 : (difficulty == .normal ? 1 : 2)
        session.campaignState.currentMission = 1
        session.campaignState.currentVariant = "EA"
        session.campaignState.isActive = true
        session.campaignState.carryOverCredits = 0
        session.campaignState.completedMissions.removeAll()

        // Load first scenario using existing startNextMission()
        if startNextMission() {
            // Initialize game camera — center on player start waypoint 98, or map bounds
            if let scenario = scenarioData,
               let startWP = scenario.waypoints.first(where: { $0.id == 98 }) {
                let pos = cellToPixel(startWP.cell)
                let vpW = Double(renderState.windowWidth - sidebarWidth)
                let vpH = Double(renderState.windowHeight)
                renderState.gameCameraX = Double(pos.px) - vpW / 2.0
                renderState.gameCameraY = Double(pos.py) - vpH / 2.0
            } else if let bounds = session.world?.mapBounds {
                renderState.gameCameraX = Double(bounds.x * 24)
                renderState.gameCameraY = Double(bounds.y * 24)
            }
            renderState.gameZoomLevel = 1.0
            session.lastTickTime = 0
            session.tickAccumulator = 0
            session.missionScore.reset()
            session.triggerWinState = .playing
            menuState = .playing
        } else {
            // Fallback if scenario not found
            print("Failed to load first mission for \(faction.rawValue)")
            menuState = .main
        }

    case .spriteViewer:
        let shapeName = viewableShapes[renderState.spriteViewerIndex]

        // Title and info
        drawText(renderer, "Sprite Viewer", centerX: renderState.windowWidth / 2, centerY: 30, color: .amber, scale: 3)
        drawText(renderer, shapeName, centerX: renderState.windowWidth / 2, centerY: 70, color: .green, scale: 2)

        if let shp = renderState.currentSHP, !shp.frames.isEmpty {
            // Auto-animate
            let now = SDL_GetTicks()
            if renderState.spriteViewerAnimating && now - renderState.spriteViewerFrameTimer > 100 {
                renderState.spriteViewerFrameTimer = now
                renderState.spriteViewerFrame = (renderState.spriteViewerFrame + 1) % shp.frames.count
            }

            let frame = shp.frames[renderState.spriteViewerFrame]
            let info = "Frame \(renderState.spriteViewerFrame)/\(shp.frames.count)  \(frame.width)x\(frame.height)"
            drawText(renderer, info, centerX: renderState.windowWidth / 2, centerY: 100, color: .green, scale: 1)

            // Calculate scale to fit sprite nicely
            let maxDisplayW: Int32 = 400
            let maxDisplayH: Int32 = 350
            let scaleX = frame.width > 0 ? maxDisplayW / Int32(frame.width) : 1
            let scaleY = frame.height > 0 ? maxDisplayH / Int32(frame.height) : 1
            let pixelScale = max(1, min(scaleX, scaleY))

            let drawW = Int32(frame.width) * pixelScale
            let drawH = Int32(frame.height) * pixelScale
            let drawX = renderState.windowWidth / 2 - drawW / 2
            let drawY: Int32 = 130 + (maxDisplayH - drawH) / 2

            // Draw a subtle border around the sprite area
            SDL_SetRenderDrawColor(renderer, 40, 40, 40, 255)
            var border = SDL_Rect(x: drawX - 2, y: drawY - 2, w: drawW + 4, h: drawH + 4)
            SDL_RenderDrawRect(renderer, &border)

            // Render the sprite
            renderSHPFrame(renderer, frame: frame, atX: drawX, atY: drawY, scale: pixelScale)
        } else {
            drawText(renderer, "Not Found", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight / 2, color: .red, scale: 2)
        }

        // Controls
        let animLabel = renderState.spriteViewerAnimating ? "Playing" : "Paused"
        drawText(renderer, "Left/Right: Shape  Up/Down: Frame  Space: \(animLabel)", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 60, color: .gray, scale: 1)
        drawText(renderer, "Esc: Back", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 35, color: .gray, scale: 1)

    case .soundTest:
        renderSoundTest(renderer)

    case .mapViewer:
        // Increment animation frame for terrain (trees etc.)
        renderState.animationFrame += 1

        // Render the map tiles + scenario objects
        renderMapViewer(renderer)

        // HUD overlay
        let cellX = renderState.cameraX / 24
        let cellY = renderState.cameraY / 24
        let scenarioLabel = "\(scenarioList[scenarioIndex]) (\(scenarioIndex + 1)/\(scenarioList.count))"
        drawText(renderer, "Map Viewer - \(scenarioLabel)", centerX: renderState.windowWidth / 2, centerY: 15, color: .amber, scale: 2)
        let zoomPct = String(format: "%.0f%%", renderState.zoomLevel * 100)
        drawText(renderer, "Camera: \(cellX) \(cellY)  Zoom: \(zoomPct)", centerX: renderState.windowWidth / 2, centerY: 35, color: .green, scale: 1)
        if let sd = scenarioData {
            let counts = "T:\(sd.terrain.count) O:\(sd.overlays.count) S:\(sd.structures.count) U:\(sd.units.count) I:\(sd.infantry.count)"
            drawText(renderer, counts, centerX: renderState.windowWidth / 2, centerY: 52, color: .green, scale: 1)
        }
        drawText(renderer, "Arrows/Drag: Pan  +/-: Zoom  [/]: Scenario  G: Grid  I: Info  T: Triggers  B: Base  P: Play  0-9: WP", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 15, color: .gray, scale: 1)

    case .playing:
        renderGame(renderer)
    }
}
