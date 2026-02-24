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
                // Initialize game camera
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
                session.currentScreen = PlayingScreen()
            } else {
                session.currentScreen = MainMenuScreen()
            }
        }
    }
}

// MARK: - Sprite Viewer Screen

class SpriteViewerScreen: MenuScreen {
    func render(_ renderer: OpaquePointer?) {
        let shapeName = viewableShapes[renderState.spriteViewerIndex]

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

            let maxDisplayW: Int32 = 400
            let maxDisplayH: Int32 = 350
            let scaleX = frame.width > 0 ? maxDisplayW / Int32(frame.width) : 1
            let scaleY = frame.height > 0 ? maxDisplayH / Int32(frame.height) : 1
            let pixelScale = max(1, min(scaleX, scaleY))

            let drawW = Int32(frame.width) * pixelScale
            let drawH = Int32(frame.height) * pixelScale
            let drawX = renderState.windowWidth / 2 - drawW / 2
            let drawY: Int32 = 130 + (maxDisplayH - drawH) / 2

            SDL_SetRenderDrawColor(renderer, 40, 40, 40, 255)
            var border = SDL_Rect(x: drawX - 2, y: drawY - 2, w: drawW + 4, h: drawH + 4)
            SDL_RenderDrawRect(renderer, &border)

            renderSHPFrame(renderer, frame: frame, atX: drawX, atY: drawY, scale: pixelScale)
        } else {
            drawText(renderer, "Not Found", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight / 2, color: .red, scale: 2)
        }

        let animLabel = renderState.spriteViewerAnimating ? "Playing" : "Paused"
        drawText(renderer, "Left/Right: Shape  Up/Down: Frame  Space: \(animLabel)", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 60, color: .gray, scale: 1)
        drawText(renderer, "Esc: Back", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight - 35, color: .gray, scale: 1)
    }

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            session.currentScreen = MainMenuScreen()
            return
        }
        if key == Int32(SDLK_RIGHT.rawValue) || key == Int32(SDLK_d.rawValue) {
            renderState.spriteViewerIndex = (renderState.spriteViewerIndex + 1) % viewableShapes.count
            loadCurrentSprite()
        } else if key == Int32(SDLK_LEFT.rawValue) || key == Int32(SDLK_a.rawValue) {
            renderState.spriteViewerIndex = (renderState.spriteViewerIndex - 1 + viewableShapes.count) % viewableShapes.count
            loadCurrentSprite()
        } else if key == Int32(SDLK_UP.rawValue) || key == Int32(SDLK_w.rawValue) {
            if let shp = renderState.currentSHP, shp.frames.count > 0 {
                renderState.spriteViewerFrame = (renderState.spriteViewerFrame + 1) % shp.frames.count
            }
        } else if key == Int32(SDLK_DOWN.rawValue) || key == Int32(SDLK_s.rawValue) {
            if let shp = renderState.currentSHP, shp.frames.count > 0 {
                renderState.spriteViewerFrame = (renderState.spriteViewerFrame - 1 + shp.frames.count) % shp.frames.count
            }
        } else if key == Int32(SDLK_SPACE.rawValue) {
            renderState.spriteViewerAnimating = !renderState.spriteViewerAnimating
        }
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
            if session.isPlacingStructure {
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
            renderState.gameZoomLevel = min(3.0, renderState.gameZoomLevel + 0.25)
        } else if key == Int32(SDLK_MINUS.rawValue) {
            renderState.gameZoomLevel = max(0.5, renderState.gameZoomLevel - 0.25)
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
        } else if key == Int32(SDLK_r.rawValue) {
            if session.triggerWinState != .playing {
                session.campaign.restart()
                session.triggerWinState = .playing
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
            } else {
                let shiftHeld = (SDL_GetModState().rawValue & UInt32(KMOD_SHIFT.rawValue)) != 0
                handleGameLeftDown(x, y, shiftHeld: shiftHeld)
            }
        } else if button == UInt8(SDL_BUTTON_RIGHT) {
            if session.superWeaponTargeting != nil {
                session.superWeaponTargeting = nil
            } else if session.isRepairMode || session.isSellMode {
                session.isRepairMode = false
                session.isSellMode = false
            } else if session.isPlacingStructure {
                session.isPlacingStructure = false
                session.placementType = nil
            } else {
                handleGameRightClick(x, y)
            }
        }
    }

    func handleMouseUp(_ x: Int32, _ y: Int32, button: UInt8) {
        if button == UInt8(SDL_BUTTON_LEFT) {
            if x < renderState.windowWidth - sidebarWidth && !session.isPlacingStructure {
                let shiftHeld = (SDL_GetModState().rawValue & UInt32(KMOD_SHIFT.rawValue)) != 0
                handleGameLeftUp(x, y, shiftHeld: shiftHeld)
            }
        }
    }

    func handleMouseMotion(_ x: Int32, _ y: Int32, xrel: Int32, yrel: Int32) {
        if input.selectionBoxStartX != nil {
            handleGameLeftDrag(x, y)
        }
    }

    func handleContinuousInput() {
        let panSpeed = max(1.0, 8.0 / renderState.gameZoomLevel)
        let visibleW = Double(renderState.windowWidth - sidebarWidth) / renderState.gameZoomLevel
        let visibleH = Double(renderState.windowHeight) / renderState.gameZoomLevel
        let maxCamX = Double(64 * 24) - visibleW
        let maxCamY = Double(64 * 24) - visibleH

        if let keyState = SDL_GetKeyboardState(nil) {
            if keyState[Int(SDL_SCANCODE_LEFT.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_A.rawValue)] != 0 {
                renderState.gameCameraX = max(0, renderState.gameCameraX - panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_RIGHT.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_D.rawValue)] != 0 {
                renderState.gameCameraX = min(maxCamX, renderState.gameCameraX + panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_UP.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_W.rawValue)] != 0 {
                renderState.gameCameraY = max(0, renderState.gameCameraY - panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_DOWN.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_S.rawValue)] != 0 {
                renderState.gameCameraY = min(maxCamY, renderState.gameCameraY + panSpeed)
            }
        }
    }
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
