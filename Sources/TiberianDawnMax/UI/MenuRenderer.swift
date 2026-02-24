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
            session.currentScreen = DifficultyScreen()
        },
        Button(label: "Sprite Viewer", x: cx, y: startY + 60, w: bw, h: bh) {
            loadCurrentSprite()
            session.currentScreen = SpriteViewerScreen()
        },
        Button(label: "Sound Test", x: cx, y: startY + 120, w: bw, h: bh) {
            session.soundTest.initialize()
            session.currentScreen = SoundTestScreen()
        },
        Button(label: "Map Viewer", x: cx, y: startY + 180, w: bw, h: bh) {
            loadMapViewerData(session.scenarioList[session.scenarioIndex])
            session.currentScreen = MapViewerScreen()
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
            session.currentScreen = FactionScreen()
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
            session.currentScreen = LaunchingScreen(faction: .gdi, difficulty: session.selectedDifficulty)
        },
        Button(label: "NOD", x: startX + bw + gap, y: cy, w: bw, h: bh) {
            session.selectedFaction = .nod
            session.currentScreen = LaunchingScreen(faction: .nod, difficulty: session.selectedDifficulty)
        },
    ]
}

// MARK: - Menu State Rendering

func renderMenuState(_ renderer: OpaquePointer?) {
    session.currentScreen.render(renderer)
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
    let briefing = session.campaign.briefingText(scenarioName: scenName)
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
    let scoreData = session.campaign.scoreScreen(won: won)

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
