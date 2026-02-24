import CSDL2
import Foundation

// MARK: - Game Data

let dataPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Vanilla-Conquer/vanillatd")

let assetManager = AssetManager(dataPath: dataPath)

/// Temporary shim — existing code references `mixManager` everywhere.
/// New code should use `assetManager.retrieve()` instead.
var mixManager: MIXFileManager { assetManager.mixManager }

func loadGameData() {
    assetManager.initialize()

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

// Index remastered sprites (if available)
initRemasteredSprites()

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

session.scenarioList = discoverScenarios()

print("Discovered \(session.scenarioList.count) scenarios: \(session.scenarioList.joined(separator: ", "))")

// MARK: - App

guard SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS | SDL_INIT_AUDIO) == 0 else {
    print("SDL_Init failed: \(String(cString: SDL_GetError()))")
    exit(1)
}

guard let window = SDL_CreateWindow(
    "Tiberian Dawn Max",
    Int32(SDL_WINDOWPOS_CENTERED_MASK),
    Int32(SDL_WINDOWPOS_CENTERED_MASK),
    renderState.windowWidth,
    renderState.windowHeight,
    SDL_WINDOW_SHOWN.rawValue | SDL_WINDOW_ALLOW_HIGHDPI.rawValue | SDL_WINDOW_RESIZABLE.rawValue
) else {
    print("SDL_CreateWindow failed: \(String(cString: SDL_GetError()))")
    exit(1)
}

guard let renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED.rawValue | SDL_RENDERER_PRESENTVSYNC.rawValue) else {
    print("SDL_CreateRenderer failed: \(String(cString: SDL_GetError()))")
    exit(1)
}

// Initialize audio system
audioManager.initialize()
audioManager.soundLibrary = SoundLibrary(assetManager: assetManager)

var event = SDL_Event()

// MARK: - Main Loop

while session.running {
    perf.beginFrame()

    // Events
    while SDL_PollEvent(&event) != 0 {
        let eventType = SDL_EventType(rawValue: event.type)
        switch eventType {
        case SDL_QUIT:
            session.running = false
        case SDL_KEYDOWN:
            handleKeyDown(event.key.keysym.sym)
        case SDL_MOUSEMOTION:
            handleMouseMotion(event)
        case SDL_MOUSEBUTTONDOWN:
            handleMouseButtonDown(event)
        case SDL_MOUSEBUTTONUP:
            handleMouseButtonUp(event)
        case SDL_WINDOWEVENT:
            handleWindowEvent(event)
        default:
            break
        }
    }

    // Continuous input (camera panning)
    handleContinuousInput()

    // Update game logic in playing state
    if case .playing = session.menuState {
        perf.beginSection("Logic")
        updateGame()
        perf.endSection("Logic")
    }

    // Tick audio system (mix and queue output)
    perf.beginSection("Audio")
    audioManager.tick()
    perf.endSection("Audio")

    // Render
    perf.beginSection("Render")
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
    SDL_RenderClear(renderer)

    renderMenuState(renderer, state: session.menuState)

    perf.endSection("Render")

    // Performance overlay (F3 to toggle)
    perf.renderOverlay(renderer)
    perf.endFrame()

    SDL_RenderPresent(renderer)
    SDL_Delay(16) // ~60fps
}

audioManager.shutdown()
SDL_DestroyRenderer(renderer)
SDL_DestroyWindow(window)
SDL_Quit()
