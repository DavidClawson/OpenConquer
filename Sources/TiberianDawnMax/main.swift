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
        fflush(stdout)
        if let data = mixManager.retrieve(name) {
            print("\(name): \(data.count) bytes raw data")
            fflush(stdout)
            // Re-base data to start at index 0 (MIX returns a slice with non-zero startIndex)
            let data = Data(data)
            // Dump first 32 bytes for debugging
            let header = data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
            print("  header: \(header)")
            fflush(stdout)
            // Parse numshapes and first offset manually
            let numShapes = Int(data[0]) | (Int(data[1]) << 8)
            print("  numShapes: \(numShapes)")
            if numShapes > 0 && data.count >= 6 {
                let off0 = Int(data[2]) | (Int(data[3]) << 8) | (Int(data[4]) << 16) | (Int(data[5]) << 24)
                print("  offset[0]: \(off0)")
                let shapeStart = 2 + off0
                if shapeStart + 10 < data.count {
                    let shapeType = Int(data[shapeStart]) | (Int(data[shapeStart+1]) << 8)
                    let h = Int(data[shapeStart+2])
                    let w = Int(data[shapeStart+3]) | (Int(data[shapeStart+4]) << 8)
                    print("  frame0: type=\(shapeType) w=\(w) h=\(h)")
                }
            }
            do {
                let shp = try SHPFile(data: data)
                print("  \(shp.frames.count) frames parsed")
                for (i, frame) in shp.frames.prefix(5).enumerated() {
                    let nonZero = frame.pixels.filter { $0 != 0 }.count
                    print("  frame \(i): \(frame.width)x\(frame.height), \(nonZero) visible pixels")
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

let gamePalette = loadPalette()

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
}

// MARK: - Sprite Viewer State

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

// MARK: - Colors (C&C palette style)

struct Color {
    let r: UInt8, g: UInt8, b: UInt8, a: UInt8

    static let black       = Color(r: 0,   g: 0,   b: 0,   a: 255)
    static let darkGreen   = Color(r: 0,   g: 100, b: 0,   a: 255)
    static let green       = Color(r: 0,   g: 180, b: 0,   a: 255)
    static let brightGreen = Color(r: 0,   g: 255, b: 0,   a: 255)
    static let amber       = Color(r: 200, g: 160, b: 0,   a: 255)
    static let red         = Color(r: 180, g: 0,   b: 0,   a: 255)
    static let gray        = Color(r: 120, g: 120, b: 120, a: 255)
    static let white       = Color(r: 255, g: 255, b: 255, a: 255)
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

// MARK: - Simple text rendering (pixel font)

// 5x7 pixel font for uppercase + digits + space
let glyphs: [Character: [[Bool]]] = buildGlyphTable()

func buildGlyphTable() -> [Character: [[Bool]]] {
    // Each glyph is 5 wide x 7 tall, encoded as strings for readability
    func g(_ rows: [String]) -> [[Bool]] {
        rows.map { row in row.map { $0 == "#" } }
    }

    return [
        "A": g(["_###_", "#___#", "#___#", "#####", "#___#", "#___#", "#___#"]),
        "B": g(["####_", "#___#", "#___#", "####_", "#___#", "#___#", "####_"]),
        "C": g(["_####", "#____", "#____", "#____", "#____", "#____", "_####"]),
        "D": g(["####_", "#___#", "#___#", "#___#", "#___#", "#___#", "####_"]),
        "E": g(["#####", "#____", "#____", "####_", "#____", "#____", "#####"]),
        "F": g(["#####", "#____", "#____", "####_", "#____", "#____", "#____"]),
        "G": g(["_####", "#____", "#____", "#_###", "#___#", "#___#", "_####"]),
        "H": g(["#___#", "#___#", "#___#", "#####", "#___#", "#___#", "#___#"]),
        "I": g(["#####", "__#__", "__#__", "__#__", "__#__", "__#__", "#####"]),
        "J": g(["__###", "___#_", "___#_", "___#_", "___#_", "#__#_", "_##__"]),
        "K": g(["#___#", "#__#_", "#_#__", "##___", "#_#__", "#__#_", "#___#"]),
        "L": g(["#____", "#____", "#____", "#____", "#____", "#____", "#####"]),
        "M": g(["#___#", "##_##", "#_#_#", "#___#", "#___#", "#___#", "#___#"]),
        "N": g(["#___#", "##__#", "#_#_#", "#__##", "#___#", "#___#", "#___#"]),
        "O": g(["_###_", "#___#", "#___#", "#___#", "#___#", "#___#", "_###_"]),
        "P": g(["####_", "#___#", "#___#", "####_", "#____", "#____", "#____"]),
        "Q": g(["_###_", "#___#", "#___#", "#___#", "#_#_#", "#__#_", "_##_#"]),
        "R": g(["####_", "#___#", "#___#", "####_", "#_#__", "#__#_", "#___#"]),
        "S": g(["_####", "#____", "#____", "_###_", "____#", "____#", "####_"]),
        "T": g(["#####", "__#__", "__#__", "__#__", "__#__", "__#__", "__#__"]),
        "U": g(["#___#", "#___#", "#___#", "#___#", "#___#", "#___#", "_###_"]),
        "V": g(["#___#", "#___#", "#___#", "#___#", "_#_#_", "_#_#_", "__#__"]),
        "W": g(["#___#", "#___#", "#___#", "#___#", "#_#_#", "##_##", "#___#"]),
        "X": g(["#___#", "#___#", "_#_#_", "__#__", "_#_#_", "#___#", "#___#"]),
        "Y": g(["#___#", "#___#", "_#_#_", "__#__", "__#__", "__#__", "__#__"]),
        "Z": g(["#####", "____#", "___#_", "__#__", "_#___", "#____", "#####"]),
        "0": g(["_###_", "#___#", "#__##", "#_#_#", "##__#", "#___#", "_###_"]),
        "1": g(["__#__", "_##__", "__#__", "__#__", "__#__", "__#__", "#####"]),
        "2": g(["_###_", "#___#", "____#", "__##_", "_#___", "#____", "#####"]),
        "3": g(["_###_", "#___#", "____#", "_###_", "____#", "#___#", "_###_"]),
        "4": g(["#___#", "#___#", "#___#", "#####", "____#", "____#", "____#"]),
        "5": g(["#####", "#____", "####_", "____#", "____#", "#___#", "_###_"]),
        "6": g(["_###_", "#____", "#____", "####_", "#___#", "#___#", "_###_"]),
        "7": g(["#####", "____#", "___#_", "__#__", "_#___", "_#___", "_#___"]),
        "8": g(["_###_", "#___#", "#___#", "_###_", "#___#", "#___#", "_###_"]),
        "9": g(["_###_", "#___#", "#___#", "_####", "____#", "____#", "_###_"]),
        " ": g(["_____", "_____", "_____", "_____", "_____", "_____", "_____"]),
        ":": g(["_____", "__#__", "__#__", "_____", "__#__", "__#__", "_____"]),
        "-": g(["_____", "_____", "_____", "#####", "_____", "_____", "_____"]),
        "&": g(["_##__", "#__#_", "#_#__", "_#___", "#_#_#", "#__#_", "_##_#"]),
        "/": g(["____#", "___#_", "___#_", "__#__", "_#___", "_#___", "#____"]),
        "'": g(["__#__", "__#__", "_#___", "_____", "_____", "_____", "_____"]),
    ]
}

func drawText(_ renderer: OpaquePointer?, _ text: String, centerX: Int32, centerY: Int32, color: Color, scale: Int32 = 2) {
    let charW: Int32 = 5 * scale + scale  // 5 pixels + 1 pixel gap, scaled
    let charH: Int32 = 7 * scale
    let totalW = Int32(text.count) * charW
    var cursorX = centerX - totalW / 2
    let cursorY = centerY - charH / 2

    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)

    for ch in text.uppercased() {
        if let glyph = glyphs[ch] {
            for (row, rowData) in glyph.enumerated() {
                for (col, on) in rowData.enumerated() {
                    if on {
                        var pixel = SDL_Rect(
                            x: cursorX + Int32(col) * scale,
                            y: cursorY + Int32(row) * scale,
                            w: scale,
                            h: scale
                        )
                        SDL_RenderFillRect(renderer, &pixel)
                    }
                }
            }
        }
        cursorX += charW
    }
}

func drawTextLeft(_ renderer: OpaquePointer?, _ text: String, x: Int32, y: Int32, color: Color, scale: Int32 = 2) {
    let charW: Int32 = 5 * scale + scale
    let charH: Int32 = 7 * scale
    let totalW = Int32(text.count) * charW
    // Reuse centered drawing with adjusted center
    drawText(renderer, text, centerX: x + totalW / 2, centerY: y + charH / 2, color: color, scale: scale)
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
        Button(label: "Exit Game", x: cx, y: startY + 120, w: bw, h: bh) {
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

        case SDL_MOUSEMOTION:
            mouseX = event.motion.x
            mouseY = event.motion.y

        case SDL_MOUSEBUTTONDOWN:
            if event.button.button == UInt8(SDL_BUTTON_LEFT) {
                let buttons: [Button]
                switch state {
                case .main: buttons = makeMainButtons()
                case .chooseDifficulty: buttons = makeDifficultyButtons()
                case .chooseFaction: buttons = makeFactionButtons()
                case .spriteViewer: buttons = []
                case .launching: buttons = []
                }
                for btn in buttons {
                    if btn.contains(mouseX, mouseY) {
                        btn.action()
                        break
                    }
                }
            }

        default:
            break
        }
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
    }

    SDL_RenderPresent(renderer)
    SDL_Delay(16) // ~60fps
}

SDL_DestroyRenderer(renderer)
SDL_DestroyWindow(window)
SDL_Quit()
