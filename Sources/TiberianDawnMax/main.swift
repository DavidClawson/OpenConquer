import CSDL2
import Foundation

// MARK: - Game Data

let dataPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Vanilla-Conquer/vanillatd")

let mixManager = MIXFileManager()

func loadGameData() {
    print("Loading game data from: \(dataPath.path)")

    do {
        try mixManager.registerAll(in: dataPath)

        // Also check gdi/ and nod/ subdirectories
        let gdiDir = dataPath.appendingPathComponent("gdi")
        let nodDir = dataPath.appendingPathComponent("nod")
        if FileManager.default.fileExists(atPath: gdiDir.path) {
            try mixManager.registerAll(in: gdiDir)
        }
        if FileManager.default.fileExists(atPath: nodDir.path) {
            try mixManager.registerAll(in: nodDir)
        }
    } catch {
        print("Error loading MIX files: \(error)")
    }

    print("Total MIX files: \(mixManager.registeredFiles.count)")
    print("Total entries: \(mixManager.totalEntries)")
    print("")

    // Test some known filenames
    let testFiles = [
        "CONQUER.ENG",   // English language strings
        "DESERT.MIX",    // Desert theater tileset (nested MIX)
        "TRANS.ICN",     // Transparent icon
        "MOUSE.SHP",     // Mouse cursor shapes
        "OPTIONS.SHP",   // Options menu shapes
        "SIDEBAR.SHP",   // Sidebar shapes
        "STRUGGLE.AUD",  // Audio
        "CHOOSE.WSA",    // Choose side animation
        "SCG01EA.INI",   // GDI mission 1 scenario
        "TEMPERAT.PAL",  // Temperate theater palette
        "DESERT.PAL",    // Desert theater palette
    ]

    print("File lookup test:")
    for file in testFiles {
        if let location = mixManager.locate(file) {
            let data = mixManager.retrieve(file)!
            print("  \(file) -> \(location) (\(data.count) bytes)")
        } else {
            let crc = MIXFile.crc(for: file)
            print("  \(file) -> NOT FOUND (CRC: 0x\(String(UInt32(bitPattern: crc), radix: 16, uppercase: true)))")
        }
    }
    print("")
}

// Run MIX loading on startup
loadGameData()

// If --test-mix flag, just print results and exit
if CommandLine.arguments.contains("--test-mix") {
    exit(0)
}

// If --test-shp, parse and dump SHP info
if CommandLine.arguments.contains("--test-shp") {
    let testShapes = ["MOUSE.SHP", "OPTIONS.SHP", "LTNK.SHP"]
    for name in testShapes {
        print("Testing \(name)...")
        if let data = mixManager.retrieve(name) {
            let data = Data(data)
            do {
                let shp = try SHPFile(data: data)
                print("  \(shp.frames.count) frames parsed")
                for (i, frame) in shp.frames.prefix(5).enumerated() {
                    let nonZero = frame.pixels.filter { $0 != 0 }.count
                    print("  frame \(i): \(frame.width)x\(frame.height), \(nonZero) visible pixels")
                }
                // Also print frame 33 for MOUSE.SHP
                if name == "MOUSE.SHP" && shp.frames.count > 33 {
                    let f33 = shp.frames[33]
                    let nz33 = f33.pixels.filter { $0 != 0 }.count
                    print("  frame 33: \(f33.width)x\(f33.height), \(nz33) visible pixels")
                    // Print ASCII art
                    for y in 0..<f33.height {
                        var row = "  "
                        for x in 0..<f33.width {
                            let p = f33.pixels[y * f33.width + x]
                            row += p == 0 ? "." : String(format: "%X", p & 0xF)
                        }
                        print(row)
                    }
                }
                if shp.frames.count > 5 {
                    print("  ... (\(shp.frames.count - 5) more frames)")
                }
            } catch {
                print("  PARSE ERROR: \(error)")
            }
        } else {
            print("\(name): not found in MIX files")
        }
    }
    exit(0)
}

// MARK: - Palette

// Load the 256-color palette (768 bytes, 6-bit VGA RGB)
func loadPalette(_ name: String = "TEMPERAT.PAL") -> [(r: UInt8, g: UInt8, b: UInt8)] {
    guard let data = mixManager.retrieve(name), data.count >= 768 else {
        print("Warning: Could not load palette \(name), using grayscale")
        return (0..<256).map { i in (r: UInt8(i), g: UInt8(i), b: UInt8(i)) }
    }
    let palData = Data(data)
    return (0..<256).map { i in
        // 6-bit VGA (0-63) -> 8-bit (0-255): multiply by ~4
        let r6 = palData[i * 3]
        let g6 = palData[i * 3 + 1]
        let b6 = palData[i * 3 + 2]
        return (r: (r6 << 2) | (r6 >> 4), g: (g6 << 2) | (g6 >> 4), b: (b6 << 2) | (b6 >> 4))
    }
}

var gamePalette = loadPalette()

// MARK: - Scenario Discovery

/// Build a list of available scenario base names from the MIX files
func discoverScenarios() -> [String] {
    var found: [String] = []
    // GDI missions: SCG01EA through SCG15EA, plus B/C variants
    for i in 1...15 {
        let num = String(format: "%02d", i)
        for variant in ["EA", "EB", "EC"] {
            let name = "SCG\(num)\(variant)"
            if mixManager.contains("\(name).INI") {
                found.append(name)
            }
        }
    }
    // Nod missions: SCB01EA through SCB13EA, plus B/C variants
    for i in 1...13 {
        let num = String(format: "%02d", i)
        for variant in ["EA", "EB", "EC"] {
            let name = "SCB\(num)\(variant)"
            if mixManager.contains("\(name).INI") {
                found.append(name)
            }
        }
    }
    if found.isEmpty {
        found.append("SCG01EA")
    }
    return found
}

var scenarioList = discoverScenarios()
var scenarioIndex = 0

print("Discovered \(scenarioList.count) scenarios: \(scenarioList.joined(separator: ", "))")

// MARK: - Types

enum Faction: String {
    case gdi = "GDI"
    case nod = "NOD"
}

enum Difficulty: String, CaseIterable {
    case easy = "Easy"
    case normal = "Normal"
    case hard = "Hard"
}

enum MenuState {
    case main
    case chooseDifficulty
    case chooseFaction
    case launching(Faction, Difficulty)
    case spriteViewer
    case mapViewer
    case playing
}

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

// MARK: - App

let windowWidth: Int32 = 960
let windowHeight: Int32 = 600

guard SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) == 0 else {
    print("SDL_Init failed: \(String(cString: SDL_GetError()))")
    exit(1)
}

guard let window = SDL_CreateWindow(
    "Tiberian Dawn Max",
    Int32(SDL_WINDOWPOS_CENTERED_MASK),
    Int32(SDL_WINDOWPOS_CENTERED_MASK),
    windowWidth,
    windowHeight,
    SDL_WINDOW_SHOWN.rawValue | SDL_WINDOW_ALLOW_HIGHDPI.rawValue
) else {
    print("SDL_CreateWindow failed: \(String(cString: SDL_GetError()))")
    exit(1)
}

guard let renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED.rawValue | SDL_RENDERER_PRESENTVSYNC.rawValue) else {
    print("SDL_CreateRenderer failed: \(String(cString: SDL_GetError()))")
    exit(1)
}

var state: MenuState = .main
var running = true
var event = SDL_Event()
var mouseX: Int32 = 0
var mouseY: Int32 = 0
var selectedDifficulty: Difficulty = .normal
var selectedFaction: Faction = .gdi

// Mouse panning state for map viewer
var mousePanning = false
var lastMouseX: Int32 = 0
var lastMouseY: Int32 = 0

func makeMainButtons() -> [Button] {
    let bw: Int32 = 300
    let bh: Int32 = 44
    let cx = windowWidth / 2 - bw / 2
    let startY: Int32 = 200

    return [
        Button(label: "Start New Game", x: cx, y: startY, w: bw, h: bh) {
            state = .chooseDifficulty
        },
        Button(label: "Sprite Viewer", x: cx, y: startY + 60, w: bw, h: bh) {
            loadCurrentSprite()
            state = .spriteViewer
        },
        Button(label: "Map Viewer", x: cx, y: startY + 120, w: bw, h: bh) {
            loadMapViewerData(scenarioList[scenarioIndex])
            state = .mapViewer
        },
        Button(label: "Exit Game", x: cx, y: startY + 180, w: bw, h: bh) {
            running = false
        },
    ]
}

func makeDifficultyButtons() -> [Button] {
    let bw: Int32 = 200
    let bh: Int32 = 44
    let cx = windowWidth / 2 - bw / 2
    let startY: Int32 = 200

    return Difficulty.allCases.enumerated().map { i, diff in
        Button(label: diff.rawValue, x: cx, y: startY + Int32(i) * 60, w: bw, h: bh) {
            selectedDifficulty = diff
            state = .chooseFaction
        }
    }
}

func makeFactionButtons() -> [Button] {
    let bw: Int32 = 200
    let bh: Int32 = 80
    let gap: Int32 = 60
    let totalW = bw * 2 + gap
    let startX = windowWidth / 2 - totalW / 2
    let cy: Int32 = 250

    return [
        Button(label: "GDI", x: startX, y: cy, w: bw, h: bh) {
            selectedFaction = .gdi
            state = .launching(.gdi, selectedDifficulty)
        },
        Button(label: "NOD", x: startX + bw + gap, y: cy, w: bw, h: bh) {
            selectedFaction = .nod
            state = .launching(.nod, selectedDifficulty)
        },
    ]
}

// MARK: - Main loop

while running {
    // Events
    while SDL_PollEvent(&event) != 0 {
        let eventType = SDL_EventType(rawValue: event.type)
        switch eventType {
        case SDL_QUIT:
            running = false

        case SDL_KEYDOWN:
            let key = event.key.keysym.sym
            if key == Int32(SDLK_ESCAPE.rawValue) {
                switch state {
                case .main:
                    running = false
                case .chooseDifficulty:
                    state = .main
                case .chooseFaction:
                    state = .chooseDifficulty
                case .launching:
                    state = .chooseFaction
                case .spriteViewer:
                    state = .main
                case .mapViewer:
                    state = .main
                case .playing:
                    if isPlacingStructure {
                        isPlacingStructure = false
                        placementType = nil
                    } else if let world = gameWorld, !world.selectedObjects().isEmpty {
                        world.deselectAll()
                    } else {
                        state = .mapViewer
                    }
                }
            }
            // Sprite viewer controls
            if case .spriteViewer = state {
                if key == Int32(SDLK_RIGHT.rawValue) || key == Int32(SDLK_d.rawValue) {
                    spriteViewerIndex = (spriteViewerIndex + 1) % viewableShapes.count
                    loadCurrentSprite()
                } else if key == Int32(SDLK_LEFT.rawValue) || key == Int32(SDLK_a.rawValue) {
                    spriteViewerIndex = (spriteViewerIndex - 1 + viewableShapes.count) % viewableShapes.count
                    loadCurrentSprite()
                } else if key == Int32(SDLK_UP.rawValue) || key == Int32(SDLK_w.rawValue) {
                    if let shp = currentSHP, shp.frames.count > 0 {
                        spriteViewerFrame = (spriteViewerFrame + 1) % shp.frames.count
                    }
                } else if key == Int32(SDLK_DOWN.rawValue) || key == Int32(SDLK_s.rawValue) {
                    if let shp = currentSHP, shp.frames.count > 0 {
                        spriteViewerFrame = (spriteViewerFrame - 1 + shp.frames.count) % shp.frames.count
                    }
                } else if key == Int32(SDLK_SPACE.rawValue) {
                    spriteViewerAnimating = !spriteViewerAnimating
                }
            }
            // Map viewer controls: [ and ] to cycle scenarios, +/- to zoom
            if case .mapViewer = state {
                if key == Int32(SDLK_RIGHTBRACKET.rawValue) {
                    scenarioIndex = (scenarioIndex + 1) % scenarioList.count
                    loadMapViewerData(scenarioList[scenarioIndex])
                } else if key == Int32(SDLK_LEFTBRACKET.rawValue) {
                    scenarioIndex = (scenarioIndex - 1 + scenarioList.count) % scenarioList.count
                    loadMapViewerData(scenarioList[scenarioIndex])
                } else if key == Int32(SDLK_EQUALS.rawValue) {
                    zoomLevel = min(3.0, zoomLevel + 0.25)
                } else if key == Int32(SDLK_MINUS.rawValue) {
                    zoomLevel = max(0.5, zoomLevel - 0.25)
                } else if key == Int32(SDLK_g.rawValue) {
                    showGrid = !showGrid
                } else if key == Int32(SDLK_i.rawValue) {
                    showInfoPanel = !showInfoPanel
                } else if key == Int32(SDLK_t.rawValue) {
                    showCellTriggers = !showCellTriggers
                } else if key == Int32(SDLK_b.rawValue) {
                    showBaseList = !showBaseList
                } else if key == Int32(SDLK_p.rawValue) {
                    // Enter playing mode
                    if let sd = scenarioData {
                        initGameWorld(scenario: sd, scenarioName: scenarioList[scenarioIndex])
                        // Initialize game camera to match map viewer camera
                        gameCameraX = Double(cameraX)
                        gameCameraY = Double(cameraY)
                        gameZoomLevel = zoomLevel
                        lastTickTime = 0
                        tickAccumulator = 0
                        state = .playing
                    }
                } else if key >= Int32(SDLK_0.rawValue) && key <= Int32(SDLK_9.rawValue) {
                    let wpId = Int(key - Int32(SDLK_0.rawValue))
                    if let sd = scenarioData,
                       let wp = sd.waypoints.first(where: { $0.id == wpId }) {
                        let pos = cellToPixel(wp.cell)
                        cameraX = pos.px - Int(Double(windowWidth) / zoomLevel) / 2
                        cameraY = pos.py - Int(Double(windowHeight) / zoomLevel) / 2
                        // Clamp camera
                        let visW = Int(Double(windowWidth) / zoomLevel)
                        let visH = Int(Double(windowHeight) / zoomLevel)
                        let maxCX = 64 * 24 - visW
                        let maxCY = 64 * 24 - visH
                        cameraX = max(0, min(maxCX, cameraX))
                        cameraY = max(0, min(maxCY, cameraY))
                    }
                }
            }
            // Playing state key controls
            if case .playing = state {
                if key == Int32(SDLK_EQUALS.rawValue) {
                    gameZoomLevel = min(3.0, gameZoomLevel + 0.25)
                } else if key == Int32(SDLK_MINUS.rawValue) {
                    gameZoomLevel = max(0.5, gameZoomLevel - 0.25)
                }
            }

        case SDL_MOUSEMOTION:
            mouseX = event.motion.x
            mouseY = event.motion.y
            // Update world coordinates for info panel
            if case .mapViewer = state {
                mouseWorldX = cameraX + Int(Double(event.motion.x) / zoomLevel)
                mouseWorldY = cameraY + Int(Double(event.motion.y) / zoomLevel)
            }
            // Drag select tracking in playing mode
            if case .playing = state {
                if selectionBoxStartX != nil {
                    handleGameLeftDrag(event.motion.x, event.motion.y)
                }
            }
            // Mouse panning in map viewer
            if case .mapViewer = state, mousePanning {
                let dx = event.motion.xrel
                let dy = event.motion.yrel
                cameraX -= Int(Double(dx) / zoomLevel)
                cameraY -= Int(Double(dy) / zoomLevel)
                // Clamp
                let visW = Int(Double(windowWidth) / zoomLevel)
                let visH = Int(Double(windowHeight) / zoomLevel)
                let maxCX = 64 * 24 - visW
                let maxCY = 64 * 24 - visH
                cameraX = max(0, min(maxCX, cameraX))
                cameraY = max(0, min(maxCY, cameraY))
            }

        case SDL_MOUSEBUTTONUP:
            if event.button.button == UInt8(SDL_BUTTON_LEFT) {
                mousePanning = false
                if case .playing = state {
                    if event.button.x < windowWidth - sidebarWidth && !isPlacingStructure {
                        let shiftHeld = (SDL_GetModState().rawValue & UInt32(KMOD_SHIFT.rawValue)) != 0
                        handleGameLeftUp(event.button.x, event.button.y, shiftHeld: shiftHeld)
                    }
                }
            }

        case SDL_MOUSEBUTTONDOWN:
            if event.button.button == UInt8(SDL_BUTTON_LEFT) {
                // Start mouse panning in map viewer
                if case .mapViewer = state {
                    mousePanning = true
                    lastMouseX = event.button.x
                    lastMouseY = event.button.y
                }

                // Start selection in playing mode
                if case .playing = state {
                    // Check if click is in sidebar area
                    if event.button.x >= windowWidth - sidebarWidth {
                        handleSidebarClick(event.button.x, event.button.y)
                    } else if isPlacingStructure {
                        handleStructurePlacement(event.button.x, event.button.y)
                    } else {
                        let shiftHeld = (SDL_GetModState().rawValue & UInt32(KMOD_SHIFT.rawValue)) != 0
                        handleGameLeftDown(event.button.x, event.button.y, shiftHeld: shiftHeld)
                    }
                }

                let buttons: [Button]
                switch state {
                case .main: buttons = makeMainButtons()
                case .chooseDifficulty: buttons = makeDifficultyButtons()
                case .chooseFaction: buttons = makeFactionButtons()
                case .spriteViewer: buttons = []
                case .mapViewer: buttons = []
                case .launching: buttons = []
                case .playing: buttons = []
                }
                for btn in buttons {
                    if btn.contains(mouseX, mouseY) {
                        btn.action()
                        break
                    }
                }
            }
            // Right click for move order in playing mode (or cancel placement)
            if event.button.button == UInt8(SDL_BUTTON_RIGHT) {
                if case .playing = state {
                    if isPlacingStructure {
                        isPlacingStructure = false
                        placementType = nil
                    } else {
                        handleGameRightClick(event.button.x, event.button.y)
                    }
                }
            }

        default:
            break
        }
    }

    // Map viewer camera panning (continuous key state)
    if case .mapViewer = state {
        let panSpeed = max(1, Int(8.0 / zoomLevel))
        let visibleW = Int(Double(windowWidth) / zoomLevel)
        let visibleH = Int(Double(windowHeight) / zoomLevel)
        let maxCameraX = 64 * 24 - visibleW
        let maxCameraY = 64 * 24 - visibleH

        if let keyState = SDL_GetKeyboardState(nil) {
            if keyState[Int(SDL_SCANCODE_LEFT.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_A.rawValue)] != 0 {
                cameraX = max(0, cameraX - panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_RIGHT.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_D.rawValue)] != 0 {
                cameraX = min(maxCameraX, cameraX + panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_UP.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_W.rawValue)] != 0 {
                cameraY = max(0, cameraY - panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_DOWN.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_S.rawValue)] != 0 {
                cameraY = min(maxCameraY, cameraY + panSpeed)
            }
        }
    }

    // Playing state camera panning (continuous key state)
    if case .playing = state {
        let panSpeed = max(1.0, 8.0 / gameZoomLevel)
        let visibleW = Double(windowWidth - sidebarWidth) / gameZoomLevel
        let visibleH = Double(windowHeight) / gameZoomLevel
        let maxCamX = Double(64 * 24) - visibleW
        let maxCamY = Double(64 * 24) - visibleH

        if let keyState = SDL_GetKeyboardState(nil) {
            if keyState[Int(SDL_SCANCODE_LEFT.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_A.rawValue)] != 0 {
                gameCameraX = max(0, gameCameraX - panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_RIGHT.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_D.rawValue)] != 0 {
                gameCameraX = min(maxCamX, gameCameraX + panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_UP.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_W.rawValue)] != 0 {
                gameCameraY = max(0, gameCameraY - panSpeed)
            }
            if keyState[Int(SDL_SCANCODE_DOWN.rawValue)] != 0 || keyState[Int(SDL_SCANCODE_S.rawValue)] != 0 {
                gameCameraY = min(maxCamY, gameCameraY + panSpeed)
            }
        }
    }

    // Update game logic in playing state
    if case .playing = state {
        updateGame()
    }

    // Render
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
    SDL_RenderClear(renderer)

    switch state {
    case .main:
        drawText(renderer, "Command & Conquer", centerX: windowWidth / 2, centerY: 80, color: .amber, scale: 4)
        drawText(renderer, "Tiberian Dawn Max", centerX: windowWidth / 2, centerY: 140, color: .green, scale: 3)

        for btn in makeMainButtons() {
            btn.draw(renderer, highlighted: btn.contains(mouseX, mouseY))
        }

        drawText(renderer, "R964", centerX: windowWidth / 2, centerY: windowHeight - 40, color: .gray, scale: 1)

    case .chooseDifficulty:
        drawText(renderer, "Select Difficulty", centerX: windowWidth / 2, centerY: 120, color: .amber, scale: 3)

        for btn in makeDifficultyButtons() {
            btn.draw(renderer, highlighted: btn.contains(mouseX, mouseY))
        }

        drawText(renderer, "Esc: Back", centerX: windowWidth / 2, centerY: windowHeight - 40, color: .gray, scale: 1)

    case .chooseFaction:
        drawText(renderer, "Choose Your Side", centerX: windowWidth / 2, centerY: 100, color: .amber, scale: 3)
        drawText(renderer, "Difficulty: \(selectedDifficulty.rawValue)", centerX: windowWidth / 2, centerY: 160, color: .green, scale: 2)

        for btn in makeFactionButtons() {
            let isGDI = btn.label == "GDI"
            let highlighted = btn.contains(mouseX, mouseY)
            btn.draw(renderer, highlighted: highlighted)
            // Subtitle
            let subtitle = isGDI ? "Global Defense Initiative" : "Brotherhood of Nod"
            drawText(renderer, subtitle, centerX: btn.x + btn.w / 2, centerY: btn.y + btn.h + 20, color: isGDI ? .amber : .red, scale: 1)
        }

        drawText(renderer, "Esc: Back", centerX: windowWidth / 2, centerY: windowHeight - 40, color: .gray, scale: 1)

    case .launching(let faction, let difficulty):
        drawText(renderer, "Launching...", centerX: windowWidth / 2, centerY: windowHeight / 2 - 40, color: .green, scale: 3)
        drawText(renderer, "\(faction.rawValue) / \(difficulty.rawValue)", centerX: windowWidth / 2, centerY: windowHeight / 2 + 20, color: .amber, scale: 2)

        // TODO: Actually launch game engine here
        drawText(renderer, "Game engine not yet connected", centerX: windowWidth / 2, centerY: windowHeight / 2 + 70, color: .gray, scale: 1)
        drawText(renderer, "Esc: Back", centerX: windowWidth / 2, centerY: windowHeight - 40, color: .gray, scale: 1)

    case .spriteViewer:
        let shapeName = viewableShapes[spriteViewerIndex]

        // Title and info
        drawText(renderer, "Sprite Viewer", centerX: windowWidth / 2, centerY: 30, color: .amber, scale: 3)
        drawText(renderer, shapeName, centerX: windowWidth / 2, centerY: 70, color: .green, scale: 2)

        if let shp = currentSHP, !shp.frames.isEmpty {
            // Auto-animate
            let now = SDL_GetTicks()
            if spriteViewerAnimating && now - spriteViewerFrameTimer > 100 {
                spriteViewerFrameTimer = now
                spriteViewerFrame = (spriteViewerFrame + 1) % shp.frames.count
            }

            let frame = shp.frames[spriteViewerFrame]
            let info = "Frame \(spriteViewerFrame)/\(shp.frames.count)  \(frame.width)x\(frame.height)"
            drawText(renderer, info, centerX: windowWidth / 2, centerY: 100, color: .green, scale: 1)

            // Calculate scale to fit sprite nicely
            let maxDisplayW: Int32 = 400
            let maxDisplayH: Int32 = 350
            let scaleX = frame.width > 0 ? maxDisplayW / Int32(frame.width) : 1
            let scaleY = frame.height > 0 ? maxDisplayH / Int32(frame.height) : 1
            let pixelScale = max(1, min(scaleX, scaleY))

            let drawW = Int32(frame.width) * pixelScale
            let drawH = Int32(frame.height) * pixelScale
            let drawX = windowWidth / 2 - drawW / 2
            let drawY: Int32 = 130 + (maxDisplayH - drawH) / 2

            // Draw a subtle border around the sprite area
            SDL_SetRenderDrawColor(renderer, 40, 40, 40, 255)
            var border = SDL_Rect(x: drawX - 2, y: drawY - 2, w: drawW + 4, h: drawH + 4)
            SDL_RenderDrawRect(renderer, &border)

            // Render the sprite
            renderSHPFrame(renderer, frame: frame, atX: drawX, atY: drawY, scale: pixelScale)
        } else {
            drawText(renderer, "Not Found", centerX: windowWidth / 2, centerY: windowHeight / 2, color: .red, scale: 2)
        }

        // Controls
        let animLabel = spriteViewerAnimating ? "Playing" : "Paused"
        drawText(renderer, "Left/Right: Shape  Up/Down: Frame  Space: \(animLabel)", centerX: windowWidth / 2, centerY: windowHeight - 60, color: .gray, scale: 1)
        drawText(renderer, "Esc: Back", centerX: windowWidth / 2, centerY: windowHeight - 35, color: .gray, scale: 1)

    case .mapViewer:
        // Increment animation frame for terrain (trees etc.)
        animationFrame += 1

        // Render the map tiles + scenario objects
        renderMapViewer(renderer)

        // HUD overlay
        let cellX = cameraX / 24
        let cellY = cameraY / 24
        let scenarioLabel = "\(scenarioList[scenarioIndex]) (\(scenarioIndex + 1)/\(scenarioList.count))"
        drawText(renderer, "Map Viewer - \(scenarioLabel)", centerX: windowWidth / 2, centerY: 15, color: .amber, scale: 2)
        let zoomPct = String(format: "%.0f%%", zoomLevel * 100)
        drawText(renderer, "Camera: \(cellX) \(cellY)  Zoom: \(zoomPct)", centerX: windowWidth / 2, centerY: 35, color: .green, scale: 1)
        if let sd = scenarioData {
            let counts = "T:\(sd.terrain.count) O:\(sd.overlays.count) S:\(sd.structures.count) U:\(sd.units.count) I:\(sd.infantry.count)"
            drawText(renderer, counts, centerX: windowWidth / 2, centerY: 52, color: .green, scale: 1)
        }
        drawText(renderer, "Arrows/Drag: Pan  +/-: Zoom  [/]: Scenario  G: Grid  I: Info  T: Triggers  B: Base  P: Play  0-9: WP", centerX: windowWidth / 2, centerY: windowHeight - 15, color: .gray, scale: 1)

    case .playing:
        renderGame(renderer)
    }

    SDL_RenderPresent(renderer)
    SDL_Delay(16) // ~60fps
}

SDL_DestroyRenderer(renderer)
SDL_DestroyWindow(window)
SDL_Quit()
