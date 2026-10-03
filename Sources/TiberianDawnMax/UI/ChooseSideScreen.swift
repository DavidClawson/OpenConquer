import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// MARK: - Choose your side (Choose_Side, INTRO.CPP:79-310)
//
// CHOOSE.WSA loops (the GDI eagle and the Nod scorpion, one frame per three
// 60 Hz ticks) under the "struggle" static (STRUGGLE.AUD at a quarter volume,
// restarted every 63 ticks) while GLOBAL DEFENSE INITIATIVE, BROTHERHOOD OF
// NOD and SELECT TRANSMISSION type out. A click on the left half picks GDI,
// the right half Nod: the side's speech plays (GDI_SLCT / NOD_SLCT) and the
// animation runs on to the chosen side's frame (0 for GDI, 14 for Nod) before
// the side's first movie — GDI1 or NOD1PRE — and the campaign starts.
//
// Pages as in the Win95 build: the animation goes to a 320x200 page
// (PseudoSeenBuff) shown doubled with interpolation (Interpolate_2X_Scale);
// the text to a 640x400 layer (TextPrintBuffer) in the hi-res 12GRNGRD font,
// every coordinate doubled. Esc goes back to the title (the original had no
// way back). CHOOSE.WSA is in TRANSIT.MIX; without it the plain
// FactionScreen is used.

final class ChooseSideScreen: MenuScreen {
    /// Start a new campaign at `difficulty`: this screen if its art is
    /// installed, else the plain faction picker.
    static func begin(difficulty: Difficulty) {
        app.currentScreen = ChooseSideScreen() ?? FactionScreen()
    }

    private static let pw = 320, ph = 200, tw = 640, th = 400

    // Font palettes (INTRO.CPP:96-98).
    private static let yellowPal: [UInt8] = [0x0, 0xC9, 0xBA, 0x93, 0x61, 0xEE, 0xEE, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    private static let redPal: [UInt8] = [0x0, 0xA8, 0xD9, 0xDA, 0xE1, 0xD4, 0xDA, 0x0, 0xE1, 0, 0, 0, 0, 0, 0xD4, 0]
    private static let grayPal: [UInt8] = [0x0, 0x17, 0x10, 0x12, 0x14, 0x1C, 0x12, 0x1C, 0x14, 0, 0, 0, 0, 0, 0x1C, 0]
    private static let whitePal = [UInt8](repeating: 0x0F, count: 16)
    private static let blackPal = [UInt8](repeating: ClassicColor.black, count: 16)

    private let anim: WSAFile
    private var player: WSAPlayer
    private let font: WWFont
    private var pseudo = [UInt8](repeating: 0, count: pw * ph)
    private var textLayer = [UInt8](repeating: 0, count: tw * th)
    private var palette: [UInt8]
    private var texture: OpaquePointer?
    private var dirty = true

    private struct PrintJob { var chars: [UInt8]; let x: Int; let y: Int; let pal: [UInt8]; var stage = 0 }
    private var printJobs: [PrintJob] = []

    private var frame = 0
    private var endFrame = 255
    private var frameDelay = 0
    private var chosen: Faction?
    private var staticHandle = 0
    private var staticTimer = 0
    private var speechHandle = 0
    private var done = false
    private var lastTicks: UInt64 = 0
    private var tickAccumulator = 0.0

    private init?() {
        guard let data = mixManager.retrieve("CHOOSE.WSA"), let wsa = try? WSAFile(data: data),
              let pal = wsa.palette, let font = ClassicDialogArt.shared.scoreFont else {
            print("ChooseSide: CHOOSE.WSA (TRANSIT.MIX) or 12GRNGRD.FNT not installed — using the plain picker")
            return nil
        }
        anim = wsa
        player = WSAPlayer(wsa)
        self.font = font
        palette = pal.rgb8
        let art = ClassicDialogArt.shared
        gameAudio.stopMusic()  // Theme.Fade_Out before Choose_Side
        staticHandle = gameAudio.playSample("STRUGGLE", volume: 64)
        staticTimer = 0x3F
        typeText(art.text(660, "GLOBAL DEFENSE INITIATIVE"), x: 0, y: 180, pal: Self.yellowPal)
        typeText(art.text(661, "BROTHERHOOD OF NOD"), x: 180, y: 180, pal: Self.redPal)
        typeText(art.text(662, "SELECT TRANSMISSION"), x: 103, y: 190, pal: Self.grayPal)
        showFrame()
    }

    deinit {
        if let texture { SDL_DestroyTexture(texture) }
    }

    // MARK: Animation (the Choose_Side loop)

    /// Animate_Frame into the (cleared) SysMemPage, then rows 22-177 to
    /// PseudoSeenBuff — CHOOSE.WSA is 320x156 at (0, 22), so that is the
    /// frame itself.
    private func showFrame() {
        player.seek(to: frame)
        let wsa = player.wsa
        for y in 0..<wsa.height where wsa.y + y >= 22 && wsa.y + y < 22 + 156 {
            for x in 0..<wsa.width where wsa.x + x >= 0 && wsa.x + x < Self.pw {
                pseudo[(wsa.y + y) * Self.pw + wsa.x + x] = player.buffer[y * wsa.width + x]
            }
        }
        dirty = true
    }

    /// One 60 Hz tick: letters advance every tick (Call_Back_Delay runs
    /// Animate_Score_Objs), the animation every third.
    private func tick() {
        updatePrintJobs()
        staticTimer -= 1
        if chosen == nil && (!gameAudio.isSamplePlaying(staticHandle) || staticTimer <= 0) {
            gameAudio.stopSample(staticHandle)
            staticHandle = gameAudio.playSample("STRUGGLE", volume: 64)
            staticTimer = 0x3F
        }
        frameDelay += 1
        guard frameDelay >= 3 else { return }
        frameDelay = 0
        frame += 1
        if frame >= anim.frameCount { frame = 0 }
        if endFrame != frame || chosen == nil {
            showFrame()
        }
        if let side = chosen, frame == endFrame, !gameAudio.isSamplePlaying(speechHandle) {
            finish(side)
        }
    }

    private func pick(_ side: Faction) {
        guard chosen == nil else { return }
        chosen = side
        endFrame = side == .gdi ? 0 : 14
        speechHandle = gameAudio.playSample(side == .gdi ? "GDI_SLCT" : "NOD_SLCT")
    }

    /// Erase the captions, play the side's first movie, start the campaign.
    private func finish(_ side: Faction) {
        guard !done else { return }
        done = true
        gameAudio.stopSample(staticHandle)
        app.selectedFaction = side
        let movie = side == .gdi ? "GDI1" : "NOD1PRE"
        let briefed = MoviePlayerScreen.willPlay(movie)
        MoviePlayerScreen.play([movie]) {
            app.currentScreen = LaunchingScreen(faction: side, difficulty: app.selectedDifficulty, briefed: briefed)
        }
    }

    // MARK: Text (ScorePrintClass::Update, SCORE.CPP:291-327 — Win95 coordinates doubled)

    private func typeText(_ text: String, x: Int, y: Int, pal: [UInt8]) {
        printJobs.append(PrintJob(chars: Array(text.utf8), x: x, y: y, pal: pal))
    }

    private func updatePrintJobs() {
        guard !printJobs.isEmpty else { return }
        for j in printJobs.indices {
            let job = printJobs[j]
            let s = job.stage
            let pos = job.x + s * 6
            if s > 0 {
                let ch = String(UnicodeScalar(job.chars[s - 1]))
                draw(ch, 2 * (pos - 6), 2 * (job.y - 1), Self.blackPal)
                draw(ch, 2 * (pos - 6), 2 * (job.y + 1), Self.blackPal)
                draw(ch, 2 * (pos - 6 + 1), 2 * job.y, Self.blackPal)
                draw(ch, 2 * (pos - 6), 2 * job.y, job.pal)
            }
            if s < job.chars.count {
                let ch = String(UnicodeScalar(job.chars[s]))
                draw(ch, pos * 2, 2 * (job.y - 1), Self.whitePal)
                draw(ch, pos * 2, 2 * (job.y + 1), Self.whitePal)
                draw(ch, (pos + 1) * 2, 2 * job.y, Self.whitePal)
            }
            printJobs[j].stage += 1
        }
        printJobs.removeAll { $0.stage > $0.chars.count }
        dirty = true
    }

    private func draw(_ ch: String, _ x: Int, _ y: Int, _ pal: [UInt8]) {
        font.draw(ch, into: &textLayer, pageWidth: Self.tw, pageHeight: Self.th, x: x, y: y, remap: pal)
    }

    // MARK: Display

    func render(_ renderer: OpaquePointer?) {
        let now = SDL_GetPerformanceCounter()
        if lastTicks == 0 { lastTicks = now }
        tickAccumulator += Double(now - lastTicks) / Double(SDL_GetPerformanceFrequency()) * 60
        lastTicks = now
        var budget = 8
        while tickAccumulator >= 1 && budget > 0 && !done {
            tick()
            tickAccumulator -= 1
            budget -= 1
        }
        if budget == 0 { tickAccumulator = 0 }
        if done { return }

        if texture == nil {
            texture = SDL_CreateTexture(renderer, 0x16762004 /* ABGR8888 = RGBA bytes */,
                                        Int32(SDL_TEXTUREACCESS_STREAMING.rawValue), Int32(Self.tw), Int32(Self.th))
            SDL_SetTextureScaleMode(texture, SDL_ScaleModeLinear)
        }
        if dirty {
            let out = composeRGBA()
            out.withUnsafeBytes { _ = SDL_UpdateTexture(texture, nil, $0.baseAddress, Int32(Self.tw * 4)) }
            dirty = false
        }
        var dst = ClassicPage.displayRect()
        SDL_RenderCopy(renderer, texture, nil, &dst)
    }

    /// The page doubled with Interpolate_2X_Scale-style averaging, the text
    /// layer (index 0 transparent) on top.
    private func composeRGBA() -> [UInt8] {
        var out = [UInt8](repeating: 255, count: Self.tw * Self.th * 4)
        let w = Self.pw, h = Self.ph
        for Y in 0..<Self.th {
            let sy = Y >> 1, sy2 = (Y & 1 == 1 && sy + 1 < h) ? sy + 1 : sy
            for X in 0..<Self.tw {
                let di = (Y * Self.tw + X) * 4
                let t = textLayer[Y * Self.tw + X]
                if t != 0 {
                    out[di] = palette[Int(t) * 3]; out[di + 1] = palette[Int(t) * 3 + 1]; out[di + 2] = palette[Int(t) * 3 + 2]
                    continue
                }
                let sx = X >> 1, sx2 = (X & 1 == 1 && sx + 1 < w) ? sx + 1 : sx
                let a = Int(pseudo[sy * w + sx]) * 3, b = Int(pseudo[sy * w + sx2]) * 3
                let c = Int(pseudo[sy2 * w + sx]) * 3, d = Int(pseudo[sy2 * w + sx2]) * 3
                for k in 0..<3 {
                    out[di + k] = UInt8((Int(palette[a + k]) + Int(palette[b + k]) + Int(palette[c + k]) + Int(palette[d + k]) + 2) >> 2)
                }
            }
        }
        return out
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT), chosen == nil, let p = ClassicPage.pagePoint(x, y) else { return }
        // INTRO.CPP:213-238, in the Win95 build's 640x400 mouse coordinates.
        guard p.y > 48 * 2, p.y < 150 * 2 else { return }
        if p.x > 18 * 2 && p.x < 148 * 2 {
            pick(.gdi)
        } else if p.x > 160 * 2 && p.x < 300 * 2 {
            pick(.nod)
        }
    }

    func handleKeyDown(_ key: Int32) {
        guard key == Int32(SDLK_ESCAPE.rawValue), chosen == nil else { return }
        done = true
        gameAudio.stopSample(staticHandle)
        app.currentScreen = makeMainMenu()
    }
}

// MARK: - Headless (--test-choose)

extension ChooseSideScreen {
    static func makeForTesting() -> ChooseSideScreen? { ChooseSideScreen() }
    func testAdvance(ticks: Int) { for _ in 0..<ticks where !done { tick() } }
    func testSnapshot() -> [UInt8] { composeRGBA() }
    func testPick(_ side: Faction) { pick(side) }
    var testFrame: Int { frame }
    var testFinished: Bool { done }
}
