import Foundation
import OpenConquerCore

// --test-map-select GDI|NOD ROW [E|W] OUTDIR
// Drives the animated map-selection screen headlessly: sets the campaign as if
// mission ROW was just won, runs the 60 Hz script, saves PNG snapshots at key
// moments (globe, territories, prompt, stats), makes a wrong click then the
// first valid one, and checks the choice is committed. Asset-backed.

func runMapSelectionDiagnosticsIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--test-map-select") else { return nil }
    guard i + 3 < args.count || (i + 3 == args.count) else { return usage() }
    let rest = Array(args[(i + 1)...])
    guard rest.count >= 3, let row = Int(rest[1]) else { return usage() }
    let faction = rest[0].uppercased() == "NOD" ? "NOD" : "GDI"
    let dir: Character = rest.count >= 4 && rest[2].uppercased() == "W" ? "W" : "E"
    let outDir = URL(fileURLWithPath: rest.last!)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    prepareCampaign(faction: faction, wonRow: row, dir: dir)
    let choices = CampaignGraph.choices(faction: faction, wonMission: row, dir: dir)
    guard let screen = MapSelectionScreen.makeForTesting(choices: choices) else {
        print("FAIL: map-selection art not installed or no entry for \(faction) row \(row)")
        return 1
    }
    let (w, h) = screen.testFrameSize
    func snap(_ name: String) {
        _ = writeRGBAPNG(rgba: screen.testSnapshot(), width: w, height: h,
                           to: outDir.appendingPathComponent("\(name).png"))
    }

    var ticks = 0
    let marks = [(60, "01-grey-earth"), (200, "02-globe"), (420, "03-zoom"), (700, "04-territories"),
                 (1000, "05-crosshairs")]
    for (at, name) in marks {
        screen.testAdvance(ticks: at - ticks)
        ticks = at
        snap(name)
    }
    while screen.testPhase == "intro" && ticks < 4000 {
        screen.testAdvance(ticks: 10)
        ticks += 10
    }
    guard screen.testPhase == "selecting" else {
        print("FAIL: never reached the country prompt (phase \(screen.testPhase) after \(ticks) ticks)")
        return 1
    }
    screen.testAdvance(ticks: 30)
    snap("06-prompt")
    print("prompt after \(ticks) ticks (\(String(format: "%.1f", Double(ticks) / 60)) s); \(choices.count) choice(s): \(choices.map(\.suffix))")

    _ = screen.testClick(choice: nil)
    guard screen.testPhase == "selecting" else {
        print("FAIL: a click off the candidates was accepted")
        return 1
    }
    guard screen.testClick(choice: 0) else {
        print("FAIL: choice 0's colour isn't on the click map")
        return 1
    }
    var statTicks = 0
    while screen.testPhase == "stats" && statTicks < 3000 {
        screen.testAdvance(ticks: 10)
        statTicks += 10
    }
    snap("07-stats")
    guard screen.testPhase == "awaitingContinue" else {
        print("FAIL: statistics never finished (phase \(screen.testPhase))")
        return 1
    }
    let before = session.campaignState.currentVariant
    screen.testContinue()
    screen.testAdvance(ticks: 30)
    let after = session.campaignState.currentVariant
    print("stats typed in \(statTicks) ticks; variant \(before) -> \(after) (expected \(choices.first?.suffix ?? "?"))")
    guard after == choices.first?.suffix else {
        print("FAIL: the pick wasn't committed")
        return 1
    }
    print("PASS — snapshots in \(outDir.path)")
    return 0
}

/// Campaign state as MapSelectionScreen sees it after handleWin(): the next
/// mission number set, the variant (and so the direction) still the won one's.
func prepareCampaign(faction: String, wonRow: Int, dir: Character) {
    let s = session.campaignState
    s.currentFaction = faction
    s.isActive = true
    s.currentMission = wonRow + 1
    s.currentVariant = "\(dir)A"
}

private func usage() -> Int32 {
    print("usage: --test-map-select GDI|NOD ROW [E|W] OUTDIR")
    return 2
}
