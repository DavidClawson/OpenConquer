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
    print("PASS — snapshots in \(outDir.path)")
    return 0
}
