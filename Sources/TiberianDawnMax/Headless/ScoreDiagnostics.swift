import CSDL2
import Foundation
import OpenConquerCore

// --test-score GDI|NOD OUTDIR
// Drives the end-of-mission score screen headlessly with made-up mission
// stats: runs the 60 Hz script, saves a PNG every two seconds plus a contact
// sheet, types a hall-of-fame name and checks it was stored. Uses a scratch
// hall of fame, not the player's. Asset-backed.

/// Made-up stats for a mid-campaign win (also used by --score-screen).
func sampleScoreInputs(gdi: Bool) -> ScoreInputs {
    ScoreInputs(isGDI: gdi, scenario: gdi ? 3 : 4, elapsedTicks: 15 * 60 * 23 + 15 * 40,
                survivingObjects: 24, gdiUnitsLost: gdi ? 6 : 31, nodUnitsLost: gdi ? 37 : 9, civUnitsLost: 4,
                gdiBuildingsLost: gdi ? 1 : 6, nodBuildingsLost: gdi ? 9 : 2, civBuildingsLost: 3,
                harvestedCredits: 4200, initialCredits: 2000, credits: gdi ? 2675 : 3140)
}

func runScoreDiagnosticsIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--test-score") else { return nil }
    guard i + 2 < args.count else {
        print("usage: --test-score GDI|NOD OUTDIR")
        return 2
    }
    let gdi = args[i + 1].uppercased() != "NOD"
    let outDir = URL(fileURLWithPath: args[i + 2])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let fameKey = "TDMax.hallOfFame.selftest"
    UserDefaults.standard.removeObject(forKey: fameKey)
    defer { UserDefaults.standard.removeObject(forKey: fameKey) }

    let inputs = sampleScoreInputs(gdi: gdi)
    var finished = false
    guard let screen = ScorePresentationScreen.make(inputs: inputs, fameKey: fameKey, then: { finished = true }) else {
        print("FAIL: score-screen art not installed")
        return 1
    }
    let r = screen.testResult
    print("leadership \(r.leadership)%  efficiency \(r.efficiency)%  total \(r.total)  time \(r.minutes)m")

    let (w, h) = screen.testFrameSize
    var frames: [[UInt8]] = []
    func snap(_ name: String) {
        let rgba = screen.testSnapshot()
        frames.append(rgba)
        _ = writeRGBAPNG(rgba: rgba, width: w, height: h, to: outDir.appendingPathComponent("\(name).png"))
    }

    var ticks = 0
    while screen.testPhase == "presenting" && ticks < 60 * 120 {
        screen.testAdvance(ticks: 120)
        ticks += 120
        snap(String(format: "%02d-t%04d", frames.count + 1, ticks))
    }
    guard screen.testPhase == "nameEntry" else {
        print("FAIL: never reached the hall of fame (phase \(screen.testPhase) after \(ticks) ticks)")
        return 1
    }
    print("hall of fame after \(ticks) ticks (\(String(format: "%.1f", Double(ticks) / 60)) s)")

    for ch in "claudx" {
        screen.handleKeyDown(Int32(ch.asciiValue!))
        screen.testAdvance(ticks: 8)
    }
    snap(String(format: "%02d-typing", frames.count + 1))
    screen.handleKeyDown(Int32(SDLK_BACKSPACE.rawValue))
    screen.testAdvance(ticks: 2)
    screen.handleKeyDown(Int32(Character("e").asciiValue!))
    screen.testAdvance(ticks: 3)
    snap(String(format: "%02d-zoom", frames.count + 1))
    screen.testAdvance(ticks: 20)
    snap(String(format: "%02d-name", frames.count + 1))
    screen.handleKeyDown(Int32(SDLK_RETURN.rawValue))
    screen.testAdvance(ticks: 30)
    guard finished else {
        print("FAIL: Return didn't leave the screen (phase \(screen.testPhase))")
        return 1
    }
    let stored = UserDefaults.standard.data(forKey: fameKey)
        .flatMap { try? JSONDecoder().decode([FameEntry].self, from: $0) } ?? []
    guard let top = stored.first, top.name == "CLAUDE", top.score == r.total, top.level == inputs.scenario else {
        print("FAIL: hall of fame not stored as expected: \(stored)")
        return 1
    }

    // Contact sheet: every frame at half size, four across.
    let cols = 4, cw = w / 2, ch = h / 2
    let rows = (frames.count + cols - 1) / cols
    var sheet = [UInt8](repeating: 40, count: cols * cw * rows * ch * 4)
    for (n, f) in frames.enumerated() {
        let ox = (n % cols) * cw, oy = (n / cols) * ch
        for y in 0..<ch {
            for x in 0..<cw {
                let s = ((y * 2) * w + x * 2) * 4, d = ((oy + y) * cols * cw + ox + x) * 4
                for k in 0..<4 { sheet[d + k] = f[s + k] }
            }
        }
    }
    _ = writeRGBAPNG(rgba: sheet, width: cols * cw, height: rows * ch, to: outDir.appendingPathComponent("sheet.png"))
    print("PASS — \(frames.count) snapshots and sheet.png in \(outDir.path)")
    return 0
}
