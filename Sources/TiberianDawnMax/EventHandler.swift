import CSDL2
import Foundation

// MARK: - Event Handling

func handleKeyDown(_ key: Int32) {
    if key == Int32(SDLK_ESCAPE.rawValue) {
        switch menuState {
        case .main:
            running = false
        case .chooseDifficulty:
            menuState = .main
        case .chooseFaction:
            menuState = .chooseDifficulty
        case .launching:
            menuState = .chooseFaction
        case .spriteViewer:
            menuState = .main
        case .soundTest:
            menuState = .main
        case .mapViewer:
            menuState = .main
        case .playing:
            if session.isPlacingStructure {
                session.isPlacingStructure = false
                session.placementType = nil
            } else if let world = session.world, !world.selectedObjects().isEmpty {
                world.deselectAll()
            } else {
                menuState = .mapViewer
                // Restore system cursor when leaving game
                SDL_ShowCursor(SDL_ENABLE)
                renderState.systemCursorHidden = false
            }
        }
    }
    // Global: F3 toggles performance overlay
    if key == Int32(SDLK_F3.rawValue) {
        renderState.perfShowOverlay.toggle()
    }
    // Sprite viewer controls
    if case .spriteViewer = menuState {
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
    // Sound test controls
    if case .soundTest = menuState {
        handleSoundTestKey(key)
    }
    // Map viewer controls: [ and ] to cycle scenarios, +/- to zoom
    if case .mapViewer = menuState {
        if key == Int32(SDLK_RIGHTBRACKET.rawValue) {
            scenarioIndex = (scenarioIndex + 1) % scenarioList.count
            loadMapViewerData(scenarioList[scenarioIndex])
        } else if key == Int32(SDLK_LEFTBRACKET.rawValue) {
            scenarioIndex = (scenarioIndex - 1 + scenarioList.count) % scenarioList.count
            loadMapViewerData(scenarioList[scenarioIndex])
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
            // Enter playing mode
            if let sd = scenarioData {
                let scenName = scenarioList[scenarioIndex]
                initGameWorld(scenario: sd, scenarioName: scenName)
                session.currentScenarioName = scenName
                // Initialize game camera to match map viewer camera
                renderState.gameCameraX = Double(renderState.cameraX)
                renderState.gameCameraY = Double(renderState.cameraY)
                renderState.gameZoomLevel = renderState.zoomLevel
                session.lastTickTime = 0
                session.tickAccumulator = 0
                session.missionScore.reset()
                menuState = .playing
            }
        } else if key >= Int32(SDLK_0.rawValue) && key <= Int32(SDLK_9.rawValue) {
            let wpId = Int(key - Int32(SDLK_0.rawValue))
            if let sd = scenarioData,
               let wp = sd.waypoints.first(where: { $0.id == wpId }) {
                let pos = cellToPixel(wp.cell)
                renderState.cameraX = pos.px - Int(Double(renderState.windowWidth) / renderState.zoomLevel) / 2
                renderState.cameraY = pos.py - Int(Double(renderState.windowHeight) / renderState.zoomLevel) / 2
                // Clamp camera
                let visW = Int(Double(renderState.windowWidth) / renderState.zoomLevel)
                let visH = Int(Double(renderState.windowHeight) / renderState.zoomLevel)
                let maxCX = 64 * 24 - visW
                let maxCY = 64 * 24 - visH
                renderState.cameraX = max(0, min(maxCX, renderState.cameraX))
                renderState.cameraY = max(0, min(maxCY, renderState.cameraY))
            }
        }
    }
    // Playing state key controls
    if case .playing = menuState {
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
        } else if key == Int32(SDLK_r.rawValue) {
            // Restart mission
            if session.triggerWinState != .playing {
                restartMission()
                session.triggerWinState = .playing
            }
        } else if key == Int32(SDLK_n.rawValue) {
            // Next mission (after win)
            if session.triggerWinState == .won && session.campaignState.isActive {
                handleMissionWin()
                if !session.campaignState.isComplete {
                    if startNextMission() {
                        session.triggerWinState = .playing
                    }
                } else {
                    menuState = .main
                }
            }
        }
    }
}

func handleMouseMotion(_ event: SDL_Event) {
    input.mouseX = event.motion.x
    input.mouseY = event.motion.y
    // Update world coordinates for info panel
    if case .mapViewer = menuState {
        input.mouseWorldX = renderState.cameraX + Int(Double(event.motion.x) / renderState.zoomLevel)
        input.mouseWorldY = renderState.cameraY + Int(Double(event.motion.y) / renderState.zoomLevel)
    }
    // Drag select tracking in playing mode
    if case .playing = menuState {
        if input.selectionBoxStartX != nil {
            handleGameLeftDrag(event.motion.x, event.motion.y)
        }
    }
    // Mouse panning in map viewer
    if case .mapViewer = menuState, input.isPanning {
        let dx = event.motion.xrel
        let dy = event.motion.yrel
        renderState.cameraX -= Int(Double(dx) / renderState.zoomLevel)
        renderState.cameraY -= Int(Double(dy) / renderState.zoomLevel)
        // Clamp
        let visW = Int(Double(renderState.windowWidth) / renderState.zoomLevel)
        let visH = Int(Double(renderState.windowHeight) / renderState.zoomLevel)
        let maxCX = 64 * 24 - visW
        let maxCY = 64 * 24 - visH
        renderState.cameraX = max(0, min(maxCX, renderState.cameraX))
        renderState.cameraY = max(0, min(maxCY, renderState.cameraY))
    }
}

func handleMouseButtonUp(_ event: SDL_Event) {
    if event.button.button == UInt8(SDL_BUTTON_LEFT) {
        input.isPanning = false
        if case .playing = menuState {
            if event.button.x < renderState.windowWidth - sidebarWidth && !session.isPlacingStructure {
                let shiftHeld = (SDL_GetModState().rawValue & UInt32(KMOD_SHIFT.rawValue)) != 0
                handleGameLeftUp(event.button.x, event.button.y, shiftHeld: shiftHeld)
            }
        }
    }
}

func handleMouseButtonDown(_ event: SDL_Event) {
    if event.button.button == UInt8(SDL_BUTTON_LEFT) {
        // Start mouse panning in map viewer
        if case .mapViewer = menuState {
            input.isPanning = true
            input.lastMouseX = event.button.x
            input.lastMouseY = event.button.y
        }

        // Start selection in playing mode
        if case .playing = menuState {
            // Check if click is in sidebar area
            if event.button.x >= renderState.windowWidth - sidebarWidth {
                // Check super weapon buttons first
                if handleSuperWeaponClick(event.button.x, event.button.y) {
                    // Handled
                } else if !handleRepairSellClick(event.button.x, event.button.y) {
                    handleSidebarClick(event.button.x, event.button.y)
                }
            } else if session.superWeaponTargeting != nil {
                // Super weapon targeting: deploy at clicked position
                let worldPos = gameScreenToWorld(event.button.x, event.button.y)
                if !handleSuperWeaponGameClick(worldX: worldPos.worldX, worldY: worldPos.worldY) {
                    session.superWeaponTargeting = nil
                }
            } else if session.isPlacingStructure {
                handleStructurePlacement(event.button.x, event.button.y)
            } else if session.isRepairMode || session.isSellMode {
                // Repair/sell mode: click on building in game world
                let worldPos = gameScreenToWorld(event.button.x, event.button.y)
                if !handleRepairSellGameClick(worldX: worldPos.worldX, worldY: worldPos.worldY) {
                    // Clicked on non-building — cancel mode
                    session.isRepairMode = false
                    session.isSellMode = false
                }
            } else {
                let shiftHeld = (SDL_GetModState().rawValue & UInt32(KMOD_SHIFT.rawValue)) != 0
                handleGameLeftDown(event.button.x, event.button.y, shiftHeld: shiftHeld)
            }
        }

        let buttons: [Button]
        switch menuState {
        case .main: buttons = makeMainButtons()
        case .chooseDifficulty: buttons = makeDifficultyButtons()
        case .chooseFaction: buttons = makeFactionButtons()
        case .spriteViewer: buttons = []
        case .soundTest: buttons = []
        case .mapViewer: buttons = []
        case .launching: buttons = []
        case .playing: buttons = []
        }
        for btn in buttons {
            if btn.contains(input.mouseX, input.mouseY) {
                btn.action()
                break
            }
        }
    }
    // Right click for move order in playing mode (or cancel placement)
    if event.button.button == UInt8(SDL_BUTTON_RIGHT) {
        if case .playing = menuState {
            if session.superWeaponTargeting != nil {
                session.superWeaponTargeting = nil
            } else if session.isRepairMode || session.isSellMode {
                session.isRepairMode = false
                session.isSellMode = false
            } else if session.isPlacingStructure {
                session.isPlacingStructure = false
                session.placementType = nil
            } else {
                handleGameRightClick(event.button.x, event.button.y)
            }
        }
    }
}

func handleWindowEvent(_ event: SDL_Event) {
    if event.window.event == UInt8(SDL_WINDOWEVENT_RESIZED.rawValue) {
        renderState.windowWidth = event.window.data1
        renderState.windowHeight = event.window.data2
    }
}

// MARK: - Continuous Input (Camera Panning)

func handleContinuousInput() {
    // Map viewer camera panning (continuous key state)
    if case .mapViewer = menuState {
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

    // Playing state camera panning (continuous key state)
    if case .playing = menuState {
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
