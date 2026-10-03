import Foundation
import OpenConquerCore

// --test-title OUTDIR
// Renders the classic front end headlessly: the title + main menu (mid fade
// and settled), the difficulty and developer-tools dialogs, then drives the
// choose-your-side screen — captions typing, the loop, a Nod pick running on
// to frame 14 — and saves PNG snapshots of each. Asset-backed.

func runTitleDiagnosticsIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--test-title") else { return nil }
    guard i + 1 < args.count else {
        print("usage: --test-title OUTDIR")
        return 2
    }
    let outDir = URL(fileURLWithPath: args[i + 1])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    func save(_ rgba: [UInt8], _ name: String) {
        _ = writeRGBAPNG(rgba: rgba, width: 640, height: 400, to: outDir.appendingPathComponent("\(name).png"))
    }

    guard let title = TitleScreen(fadeIn: true) else {
        print("FAIL: no title art (HTITLE.PCX / TITLE.CPS)")
        return 1
    }
    save(title.testSnapshot(menu: "main", ticks: 15), "01-title-fading")
    save(title.testSnapshot(menu: "main", ticks: 30), "02-title")
    save(title.testSnapshot(menu: "difficulty", ticks: 0), "03-difficulty")
    save(title.testSnapshot(menu: "tools", ticks: 0), "04-tools")
    gameAudio.stopMusic()

    guard let choose = ChooseSideScreen.makeForTesting() else {
        print("FAIL: CHOOSE.WSA / 12GRNGRD.FNT not installed")
        return 1
    }
    choose.testAdvance(ticks: 12)
    save(choose.testSnapshot(), "05-choose-typing")
    choose.testAdvance(ticks: 150)
    save(choose.testSnapshot(), "06-choose")
    let t0 = Date()
    for _ in 0..<20 { _ = choose.testSnapshot() }
    print(String(format: "choose compose: %.1f ms/frame", Date().timeIntervalSince(t0) * 1000 / 20))
    choose.testPick(.nod)
    var ticks = 0
    while !choose.testFinished && ticks < 600 {
        choose.testAdvance(ticks: 1)
        ticks += 1
        if choose.testFrame == 14 && !choose.testFinished { save(choose.testSnapshot(), "07-choose-nod-end") }
    }
    print("Nod pick: animation reached frame \(choose.testFrame) after \(ticks) ticks; finished=\(choose.testFinished)")
    guard choose.testFrame == 14 else {
        print("FAIL: the Nod pick didn't stop on frame 14")
        return 1
    }
    // Nod_Ending's target screen: the prompt typed out, and the quadrants.
    guard let target = NodTargetScreen(then: { _ in }) else {
        print("FAIL: SATSEL.CPS / SATSEL.PAL not installed")
        return 1
    }
    target.testAdvance(ticks: 40)
    save(target.composeRGBA(), "08-nod-target")
    let quadrants = [(500, 100, 1), (100, 100, 2), (100, 300, 3), (500, 300, 4)]
    for (x, y, want) in quadrants where NodTargetScreen.target(atX: x, y: y) != want {
        print("FAIL: click (\(x),\(y)) should pick NODEND\(want)")
        return 1
    }
    guard NodTargetScreen.target(atX: 300, y: 20) == nil else {
        print("FAIL: a click above the picture band was accepted")
        return 1
    }
    print("PASS — snapshots in \(outDir.path)")
    return 0
}
