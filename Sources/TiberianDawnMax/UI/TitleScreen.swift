import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// MARK: - Title screen and main menu (Select_Game, INIT.CPP; Main_Menu, MENUS.CPP)
//
// The Win95 build's front end: the title picture (HTITLE.PCX, 640x400, or the
// DOS TITLE.CPS doubled) fades in, the version prints in the bottom-right
// corner, and Main_Menu draws its dialog — a black box with a light-grey
// border and the corner filigree — over the logo, with a column of textured
// green buttons in the 6-point gradient font. Up/Down move the keyboard focus
// (the bright label), Return picks it, a click picks the button under it.
// The music is THEME_MAP1, as in Select_Game.
//
// The buttons are the original's where we have the feature (Start New Game,
// Load Mission, Intro & Sneak Peek, Exit Game) plus our own (Options and
// Developer Tools) in the slots of the ones we don't (Internet and
// Multiplayer Game). Start New Game asks for a difficulty — the original
// campaign had none; this is Vanilla Conquer's addition — in the same dialog
// style, then goes to the choose-your-side screen. Falls back to the plain
// menu (ModernMainMenuScreen) when the title art isn't installed.

/// The main menu: the classic title screen when its art is installed.
func makeMainMenu(fadeIn: Bool = false) -> MenuScreen {
    TitleScreen(fadeIn: fadeIn) ?? ModernMainMenuScreen()
}

final class TitleScreen: MenuScreen {
    private enum Menu { case main, difficulty, tools }

    private let page = ClassicPage()
    private let background: [UInt8]
    private let titlePalette: [UInt8]
    private var menu: Menu = .main
    private var buttons: [ClassicTextButton] = []
    private var focus = 0
    private var pressed: Int?
    private var lastTicks: UInt64 = 0
    private var tickAccumulator = 0.0
    /// Set while fading out before an action (Exit, Intro).
    private var leaving: (() -> Void)?

    // Main_Menu's layout (MENUS.CPP:456-505, the NEWMENU build): the dialog
    // over the logo, 250x18 buttons from y=50, 30 apart; Exit is narrower.
    private static let dialog = (x: 170, y: 0, w: 304, h: 272)
    private static let buttonX = 196, buttonW = 250, buttonH = 18, firstY = 50, step = 30

    init?(fadeIn: Bool) {
        if let data = mixManager.retrieve("HTITLE.PCX"), let pcx = try? PCXFile(data: data),
           pcx.width == ClassicPage.width, pcx.height == ClassicPage.height, let pal = pcx.palette {
            background = pcx.pixels
            titlePalette = pal.rgb8
        } else if let data = mixManager.retrieve("TITLE.CPS"), let cps = try? CPSFile(data: data),
                  cps.pixels.count >= 320 * 200, let pal = cps.palette {
            let doubled = ClassicPage()
            doubled.blitDoubled(cps.pixels)
            background = doubled.pixels
            titlePalette = pal.rgb8
        } else {
            print("TitleScreen: no HTITLE.PCX / TITLE.CPS — using the plain menu")
            return nil
        }
        if fadeIn {
            page.setPalette(ClassicPage.blackPalette)
            page.fade(to: titlePalette, ticks: 30)  // FADE_PALETTE_SLOW
        } else {
            page.setPalette(titlePalette)
        }
        show(.main)
        if !gameAudio.isMusicPlaying || gameAudio.currentTheme != .map1 {
            gameAudio.playMenuMusic(.map1)
        }
    }

    // MARK: Menus

    private func show(_ m: Menu) {
        menu = m
        pressed = nil
        let art = ClassicDialogArt.shared
        func button(_ i: Int, _ label: String, _ action: @escaping () -> Void) -> ClassicTextButton {
            ClassicTextButton(label: label, x: Self.buttonX, y: Self.firstY + i * Self.step,
                              w: Self.buttonW, h: Self.buttonH, action: action)
        }
        func back(_ i: Int, _ label: String, _ action: @escaping () -> Void) -> ClassicTextButton {
            // D_EXIT_X / D_EXIT_W: the narrower button at the bottom.
            ClassicTextButton(label: label, x: 256, y: Self.firstY + i * Self.step,
                              w: 126, h: Self.buttonH, action: action)
        }
        switch m {
        case .main:
            buttons = [
                button(0, art.text(25, "Start New Game")) { [unowned self] in show(.difficulty) },
                button(1, art.text(53, "Load Mission")) { app.currentScreen = LoadMissionFactionScreen() },
                button(2, art.text(65, "Options")) { app.currentScreen = OptionsScreen() },
                button(3, art.text(26, "Intro & Sneak Peek")) { [unowned self] in playIntro() },
                button(4, "Developer Tools") { [unowned self] in show(.tools) },
                back(5, art.text(64, "Exit Game")) { [unowned self] in exitGame() },
            ]
            focus = 0
        case .difficulty:
            buttons = Difficulty.allCases.enumerated().map { i, d in
                button(i + 1, d.rawValue) {
                    app.selectedDifficulty = d
                    ChooseSideScreen.begin(difficulty: d)
                }
            } + [back(5, "Back") { [unowned self] in show(.main) }]
            focus = Difficulty.allCases.firstIndex(of: .normal) ?? 0
        case .tools:
            buttons = [
                button(0, "Map Viewer") {
                    loadMapViewerData(app.scenarioList[app.scenarioIndex])
                    app.currentScreen = MapViewerScreen()
                },
                button(1, "Sprite Playground") {
                    app.spritePlayground.initialize()
                    app.currentScreen = SpritePlaygroundScreen()
                },
                button(2, "Sound Test") {
                    app.soundTest.initialize()
                    app.currentScreen = SoundTestScreen()
                },
                back(5, "Back") { [unowned self] in show(.main) },
            ]
            focus = 0
        }
        redraw()
    }

    /// Select_Game's title page plus Main_Menu's dialog and buttons.
    private func redraw() {
        page.pixels = background
        page.markDirty()
        page.fancyText(versionText, x: ClassicPage.width - 1, y: ClassicPage.height - 10,
                       fore: ClassicColor.grey, font: .point6, flags: [.right, .fullShadow])
        let d = Self.dialog
        page.dialogBox(x: d.x, y: d.y, w: d.w, h: d.h)
        if menu == .difficulty {
            page.fancyText("Select Difficulty", x: d.x + d.w / 2, y: Self.firstY - 2, fore: ClassicColor.green,
                           font: .grad6, flags: [.center, .noShadow, .useGradPal, .mediumColor])
        }
        for (i, b) in buttons.enumerated() {
            b.draw(on: page, on: i == focus, pressed: i == pressed)
        }
    }

    private var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "OpenConquer " + (v.map { "V.\($0)" } ?? "dev")
    }

    // MARK: Actions

    /// SEL_INTRO: the intro, then the Tiberian Sun teaser, back to the title.
    private func playIntro() {
        fadeOut {
            gameAudio.stopMusic()
            MoviePlayerScreen.play(["INTRO2", "CC2TEASE"]) { app.currentScreen = makeMainMenu(fadeIn: true) }
        }
    }

    /// SEL_EXIT: the music and palette fade out, then quit.
    private func exitGame() {
        gameAudio.stopMusic()
        fadeOut { app.running = false }
    }

    private func fadeOut(then action: @escaping () -> Void) {
        guard leaving == nil else { return }
        leaving = action
        page.fade(to: ClassicPage.blackPalette, ticks: 30)
    }

    // MARK: MenuScreen

    func render(_ renderer: OpaquePointer?) {
        let now = SDL_GetPerformanceCounter()
        if lastTicks == 0 { lastTicks = now }
        tickAccumulator += Double(now - lastTicks) / Double(SDL_GetPerformanceFrequency()) * 60
        lastTicks = now
        while tickAccumulator >= 1 {
            page.tick()
            tickAccumulator -= 1
        }
        if let action = leaving, !page.isFading {
            leaving = nil
            action()
            return
        }
        page.present(renderer)
    }

    func handleKeyDown(_ key: Int32) {
        guard leaving == nil else { return }
        switch key {
        case Int32(SDLK_UP.rawValue):
            focus = (focus + buttons.count - 1) % buttons.count
            redraw()
        case Int32(SDLK_DOWN.rawValue):
            focus = (focus + 1) % buttons.count
            redraw()
        case Int32(SDLK_RETURN.rawValue), Int32(SDLK_KP_ENTER.rawValue):
            buttons[focus].action()
        case Int32(SDLK_ESCAPE.rawValue):
            if menu == .main { exitGame() } else { show(.main) }
        case Int32(SDLK_m.rawValue):
            gameAudio.toggleMusic()
            if gameAudio.musicEnabled && !gameAudio.isMusicPlaying { gameAudio.playMenuMusic(.map1) }
        default:
            break
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT), leaving == nil, let p = ClassicPage.pagePoint(x, y),
              let i = buttons.firstIndex(where: { $0.contains(p) }) else { return }
        pressed = i
        redraw()
    }

    /// GadgetClass buttons fire on release over the same button.
    func handleMouseUp(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT), let i = pressed else { return }
        pressed = nil
        redraw()
        guard let p = ClassicPage.pagePoint(x, y), buttons[i].contains(p) else { return }
        buttons[i].action()
    }
}

// MARK: - Headless (--test-title)

extension TitleScreen {
    /// The composed page after `ticks` 60 Hz ticks, for the snapshot harness.
    func testSnapshot(menu name: String, ticks: Int) -> [UInt8] {
        switch name {
        case "difficulty": show(.difficulty)
        case "tools": show(.tools)
        default: show(.main)
        }
        for _ in 0..<ticks { page.tick() }
        return page.rgba()
    }
}
