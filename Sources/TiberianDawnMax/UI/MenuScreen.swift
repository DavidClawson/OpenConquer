import CSDL2
import Foundation

// MARK: - MenuScreen Protocol

protocol MenuScreen: AnyObject {
    func render(_ renderer: OpaquePointer?)
    func handleKeyDown(_ key: Int32)
    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8)
    func handleMouseUp(_ x: Int32, _ y: Int32, button: UInt8)
    func handleMouseMotion(_ x: Int32, _ y: Int32, xrel: Int32, yrel: Int32)
    func handleMouseWheel(_ dy: Int32, atX: Int32, atY: Int32)
    func handleContinuousInput()
}

// Default no-op implementations
extension MenuScreen {
    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {}
    func handleMouseUp(_ x: Int32, _ y: Int32, button: UInt8) {}
    func handleMouseMotion(_ x: Int32, _ y: Int32, xrel: Int32, yrel: Int32) {}
    func handleMouseWheel(_ dy: Int32, atX: Int32, atY: Int32) {}
    func handleContinuousInput() {}
}

// MARK: - Main Menu Screen

class MainMenuScreen: MenuScreen {
    private var musicStarted = false

    func render(_ renderer: OpaquePointer?) {
        // Start menu music on first render
        if !musicStarted {
            musicStarted = true
            if !audioManager.isMusicPlaying {
                audioManager.playMenuMusic(.aoi)
            }
        }

        drawText(renderer, "Command & Conquer", centerX: renderState.windowWidth / 2, centerY: 80, color: .amber, scale: 4)
        drawText(renderer, "Tiberian Dawn Max", centerX: renderState.windowWidth / 2, centerY: 140, color: .green, scale: 3)

        for btn in makeMainButtons() {
            btn.draw(renderer, highlighted: btn.contains(input.mouseX, input.mouseY))
        }

        // Music status
        let musicStatus = audioManager.musicEnabled ? "M: Music ON" : "M: Music OFF"
        drawText(renderer, musicStatus, centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 60, color: .gray, scale: 1)
        drawText(renderer, "R964", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 40, color: .gray, scale: 1)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.running = false
        } else if key == Int32(SDLK_m.rawValue) {
            audioManager.toggleMusic()
            if audioManager.musicEnabled && !audioManager.isMusicPlaying {
                audioManager.playMenuMusic(.aoi)
            }
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        for btn in makeMainButtons() {
            if btn.contains(input.mouseX, input.mouseY) {
                btn.action()
                break
            }
        }
    }
}

// MARK: - Difficulty Screen

class DifficultyScreen: MenuScreen {
    func render(_ renderer: OpaquePointer?) {
        drawText(renderer, "Select Difficulty", centerX: renderState.windowWidth / 2, centerY: 120, color: .amber, scale: 3)

        for btn in makeDifficultyButtons() {
            btn.draw(renderer, highlighted: btn.contains(input.mouseX, input.mouseY))
        }

        drawText(renderer, "Esc: Back", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 40, color: .gray, scale: 1)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = MainMenuScreen()
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        for btn in makeDifficultyButtons() {
            if btn.contains(input.mouseX, input.mouseY) {
                btn.action()
                break
            }
        }
    }
}

// MARK: - Options Screen

/// Ruleset selection (Classic 1995 vs Enhanced). Reached from the main menu so
/// the choice is made BEFORE a mission starts — `session.rules` never changes
/// mid-run (per-ruleset determinism baselines; default stays .classic1995).
class OptionsScreen: MenuScreen {
    func render(_ renderer: OpaquePointer?) {
        drawText(renderer, "Options", centerX: renderState.windowWidth / 2, centerY: 100, color: .amber, scale: 3)
        drawText(renderer, "Ruleset", centerX: renderState.windowWidth / 2, centerY: 160, color: .green, scale: 2)

        for btn in makeRulesetButtons() {
            let selected = btn.label == session.rules.name
            btn.draw(renderer, highlighted: selected || btn.contains(input.mouseX, input.mouseY))
        }

        // Describe the currently-selected preset.
        let descY: Int32 = 220 + Int32(Ruleset.presets.count) * 60 + 10
        drawText(renderer, session.rules.summary, centerX: renderState.windowWidth / 2, centerY: descY, color: .gray, scale: 1)

        drawText(renderer, "Esc: Back", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 40, color: .gray, scale: 1)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = MainMenuScreen()
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        for btn in makeRulesetButtons() {
            if btn.contains(input.mouseX, input.mouseY) {
                btn.action()
                break
            }
        }
    }
}

// MARK: - Faction Screen

class FactionScreen: MenuScreen {
    func render(_ renderer: OpaquePointer?) {
        drawText(renderer, "Choose Your Side", centerX: renderState.windowWidth / 2, centerY: 100, color: .amber, scale: 3)
        drawText(renderer, "Difficulty: \(session.selectedDifficulty.rawValue)", centerX: renderState.windowWidth / 2, centerY: 160, color: .green, scale: 2)

        for btn in makeFactionButtons() {
            let isGDI = btn.label == "GDI"
            let highlighted = btn.contains(input.mouseX, input.mouseY)
            btn.draw(renderer, highlighted: highlighted)
            let subtitle = isGDI ? "Global Defense Initiative" : "Brotherhood of Nod"
            drawText(renderer, subtitle, centerX: btn.x + btn.w / 2, centerY: btn.y + btn.h + 20, color: isGDI ? .amber : .red, scale: 1)
        }

        drawText(renderer, "Esc: Back", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 40, color: .gray, scale: 1)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = DifficultyScreen()
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        for btn in makeFactionButtons() {
            if btn.contains(input.mouseX, input.mouseY) {
                btn.action()
                break
            }
        }
    }
}

// MARK: - Launching Screen

class LaunchingScreen: MenuScreen {
    let faction: Faction
    let difficulty: Difficulty

    init(faction: Faction, difficulty: Difficulty) {
        self.faction = faction
        self.difficulty = difficulty
    }

    func render(_ renderer: OpaquePointer?) {
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
        session.currentScreen = BriefingScreen()
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = FactionScreen()
        }
    }
}

// MARK: - Briefing Screen

class BriefingScreen: MenuScreen {
    func render(_ renderer: OpaquePointer?) {
        renderMissionBriefing(renderer)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = MainMenuScreen()
            return
        }
        if key == Int32(SDLK_RETURN.rawValue) || key == Int32(SDLK_SPACE.rawValue) {
            // Launch the mission
            if session.campaign.startNextMission() {
                applyAutoFitCameraAndZoom()
                session.lastTickTime = 0
                session.tickAccumulator = 0
                session.missionScore.reset()
                session.triggerWinState = .playing
                session.currentScreen = PlayingScreen()
            } else {
                session.currentScreen = MainMenuScreen()
            }
        }
    }
}

// MARK: - Load Mission: Faction Selection

class LoadMissionFactionScreen: MenuScreen {
    func render(_ renderer: OpaquePointer?) {
        drawText(renderer, "Load Mission", centerX: renderState.windowWidth / 2, centerY: 80, color: .amber, scale: 3)
        drawText(renderer, "Choose Faction", centerX: renderState.windowWidth / 2, centerY: 140, color: .green, scale: 2)

        for btn in makeLoadMissionFactionButtons() {
            btn.draw(renderer, highlighted: btn.contains(input.mouseX, input.mouseY))
        }

        drawText(renderer, "Esc: Back", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 40, color: .gray, scale: 1)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = MainMenuScreen()
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        for btn in makeLoadMissionFactionButtons() {
            if btn.contains(input.mouseX, input.mouseY) {
                btn.action()
                break
            }
        }
    }
}

// MARK: - Load Mission: Mission List

// Mission names from the original C&C manual/campaign
// Mission titles taken from the original briefing-video descriptions
// (Vanilla-Conquer mixnamedb: gdi1..gdi15 / nod1..nod13). The number keys the
// EA/primary variant of each mission; branch variants (…EB/…EC) are noted where
// they differ (e.g. GDI 4b "Recapture the Convoy", GDI 8b "Protect Mobius").
let gdiMissionNames: [Int: String] = [
    1: "Capture the Beachhead",
    2: "Destroy the Nod Refinery",
    3: "Destroy the SAM Sites",
    4: "Capture the Village",
    5: "Repair the GDI Base",
    6: "Destroy the Nod Base",
    7: "Finish the Nod Base",
    8: "Repair GDI Equipment",
    9: "Destroy the Bunkers",
    10: "Orca Raid",
    11: "Find Delphi",
    12: "Rescue Mobius",
    13: "Destroy the Bio Lab",
    14: "Destroy the Nod Forces",
    15: "Temple Strike",
]

let nodMissionNames: [Int: String] = [
    1: "Silencing Nikoomba",
    2: "Liberation of Egypt",
    3: "Friends of the Brotherhood",
    4: "Convoy Interception",
    5: "Grounded",
    6: "Extract Detonator",
    7: "Sick and Dying",
    8: "New Construction Options",
    9: "No Mercy",
    10: "Doctor Wong",
    11: "Deceit",
    12: "Cradle of My Temple",
    13: "Deadly Reunion",
]

class LoadMissionListScreen: MenuScreen {
    let faction: String  // "GDI" or "NOD"
    let missions: [String]  // scenario names like "SCG01EA"
    var scrollOffset: Int = 0

    init(faction: String) {
        self.faction = faction
        let prefix = faction == "GDI" ? "SCG" : "SCB"
        let maxMission = faction == "GDI" ? 15 : 13
        var found: [String] = []
        for i in 1...maxMission {
            let num = String(format: "%02d", i)
            for variant in ["EA", "EB", "EC"] {
                let name = "\(prefix)\(num)\(variant)"
                if mixManager.contains("\(name).INI") {
                    found.append(name)
                }
            }
        }
        self.missions = found
    }

    private let rowHeight: Int32 = 36
    private let listTopY: Int32 = 130

    private var visibleRows: Int {
        Int((renderState.windowHeight - listTopY - 60) / rowHeight)
    }

    func render(_ renderer: OpaquePointer?) {
        let cx = renderState.windowWidth / 2
        let factionColor: Color = faction == "GDI" ? .amber : .red
        drawText(renderer, "\(faction) Missions", centerX: cx, centerY: 60, color: factionColor, scale: 3)

        let bw: Int32 = 400
        let bx = cx - bw / 2
        let maxVisible = visibleRows

        for i in 0..<min(maxVisible, missions.count - scrollOffset) {
            let idx = scrollOffset + i
            let name = missions[idx]
            let y = listTopY + Int32(i) * rowHeight

            // Parse mission number and variant for display
            let missionNum = String(name.dropFirst(3).prefix(2))
            let variant = String(name.suffix(2))
            let missionInt = Int(missionNum) ?? 0
            let nameTable = faction == "GDI" ? gdiMissionNames : nodMissionNames
            let missionTitle = nameTable[missionInt] ?? name
            let variantSuffix = variant == "EA" ? "" : " (\(variant))"
            let label = "M\(missionNum): \(missionTitle)\(variantSuffix)"

            let highlighted = input.mouseX >= bx && input.mouseX < bx + bw &&
                              input.mouseY >= y && input.mouseY < y + rowHeight
            let bgColor = highlighted ? Color.darkGreen : Color.black
            let textColor = highlighted ? Color.brightGreen : Color.green

            var rect = SDL_Rect(x: bx, y: y, w: bw, h: rowHeight - 2)
            SDL_SetRenderDrawColor(renderer, bgColor.r, bgColor.g, bgColor.b, bgColor.a)
            SDL_RenderFillRect(renderer, &rect)
            SDL_SetRenderDrawColor(renderer, textColor.r, textColor.g, textColor.b, textColor.a)
            SDL_RenderDrawRect(renderer, &rect)

            drawText(renderer, label, centerX: cx, centerY: y + rowHeight / 2, color: textColor)
        }

        // Scroll indicators
        if scrollOffset > 0 {
            drawText(renderer, "^ Scroll Up ^", centerX: cx, centerY: listTopY - 16, color: .gray, scale: 1)
        }
        if scrollOffset + maxVisible < missions.count {
            let bottomY = listTopY + Int32(maxVisible) * rowHeight + 8
            drawText(renderer, "v Scroll Down v", centerX: cx, centerY: bottomY, color: .gray, scale: 1)
        }

        drawText(renderer, "Esc: Back   Up/Down: Scroll", centerX: cx, centerY: renderState.windowHeight - 30, color: .gray, scale: 1)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = LoadMissionFactionScreen()
        } else if key == Int32(SDLK_UP.rawValue) {
            scrollOffset = max(0, scrollOffset - 1)
        } else if key == Int32(SDLK_DOWN.rawValue) {
            scrollOffset = min(max(0, missions.count - visibleRows), scrollOffset + 1)
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        let bw: Int32 = 400
        let bx = renderState.windowWidth / 2 - bw / 2
        let maxVisible = visibleRows

        for i in 0..<min(maxVisible, missions.count - scrollOffset) {
            let iy = listTopY + Int32(i) * rowHeight
            if input.mouseX >= bx && input.mouseX < bx + bw &&
               input.mouseY >= iy && input.mouseY < iy + rowHeight {
                let idx = scrollOffset + i
                launchMission(missions[idx])
                return
            }
        }
    }

    private func launchMission(_ scenName: String) {
        // Set up campaign state for this mission
        let isMissionGDI = scenName.uppercased().hasPrefix("SCG")
        session.campaignState.currentFaction = isMissionGDI ? "GDI" : "NOD"
        let numStr = String(scenName.dropFirst(3).prefix(2))
        session.campaignState.currentMission = Int(numStr) ?? 1
        session.campaignState.currentVariant = String(scenName.suffix(2))
        session.campaignState.isActive = true
        session.campaignState.carryOverCredits = 0
        session.campaignState.completedMissions.removeAll()
        session.selectedDifficulty = .normal

        // Launch directly via the briefing screen
        session.currentScreen = BriefingScreen()
    }
}

// MARK: - Sound Test Screen

class SoundTestScreen: MenuScreen {
    func render(_ renderer: OpaquePointer?) {
        session.soundTest.render(renderer)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = MainMenuScreen()
            return
        }
        session.soundTest.handleKey(key)
    }
}

// MARK: - Map Viewer Screen

class MapViewerScreen: MenuScreen {
    func render(_ renderer: OpaquePointer?) {
        renderState.animationFrame += 1
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
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = MainMenuScreen()
            return
        }
        if key == Int32(SDLK_RIGHTBRACKET.rawValue) {
            session.scenarioIndex = (session.scenarioIndex + 1) % session.scenarioList.count
            loadMapViewerData(session.scenarioList[session.scenarioIndex])
        } else if key == Int32(SDLK_LEFTBRACKET.rawValue) {
            session.scenarioIndex = (session.scenarioIndex - 1 + session.scenarioList.count) % session.scenarioList.count
            loadMapViewerData(session.scenarioList[session.scenarioIndex])
        } else if key == Int32(SDLK_EQUALS.rawValue) {
            renderState.zoomLevel = min(3.0, renderState.zoomLevel + 0.25)
        } else if key == Int32(SDLK_MINUS.rawValue) {
            renderState.zoomLevel = max(0.5, renderState.zoomLevel - 0.25)
        } else if key == Int32(SDLK_g.rawValue) {
            renderState.showGrid = !renderState.showGrid
        } else if key == Int32(SDLK_i.rawValue) {
            renderState.showInfoPanel = !renderState.showInfoPanel
        } else if key == Int32(SDLK_t.rawValue) {
            renderState.showCellTriggers = !renderState.showCellTriggers
        } else if key == Int32(SDLK_b.rawValue) {
            renderState.showBaseList = !renderState.showBaseList
        } else if key == Int32(SDLK_p.rawValue) {
            if let sd = scenarioData {
                let scenName = session.scenarioList[session.scenarioIndex]

                // Simulator launch: detach from any active campaign so handleWin/score
                // don't try to advance to the next mission afterward.
                session.campaignState.isActive = false
                session.campaignState.completedMissions.removeAll()
                session.campaignState.carryOverCredits = 0

                // Build the world (resets triggers/win state, fog, house states, super weapons).
                initGameWorld(scenario: sd, scenarioName: scenName)
                session.currentScenarioName = scenName

                // Seed credits + tech level from the scenario INI (campaign path does
                // this via startNextMission; the simulator has to do it explicitly).
                session.sidebarCredits = sd.credits
                session.displayedCredits = sd.credits
                session.scenarioBuildLevel = sd.buildLevel

                // Match the briefing path's setup so end-screen + score work.
                session.missionScore.reset()
                session.lastTickTime = 0
                session.tickAccumulator = 0
                session.triggerWinState = .playing
                applyAutoFitCameraAndZoom()

                session.currentScreen = PlayingScreen()
            }
        } else if key == Int32(SDLK_m.rawValue) {
            audioManager.toggleMusic()
        } else if key >= Int32(SDLK_0.rawValue) && key <= Int32(SDLK_9.rawValue) {
            let wpId = Int(key - Int32(SDLK_0.rawValue))
            if let sd = scenarioData,
               let wp = sd.waypoints.first(where: { $0.id == wpId }) {
                let pos = cellToPixel(wp.cell)
                renderState.cameraX = pos.px - Int(Double(renderState.windowWidth) / renderState.zoomLevel) / 2
                renderState.cameraY = pos.py - Int(Double(renderState.windowHeight) / renderState.zoomLevel) / 2
                let visW = Int(Double(renderState.windowWidth) / renderState.zoomLevel)
                let visH = Int(Double(renderState.windowHeight) / renderState.zoomLevel)
                let maxCX = 64 * 24 - visW
                let maxCY = 64 * 24 - visH
                renderState.cameraX = max(0, min(maxCX, renderState.cameraX))
                renderState.cameraY = max(0, min(maxCY, renderState.cameraY))
            }
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        input.isPanning = true
        input.lastMouseX = x
        input.lastMouseY = y
    }

    func handleMouseUp(_ x: Int32, _ y: Int32, button: UInt8) {
        if button == UInt8(SDL_BUTTON_LEFT) {
            input.isPanning = false
        }
    }

    func handleMouseWheel(_ dy: Int32, atX: Int32, atY: Int32) {
        let oldZoom = renderState.zoomLevel
        var newZoom = oldZoom + (dy > 0 ? 0.25 : -0.25)
        newZoom = max(0.5, min(3.0, newZoom))
        if abs(newZoom - oldZoom) < 0.001 { return }
        // Anchor zoom to cursor — same math as the playing screen.
        let sx = Double(atX)
        let sy = Double(atY)
        renderState.cameraX += Int(sx * (1.0 / oldZoom - 1.0 / newZoom))
        renderState.cameraY += Int(sy * (1.0 / oldZoom - 1.0 / newZoom))
        renderState.zoomLevel = newZoom
    }

    func handleMouseMotion(_ x: Int32, _ y: Int32, xrel: Int32, yrel: Int32) {
        input.mouseWorldX = renderState.cameraX + Int(Double(x) / renderState.zoomLevel)
        input.mouseWorldY = renderState.cameraY + Int(Double(y) / renderState.zoomLevel)

        if input.isPanning {
            renderState.cameraX -= Int(Double(xrel) / renderState.zoomLevel)
            renderState.cameraY -= Int(Double(yrel) / renderState.zoomLevel)
            let visW = Int(Double(renderState.windowWidth) / renderState.zoomLevel)
            let visH = Int(Double(renderState.windowHeight) / renderState.zoomLevel)
            let maxCX = 64 * 24 - visW
            let maxCY = 64 * 24 - visH
            renderState.cameraX = max(0, min(maxCX, renderState.cameraX))
            renderState.cameraY = max(0, min(maxCY, renderState.cameraY))
        }
    }

    func handleContinuousInput() {
        let panSpeed = max(1, Int(8.0 / renderState.zoomLevel))
        let visibleW = Int(Double(renderState.windowWidth) / renderState.zoomLevel)
        let visibleH = Int(Double(renderState.windowHeight) / renderState.zoomLevel)
        let maxCameraX = 64 * 24 - visibleW
        let maxCameraY = 64 * 24 - visibleH

        if let keyState = SDL_GetKeyboardState(nil) {
            if keyState[Int(SDL_SCANCODE_LEFT.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_A.rawValue)] != 0 {
                renderState.cameraX = max(0, renderState.cameraX - panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_RIGHT.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_D.rawValue)] != 0 {
                renderState.cameraX = min(maxCameraX, renderState.cameraX + panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_UP.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_W.rawValue)] != 0 {
                renderState.cameraY = max(0, renderState.cameraY - panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_DOWN.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_S.rawValue)] != 0 {
                renderState.cameraY = min(maxCameraY, renderState.cameraY + panSpeed)
            }
        }
    }
}

// MARK: - Playing Screen

class PlayingScreen: MenuScreen {
    private var musicStarted = false
    private var endScreenTimer: Int = 0
    private var showingEndScreen: Bool = false
    private var endScreenButtons: [(label: String, x: Int32, y: Int32, w: Int32, h: Int32, action: String)] = []

    // Dwell counter for right-edge pan. Counts consecutive frames the
    // cursor has spent in the right edge zone heading toward the sidebar.
    // Pan only kicks in once this exceeds rightEdgeDwellThreshold, so brisk
    // moves toward the sidebar to click a button don't accidentally scroll.
    private var rightEdgeDwellFrames: Int = 0
    private let rightEdgeDwellThreshold: Int = 8

    func render(_ renderer: OpaquePointer?) {
        // Start gameplay music on first render
        if !musicStarted {
            musicStarted = true
            audioManager.startGameplayMusic()
        }
        renderGame(renderer)

        // Victory/Defeat overlay
        if showingEndScreen {
            renderEndScreen(renderer)
        }
    }

    // MARK: - End Screen Overlay

    private func renderEndScreen(_ renderer: OpaquePointer?) {
        let winW = renderState.windowWidth
        let winH = renderState.windowHeight
        let cx = winW / 2

        // Semi-transparent dark background
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 180)
        var bgRect = SDL_Rect(x: 0, y: 0, w: winW, h: winH)
        SDL_RenderFillRect(renderer, &bgRect)
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE)

        let won = session.triggerWinState == .won

        // Title
        if won {
            drawText(renderer, "MISSION ACCOMPLISHED", centerX: cx, centerY: 80, color: .green, scale: 4)
        } else {
            drawText(renderer, "MISSION FAILED", centerX: cx, centerY: 80, color: .red, scale: 4)
        }

        // Scenario name
        let scenName = session.currentScenarioName ?? session.campaignState.scenarioName
        drawText(renderer, scenName, centerX: cx, centerY: 130, color: .amber, scale: 2)

        // Stats section
        let statY: Int32 = 180
        let leftX = cx - 200
        let valueX = cx + 120

        drawText(renderer, "-- STATISTICS --", centerX: cx, centerY: statY, color: .amber, scale: 2)

        // Time elapsed
        let ticks = session.world?.tickCount ?? 0
        let totalSeconds = ticks / 15
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let timeStr = String(format: "%d:%02d", minutes, seconds)
        drawTextLeft(renderer, "Time:", x: leftX, y: statY + 35, color: .green, scale: 2)
        drawTextLeft(renderer, timeStr, x: valueX, y: statY + 35, color: .green, scale: 2)

        // Get score data from campaign
        let scoreData = session.campaign.scoreScreen(won: won)

        // Units destroyed
        let unitsDestroyed = scoreData.gdiKills + scoreData.nodKills
        drawTextLeft(renderer, "Units Destroyed:", x: leftX, y: statY + 65, color: .green, scale: 2)
        drawTextLeft(renderer, "\(unitsDestroyed)", x: valueX, y: statY + 65, color: .green, scale: 2)

        // Units lost — use player house state if available
        let playerHouse = session.world?.playerHouse ?? .goodGuy
        let unitsLost = session.houseStates[playerHouse]?.unitsLost ?? 0
        drawTextLeft(renderer, "Units Lost:", x: leftX, y: statY + 95, color: .green, scale: 2)
        drawTextLeft(renderer, "\(unitsLost)", x: valueX, y: statY + 95, color: .green, scale: 2)

        // Buildings destroyed
        let buildingsDestroyed = scoreData.gdiBuildings + scoreData.nodBuildings
        drawTextLeft(renderer, "Buildings Destroyed:", x: leftX, y: statY + 125, color: .green, scale: 2)
        drawTextLeft(renderer, "\(buildingsDestroyed)", x: valueX, y: statY + 125, color: .green, scale: 2)

        // Buildings lost
        let buildingsLost = session.houseStates[playerHouse]?.buildingsLost ?? 0
        drawTextLeft(renderer, "Buildings Lost:", x: leftX, y: statY + 155, color: .green, scale: 2)
        drawTextLeft(renderer, "\(buildingsLost)", x: valueX, y: statY + 155, color: .green, scale: 2)

        // Score
        session.missionScore.elapsedTicks = ticks
        let score = session.missionScore.totalScore
        drawText(renderer, "Score: \(score)", centerX: cx, centerY: statY + 200, color: .amber, scale: 3)

        // Star rating
        let stars = session.missionScore.starRating
        let starStr = String(repeating: "*", count: stars) + String(repeating: "-", count: 3 - stars)
        drawText(renderer, "Rating: \(starStr)", centerX: cx, centerY: statY + 240, color: .amber, scale: 2)

        // Buttons
        for btn in endScreenButtons {
            let mx = input.mouseX
            let my = input.mouseY
            let highlighted = mx >= btn.x && mx < btn.x + btn.w && my >= btn.y && my < btn.y + btn.h

            let borderColor = highlighted ? Color.brightGreen : Color.green
            let fillColor = highlighted ? Color.darkGreen : Color.black

            var rect = SDL_Rect(x: btn.x, y: btn.y, w: btn.w, h: btn.h)
            SDL_SetRenderDrawColor(renderer, fillColor.r, fillColor.g, fillColor.b, fillColor.a)
            SDL_RenderFillRect(renderer, &rect)
            SDL_SetRenderDrawColor(renderer, borderColor.r, borderColor.g, borderColor.b, borderColor.a)
            SDL_RenderDrawRect(renderer, &rect)
            var inner = SDL_Rect(x: btn.x + 1, y: btn.y + 1, w: btn.w - 2, h: btn.h - 2)
            SDL_RenderDrawRect(renderer, &inner)

            drawText(renderer, btn.label, centerX: btn.x + btn.w / 2, centerY: btn.y + btn.h / 2, color: borderColor)
        }
    }

    private func buildEndScreenButtons() {
        let won = session.triggerWinState == .won
        let bw: Int32 = 200
        let bh: Int32 = 44
        let gap: Int32 = 40
        let cy = renderState.windowHeight - 100

        if won {
            let totalW = bw * 2 + gap
            let startX = renderState.windowWidth / 2 - totalW / 2
            endScreenButtons = [
                (label: "CONTINUE", x: startX, y: cy, w: bw, h: bh, action: "continue"),
                (label: "REPLAY", x: startX + bw + gap, y: cy, w: bw, h: bh, action: "replay"),
            ]
        } else {
            let totalW = bw * 2 + gap
            let startX = renderState.windowWidth / 2 - totalW / 2
            endScreenButtons = [
                (label: "RETRY", x: startX, y: cy, w: bw, h: bh, action: "retry"),
                (label: "MENU", x: startX + bw + gap, y: cy, w: bw, h: bh, action: "menu"),
            ]
        }
    }

    private func handleEndScreenClick(_ x: Int32, _ y: Int32) {
        for btn in endScreenButtons {
            if x >= btn.x && x < btn.x + btn.w && y >= btn.y && y < btn.y + btn.h {
                switch btn.action {
                case "continue":
                    session.missionScore.elapsedTicks = session.world?.tickCount ?? 0
                    session.campaign.handleWin()
                    if session.campaignState.isComplete {
                        session.currentScreen = MainMenuScreen()
                    } else {
                        session.currentScreen = BriefingScreen()
                    }
                case "replay", "retry":
                    session.campaign.restart()
                    session.triggerWinState = .playing
                    showingEndScreen = false
                    endScreenTimer = 0
                    endScreenButtons = []
                case "menu":
                    session.currentScreen = MainMenuScreen()
                default:
                    break
                }
                return
            }
        }
    }

    func handleKeyDown(_ key: Int32) {
        // When end screen is showing, block most input
        if showingEndScreen {
            if key == Int32(SDLK_ESCAPE.rawValue) {
                session.currentScreen = MainMenuScreen()
            }
            return
        }

        if key == Int32(SDLK_ESCAPE.rawValue) {
            if session.isPatrolMode {
                session.isPatrolMode = false
                session.patrolModeWaypoints = []
            } else if session.superWeaponTargeting != nil {
                session.superWeaponTargeting = nil
            } else if session.isAttackMoveMode {
                session.isAttackMoveMode = false
            } else if session.isPlacingStructure {
                session.isPlacingStructure = false
                session.placementType = nil
            } else if let world = session.world, !world.selectedObjects().isEmpty {
                world.deselectAll()
            } else {
                session.currentScreen = MapViewerScreen()
                SDL_ShowCursor(SDL_ENABLE)
                renderState.systemCursorHidden = false
            }
            return
        }
        if key == Int32(SDLK_EQUALS.rawValue) {
            renderState.gameZoomLevel = min(4.0, renderState.gameZoomLevel + 0.25)
        } else if key == Int32(SDLK_MINUS.rawValue) {
            // Don't zoom out past where map bounds fill the viewport
            let vpW = Double(renderState.windowWidth - sidebarWidth)
            let vpH = Double(renderState.windowHeight)
            var minZoom = 0.5
            if let bounds = session.world?.mapBounds {
                let fitX = vpW / Double(bounds.width * 24)
                let fitY = vpH / Double(bounds.height * 24)
                minZoom = max(minZoom, max(fitX, fitY))
            }
            renderState.gameZoomLevel = max(minZoom, renderState.gameZoomLevel - 0.25)
        } else if key == Int32(SDLK_F5.rawValue) {
            if quickMissionSave() {
                print("Quick saved!")
            }
        } else if key == Int32(SDLK_F9.rawValue) {
            if quickMissionLoad() {
                print("Quick loaded!")
            }
        } else if key == Int32(SDLK_RETURN.rawValue) || key == Int32(SDLK_SPACE.rawValue) {
            if session.triggerWinState == .won {
                session.missionScore.elapsedTicks = session.world?.tickCount ?? 0
                session.currentScreen = ScoreScreen(won: true)
            } else if session.triggerWinState == .lost {
                session.missionScore.elapsedTicks = session.world?.tickCount ?? 0
                session.currentScreen = ScoreScreen(won: false)
            }
        } else if key == Int32(SDLK_s.rawValue) {
            // Stop/halt selected units
            if let world = session.world {
                for obj in world.selectedObjects() {
                    if obj.kind == .structure { continue }
                    if obj.house != world.playerHouse { continue }
                    obj.mission = .guard_
                    obj.moveTargetX = nil
                    obj.moveTargetY = nil
                    obj.attackTarget = nil
                    obj.movePath = []
                    obj.isAttackMoving = false
                    obj.moveWaypoints = []
                }
            }
        } else if key == Int32(SDLK_a.rawValue) {
            // Attack-move mode: press A, then click destination
            // Units move there but engage any enemies along the way
            if let world = session.world, !world.selectedObjects().isEmpty {
                session.isAttackMoveMode = true
            }
        } else if key == Int32(SDLK_x.rawValue) {
            // Scatter: each selected unit moves to a random nearby passable cell
            if let world = session.world {
                for obj in world.selectedObjects() {
                    if obj.kind == .structure { continue }
                    if obj.house != world.playerHouse { continue }
                    // Pick a random passable cell within 2-3 cells
                    let scatterDist = 3
                    var found = false
                    for _ in 0..<8 {  // Try up to 8 random positions
                        let nx = obj.cellX + Int.random(in: -scatterDist...scatterDist)
                        let ny = obj.cellY + Int.random(in: -scatterDist...scatterDist)
                        let clampedX = max(0, min(63, nx))
                        let clampedY = max(0, min(63, ny))
                        if clampedX == obj.cellX && clampedY == obj.cellY { continue }
                        if isCellPassable(cellX: clampedX, cellY: clampedY, ignoring: obj, speedType: obj.cachedSpeedType) {
                            obj.moveTargetX = Double(clampedX * 24) + 12.0
                            obj.moveTargetY = Double(clampedY * 24) + 12.0
                            obj.mission = .move
                            obj.movePath = []
                            obj.attackTarget = nil
                            obj.isAttackMoving = false
                            obj.moveWaypoints = []
                            found = true
                            break
                        }
                    }
                    if !found {
                        // Fallback: just stop in place
                        obj.mission = .guard_
                    }
                }
                audioManager.play(audioManager.unitAcknowledgeSound())
            }
        } else if key == Int32(SDLK_g.rawValue) {
            // Guard mode: stand ground, attack enemies in range
            if let world = session.world {
                for obj in world.selectedObjects() {
                    if obj.kind == .structure { continue }
                    if obj.house != world.playerHouse { continue }
                    obj.mission = .guard_
                    obj.moveTargetX = nil
                    obj.moveTargetY = nil
                    obj.movePath = []
                    obj.isAttackMoving = false
                    obj.moveWaypoints = []
                }
            }
        } else if key == Int32(SDLK_p.rawValue) {
            // Patrol mode: press P, then click to add waypoints, right-click/ESC to finalize
            if let world = session.world, !world.selectedObjects().isEmpty {
                let hasMovable = world.selectedObjects().contains {
                    $0.kind != .structure && $0.house == world.playerHouse
                }
                if hasMovable {
                    session.isPatrolMode = true
                    session.patrolModeWaypoints = []
                }
            }
        } else if key == Int32(SDLK_r.rawValue) {
            if session.triggerWinState != .playing {
                session.campaign.restart()
                session.triggerWinState = .playing
                endScreenTimer = 0
            }
        } else if key == Int32(SDLK_h.rawValue) {
            // H key: center camera on player's Construction Yard
            if let world = session.world {
                if let cy = world.objects.first(where: {
                    $0.kind == .structure && $0.house == world.playerHouse &&
                    $0.typeName.uppercased() == "FACT" && $0.strength > 0
                }) {
                    let vpW = Double(renderState.windowWidth - sidebarWidth) / renderState.gameZoomLevel
                    let vpH = Double(renderState.windowHeight) / renderState.gameZoomLevel
                    renderState.gameCameraX = cy.worldX - vpW / 2.0
                    renderState.gameCameraY = cy.worldY - vpH / 2.0
                    clampGameCamera()
                }
            }
        } else if key == Int32(SDLK_e.rawValue) {
            // E key: select all visible player units on screen
            if let world = session.world {
                let vpW = Double(renderState.windowWidth - sidebarWidth) / renderState.gameZoomLevel
                let vpH = Double(renderState.windowHeight) / renderState.gameZoomLevel
                let camX = renderState.gameCameraX
                let camY = renderState.gameCameraY
                world.deselectAll()
                for obj in world.objects {
                    if obj.kind == .structure { continue }
                    if obj.house != world.playerHouse { continue }
                    if obj.strength <= 0 { continue }
                    if obj.worldX >= camX && obj.worldX <= camX + vpW &&
                       obj.worldY >= camY && obj.worldY <= camY + vpH {
                        obj.isSelected = true
                    }
                }
            }
        } else if key == Int32(SDLK_m.rawValue) {
            // M key: toggle music on/off
            audioManager.toggleMusic()
            if audioManager.musicEnabled && !audioManager.isMusicPlaying {
                audioManager.startGameplayMusic()
            }
        } else if isNumberKey(key) {
            // Control groups: Ctrl+0-9 to assign, 0-9 to recall, double-tap to center
            let groupNum = numberKeyIndex(key)
            let ctrlHeld = SDL_GetModState().rawValue & UInt32(KMOD_CTRL.rawValue) != 0
            if let world = session.world {
                if ctrlHeld {
                    // Assign current selection to control group
                    world.controlGroups[groupNum] = world.selectedObjects().map { $0.id }
                } else {
                    // Recall: deselect all, select group members (skip dead)
                    let ids = world.controlGroups[groupNum]
                    if !ids.isEmpty {
                        let currentTick = world.tickCount
                        let isDoubleTap = input.lastGroupKey == groupNum &&
                                          (currentTick - input.lastGroupKeyTick) < 20
                        input.lastGroupKey = groupNum
                        input.lastGroupKeyTick = currentTick

                        world.deselectAll()
                        var sumX = 0.0, sumY = 0.0, count = 0
                        for objId in ids {
                            if let obj = world.findObject(id: objId), obj.strength > 0 {
                                obj.isSelected = true
                                sumX += obj.worldX
                                sumY += obj.worldY
                                count += 1
                            }
                        }

                        // Double-tap: center camera on group center-of-mass
                        if isDoubleTap && count > 0 {
                            let centerX = sumX / Double(count)
                            let centerY = sumY / Double(count)
                            let vpW = Double(renderState.windowWidth - sidebarWidth) / renderState.gameZoomLevel
                            let vpH = Double(renderState.windowHeight) / renderState.gameZoomLevel
                            renderState.gameCameraX = centerX - vpW / 2.0
                            renderState.gameCameraY = centerY - vpH / 2.0
                            clampGameCamera()
                        }
                    }
                }
            }
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        // When end screen is showing, only handle overlay button clicks
        if showingEndScreen {
            if button == UInt8(SDL_BUTTON_LEFT) {
                handleEndScreenClick(x, y)
            }
            return
        }

        if button == UInt8(SDL_BUTTON_LEFT) {
            if x >= renderState.windowWidth - sidebarWidth {
                if handleSuperWeaponClick(x, y) {
                    // Handled
                } else if !handleRepairSellClick(x, y) {
                    handleSidebarClick(x, y)
                }
            } else if isInMinimap(x, y) {
                // Minimap click-to-navigate
                input.isDraggingMinimap = true
                handleMinimapClick(x, y)
            } else if session.superWeaponTargeting != nil {
                let worldPos = gameScreenToWorld(x, y)
                if !handleSuperWeaponGameClick(worldX: worldPos.worldX, worldY: worldPos.worldY) {
                    session.superWeaponTargeting = nil
                }
            } else if session.isPlacingStructure {
                handleStructurePlacement(x, y)
            } else if session.isRepairMode || session.isSellMode {
                let worldPos = gameScreenToWorld(x, y)
                if !handleRepairSellGameClick(worldX: worldPos.worldX, worldY: worldPos.worldY) {
                    session.isRepairMode = false
                    session.isSellMode = false
                }
            } else if session.isPatrolMode {
                // Patrol mode: left-click adds a waypoint
                let worldPos = gameScreenToWorld(x, y)
                session.patrolModeWaypoints.append((x: worldPos.worldX, y: worldPos.worldY))
            } else if session.isAttackMoveMode {
                // Attack-move: issue move order — units engage enemies along the way
                session.isAttackMoveMode = false
                let worldPos = gameScreenToWorld(x, y)
                if let world = session.world {
                    let movable = world.selectedObjects().filter {
                        $0.kind != .structure && $0.house == world.playerHouse
                    }
                    let count = movable.count

                    // Squad speed matching for attack-move
                    let groupSpeed: Double?
                    if count >= 2 {
                        let speeds = movable.map { $0.effectiveSpeed }
                        let minSpd = speeds.min() ?? 0
                        let maxSpd = speeds.max() ?? 0
                        groupSpeed = (minSpd < maxSpd) ? minSpd : nil
                    } else {
                        groupSpeed = nil
                    }

                    let cols = max(1, Int(ceil(sqrt(Double(count)))))
                    let spacing = 36.0
                    for (i, obj) in movable.enumerated() {
                        let row = i / cols
                        let col = i % cols
                        let offX = (Double(col) - Double(cols - 1) / 2.0) * spacing
                        let offY = (Double(row) - Double(max(0, (count - 1) / cols)) / 2.0) * spacing
                        let jX = Double.random(in: -6.0...6.0)
                        let jY = Double.random(in: -6.0...6.0)
                        obj.moveTargetX = max(12, min(64*24-12, worldPos.worldX + offX + jX))
                        obj.moveTargetY = max(12, min(64*24-12, worldPos.worldY + offY + jY))
                        obj.mission = .move
                        obj.movePath = []
                        obj.attackTarget = nil
                        obj.isAttackMoving = true
                        obj.moveWaypoints = []
                        obj.groupMoveSpeed = groupSpeed
                    }
                    audioManager.play(audioManager.unitAcknowledgeSound())
                }
            } else {
                let shiftHeld = (SDL_GetModState().rawValue & UInt32(KMOD_SHIFT.rawValue)) != 0
                handleGameLeftDown(x, y, shiftHeld: shiftHeld)
            }
        } else if button == UInt8(SDL_BUTTON_RIGHT) {
            if session.isAttackMoveMode {
                session.isAttackMoveMode = false
            } else if session.superWeaponTargeting != nil {
                session.superWeaponTargeting = nil
            } else if session.isRepairMode || session.isSellMode {
                session.isRepairMode = false
                session.isSellMode = false
            } else if session.isPlacingStructure {
                session.isPlacingStructure = false
                session.placementType = nil
            } else {
                let shiftHeld = (SDL_GetModState().rawValue & UInt32(KMOD_SHIFT.rawValue)) != 0
                handleGameRightClick(x, y, shiftHeld: shiftHeld)
            }
        }
    }

    func handleMouseUp(_ x: Int32, _ y: Int32, button: UInt8) {
        if showingEndScreen { return }
        if button == UInt8(SDL_BUTTON_LEFT) {
            if input.isDraggingMinimap {
                input.isDraggingMinimap = false
            } else if session.isPatrolMode {
                // Don't process left-up during patrol mode — waypoints are added on mouse-down
                // and we must not deselect units or start a selection box.
            } else if x < renderState.windowWidth - sidebarWidth && !session.isPlacingStructure {
                let shiftHeld = (SDL_GetModState().rawValue & UInt32(KMOD_SHIFT.rawValue)) != 0
                handleGameLeftUp(x, y, shiftHeld: shiftHeld)
            }
        }
    }

    func handleMouseMotion(_ x: Int32, _ y: Int32, xrel: Int32, yrel: Int32) {
        if showingEndScreen { return }
        if input.isDraggingMinimap {
            // Continue dragging on minimap — update camera position
            handleMinimapClick(x, y)
        } else if input.selectionBoxStartX != nil {
            handleGameLeftDrag(x, y)
        }
    }

    func handleMouseWheel(_ dy: Int32, atX: Int32, atY: Int32) {
        if showingEndScreen { return }
        // Don't zoom when the cursor is over the sidebar — let the wheel
        // pass through (e.g. for sidebar scroll later).
        if atX >= renderState.windowWidth - sidebarWidth { return }

        let oldZoom = renderState.gameZoomLevel
        let step = 0.25
        var newZoom = oldZoom + (dy > 0 ? step : -step)
        // Clamp: 1.0 keeps tiles at native pixels (no fractional sampling
        // ugliness); 4.0 is a comfortable zoom-in ceiling.
        newZoom = max(1.0, min(4.0, newZoom))
        if abs(newZoom - oldZoom) < 0.001 { return }

        // Anchor zoom to cursor: keep the world point under the mouse fixed.
        // worldX = camX + screenX/zoom  →  camX_new = camX_old + screenX*(1/zoom_old - 1/zoom_new)
        let sx = Double(atX)
        let sy = Double(atY)
        renderState.gameCameraX += sx * (1.0 / oldZoom - 1.0 / newZoom)
        renderState.gameCameraY += sy * (1.0 / oldZoom - 1.0 / newZoom)
        renderState.gameZoomLevel = newZoom
        clampGameCamera()
    }

    func handleContinuousInput() {
        // Manage end screen timer
        if session.triggerWinState != .playing && !showingEndScreen {
            endScreenTimer += 1
            if endScreenTimer >= 45 {  // ~3 seconds at 15 FPS
                showingEndScreen = true
                buildEndScreenButtons()
            }
        }

        // Block camera panning when end screen is up
        if showingEndScreen { return }

        let panSpeed = max(1.0, 8.0 / renderState.gameZoomLevel)
        let visibleW = Double(renderState.windowWidth - sidebarWidth) / renderState.gameZoomLevel
        let visibleH = Double(renderState.windowHeight) / renderState.gameZoomLevel

        // Clamp camera to map bounds (not full 64x64 world)
        let minCamX: Double
        let minCamY: Double
        let maxCamX: Double
        let maxCamY: Double
        if let bounds = session.world?.mapBounds {
            minCamX = Double(bounds.x * 24)
            minCamY = Double(bounds.y * 24)
            maxCamX = Double((bounds.x + bounds.width) * 24) - visibleW
            maxCamY = Double((bounds.y + bounds.height) * 24) - visibleH
        } else {
            minCamX = 0
            minCamY = 0
            maxCamX = Double(64 * 24) - visibleW
            maxCamY = Double(64 * 24) - visibleH
        }

        // Edge-of-screen mouse scrolling with acceleration
        // The deeper the cursor is into the edge zone, the faster the scroll.
        let edgeZone: Double = 40.0  // Pixels from edge that triggers scroll
        let minSpeed = panSpeed * 0.25
        let maxSpeed = panSpeed * 2.5
        let mx = Double(input.mouseX)
        let my = Double(input.mouseY)
        let gameAreaWidth = Double(renderState.windowWidth - sidebarWidth)
        let windowHeight = Double(renderState.windowHeight)

        // Left edge
        if mx < edgeZone {
            let depth = (edgeZone - mx) / edgeZone  // 0 at boundary, 1 at screen edge
            let speed = minSpeed + (maxSpeed - minSpeed) * depth * depth
            renderState.gameCameraX = max(minCamX, renderState.gameCameraX - speed)
        }
        // Right edge — gated by a dwell counter so moving toward the
        // sidebar to click a button doesn't accidentally trigger a pan.
        // The counter is reset whenever the cursor is in the sidebar
        // (true dead zone) or out of the edge zone entirely.
        if mx >= gameAreaWidth {
            // Cursor is over the sidebar — never pan.
            rightEdgeDwellFrames = 0
        } else if mx >= gameAreaWidth - edgeZone {
            rightEdgeDwellFrames += 1
            if rightEdgeDwellFrames >= rightEdgeDwellThreshold {
                let depth = (mx - (gameAreaWidth - edgeZone)) / edgeZone
                let speed = minSpeed + (maxSpeed - minSpeed) * depth * depth
                renderState.gameCameraX = min(maxCamX, renderState.gameCameraX + speed)
            }
        } else {
            rightEdgeDwellFrames = 0
        }
        // Top edge
        if my < edgeZone {
            let depth = (edgeZone - my) / edgeZone
            let speed = minSpeed + (maxSpeed - minSpeed) * depth * depth
            renderState.gameCameraY = max(minCamY, renderState.gameCameraY - speed)
        }
        // Bottom edge
        if my >= windowHeight - edgeZone {
            let depth = (my - (windowHeight - edgeZone)) / edgeZone
            let speed = minSpeed + (maxSpeed - minSpeed) * depth * depth
            renderState.gameCameraY = min(maxCamY, renderState.gameCameraY + speed)
        }

        // Clamp camera after pan (in case maxCam < minCam when viewport > map)
        renderState.gameCameraX = max(minCamX, min(maxCamX, renderState.gameCameraX))
        renderState.gameCameraY = max(minCamY, min(maxCamY, renderState.gameCameraY))
    }
}

// MARK: - Game Hotkey Helpers

/// Check if an SDLK key code is a number key (0-9)
private func isNumberKey(_ key: Int32) -> Bool {
    key >= Int32(SDLK_0.rawValue) && key <= Int32(SDLK_9.rawValue)
}

/// Convert an SDLK number key to its index (0-9). SDLK_1=1, ..., SDLK_0=0.
private func numberKeyIndex(_ key: Int32) -> Int {
    let raw = Int(key - Int32(SDLK_0.rawValue))
    return raw  // SDLK_0=0, SDLK_1=1, ..., SDLK_9=9
}

/// Auto-fit zoom so the map fills the viewport, then center the camera on
/// the player's starting position. Used by both the campaign briefing and
/// the Map Viewer's P:Play simulator so the two paths stay aligned.
///
/// Focal-point priority (most-specific first):
///   1. Tiberian Dawn HOME waypoint (id 26 — see Vanilla-Conquer
///      `tiberiandawn/defines.h` `WAYPT_HOME`).
///   2. Red Alert HOME waypoint (id 98), in case an RA scenario loads.
///   3. Centroid of the player's starting objects — handles commando
///      missions like SCG01EA that have no HOME waypoint but plenty of
///      placed infantry. Without this, the camera lands at bounds-origin
///      and the playable area renders as solid black fog of war.
///   4. Center of the playable map bounds.
///   5. Bounds origin (legacy fallback).
func applyAutoFitCameraAndZoom() {
    let vpW = max(1.0, Double(renderState.windowWidth - sidebarWidth))
    let vpH = max(1.0, Double(renderState.windowHeight))

    if let bounds = session.world?.mapBounds {
        let mapPixW = max(1.0, Double(bounds.width * 24))
        let mapPixH = max(1.0, Double(bounds.height * 24))
        // Fit-to-viewport but cap at 1.5x so tiny maps don't upscale 24x24
        // ICN tiles to a chunky 70+ pixels per tile. Empty space around a
        // small map is the right look — that's how the original C&C presents
        // bounded missions.
        let fitZoom = max(vpW / mapPixW, vpH / mapPixH)
        renderState.gameZoomLevel = max(1.0, min(1.5, fitZoom))
    } else {
        renderState.gameZoomLevel = 1.0
    }

    var focusX: Double? = nil
    var focusY: Double? = nil

    if let scenario = scenarioData {
        for id in [26, 98] {
            if let wp = scenario.waypoints.first(where: { $0.id == id }) {
                let pos = cellToPixel(wp.cell)
                focusX = Double(pos.px) + 12.0
                focusY = Double(pos.py) + 12.0
                break
            }
        }
    }

    if focusX == nil, let world = session.world {
        var sumX = 0.0, sumY = 0.0, count = 0
        for obj in world.objects where obj.house == world.playerHouse && obj.strength > 0 {
            sumX += obj.worldX
            sumY += obj.worldY
            count += 1
        }
        if count > 0 {
            focusX = sumX / Double(count)
            focusY = sumY / Double(count)
        }
    }

    if focusX == nil, let bounds = session.world?.mapBounds {
        focusX = Double((bounds.x + bounds.width / 2) * 24) + 12.0
        focusY = Double((bounds.y + bounds.height / 2) * 24) + 12.0
    }

    if let fx = focusX, let fy = focusY {
        renderState.gameCameraX = fx - vpW / renderState.gameZoomLevel / 2.0
        renderState.gameCameraY = fy - vpH / renderState.gameZoomLevel / 2.0
    } else if let bounds = session.world?.mapBounds {
        renderState.gameCameraX = Double(bounds.x * 24)
        renderState.gameCameraY = Double(bounds.y * 24)
    }
    clampGameCamera()
}

/// Clamp the game camera to map bounds
func clampGameCamera() {
    let vpW = Double(renderState.windowWidth - sidebarWidth) / renderState.gameZoomLevel
    let vpH = Double(renderState.windowHeight) / renderState.gameZoomLevel
    let minCamX: Double
    let minCamY: Double
    let maxCamX: Double
    let maxCamY: Double
    if let bounds = session.world?.mapBounds {
        let mapPixW = Double(bounds.width * 24)
        let mapPixH = Double(bounds.height * 24)
        // If the map is smaller than the viewport on an axis, CENTER it (the
        // out-of-bounds mask paints the surrounding area black) instead of
        // pinning it to a corner. Otherwise clamp so the viewport stays inside.
        if mapPixW <= vpW {
            renderState.gameCameraX = Double(bounds.x * 24) - (vpW - mapPixW) / 2.0
        } else {
            renderState.gameCameraX = max(Double(bounds.x * 24),
                min(Double((bounds.x + bounds.width) * 24) - vpW, renderState.gameCameraX))
        }
        if mapPixH <= vpH {
            renderState.gameCameraY = Double(bounds.y * 24) - (vpH - mapPixH) / 2.0
        } else {
            renderState.gameCameraY = max(Double(bounds.y * 24),
                min(Double((bounds.y + bounds.height) * 24) - vpH, renderState.gameCameraY))
        }
        return
    } else {
        minCamX = 0
        minCamY = 0
        maxCamX = Double(64 * 24) - vpW
        maxCamY = Double(64 * 24) - vpH
    }
    renderState.gameCameraX = max(minCamX, min(maxCamX, renderState.gameCameraX))
    renderState.gameCameraY = max(minCamY, min(maxCamY, renderState.gameCameraY))
}

/// Minimap layout constants (must match renderGameMinimap in GameRenderer.swift)
private func minimapRect() -> (x: Int32, y: Int32, size: Int32, cellSize: Int32) {
    let cellSize: Int32 = 2
    let size: Int32 = 64 * cellSize
    let pad: Int32 = 10
    let x = renderState.windowWidth - sidebarWidth - size - pad
    let y = renderState.windowHeight - size - pad
    return (x, y, size, cellSize)
}

/// Convert a screen-space click on the minimap to world coordinates and center camera there
private func handleMinimapClick(_ screenX: Int32, _ screenY: Int32) {
    let mm = minimapRect()
    let tileSize = 24.0
    // Convert minimap pixel to cell coordinate
    let cellX = Double(screenX - mm.x) / Double(mm.cellSize)
    let cellY = Double(screenY - mm.y) / Double(mm.cellSize)
    // Convert cell to world pixel
    let worldX = cellX * tileSize
    let worldY = cellY * tileSize
    // Center camera on that world position
    let vpW = Double(renderState.windowWidth - sidebarWidth) / renderState.gameZoomLevel
    let vpH = Double(renderState.windowHeight) / renderState.gameZoomLevel
    renderState.gameCameraX = worldX - vpW / 2.0
    renderState.gameCameraY = worldY - vpH / 2.0
    clampGameCamera()
}

/// Check if a screen coordinate is within the minimap area
private func isInMinimap(_ x: Int32, _ y: Int32) -> Bool {
    let mm = minimapRect()
    return x >= mm.x && x < mm.x + mm.size && y >= mm.y && y < mm.y + mm.size
}

// MARK: - Score Screen

class ScoreScreen: MenuScreen {
    let won: Bool

    init(won: Bool) {
        self.won = won
    }

    func render(_ renderer: OpaquePointer?) {
        renderScoreScreen(renderer, won: won)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = MainMenuScreen()
            return
        }
        if key == Int32(SDLK_n.rawValue) && won && session.campaignState.isActive {
            session.campaign.handleWin()
            if !session.campaignState.isComplete {
                session.currentScreen = BriefingScreen()
            } else {
                session.currentScreen = MainMenuScreen()
            }
        } else if key == Int32(SDLK_r.rawValue) {
            session.campaign.restart()
            session.triggerWinState = .playing
            session.currentScreen = PlayingScreen()
        }
    }
}
