import CSDL2
import Foundation
import OpenConquerCore

// MARK: - Load Mission (LoadOptionsClass::Process, LOADDLG.CPP, LOAD style)
//
// The Win95 dialog over the title picture: 500x312 centred, "Load Mission"
// caption with the OPTION_DELETE filigree, a 6-point gradient list box with
// its scroll bar, Load and Cancel buttons. The original listed saved games;
// ours lists the installed campaign missions, so it adds a GDI / Nod toggle
// pair at the right of the button row (the original had no side choice
// here). Return loads, Esc cancels, Up/Down move the selection, the mouse
// wheel scrolls (an addition). Picking a mission plays its movies and starts
// it, like the plain screen it replaces (LoadMissionListScreen.launch).

final class ClassicLoadMissionScreen: MenuScreen {
    /// This dialog, or the plain faction → list screens without title art.
    static func make() -> MenuScreen {
        ClassicLoadMissionScreen() ?? LoadMissionFactionScreen()
    }

    private let page = ClassicPage()
    private let background: [UInt8]
    private var faction = "GDI"
    private var missions: [String] = []
    private var list: ClassicListBox
    private var buttons: [ClassicTextButton] = []
    private var pressed: Int?

    // LOADDLG.CPP:83-125 with factor 2.
    private static let d = (x: (640 - 500) / 2, y: (400 - 312) / 2, w: 500, h: 312)
    private static let margin = 14, txt8 = 22
    private static let buttonW = 80, buttonH = 26

    private init?() {
        guard let bg = ClassicTitleBackground.load() else { return nil }
        background = bg.pixels
        page.setPalette(bg.palette)
        let d = Self.d
        list = ClassicListBox(x: d.x + Self.margin, y: d.y + Self.margin + Self.txt8 + Self.margin,
                              w: d.w - Self.margin * 2, h: 104 * 2)
        list.tabs = [100]
        showFaction(session.campaignState.currentFaction == "NOD" ? "NOD" : "GDI")
    }

    private func showFaction(_ f: String) {
        faction = f
        missions = LoadMissionListScreen.missions(faction: f)
        let names = f == "GDI" ? gdiMissionNames : nodMissionNames
        list.items = missions.map { name in
            let num = Int(name.dropFirst(3).prefix(2)) ?? 0
            let variant = String(name.suffix(2))
            let title = names[num] ?? name
            return "Mission \(num)\t\(title)\(variant == "EA" ? "" : " (\(variant.suffix(1)))")"
        }
        list.selected = 0
        list.top = 0
        layoutButtons()
        redraw()
    }

    private func layoutButtons() {
        let d = Self.d
        let cx = d.x + d.w / 2
        let by = d.y + d.h - Self.buttonH - Self.margin
        let art = ClassicDialogArt.shared
        let right = d.x + d.w - Self.margin
        buttons = [
            ClassicTextButton(label: art.text(56, "Load"), x: cx - Self.buttonW - Self.margin, y: by,
                              w: Self.buttonW, h: Self.buttonH) { [unowned self] in load() },
            ClassicTextButton(label: art.text(27, "Cancel"), x: cx + Self.margin, y: by,
                              w: Self.buttonW, h: Self.buttonH) { app.currentScreen = makeMainMenu() },
            ClassicTextButton(label: "GDI", x: right - 2 * 56 - 6, y: by, w: 56, h: Self.buttonH) { [unowned self] in
                if faction != "GDI" { showFaction("GDI") }
            },
            ClassicTextButton(label: "Nod", x: right - 56, y: by, w: 56, h: Self.buttonH) { [unowned self] in
                if faction != "NOD" { showFaction("NOD") }
            },
        ]
    }

    private func redraw() {
        page.pixels = background
        page.markDirty()
        let d = Self.d
        page.captionedDialog(x: d.x, y: d.y, w: d.w, h: d.h,
                             caption: ClassicDialogArt.shared.text(53, "Load Mission"), filigree: .delete)
        list.draw(on: page)
        for (i, b) in buttons.enumerated() {
            // The side toggles read as pressed-in for the side shown.
            let selectedSide = (i == 2 && faction == "GDI") || (i == 3 && faction == "NOD")
            b.draw(on: page, on: selectedSide, pressed: i == pressed || selectedSide)
        }
    }

    private func load() {
        guard missions.indices.contains(list.selected) else { return }
        LoadMissionListScreen.launch(missions[list.selected])
    }

    // MARK: MenuScreen

    func render(_ renderer: OpaquePointer?) {
        page.present(renderer)
    }

    func handleKeyDown(_ key: Int32) {
        switch key {
        case Int32(SDLK_ESCAPE.rawValue): app.currentScreen = makeMainMenu()
        case Int32(SDLK_RETURN.rawValue), Int32(SDLK_KP_ENTER.rawValue): load()
        case Int32(SDLK_UP.rawValue): list.stepSelection(-1); redraw()
        case Int32(SDLK_DOWN.rawValue): list.stepSelection(1); redraw()
        case Int32(SDLK_PAGEUP.rawValue): list.stepSelection(-list.lineCount); redraw()
        case Int32(SDLK_PAGEDOWN.rawValue): list.stepSelection(list.lineCount); redraw()
        case Int32(SDLK_LEFT.rawValue), Int32(SDLK_RIGHT.rawValue):
            showFaction(faction == "GDI" ? "NOD" : "GDI")
        default: break
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT), let p = ClassicPage.pagePoint(x, y) else { return }
        if let i = buttons.firstIndex(where: { $0.contains(p) }) {
            pressed = i
        } else if let hit = list.hit(p) {
            switch hit {
            case .entry(let i): list.selected = i
            case .arrow(let dir): list.pressedArrow = dir; list.step(dir)
            case .track(let dir): list.bump(dir)
            }
        }
        redraw()
    }

    func handleMouseUp(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        list.pressedArrow = nil
        let i = pressed
        pressed = nil
        redraw()
        if let i, let p = ClassicPage.pagePoint(x, y), buttons[i].contains(p) {
            buttons[i].action()
        }
    }

    func handleMouseWheel(_ dy: Int32, atX: Int32, atY: Int32) {
        list.step(dy > 0 ? -1 : 1)
        redraw()
    }
}

// MARK: - Headless (--test-classic-menus)

extension ClassicLoadMissionScreen {
    static func makeForTesting() -> ClassicLoadMissionScreen? { ClassicLoadMissionScreen() }

    func testSnapshot(faction f: String, select index: Int) -> [UInt8] {
        if f != faction { showFaction(f) }
        list.selected = 0
        list.top = 0
        list.stepSelection(index)
        redraw()
        return page.rgba()
    }

    var testMissionCount: Int { missions.count }
    var testSelectedMission: String? { missions.indices.contains(list.selected) ? missions[list.selected] : nil }
}
