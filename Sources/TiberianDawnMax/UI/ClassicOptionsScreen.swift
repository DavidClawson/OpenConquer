import CSDL2
import Foundation
import OpenConquerCore

// MARK: - Options, as a Win95 dialog
//
// The 1995 game had no front-end options (its Options lived in the in-game
// menu: Game Controls, Visual Controls, Sound Controls — GOPTIONS.CPP and
// friends), so this is our settings screen in that dialog style: a captioned
// dialog with the OPTION_CONTROLS filigree over the title picture, one row
// per setting — a light-green label and a row of TextButtonClass choices —
// with the current choice drawn pressed-in and bright, and the choice's
// summary in the 6-point font underneath. OK returns to the title.
// Up/Down/Left/Right move the keyboard focus, Return picks, Esc closes.
//
// Settings apply immediately, as on the plain screen (OptionsScreen), which
// is still used when the title art isn't installed. The ruleset is chosen
// here, before any mission starts — session.rules never changes mid-run.

final class ClassicOptionsScreen: MenuScreen {
    /// This dialog, or the plain options screen without title art.
    static func make() -> MenuScreen {
        ClassicOptionsScreen() ?? OptionsScreen()
    }

    private struct Choice {
        let label: String
        let isSelected: () -> Bool
        let pick: () -> Void
    }

    private struct Row {
        let title: String
        let choices: [Choice]
        let summary: () -> String
        var visible: () -> Bool = { true }
    }

    private let page = ClassicPage()
    private let background: [UInt8]
    private var rows: [Row] = []
    /// Laid-out buttons with the row each belongs to (-1 = OK).
    private var buttons: [(row: Int, button: ClassicTextButton, selected: () -> Bool)] = []
    private var focus = 0
    private var pressed: Int?

    private static let d = (x: 40, y: 8, w: 560, h: 384)
    private static let labelX = d.x + 24, buttonsX = d.x + 168, buttonsRight = d.x + d.w - 24
    private static let firstRowY = d.y + 48, rowStep = 62, buttonH = 18

    private init?() {
        guard let bg = ClassicTitleBackground.load() else { return nil }
        background = bg.pixels
        page.setPalette(bg.palette)
        rows = [
            Row(title: "Ruleset",
                choices: Ruleset.presets.map { preset in
                    Choice(label: preset.name, isSelected: { session.rules.name == preset.name },
                           pick: { session.rules = preset })
                },
                summary: { session.rules.summary }),
            Row(title: "Controls",
                choices: ControlScheme.allCases.map { scheme in
                    Choice(label: scheme.rawValue, isSelected: { UserSettings.controlScheme == scheme },
                           pick: { UserSettings.controlScheme = scheme })
                },
                summary: { UserSettings.controlScheme.summary }),
            Row(title: "Sidebar",
                choices: SidebarStyle.allCases.map { style in
                    Choice(label: style.rawValue, isSelected: { UserSettings.sidebarStyle == style },
                           pick: { UserSettings.sidebarStyle = style })
                },
                summary: {
                    let style = UserSettings.sidebarStyle
                    return style == .classic && !ClassicSidebarArt.shared.isAvailable
                        ? "Classic needs UPDATEC.MIX (run install-assets.sh) - using Modern."
                        : style.summary
                }),
            Row(title: "Sidebar Size",
                choices: SidebarSize.allCases.map { size in
                    Choice(label: size.rawValue, isSelected: { UserSettings.sidebarSize == size },
                           pick: { UserSettings.sidebarSize = size })
                },
                summary: { "Scale of the classic sidebar art." },
                visible: { UserSettings.sidebarStyle == .classic }),
            Row(title: "Movies",
                choices: MovieMode.allCases.map { mode in
                    Choice(label: mode.rawValue, isSelected: { UserSettings.movieMode == mode },
                           pick: { UserSettings.movieMode = mode })
                },
                summary: { UserSettings.movieMode.summary }),
        ]
        layout()
        focus = buttons.firstIndex { $0.selected() } ?? 0
        redraw()
    }

    private func layout() {
        buttons = []
        var y = Self.firstRowY
        for (r, row) in rows.enumerated() where row.visible() {
            let n = row.choices.count
            let gap = 8
            let total = Self.buttonsRight - Self.buttonsX
            let w = (total - gap * (n - 1)) / n
            for (i, c) in row.choices.enumerated() {
                let b = ClassicTextButton(label: c.label, x: Self.buttonsX + i * (w + gap), y: y,
                                          w: w, h: Self.buttonH) { [unowned self] in
                    c.pick()
                    let focused = buttons[safe: focus]?.button.label
                    layout()
                    focus = buttons.firstIndex { $0.button.label == focused } ?? focus
                    redraw()
                }
                buttons.append((r, b, c.isSelected))
            }
            y += Self.rowStep
        }
        let d = Self.d
        let ok = ClassicTextButton(label: ClassicDialogArt.shared.text(37, "OK"), x: d.x + d.w / 2 - 50,
                                   y: d.y + d.h - 26 - 14, w: 100, h: 26) {
            app.currentScreen = makeMainMenu()
        }
        buttons.append((-1, ok, { false }))
        focus = min(focus, buttons.count - 1)
    }

    private func redraw() {
        page.pixels = background
        page.markDirty()
        let d = Self.d
        page.captionedDialog(x: d.x, y: d.y, w: d.w, h: d.h,
                             caption: ClassicDialogArt.shared.text(65, "Options"), filigree: .controls)
        var y = Self.firstRowY
        for row in rows where row.visible() {
            page.fancyText(row.title, x: Self.labelX, y: y + 1, fore: ClassicColor.green, font: .grad6,
                           flags: [.noShadow, .useGradPal])
            let flags: TextPrintFlags = [.noShadow]
            let width = Self.buttonsRight - Self.buttonsX
            let lines = ClassicPage.wrapText(row.summary(), font: .point6, flags: flags, width: width)
            for (n, line) in lines.prefix(2).enumerated() {
                page.clipText(line, x: Self.buttonsX, y: y + Self.buttonH + 5 + n * ClassicPage.lineHeight(font: .point6, flags: flags),
                              fore: ClassicColor.ltgrey, font: .point6, flags: flags, width: width)
            }
            y += Self.rowStep
        }
        for (i, entry) in buttons.enumerated() {
            let sel = entry.selected()
            entry.button.draw(on: page, on: i == focus || sel, pressed: i == pressed || sel)
        }
    }

    /// The nearest button in a direction, for arrow-key focus.
    private func moveFocus(dx: Int, dy: Int) {
        guard let cur = buttons[safe: focus]?.button else { return }
        let cx = cur.x + cur.w / 2, cy = cur.y + cur.h / 2
        var best: (Int, Int)?
        for (i, e) in buttons.enumerated() where i != focus {
            let bx = e.button.x + e.button.w / 2, by = e.button.y + e.button.h / 2
            let ddx = bx - cx, ddy = by - cy
            if dx != 0 && (ddy != 0 || ddx * dx <= 0) { continue }
            if dy != 0 && ddy * dy <= 0 { continue }
            let dist = abs(ddx) + abs(ddy) * 4
            if best == nil || dist < best!.1 { best = (i, dist) }
        }
        if let best { focus = best.0 }
        redraw()
    }

    // MARK: MenuScreen

    func render(_ renderer: OpaquePointer?) {
        page.present(renderer)
    }

    func handleKeyDown(_ key: Int32) {
        switch key {
        case Int32(SDLK_ESCAPE.rawValue): app.currentScreen = makeMainMenu()
        case Int32(SDLK_RETURN.rawValue), Int32(SDLK_KP_ENTER.rawValue), Int32(SDLK_SPACE.rawValue):
            buttons[safe: focus]?.button.action()
        case Int32(SDLK_UP.rawValue): moveFocus(dx: 0, dy: -1)
        case Int32(SDLK_DOWN.rawValue): moveFocus(dx: 0, dy: 1)
        case Int32(SDLK_LEFT.rawValue): moveFocus(dx: -1, dy: 0)
        case Int32(SDLK_RIGHT.rawValue): moveFocus(dx: 1, dy: 0)
        default: break
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT), let p = ClassicPage.pagePoint(x, y),
              let i = buttons.firstIndex(where: { $0.button.contains(p) }) else { return }
        pressed = i
        redraw()
    }

    func handleMouseUp(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT), let i = pressed else { return }
        pressed = nil
        redraw()
        guard let p = ClassicPage.pagePoint(x, y), buttons[safe: i]?.button.contains(p) == true else { return }
        focus = i
        buttons[i].button.action()
    }
}

// MARK: - Headless (--test-classic-menus)

extension ClassicOptionsScreen {
    static func makeForTesting() -> ClassicOptionsScreen? { ClassicOptionsScreen() }

    func testSnapshot() -> [UInt8] {
        layout()
        redraw()
        return page.rgba()
    }

    /// Press the button labelled `label` in the row titled `row`, as a click would.
    func testPick(row: String, _ label: String) -> Bool {
        guard let r = rows.firstIndex(where: { $0.title == row }),
              let i = buttons.firstIndex(where: { $0.row == r && $0.button.label == label }) else { return false }
        focus = i
        buttons[i].button.action()
        return true
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
