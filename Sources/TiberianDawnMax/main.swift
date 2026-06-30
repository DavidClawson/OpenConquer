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
        "HMMV.SHP",      // Humvee (iniName — not in MIX, use JEEP.SHP)
        "JEEP.SHP",      // Humvee (actual SHP name)
        "APC.SHP",       // APC
        "MTNK.SHP",      // Medium Tank
        "E1.SHP",        // Minigunner
        "BOAT.SHP",      // Gunboat
        "HOVER.SHP",     // Hovercraft
        "LST.SHP",       // Landing Ship Tank (alternative hovercraft name?)
        "MUZZFLSH.SHP",  // Muzzle flash animation
        "PIFF.SHP",      // Impact piff
        "VEH-HIT1.SHP",  // Vehicle hit explosion
        "FBALL1.SHP",    // Fireball explosion
        "FRAG1.SHP",     // Fragment explosion
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

// Apply any data overrides from extracted/data/*.json (modder hook).
// Must run after MIX init (so the compiled tables exist) and before any
// game world is built (so resolveSpeed/resolveStrength see the new values).
loadDataOverrides()

// Index remastered sprites (if available)
initRemasteredSprites()

// If --test-mix flag, just print results and exit
if CommandLine.arguments.contains("--test-mix") {
    exit(0)
}

// Diagnostic: --dump-scenario <NAME>  prints map bounds, waypoints, etc.
if let dumpIdx = CommandLine.arguments.firstIndex(of: "--dump-scenario"),
   dumpIdx + 1 < CommandLine.arguments.count {
    let scen = CommandLine.arguments[dumpIdx + 1]
    if let data = loadScenario("\(scen).INI", from: mixManager) {
        print("--- \(scen) ---")
        if let b = data.mapBounds {
            print("MapBounds: x=\(b.x) y=\(b.y) w=\(b.width) h=\(b.height)  pixW=\(b.width*24) pixH=\(b.height*24)")
        } else {
            print("MapBounds: nil")
        }
        for wp in data.waypoints where [98, 99, 25, 26, 27].contains(wp.id) {
            let cellX = wp.cell % 64
            let cellY = wp.cell / 64
            print("Waypoint \(wp.id): cell=\(wp.cell) (\(cellX),\(cellY)) px=(\(cellX*24),\(cellY*24))")
        }
        print("Theater: \(data.theater)  Credits: \(data.credits)  BuildLevel: \(data.buildLevel)")
        // Player object placements
        let playerHouse = scen.uppercased().hasPrefix("SCB") ? "BadGuy" : "GoodGuy"
        print("--- Player (\(playerHouse)) placements ---")
        for u in data.units where u.house.rawValue == playerHouse {
            print("  unit \(u.typeName) cell=\(u.cell) (\(u.cell % 64),\(u.cell / 64))")
        }
        for inf in data.infantry where inf.house.rawValue == playerHouse {
            print("  inf  \(inf.typeName) cell=\(inf.cell) (\(inf.cell % 64),\(inf.cell / 64))")
        }
        for s in data.structures where s.house.rawValue == playerHouse {
            print("  bldg \(s.typeName) cell=\(s.cell) (\(s.cell % 64),\(s.cell / 64))")
        }
    } else {
        print("Could not load scenario \(scen)")
    }
    exit(0)
}

// Headless simulation: --headless <SCEN> <ticks> [seed]
// Runs the sim with no window/render/audio and prints a state digest.
if let idx = CommandLine.arguments.firstIndex(of: "--headless"),
   idx + 2 < CommandLine.arguments.count {
    let scen = CommandLine.arguments[idx + 1]
    let ticks = Int(CommandLine.arguments[idx + 2]) ?? 0
    let seed = idx + 3 < CommandLine.arguments.count ? UInt64(CommandLine.arguments[idx + 3]) : nil
    exit(headlessRunCommand(scenario: scen, ticks: ticks, seed: seed))
}

// World reset-hygiene test: --reset-check <SCEN> <ticks>
// Runs two worlds in one process and verifies session state is fully reset.
if let idx = CommandLine.arguments.firstIndex(of: "--reset-check"),
   idx + 2 < CommandLine.arguments.count {
    let scen = CommandLine.arguments[idx + 1]
    let ticks = Int(CommandLine.arguments[idx + 2]) ?? 0
    exit(headlessResetCheckCommand(scenario: scen, ticks: ticks))
}

// Determinism self-test: --determinism <SCEN> <ticks>
// Runs the same scenario+seed twice and verifies identical digests.
if let idx = CommandLine.arguments.firstIndex(of: "--determinism"),
   idx + 2 < CommandLine.arguments.count {
    let scen = CommandLine.arguments[idx + 1]
    let ticks = Int(CommandLine.arguments[idx + 2]) ?? 0
    exit(headlessDeterminismCommand(scenario: scen, ticks: ticks))
}

// B3 AI decide() purity check: --ai-parity <SCEN> <ticks>
if let idx = CommandLine.arguments.firstIndex(of: "--ai-parity"),
   idx + 2 < CommandLine.arguments.count {
    let scen = CommandLine.arguments[idx + 1]
    let ticks = Int(CommandLine.arguments[idx + 2]) ?? 0
    exit(headlessAIParityCommand(scenario: scen, ticks: ticks))
}

// Tier-1 per-instance flag self-test: --test-flags <SCEN>
if let idx = CommandLine.arguments.firstIndex(of: "--test-flags"),
   idx + 1 < CommandLine.arguments.count {
    let scen = CommandLine.arguments[idx + 1]
    exit(headlessTestFlagsCommand(scenario: scen))
}

// Editor round-trip fidelity gate (E1): --editor-roundtrip <SCEN>
if let idx = CommandLine.arguments.firstIndex(of: "--editor-roundtrip"),
   idx + 1 < CommandLine.arguments.count {
    let scen = CommandLine.arguments[idx + 1]
    exit(headlessEditorRoundtripCommand(scenario: scen))
}

// Tier-1 T2 self-test: --test-triggers-ex
if CommandLine.arguments.contains("--test-triggers-ex") {
    exit(headlessTestTriggersExCommand())
}

// Tier-1 T3 self-test: --test-two-event
if CommandLine.arguments.contains("--test-two-event") {
    exit(headlessTestTwoEventCommand())
}

// B3 AI decision-stream trace: --ai-trace <SCEN> <ticks>
if let idx = CommandLine.arguments.firstIndex(of: "--ai-trace"),
   idx + 2 < CommandLine.arguments.count {
    let scen = CommandLine.arguments[idx + 1]
    let ticks = Int(CommandLine.arguments[idx + 2]) ?? 0
    exit(headlessAITraceCommand(scenario: scen, ticks: ticks))
}

// Diagnostic: --probe-tiberium  parses TI1.TEM/TI12.TEM and dumps headers
if CommandLine.arguments.contains("--probe-tiberium") {
    for name in ["TI1.TEM", "TI6.TEM", "TI12.TEM"] {
        guard let data = mixManager.retrieve(name) else {
            print("\(name): NOT FOUND")
            continue
        }
        let buf = Data(data)
        let firstBytes = buf.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
        print("\(name): \(buf.count) bytes, first 16: \(firstBytes)")
        if let shp = try? SHPFile(data: buf) {
            print("  SHPFile parsed OK: \(shp.frames.count) frames")
            for (i, f) in shp.frames.prefix(3).enumerated() {
                let nz = f.pixels.filter { $0 != 0 }.count
                print("    frame \(i): \(f.width)x\(f.height), \(nz) visible px")
            }
        } else {
            print("  SHPFile parse FAILED")
        }
        if let icn = try? ICNFile(data: buf) {
            print("  ICNFile parsed OK: \(icn.count) tiles, \(icn.width)x\(icn.height)")
        }
    }
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

// Restore last window size if available, otherwise use the default.
if let saved = WindowConfig.loadSaved() {
    renderState.windowWidth = saved.width
    renderState.windowHeight = saved.height
} else {
    renderState.windowWidth = WindowConfig.defaultWidth
    renderState.windowHeight = WindowConfig.defaultHeight
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

SDL_SetWindowMinimumSize(window, WindowConfig.minWidth, WindowConfig.minHeight)

guard let renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED.rawValue | SDL_RENDERER_PRESENTVSYNC.rawValue) else {
    print("SDL_CreateRenderer failed: \(String(cString: SDL_GetError()))")
    exit(1)
}

renderState.sdlRenderer = renderer

// Query actual window size (may differ from requested on small screens)
do {
    var actualW: Int32 = 0, actualH: Int32 = 0
    SDL_GetWindowSize(window, &actualW, &actualH)
    renderState.windowWidth = actualW
    renderState.windowHeight = actualH

    // Detect HiDPI scale factor (drawable pixels vs window pixels)
    var drawW: Int32 = 0, drawH: Int32 = 0
    SDL_GetRendererOutputSize(renderer, &drawW, &drawH)
    if actualW > 0 {
        renderState.displayScale = Double(drawW) / Double(actualW)
    }

    // Set logical size so SDL maps input & rendering to window coordinates automatically.
    // This makes mouse events and render coordinates use the same coordinate space.
    SDL_RenderSetLogicalSize(renderer, actualW, actualH)
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
        case SDL_MOUSEWHEEL:
            handleMouseWheel(event)
        case SDL_WINDOWEVENT:
            handleWindowEvent(event)
        default:
            break
        }
    }

    // Continuous input (camera panning)
    handleContinuousInput()

    // Update game logic in playing state
    if session.isPlaying {
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

    renderMenuState(renderer)

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
