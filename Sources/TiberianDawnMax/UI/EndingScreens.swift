import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// MARK: - Campaign endings (GDI_Ending / Nod_Ending, ENDING.CPP)
//
// Do_Win (SCENARIO.CPP:430-450) runs these instead of the score screen and map
// selection after the last mission — GDI 15, Nod 13:
//
// GDI: GDIFINA, the score screen, GDIEND1, then the Tiberian Sun teaser
// (CC2TEASE). GDIFINB / GDIEND2 play when TempleIoned is set, but nothing in
// the source ever sets it (nor in the Remaster's DLL), so the A ending is
// the one the game shows.
//
// Nod: the score screen, NODFINAL, then Kane's satellite targeting: SATSEL.CPS
// under SATSEL.PAL while KANEFINL.AUD speaks over the LOOPIE6M.AUD loop; when
// Kane finishes, "Select a target" types out and a click on one of the four
// quadrants picks NODEND1-4 (top right is 1, top left 2, bottom left 3,
// bottom right 4), then the teaser.
//
// The ATTRACT2.CPS still the original shows for three seconds before the
// teaser isn't in the released data; the teaser follows directly.

/// After the final mission's win movie: the ending, the score screen in its
/// place in the sequence, then back to the title.
func playCampaignEnding(isGDI: Bool, scoreScreen: @escaping (_ then: @escaping () -> Void) -> Void) {
    let toTitle = { app.currentScreen = makeMainMenu(fadeIn: true) }
    if isGDI {
        MoviePlayerScreen.play(["GDIFINA"]) {
            scoreScreen {
                MoviePlayerScreen.play(["GDIEND1", "CC2TEASE"], then: toTitle)
            }
        }
    } else {
        scoreScreen {
            MoviePlayerScreen.play(["NODFINAL"]) {
                guard let screen = NodTargetScreen(then: { pick in
                    MoviePlayerScreen.play(["NODEND\(pick)", "CC2TEASE"], then: toTitle)
                }) else {
                    MoviePlayerScreen.play(["NODEND1", "CC2TEASE"], then: toTitle)
                    return
                }
                app.currentScreen = screen
            }
        }
    }
}

/// Nod_Ending's satellite target selection (ENDING.CPP:120-210).
final class NodTargetScreen: MenuScreen {
    private static let pw = 320, ph = 200, tw = 640, th = 400
    private static let tanPal: [UInt8] = [0x0, 0xED, 0xED, 0x2C, 0x2C, 0xFB, 0xFB, 0xFD, 0xFD, 0x0, 0x0, 0x0, 0x0, 0x0, 0x52, 0x0]
    private static let whitePal = [UInt8](repeating: 0x0F, count: 16)
    private static let blackPal = [UInt8](repeating: ClassicColor.black, count: 16)

    private let picture: [UInt8]
    private let palette: [UInt8]
    private let font: WWFont
    private let prompt: String
    private var textLayer = [UInt8](repeating: 0, count: tw * th)
    private var texture: OpaquePointer?
    private var dirty = true
    private let completion: (Int) -> Void

    private var kaneHandle = 0
    private var loopHandle = 0
    private var printing: (chars: [UInt8], stage: Int)?
    private var printed = false
    private var done = false
    private var lastTicks: UInt64 = 0
    private var tickAccumulator = 0.0

    init?(then completion: @escaping (Int) -> Void) {
        guard let cpsData = mixManager.retrieve("SATSEL.CPS"), let cps = try? CPSFile(data: cpsData),
              cps.pixels.count >= Self.pw * Self.ph,
              let pal = mixManager.retrieve("SATSEL.PAL").flatMap({ try? VGAPalette(data: $0) }),
              let font = ClassicDialogArt.shared.scoreFont else {
            print("NodTarget: SATSEL.CPS/PAL or 12GRNGRD.FNT missing — playing NODEND1")
            return nil
        }
        picture = cps.pixels
        palette = pal.rgb8
        self.font = font
        prompt = ClassicDialogArt.shared.text(675, "Select a target")
        self.completion = completion
        kaneHandle = gameAudio.playSample("KANEFINL", volume: 128)
        loopHandle = gameAudio.playSample("LOOPIE6M", volume: 128)
    }

    deinit {
        if let texture { SDL_DestroyTexture(texture) }
    }

    private var kaneSpeaking: Bool { gameAudio.isSamplePlaying(kaneHandle) }

    /// One 60 Hz tick of Nod_Ending's loop (Call_Back_Delay(1)).
    private func tick() {
        if !printed && !kaneSpeaking {
            printed = true
            printing = (Array(prompt.utf8), 0)
        }
        updatePrint()
        if !gameAudio.isSamplePlaying(loopHandle) {
            loopHandle = gameAudio.playSample("LOOPIE6M", volume: 128)
        }
    }

    /// ScorePrintClass::Update at (0, 180), coordinates doubled.
    private func updatePrint() {
        guard var p = printing else { return }
        let x = 0, y = 180
        let s = p.stage, pos = x + s * 6
        if s > 0 {
            let ch = String(UnicodeScalar(p.chars[s - 1]))
            draw(ch, 2 * (pos - 6), 2 * (y - 1), Self.blackPal)
            draw(ch, 2 * (pos - 6), 2 * (y + 1), Self.blackPal)
            draw(ch, 2 * (pos - 6 + 1), 2 * y, Self.blackPal)
            draw(ch, 2 * (pos - 6), 2 * y, Self.tanPal)
        }
        if s < p.chars.count {
            let ch = String(UnicodeScalar(p.chars[s]))
            draw(ch, pos * 2, 2 * (y - 1), Self.whitePal)
            draw(ch, pos * 2, 2 * (y + 1), Self.whitePal)
            draw(ch, (pos + 1) * 2, 2 * y, Self.whitePal)
        }
        p.stage += 1
        printing = p.stage > p.chars.count ? nil : p
        dirty = true
    }

    private func draw(_ ch: String, _ x: Int, _ y: Int, _ pal: [UInt8]) {
        font.draw(ch, into: &textLayer, pageWidth: Self.tw, pageHeight: Self.th, x: x, y: y, remap: pal)
    }

    /// The quadrant under a click in 640x400 coordinates, or nil outside the
    /// picture band (ENDING.CPP:178-186).
    static func target(atX x: Int, y: Int) -> Int? {
        guard y >= 22 * 2 && y <= 177 * 2 else { return nil }
        if x < 160 * 2 && y < 100 * 2 { return 2 }
        if x < 160 * 2 && y >= 100 * 2 { return 3 }
        if x >= 160 * 2 && y >= 100 * 2 { return 4 }
        return 1
    }

    private func choose(_ pick: Int) {
        guard !done else { return }
        done = true
        gameAudio.stopSample(loopHandle)
        completion(pick)
    }

    // MARK: MenuScreen

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

    /// SATSEL doubled with Interpolate_2X_Scale-style averaging, text on top.
    func composeRGBA() -> [UInt8] {
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
                let a = Int(picture[sy * w + sx]) * 3, b = Int(picture[sy * w + sx2]) * 3
                let c = Int(picture[sy2 * w + sx]) * 3, d = Int(picture[sy2 * w + sx2]) * 3
                for k in 0..<3 {
                    out[di + k] = UInt8((Int(palette[a + k]) + Int(palette[b + k]) + Int(palette[c + k]) + Int(palette[d + k]) + 2) >> 2)
                }
            }
        }
        return out
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        // Clicks are thrown away while Kane is still speaking.
        guard button == UInt8(SDL_BUTTON_LEFT), !kaneSpeaking, let p = ClassicPage.pagePoint(x, y),
              let pick = Self.target(atX: p.x, y: p.y) else { return }
        choose(pick)
    }

    func handleKeyDown(_ key: Int32) {}
}

// MARK: - Headless (--test-ending)

extension NodTargetScreen {
    func testAdvance(ticks: Int) { for _ in 0..<ticks where !done { tick() } }
}
