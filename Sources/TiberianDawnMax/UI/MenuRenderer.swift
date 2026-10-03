import CSDL2
import Foundation
import OpenConquerCore

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
            app.currentScreen = DifficultyScreen()
        },
        Button(label: "Load Mission", x: cx, y: startY + 60, w: bw, h: bh) {
            app.currentScreen = LoadMissionFactionScreen()
        },
        Button(label: "Sprite Playground", x: cx, y: startY + 120, w: bw, h: bh) {
            app.spritePlayground.initialize()
            app.currentScreen = SpritePlaygroundScreen()
        },
        Button(label: "Sound Test", x: cx, y: startY + 180, w: bw, h: bh) {
            app.soundTest.initialize()
            app.currentScreen = SoundTestScreen()
        },
        Button(label: "Map Viewer", x: cx, y: startY + 240, w: bw, h: bh) {
            loadMapViewerData(app.scenarioList[app.scenarioIndex])
            app.currentScreen = MapViewerScreen()
        },
        Button(label: "Options", x: cx, y: startY + 300, w: bw, h: bh) {
            app.currentScreen = OptionsScreen()
        },
        Button(label: "Exit Game", x: cx, y: startY + 360, w: bw, h: bh) {
            app.running = false
        },
    ]
}

/// Ruleset presets (Classic 1995 vs Enhanced). Chosen on the Options screen —
/// i.e. before a mission starts — so `session.rules` never changes mid-run
/// (per-ruleset determinism baselines; default stays .classic1995).
func makeRulesetButtons() -> [Button] {
    let bw: Int32 = 300
    let bh: Int32 = 44
    let cx = renderState.windowWidth / 2 - bw / 2
    let startY: Int32 = 220

    return Ruleset.presets.enumerated().map { i, preset in
        Button(label: preset.name, x: cx, y: startY + Int32(i) * 60, w: bw, h: bh) {
            session.rules = preset
        }
    }
}

/// Y of the ruleset description line — the Controls section stacks below it.
func rulesetDescriptionY() -> Int32 {
    220 + Int32(Ruleset.presets.count) * 60 + 10
}

/// Side-by-side Classic / Modern control-scheme toggle on the Options screen.
func makeControlSchemeButtons() -> [Button] {
    let bw: Int32 = 200
    let bh: Int32 = 44
    let gap: Int32 = 20
    let schemes = ControlScheme.allCases
    let totalW = bw * Int32(schemes.count) + gap * Int32(schemes.count - 1)
    let startX = renderState.windowWidth / 2 - totalW / 2
    let y = rulesetDescriptionY() + 90

    return schemes.enumerated().map { i, scheme in
        Button(label: scheme.rawValue, x: startX + Int32(i) * (bw + gap), y: y, w: bw, h: bh) {
            UserSettings.controlScheme = scheme
        }
    }
}

/// Side-by-side Classic / Modern sidebar toggle, below the controls row.
func makeSidebarStyleButtons() -> [Button] {
    let bw: Int32 = 200
    let bh: Int32 = 44
    let gap: Int32 = 20
    let styles = SidebarStyle.allCases
    let totalW = bw * Int32(styles.count) + gap * Int32(styles.count - 1)
    let startX = renderState.windowWidth / 2 - totalW / 2
    let y = rulesetDescriptionY() + 240

    return styles.enumerated().map { i, style in
        Button(label: style.rawValue, x: startX + Int32(i) * (bw + gap), y: y, w: bw, h: bh) {
            UserSettings.sidebarStyle = style
        }
    }
}

/// 2x / 3x classic sidebar width, below the sidebar style row.
func makeSidebarSizeButtons() -> [Button] {
    let bw: Int32 = 90
    let bh: Int32 = 36
    let gap: Int32 = 20
    let sizes = SidebarSize.allCases
    let totalW = bw * Int32(sizes.count) + gap * Int32(sizes.count - 1)
    let startX = renderState.windowWidth / 2 - totalW / 2
    let y = rulesetDescriptionY() + 340

    return sizes.enumerated().map { i, size in
        Button(label: size.rawValue, x: startX + Int32(i) * (bw + gap), y: y, w: bw, h: bh) {
            UserSettings.sidebarSize = size
        }
    }
}

/// Off / Pixels / Smooth / Enhanced movie playback, below the sidebar rows.
func makeMovieModeButtons() -> [Button] {
    let bw: Int32 = 150
    let bh: Int32 = 40
    let gap: Int32 = 16
    let modes = MovieMode.allCases
    let totalW = bw * Int32(modes.count) + gap * Int32(modes.count - 1)
    let startX = renderState.windowWidth / 2 - totalW / 2
    let y = rulesetDescriptionY() + 440

    return modes.enumerated().map { i, mode in
        Button(label: mode.rawValue, x: startX + Int32(i) * (bw + gap), y: y, w: bw, h: bh) {
            UserSettings.movieMode = mode
        }
    }
}

func makeDifficultyButtons() -> [Button] {
    let bw: Int32 = 200
    let bh: Int32 = 44
    let cx = renderState.windowWidth / 2 - bw / 2
    let startY: Int32 = 200

    return Difficulty.allCases.enumerated().map { i, diff in
        Button(label: diff.rawValue, x: cx, y: startY + Int32(i) * 60, w: bw, h: bh) {
            app.selectedDifficulty = diff
            app.currentScreen = FactionScreen()
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
            app.selectedFaction = .gdi
            app.currentScreen = LaunchingScreen(faction: .gdi, difficulty: app.selectedDifficulty)
        },
        Button(label: "NOD", x: startX + bw + gap, y: cy, w: bw, h: bh) {
            app.selectedFaction = .nod
            app.currentScreen = LaunchingScreen(faction: .nod, difficulty: app.selectedDifficulty)
        },
    ]
}

func makeLoadMissionFactionButtons() -> [Button] {
    let bw: Int32 = 200
    let bh: Int32 = 80
    let gap: Int32 = 60
    let totalW = bw * 2 + gap
    let startX = renderState.windowWidth / 2 - totalW / 2
    let cy: Int32 = 220

    return [
        Button(label: "GDI", x: startX, y: cy, w: bw, h: bh) {
            app.currentScreen = LoadMissionListScreen(faction: "GDI")
        },
        Button(label: "NOD", x: startX + bw + gap, y: cy, w: bw, h: bh) {
            app.currentScreen = LoadMissionListScreen(faction: "NOD")
        },
    ]
}

// MARK: - Menu State Rendering

func renderMenuState(_ renderer: OpaquePointer?) {
    app.currentScreen.render(renderer)
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
    let nameTable: [Int: String] = faction == "GDI" ? gdiMissionNames : nodMissionNames
    let missionTitle = nameTable[missionNum] ?? "Mission \(missionNum)"
    drawText(renderer, "Mission \(missionNum): \(missionTitle)", centerX: cx, centerY: 100, color: .green, scale: 2)

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
