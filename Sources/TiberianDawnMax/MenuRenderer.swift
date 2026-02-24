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
            session.menuState = .chooseDifficulty
        },
        Button(label: "Sprite Viewer", x: cx, y: startY + 60, w: bw, h: bh) {
            loadCurrentSprite()
            session.menuState = .spriteViewer
        },
        Button(label: "Sound Test", x: cx, y: startY + 120, w: bw, h: bh) {
            session.soundTest.initialize()
            session.menuState = .soundTest
        },
        Button(label: "Map Viewer", x: cx, y: startY + 180, w: bw, h: bh) {
            loadMapViewerData(session.scenarioList[session.scenarioIndex])
            session.menuState = .mapViewer
        },
        Button(label: "Exit Game", x: cx, y: startY + 240, w: bw, h: bh) {
            session.running = false
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
            session.selectedDifficulty = diff
            session.menuState = .chooseFaction
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
            session.selectedFaction = .gdi
            session.menuState = .launching(.gdi, session.selectedDifficulty)
        },
        Button(label: "NOD", x: startX + bw + gap, y: cy, w: bw, h: bh) {
            session.selectedFaction = .nod
            session.menuState = .launching(.nod, session.selectedDifficulty)
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
        drawText(renderer, "Difficulty: \(session.selectedDifficulty.rawValue)", centerX: renderState.windowWidth / 2, centerY: 160, color: .green, scale: 2)

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

        // Show mission briefing before starting
        session.menuState = .missionBriefing

    case .missionBriefing:
        renderMissionBriefing(renderer)

    case .scoreScreen(let won):
        renderScoreScreen(renderer, won: won)

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
        session.soundTest.render(renderer)

    case .mapViewer:
        // Increment animation frame for terrain (trees etc.)
        renderState.animationFrame += 1

        // Render the map tiles + scenario objects
        renderMapViewer(renderer)

        // HUD overlay
        let cellX = renderState.cameraX / 24
        let cellY = renderState.cameraY / 24
        let scenarioLabel = "\(session.scenarioList[session.scenarioIndex]) (\(session.scenarioIndex + 1)/\(session.scenarioList.count))"
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

// MARK: - Mission Briefing Screen

func renderMissionBriefing(_ renderer: OpaquePointer?) {
    let cx = renderState.windowWidth / 2
    let faction = session.campaignState.currentFaction
    let missionNum = session.campaignState.currentMission
    let scenName = session.campaignState.scenarioName

    // Title
    let factionColor: Color = faction == "GDI" ? .amber : .red
    drawText(renderer, "\(faction) Campaign", centerX: cx, centerY: 50, color: factionColor, scale: 3)
    drawText(renderer, "Mission \(missionNum)", centerX: cx, centerY: 100, color: .green, scale: 3)

    // Briefing text
    let briefing = getBriefingText(scenarioName: scenName)
    if let briefing = briefing, !briefing.isEmpty {
        // Word-wrap briefing text to fit screen
        let maxCharsPerLine = Int((renderState.windowWidth - 100) / 12)  // scale 2 chars are ~12px wide
        let lines = wordWrap(briefing, maxWidth: maxCharsPerLine)
        var y: Int32 = 160
        for line in lines {
            drawText(renderer, line, centerX: cx, centerY: y, color: .green, scale: 2)
            y += 22
            if y > renderState.windowHeight - 100 { break }
        }
    } else {
        drawText(renderer, "No briefing available", centerX: cx, centerY: 200, color: .gray, scale: 2)
    }

    // Difficulty
    let diffLabel = session.campaignState.difficulty == 0 ? "Easy" :
                    session.campaignState.difficulty == 1 ? "Normal" : "Hard"
    drawText(renderer, "Difficulty: \(diffLabel)", centerX: cx, centerY: renderState.windowHeight - 80, color: .gray, scale: 1)

    // Prompt
    drawText(renderer, "Press Enter to Begin", centerX: cx, centerY: renderState.windowHeight - 50, color: .amber, scale: 2)
    drawText(renderer, "Esc: Cancel", centerX: cx, centerY: renderState.windowHeight - 25, color: .gray, scale: 1)
}

// MARK: - Score Screen

func renderScoreScreen(_ renderer: OpaquePointer?, won: Bool) {
    let cx = renderState.windowWidth / 2
    let scoreData = generateScoreScreen(won: won)

    // Title
    if won {
        drawText(renderer, "MISSION ACCOMPLISHED", centerX: cx, centerY: 50, color: .green, scale: 3)
    } else {
        drawText(renderer, "MISSION FAILED", centerX: cx, centerY: 50, color: .red, scale: 3)
    }

    // Scenario name
    drawText(renderer, scoreData.scenarioName, centerX: cx, centerY: 95, color: .amber, scale: 2)

    // Score and time
    drawText(renderer, "Score: \(scoreData.score)", centerX: cx, centerY: 140, color: .green, scale: 3)

    // Star rating
    let stars = String(repeating: "*", count: scoreData.stars)
    let emptyStars = String(repeating: "-", count: 3 - scoreData.stars)
    drawText(renderer, "Rating: \(stars)\(emptyStars)", centerX: cx, centerY: 180, color: .amber, scale: 2)

    // Time
    drawText(renderer, "Time: \(scoreData.elapsedTime)", centerX: cx, centerY: 215, color: .green, scale: 2)

    // Stats table
    let statY: Int32 = 260
    let leftX = cx - 160
    let rightX = cx + 60

    drawText(renderer, "-- STATISTICS --", centerX: cx, centerY: statY, color: .amber, scale: 2)

    drawTextLeft(renderer, "GDI Units Destroyed:", x: leftX, y: statY + 35, color: .green, scale: 1)
    drawTextLeft(renderer, "\(scoreData.gdiKills)", x: rightX + 100, y: statY + 35, color: .green, scale: 1)

    drawTextLeft(renderer, "NOD Units Destroyed:", x: leftX, y: statY + 55, color: .green, scale: 1)
    drawTextLeft(renderer, "\(scoreData.nodKills)", x: rightX + 100, y: statY + 55, color: .green, scale: 1)

    drawTextLeft(renderer, "Civilians Killed:", x: leftX, y: statY + 75, color: .green, scale: 1)
    drawTextLeft(renderer, "\(scoreData.civKills)", x: rightX + 100, y: statY + 75, color: .green, scale: 1)

    drawTextLeft(renderer, "Buildings Destroyed:", x: leftX, y: statY + 95, color: .green, scale: 1)
    drawTextLeft(renderer, "\(scoreData.gdiBuildings + scoreData.nodBuildings)", x: rightX + 100, y: statY + 95, color: .green, scale: 1)

    drawTextLeft(renderer, "Credits Harvested:", x: leftX, y: statY + 115, color: .green, scale: 1)
    drawTextLeft(renderer, "\(scoreData.creditsHarvested)", x: rightX + 100, y: statY + 115, color: .green, scale: 1)

    // Controls
    if won && session.campaignState.isActive && !session.campaignState.isComplete {
        drawText(renderer, "N: Next Mission  R: Restart  Esc: Menu", centerX: cx, centerY: renderState.windowHeight - 40, color: .amber, scale: 2)
    } else if won && session.campaignState.isComplete {
        drawText(renderer, "Campaign Complete!", centerX: cx, centerY: renderState.windowHeight - 70, color: .green, scale: 2)
        drawText(renderer, "Esc: Main Menu", centerX: cx, centerY: renderState.windowHeight - 40, color: .amber, scale: 2)
    } else {
        drawText(renderer, "R: Restart  Esc: Menu", centerX: cx, centerY: renderState.windowHeight - 40, color: .amber, scale: 2)
    }
}

// MARK: - Word Wrap Helper

func wordWrap(_ text: String, maxWidth: Int) -> [String] {
    let words = text.components(separatedBy: " ")
    var lines: [String] = []
    var currentLine = ""

    for word in words {
        if currentLine.isEmpty {
            currentLine = word
        } else if currentLine.count + 1 + word.count <= maxWidth {
            currentLine += " " + word
        } else {
            lines.append(currentLine)
            currentLine = word
        }
    }
    if !currentLine.isEmpty {
        lines.append(currentLine)
    }
    return lines
}
