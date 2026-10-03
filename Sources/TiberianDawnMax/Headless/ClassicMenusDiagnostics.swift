import Foundation
import OpenConquerCore

// --test-classic-menus OUTDIR
// Renders the classic Load Mission and Options dialogs headlessly: the GDI
// and Nod mission lists (top, and scrolled to the end), and the options
// dialog with the sidebar on Classic and on Modern (the size row hides).
// Checks the lists are populated and that picking a choice changes the
// setting, restoring the user's settings afterwards. Asset-backed.

func runClassicMenusDiagnosticsIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--test-classic-menus") else { return nil }
    guard i + 1 < args.count else {
        print("usage: --test-classic-menus OUTDIR")
        return 2
    }
    let outDir = URL(fileURLWithPath: args[i + 1])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    func save(_ rgba: [UInt8], _ name: String) {
        _ = writeRGBAPNG(rgba: rgba, width: 640, height: 400, to: outDir.appendingPathComponent("\(name).png"))
    }

    guard let load = ClassicLoadMissionScreen.makeForTesting() else {
        print("FAIL: no title art (HTITLE.PCX / TITLE.CPS)")
        return 1
    }
    save(load.testSnapshot(faction: "GDI", select: 2), "01-load-gdi")
    let gdiCount = load.testMissionCount
    save(load.testSnapshot(faction: "GDI", select: gdiCount - 1), "02-load-gdi-end")
    let lastGDI = load.testSelectedMission ?? "-"
    save(load.testSnapshot(faction: "NOD", select: 0), "03-load-nod")
    let nodCount = load.testMissionCount
    print("Load Mission: \(gdiCount) GDI and \(nodCount) Nod missions; last GDI = \(lastGDI)")
    guard gdiCount > 0, nodCount > 0 else {
        print("FAIL: empty mission list")
        return 1
    }

    guard let options = ClassicOptionsScreen.makeForTesting() else {
        print("FAIL: options dialog needs the title art")
        return 1
    }
    let saved = (UserSettings.sidebarStyle, UserSettings.movieMode)
    defer { (UserSettings.sidebarStyle, UserSettings.movieMode) = saved }
    guard options.testPick(row: "Sidebar", SidebarStyle.classic.rawValue) else {
        print("FAIL: no Sidebar / Classic button")
        return 1
    }
    save(options.testSnapshot(), "04-options")
    guard options.testPick(row: "Movies", MovieMode.pixels.rawValue), UserSettings.movieMode == .pixels else {
        print("FAIL: picking Movies / Pixels didn't set the movie mode")
        return 1
    }
    guard options.testPick(row: "Sidebar", SidebarStyle.modern.rawValue), UserSettings.sidebarStyle == .modern else {
        print("FAIL: picking Sidebar / Modern didn't set the sidebar")
        return 1
    }
    save(options.testSnapshot(), "05-options-modern-sidebar")
    print("PASS — snapshots in \(outDir.path)")
    return 0
}
