import CSDL2
import Foundation

// MARK: - Setup / Missing-Assets Screen

/// Shown instead of the main menu when no game data could be loaded.
///
/// This screen must render with **zero assets**. It is what a first-time user
/// sees when they double-click the app before extracting anything, and at that
/// point there is no palette, no SHP, and no font in the MIX — so everything
/// here is SDL primitives plus the built-in 5x7 pixel font (`TextRenderer`).
///
/// It exists because a Finder-launched app has no stdout: the "NOT FOUND"
/// diagnostics the asset manager prints go nowhere, and without this screen a
/// fresh install is just a black window with no explanation.
final class SetupScreen: MenuScreen {

    /// Set after a RETRY that still found nothing, so the screen can say so
    /// rather than looking like the click did nothing.
    private var retryFailed = false

    // MARK: Layout

    /// Home-relative path, so the line fits and reads the way the README writes it.
    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let full = dataPath.path
        return full.hasPrefix(home) ? "~" + full.dropFirst(home.count) : full
    }

    /// True when the path came from an override rather than the built-in default —
    /// worth saying out loud, since a typo'd override looks identical to "assets
    /// were never installed".
    private var isOverridden: Bool {
        if !(ProcessInfo.processInfo.environment["OPENCONQUER_DATA_DIR"] ?? "").isEmpty {
            return true
        }
        return !(UserDefaults.standard.string(forKey: "TDMax.dataDir") ?? "").isEmpty
    }

    /// Body text scale, so the screen stays legible from a 640-wide window up to
    /// the 1920x1200 default without a fixed pixel layout.
    private var bodyScale: Int32 {
        max(1, min(3, renderState.windowWidth / 800))
    }

    /// One rendered line. The screen is laid out by measuring this list first,
    /// then drawing it centred — the window is user-resizable, so nothing here
    /// can assume a fixed height.
    private struct Line {
        let text: String
        let color: Color
        let scale: Int32
        let gapAfter: Int32
        /// A horizontal rule rather than text.
        let rule: Bool

        init(_ text: String, _ color: Color, _ scale: Int32, gapAfter: Int32 = 0, rule: Bool = false) {
            self.text = text; self.color = color; self.scale = scale
            self.gapAfter = gapAfter; self.rule = rule
        }

        var height: Int32 { (rule ? 1 : 7 * scale) + gapAfter }
    }

    private func makeLines() -> [Line] {
        let b = bodyScale
        var lines: [Line] = [
            Line("OPENCONQUER", .amber, b * 2, gapAfter: 10 * b),
            Line("", .darkGreen, 0, gapAfter: 12 * b, rule: true),
            Line("NO GAME DATA FOUND", .red, b + 1, gapAfter: 16 * b),
            Line(isOverridden ? "LOOKED IN (OVERRIDDEN PATH):" : "LOOKED IN:",
                 .gray, b, gapAfter: 4 * b),
        ]
        for line in wrap(displayPath, width: 46) {
            lines.append(Line(line, .green, b, gapAfter: 3 * b))
        }
        lines[lines.count - 1] = Line(lines[lines.count - 1].text, .green, b, gapAfter: 14 * b)

        lines += [
            Line("OPENCONQUER SHIPS NO GAME ASSETS.", .white, b, gapAfter: 4 * b),
            Line("YOU SUPPLY THEM FROM YOUR OWN COPY OF", .white, b, gapAfter: 4 * b),
            Line("THE C&C REMASTERED COLLECTION.", .white, b, gapAfter: 16 * b),
            Line("IN A TERMINAL, FROM THE SOURCE FOLDER:", .gray, b, gapAfter: 5 * b),
            Line("./INSTALL-ASSETS.SH /PATH/TO/CNCREMASTERED", .amber, b, gapAfter: 14 * b),
            Line("THEN PRESS RETRY - NO NEED TO RELAUNCH.", .gray, b, gapAfter: 4 * b),
            Line("DETAILS: README > ASSETS", .gray, b, gapAfter: 0),
        ]
        if retryFailed {
            lines.append(Line("STILL NOTHING THERE.", .red, b, gapAfter: 0))
        }
        return lines
    }

    private var buttonMetrics: (w: Int32, h: Int32, gap: Int32) {
        let b = bodyScale
        return (w: 60 * b, h: 17 * b, gap: 12 * b)
    }

    /// Buttons sit under the measured text block, not pinned to the window
    /// bottom — otherwise they strand themselves half a screen away at 1200px tall.
    private func makeButtons() -> [Button] {
        let cx = renderState.windowWidth / 2
        let m = buttonMetrics
        let y = textBlockBottom() + 26 * bodyScale
        return [
            Button(label: "QUIT", x: cx - m.w - m.gap / 2, y: y, w: m.w, h: m.h) {
                session.running = false
            },
            Button(label: "RETRY", x: cx + m.gap / 2, y: y, w: m.w, h: m.h) { [weak self] in
                self?.retry()
            },
        ]
    }

    private func blockHeight() -> Int32 {
        let m = buttonMetrics
        return makeLines().reduce(0) { $0 + $1.height } + 26 * bodyScale + m.h
    }

    private func textBlockTop() -> Int32 {
        max(20, (renderState.windowHeight - blockHeight()) / 2)
    }

    private func textBlockBottom() -> Int32 {
        textBlockTop() + makeLines().reduce(0) { $0 + $1.height }
    }

    // MARK: Render

    func render(_ renderer: OpaquePointer?) {
        let cx = renderState.windowWidth / 2
        var y = textBlockTop()

        for line in makeLines() {
            if line.rule {
                SDL_SetRenderDrawColor(renderer, Color.darkGreen.r, Color.darkGreen.g,
                                       Color.darkGreen.b, 255)
                let w = 130 * bodyScale
                var rect = SDL_Rect(x: cx - w / 2, y: y, w: w, h: 1)
                SDL_RenderFillRect(renderer, &rect)
            } else {
                // drawText centres vertically on the y it is given.
                drawText(renderer, line.text, centerX: cx,
                         centerY: y + (7 * line.scale) / 2,
                         color: line.color, scale: line.scale)
            }
            y += line.height
        }

        for btn in makeButtons() {
            btn.draw(renderer, highlighted: btn.contains(input.mouseX, input.mouseY))
        }
    }

    // MARK: Retry

    /// Re-run asset discovery in place, so a user can extract assets in another
    /// window and come back without relaunching.
    private func retry() {
        assetManager.initialize()
        guard assetManager.mixManager.totalEntries > 0 else {
            retryFailed = true
            return
        }
        loadDataOverrides()
        initRemasteredSprites()
        audioManager.soundLibrary = SoundLibrary(assetManager: assetManager)
        session.currentScreen = MainMenuScreen()
    }

    /// Break a long path across lines without a word-boundary assumption —
    /// paths have no spaces to break on.
    private func wrap(_ text: String, width: Int) -> [String] {
        guard text.count > width else { return [text] }
        var out: [String] = []
        var rest = Substring(text)
        while rest.count > width {
            out.append(String(rest.prefix(width)))
            rest = rest.dropFirst(width)
        }
        if !rest.isEmpty { out.append(String(rest)) }
        return out
    }

    // MARK: Input

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) || key == Int32(SDLK_q.rawValue) {
            session.running = false
        } else if key == Int32(SDLK_RETURN.rawValue) || key == Int32(SDLK_r.rawValue) {
            retry()
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        for btn in makeButtons() where btn.contains(x, y) {
            btn.action()
            return
        }
    }
}
