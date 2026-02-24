import CSDL2
import Foundation

// MARK: - MenuScreen Protocol

protocol MenuScreen: AnyObject {
    func render(_ renderer: OpaquePointer?)
    func handleKeyDown(_ key: Int32)
    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8)
    func handleMouseUp(_ x: Int32, _ y: Int32, button: UInt8)
    func handleMouseMotion(_ x: Int32, _ y: Int32, xrel: Int32, yrel: Int32)
    func handleContinuousInput()
}

// Default no-op implementations
extension MenuScreen {
    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {}
    func handleMouseUp(_ x: Int32, _ y: Int32, button: UInt8) {}
    func handleMouseMotion(_ x: Int32, _ y: Int32, xrel: Int32, yrel: Int32) {}
    func handleContinuousInput() {}
}

// MARK: - Main Menu Screen

class MainMenuScreen: MenuScreen {
    func render(_ renderer: OpaquePointer?) {
        drawText(renderer, "Command & Conquer", centerX: renderState.windowWidth / 2, centerY: 80, color: .amber, scale: 4)
        drawText(renderer, "Tiberian Dawn Max", centerX: renderState.windowWidth / 2, centerY: 140, color: .green, scale: 3)

        for btn in makeMainButtons() {
            btn.draw(renderer, highlighted: btn.contains(input.mouseX, input.mouseY))
        }

        drawText(renderer, "R964", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 40, color: .gray, scale: 1)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.running = false
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
                // Calculate auto-zoom to fit map bounds in viewport
                let vpW = Double(renderState.windowWidth - sidebarWidth)
                let vpH = Double(renderState.windowHeight)
                if let bounds = session.world?.mapBounds {
                    let mapPixW = Double(bounds.width * 24)
                    let mapPixH = Double(bounds.height * 24)
                    let fitZoomX = vpW / mapPixW
                    let fitZoomY = vpH / mapPixH
                    // Use the larger zoom so map fills viewport (no empty space)
                    renderState.gameZoomLevel = max(fitZoomX, fitZoomY)
                    // Minimum zoom is 1.0 (don't zoom out beyond native pixel size)
                    renderState.gameZoomLevel = max(1.0, renderState.gameZoomLevel)
                } else {
                    renderState.gameZoomLevel = 1.0
                }

                // Initialize game camera — center on start waypoint or map bounds
                if let scenario = scenarioData,
                   let startWP = scenario.waypoints.first(where: { $0.id == 98 }) {
                    let pos = cellToPixel(startWP.cell)
                    renderState.gameCameraX = Double(pos.px) - vpW / renderState.gameZoomLevel / 2.0
                    renderState.gameCameraY = Double(pos.py) - vpH / renderState.gameZoomLevel / 2.0
                } else if let bounds = session.world?.mapBounds {
                    renderState.gameCameraX = Double(bounds.x * 24)
                    renderState.gameCameraY = Double(bounds.y * 24)
                }
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
let gdiMissionNames: [Int: String] = [
    1: "X16-Y42",
    2: "Knock Out That Refinery",
    3: "Air Supremacy",
    4: "Reinforce Bialystok",
    5: "Evacuate Nikoomba",
    6: "Destroy the Airstrip",
    7: "Infiltrate Nod Base",
    8: "Remove SAM Sites",
    9: "Locate the Prison",
    10: "Rescue Mobius",
    11: "Code Name Delphi",
    12: "Saving Doctor Wong",
    13: "Retrieve the Detonator",
    14: "Destroy Nod Factory",
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
                initGameWorld(scenario: sd, scenarioName: scenName)
                session.currentScenarioName = scenName
                renderState.gameCameraX = Double(renderState.cameraX)
                renderState.gameCameraY = Double(renderState.cameraY)
                renderState.gameZoomLevel = renderState.zoomLevel
                session.lastTickTime = 0
                session.tickAccumulator = 0
                session.missionScore.reset()
                session.currentScreen = PlayingScreen()
            }
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
    func render(_ renderer: OpaquePointer?) {
        renderGame(renderer)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            if session.superWeaponTargeting != nil {
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
            if quickSave() {
                print("Quick saved!")
            }
        } else if key == Int32(SDLK_F9.rawValue) {
            if quickLoad() {
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
        } else if key == Int32(SDLK_r.rawValue) {
            if session.triggerWinState != .playing {
                session.campaign.restart()
                session.triggerWinState = .playing
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
            } else if session.isAttackMoveMode {
                // Attack-move: issue move order — units engage enemies along the way
                session.isAttackMoveMode = false
                let worldPos = gameScreenToWorld(x, y)
                if let world = session.world {
                    let movable = world.selectedObjects().filter {
                        $0.kind != .structure && $0.house == world.playerHouse
                    }
                    let count = movable.count
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
        if button == UInt8(SDL_BUTTON_LEFT) {
            if input.isDraggingMinimap {
                input.isDraggingMinimap = false
            } else if x < renderState.windowWidth - sidebarWidth && !session.isPlacingStructure {
                let shiftHeld = (SDL_GetModState().rawValue & UInt32(KMOD_SHIFT.rawValue)) != 0
                handleGameLeftUp(x, y, shiftHeld: shiftHeld)
            }
        }
    }

    func handleMouseMotion(_ x: Int32, _ y: Int32, xrel: Int32, yrel: Int32) {
        if input.isDraggingMinimap {
            // Continue dragging on minimap — update camera position
            handleMinimapClick(x, y)
        } else if input.selectionBoxStartX != nil {
            handleGameLeftDrag(x, y)
        }
    }

    func handleContinuousInput() {
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

        // Edge-of-screen mouse scrolling (classic C&C style)
        let edgeSize: Int32 = 8  // Pixels from edge to trigger scroll
        let mx = input.mouseX
        let my = input.mouseY
        let gameAreaWidth = renderState.windowWidth - sidebarWidth

        if mx < edgeSize {
            renderState.gameCameraX = max(minCamX, renderState.gameCameraX - panSpeed)
        }
        if mx >= gameAreaWidth - edgeSize {
            renderState.gameCameraX = min(maxCamX, renderState.gameCameraX + panSpeed)
        }
        if my < edgeSize {
            renderState.gameCameraY = max(minCamY, renderState.gameCameraY - panSpeed)
        }
        if my >= renderState.windowHeight - edgeSize {
            renderState.gameCameraY = min(maxCamY, renderState.gameCameraY + panSpeed)
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

/// Clamp the game camera to map bounds
private func clampGameCamera() {
    let vpW = Double(renderState.windowWidth - sidebarWidth) / renderState.gameZoomLevel
    let vpH = Double(renderState.windowHeight) / renderState.gameZoomLevel
    let minCamX: Double
    let minCamY: Double
    let maxCamX: Double
    let maxCamY: Double
    if let bounds = session.world?.mapBounds {
        minCamX = Double(bounds.x * 24)
        minCamY = Double(bounds.y * 24)
        maxCamX = Double((bounds.x + bounds.width) * 24) - vpW
        maxCamY = Double((bounds.y + bounds.height) * 24) - vpH
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
