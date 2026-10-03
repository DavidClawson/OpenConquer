import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// MARK: - Map Selection Screen (campaign branching)
//
// The between-missions territory pick, ported from Map_Selection
// (MAPSEL.CPP:213-802): the grey globe fades in and turns to colour, the globe
// spins and zooms on Europe (GDI) or Africa (Nod), last mission's territories
// dissolve in, crosshairs flash over the candidates, and the player clicks a
// country — resolved through the hidden CLICK_*.CPS colour map, exactly like
// the original. The chosen country is drawn over the clean map, everything
// else fades dark (DARK_E.PAL) and its statistics type out (Print_Statistics).
//
// The original is one blocking function paced by Call_Back_Delay in 60 Hz
// timer ticks; here it is a list of steps run by a 60 Hz tick. Pages mirror
// the original's: `page` = PseudoSeenBuff (what is shown, 320x200),
// `sysPage` = SysMemPage (scratch, later the click map), `textLayer` =
// TextPrintBuffer (index 0 transparent). The original's TextPrintBuffer is
// 640x400 with every coordinate doubled, but SCOREFNT is a 6-pixel font laid
// out on a 6-pixel grid, so it is kept here at 320x200 and pixel-doubled. The
// shown image is `page` doubled with interpolation (Interpolate_2X_Scale)
// under the text.
//
// The original loops until a valid country is clicked; there is no cancel.
// Esc or Space fast-forwards the intro to the selection. Falls back to the
// plain list (MapSelectionListScreen) when the art isn't installed.

final class MapSelectionScreen: MenuScreen {

    /// The animated screen if its art is installed, else the plain list.
    static func make(choices: [CampaignChoice]) -> MenuScreen {
        MapSelectionScreen(choices: choices) ?? MapSelectionListScreen(choices: choices)
    }

    private typealias Data_ = MapSelectionData

    // MARK: Setup

    private let choices: [CampaignChoice]
    private let isGDI: Bool
    private let last: Bool
    private let dirIdx: Int
    private let country: MapSelectionData.Country
    private let strings: StringTable
    private let font: WWFont

    private let greyEarth: WSAFile
    private let greyEarth2: WSAFile
    private let earth: WSAFile
    private let progressWSA: WSAFile
    private let clickCPS: CPSFile
    private let countryShapes: SHPFile?
    private let darkPalette: [UInt8]?

    // Pages (see the header comment).
    private static let w = 320, h = 200, tw = 640, th = 400
    private var page = [UInt8](repeating: 0, count: w * h)
    private var sysPage = [UInt8](repeating: 0, count: w * h)
    private var textLayer = [UInt8](repeating: 0, count: w * h)
    private var europe = [UInt8](repeating: 0, count: w * h)
    private var backPage = [UInt8](repeating: 0, count: 120 * 8)

    // Palette (8-bit RGB) and its fade / colour-cycle state.
    private var palette = [UInt8](repeating: 0, count: 768)
    private var fade: (from: [UInt8], to: [UInt8], tick: Int, length: Int)?
    private var cycling = false
    private var cycleCounter = 0

    private var progress: WSAPlayer
    private var anim: WSAPlayer

    // Step engine.
    private enum Step {
        case run(() -> Void)
        case wait(Int)
        case until(() -> Bool)
    }
    private var steps: [Step] = []
    private var waitLeft = 0
    private var skipping = false
    private var tickAccumulator: Double = 0
    private var lastTicks: UInt64 = 0

    // Typed text (ScorePrintClass / MultiStagePrintClass).
    private struct PrintJob {
        let chars: [UInt8]
        let x: Int, y: Int
        let remap: [UInt8]
        let perTick: Int
        var stage = 0
    }
    private var printJobs: [PrintJob] = []

    // Interaction.
    private enum Phase { case intro, selecting, stats, awaitingContinue, leaving }
    private var phase = Phase.intro
    private var selection = 0
    private var finished = false

    private var texture: OpaquePointer?
    private var dirty = true

    // Font palettes (MAPSEL.CPP:244-246, SCORE.CPP).
    private static let greenPal: [UInt8] = [0, 0x41, 0x42, 0x43] + [UInt8](repeating: 0x44, count: 12)
    private static let otherGreenPal: [UInt8] = [0, 0x21, 0x22, 0x23, 0x24, 0x25] + [UInt8](repeating: 0x26, count: 10)
    private static let whitePal = [UInt8](repeating: 0x0F, count: 16)
    /// TD's BLACK (index 12 in the game palettes, DEFINES.H) — used for erase fills.
    private static let black: UInt8 = 12
    private static let blackPal = [UInt8](repeating: black, count: 16)

    private init?(choices: [CampaignChoice]) {
        let state = session.campaignState
        let gdi = state.currentFaction == "GDI"
        // Map_Selection indexes the just-won mission (post-skip row); after
        // completeMission() that is currentMission - 1, and `dir` is still
        // the direction of the mission just won (ScenDir).
        let row = state.currentMission - 1
        guard row >= 1, let entry = Data_.countries[safe: row + (gdi ? 0 : 14)] ?? nil else { return nil }
        let dirIdx = state.dir == "W" ? 1 : 0
        guard entry.choices[dirIdx] > 0 else { return nil }

        func wsa(_ n: String) -> WSAFile? { mixManager.retrieve(n).flatMap { try? WSAFile(data: $0) } }
        let last = gdi ? row == 14 : row == 12
        guard let strData = mixManager.retrieve("CONQUER.ENG"), let strings = StringTable(data: strData),
              let fontData = mixManager.retrieve("SCOREFNT.FNT"), let font = WWFont(data: fontData),
              let grey = wsa("GREYERTH.WSA"), let grey2 = wsa("E-BWTOCL.WSA"),
              let earth = wsa(gdi ? "EARTH_E.WSA" : "EARTH_A.WSA"),
              let prog = wsa(gdi ? (last ? "BOSNIA.WSA" : "EUROPE.WSA") : (last ? "S_AFRICA.WSA" : "AFRICA.WSA")),
              let clickData = mixManager.retrieve(gdi ? (last ? "CLICK_EB.CPS" : "CLICK_E.CPS")
                                                      : (last ? "CLICK_SA.CPS" : "CLICK_A.CPS")),
              let click = try? CPSFile(data: clickData) else {
            print("MapSelection: art not installed — using the list")
            return nil
        }
        self.choices = choices.isEmpty ? [CampaignChoice(dir: "E", variant: "A")] : choices
        self.isGDI = gdi
        self.last = last
        self.dirIdx = dirIdx
        self.country = entry
        self.strings = strings
        self.font = font
        self.greyEarth = grey
        self.greyEarth2 = grey2
        self.earth = earth
        self.progressWSA = prog
        self.clickCPS = click
        self.countryShapes = mixManager.retrieve(gdi ? "COUNTRYE.SHP" : "COUNTRYA.SHP").flatMap { try? SHPFile(data: $0) }
        let darkName = last ? (gdi ? "DARK_B.PAL" : "DARK_SA.PAL") : "DARK_E.PAL"
        self.darkPalette = mixManager.retrieve(darkName).flatMap { try? VGAPalette(data: $0) }?.rgb8
        self.progress = WSAPlayer(prog)
        self.anim = WSAPlayer(earth)
        buildIntro()
    }

    deinit {
        if let texture { SDL_DestroyTexture(texture) }
    }

    // MARK: Script (MAPSEL.CPP:253-686)

    private func buildIntro() {
        let gdi = isGDI
        let last = self.last

        run { gameAudio.playTheme(.map1) }

        // Grey earth fades in (283-342).
        var grey = WSAPlayer(greyEarth)
        run { [self] in
            animate(&grey, frame: 0, onto: &page)
            sample("APPEAR1", 110)
            startFade(to: greyEarth.palette?.rgb8)
        }
        until { [self] in fade == nil }
        for i in 1..<greyEarth.frameCount {
            wait(4)
            run { [self] in animate(&grey, frame: i, onto: &page) }
        }

        // Grey to colour (344-360).
        wait(4)
        var grey2 = WSAPlayer(greyEarth2)
        run { [self] in
            sysPage.fill(0)
            animate(&grey2, frame: 0, onto: &sysPage)
            setPalette(greyEarth2.palette?.rgb8)
            page = sysPage
        }
        wait(4)
        for i in 1..<greyEarth2.frameCount {
            run { [self] in animate(&grey2, frame: i, onto: &page) }
            wait(4)
        }

        // The spinning globe (365-454). EARTH_E/A have the status captions
        // baked into their frames (the shipped code prints them over the
        // caption-less Win95 H-variants), so only the sounds are kept here.
        run { [self] in
            sysPage.fill(0)
            animate(&anim, frame: 1, onto: &sysPage)
            page = sysPage
            setPalette(earth.palette?.rgb8)
            sample("SFX4", 130)
            sample("TEXT2", 90)
        }
        for frame in 1..<earth.frameCount {
            run { [self] in
                if [16, 33, 44, 70, 73].contains(frame) { sample("TEXT2", 90) }
                if frame == 21 || frame == 27 { sample("TARGET1", 90) }
                if [45, 47, 49].contains(frame) { sample("BEEPY6", 90) }
                if frame == 51 { sample("WORLD2", 90) }
                if frame == 70 || frame == 72 { sample("BEEPY2", 90) }
                if frame == 74 { sample("TARGET2", 110) }
                animate(&anim, frame: frame, onto: &page)
            }
            wait(3)
        }
        wait(2)

        // Freeze on Europe / Africa; last mission's territories (463-483).
        let startFrame = country.start[dirIdx]
        run { [self] in
            sysPage.fill(0)
            animate(&progress, frame: 0, onto: &sysPage)
            page = sysPage
            europe = sysPage
            if startFrame != 0 {
                animate(&progress, frame: startFrame, onto: &sysPage)
                page = sysPage
            }
            setPalette(progressWSA.palette?.rgb8)
        }
        wait(45)

        // First advance of territories (489-503).
        let xcoord = gdi ? 0 : 204
        run { [self] in
            copyRect(from: sysPage, x: xcoord, y: 1, w: 120, h: 8, into: &backPage)
            sample("TEXT2", 90)
            typeText(strings[Data_.mapGdi + (gdi ? 0 : 1)], x: xcoord, y: 2, remap: Self.greenPal)
        }
        wait(60)
        run { [self] in
            sample("COUNTRY1", 90)
            animate(&progress, frame: startFrame + 1, onto: &sysPage)
            beginDissolve()
        }
        until { [self] in dissolve == nil }
        run { [self] in pasteRect(backPage, w: 120, h: 8, into: &sysPage, x: xcoord, y: 1) }
        wait(85)

        // Second advance (508-540).
        run { [self] in
            page.fillRect(x1: xcoord, y1: 0, x2: xcoord + 6 * 16, y2: 8, color: Self.black, width: Self.w)
            textLayer.fillRect(x1: xcoord, y1: 0, x2: xcoord + 6 * 16, y2: 8, color: Self.black, width: Self.w)
            copyRect(from: sysPage, x: xcoord, y: 1, w: 120, h: 8, into: &backPage)
            if !last {
                sample("TEXT2", 90)
                typeText(strings[gdi ? Data_.mapNod : Data_.mapGdi], x: xcoord, y: 12, remap: Self.greenPal)
            }
        }
        if !last { wait(65) }
        run { [self] in
            sample("COUNTRY1", 90)
            animate(&progress, frame: startFrame + 2, onto: &sysPage)
            beginDissolve()
        }
        until { [self] in dissolve == nil }
        run { [self] in pasteRect(backPage, w: 120, h: 8, into: &sysPage, x: xcoord, y: 11) }
        if !last { wait(85) }
        run { [self] in
            page.fillRect(x1: xcoord, y1: 12, x2: xcoord + 6 * 16, y2: 20, color: Self.black, width: Self.w)
            textLayer.fillRect(x1: xcoord, y1: 12, x2: xcoord + 6 * 16, y2: 20, color: Self.black, width: Self.w)
        }

        // "Locating coordinates of next mission" (547-555).
        run { [self] in
            sample("TEXT2", 90)
            typeText(strings[Data_.mapLocate], x: 0, y: 160, remap: Self.greenPal)
        }
        wait(20)
        run { [self] in typeText(strings[Data_.mapNextMission], x: 0, y: 170, remap: Self.greenPal) }
        wait(50)
        if last {
            run { [self] in
                sysPage.fillRect(x1: 0, y1: 160, x2: 120, y2: 176, color: 0, width: Self.w)
                page.fillRect(x1: 0, y1: 160, x2: 120, y2: 176, color: 0, width: Self.w)
                textLayer.fillRect(x1: 0, y1: 160, x2: 120, y2: 176, color: Self.black, width: Self.w)
            }
        }

        // Crosshairs over the candidates (594-649): frames 0-4, then 3-4
        // four more times, then on to 12 (the whole anim on the last mission).
        let contFrame = country.cont[dirIdx]
        var sequence: [Int] = []
        var q = 0
        var frame = 0
        let end = last ? progressWSA.frameCount - 4 : 13
        while frame < end {
            sequence.append(frame)
            if !last && frame == 4 && q < 4 { frame = 2; q += 1 }
            frame += 1
        }
        for f in sequence {
            run { [self] in
                if f == 0 || f == 2 { sample("BEEPY3", 90) }
                if f == 6 { sample("NEWTARG1", 90) }
                if last { lastScenarioCaption(frame: f) }
                animate(&progress, frame: contFrame + f, onto: &page)
            }
            wait(6)
        }

        // Erase "locating…", load the click map, prompt (651-686).
        let attackX = (!gdi && last) ? 200 : 0
        run { [self] in
            sample("BEEPY6", 90)
            if !last {
                sysPage.fillRect(x1: 0, y1: 160, x2: 120, y2: 176, color: 0, width: Self.w)
                page.fillRect(x1: 0, y1: 160, x2: 120, y2: 176, color: 0, width: Self.w)
                textLayer.fillRect(x1: 0, y1: 160, x2: 120, y2: 176, color: Self.black, width: Self.w)
            }
            sysPage = clickCPS.pixels
            sample("TEXT2", 90)
            typeText(strings[Data_.mapSelect], x: attackX, y: 160, remap: Self.greenPal)
            cycling = true
        }
        wait(16)
        run { [self] in typeText(strings[Data_.mapToAttack], x: attackX, y: 170, remap: Self.greenPal) }
        wait(24)
        run { [self] in phase = .selecting; skipping = false }
    }

    /// The last-mission caption over BOSNIA/S_AFRICA (MAPSEL.CPP:601-639),
    /// including case 23's fall-through into case 35.
    private func lastScenarioCaption(frame: Int) {
        let x = isGDI ? 0 : 210
        let width = font.width(of: strings[Data_.enhancingImage])
        if frame == 23 {
            typeText(strings[Data_.enhancingImage], x: x, y: 10, remap: Self.otherGreenPal, perTick: 10)
        }
        if frame == 23 || frame == 35 {
            textLayer.fillRect(x1: x, y1: 10, x2: x + width, y2: 22, color: Self.black, width: Self.w)
        } else if frame == 36 {
            textLayer.fillRect(x1: x, y1: 10, x2: x + width, y2: 22, color: 0, width: Self.w)
        }
    }

    // MARK: Selection (MAPSEL.CPP:690-792)

    private func select(atPageX x: Int, y: Int) {
        guard phase == .selecting else { return }
        var color = Int(clickCPS.index(x: x, y: y) ?? 0)
        let count = country.choices[dirIdx]
        for sel in 0..<count {
            let want = country.colors[dirIdx][sel]
            // Special hack for Egypt the second time through (702-704).
            if want == 0xA0 && (color == 0x80 || color == 0x81) { color = 0xA0 }
            if want == color {
                sample("WORLD2", 90)
                selection = sel
                beginStats(color: color)
                return
            }
            sample("SCOLD1", 90)
        }
    }

    private func beginStats(color: Int) {
        phase = .stats
        cycling = false
        steps.removeAll()
        waitLeft = 0
        let attackX = (!isGDI && last) ? 200 : 0

        if !last {
            let shape = country.shapes[dirIdx][selection]
            let xy = shape + (isGDI ? 0 : 18)
            let cx = Data_.countryX[safe: xy] ?? 160, cy = Data_.countryY[safe: xy] ?? 100
            run { [self] in
                page.fillRect(x1: attackX, y1: 160, x2: attackX + 17 * 6, y2: 178, color: Self.black, width: Self.w)
                textLayer.fillRect(x1: attackX, y1: 160, x2: attackX + 17 * 6, y2: 178,
                                   color: Self.black, width: Self.w)
                sysPage = europe
                if let f = countryShapes?.frames[safe: shape] {
                    sysPage.drawShape(f, centerX: cx, centerY: cy, width: Self.w, height: Self.h)
                }
                page = sysPage
                startFade(to: darkPalette)
            }
            until { [self] in fade == nil }
            printStatistics(country: color & 0x7F, x: cx, y: cy)
        } else {
            run { [self] in
                if let darkPalette { setPalette(darkPalette) }
                page.fillRect(x1: attackX, y1: 160, x2: attackX + 17 * 6, y2: 199, color: Self.black, width: Self.w)
                textLayer.fillRect(x1: attackX, y1: 160, x2: attackX + 17 * 6, y2: 199,
                                   color: Self.black, width: Self.w)
                animate(&progress, frame: progressWSA.frameCount - 1, onto: &page)
                sysPage = page
            }
            printStatistics(country: 20, x: 160, y: isGDI ? 0 : 160)
        }
    }

    /// Print_Statistics (MAPSEL.CPP:819-1034).
    private func printStatistics(country input: Int, x: Int, y: Int) {
        let xpos = x > 128 ? 8 : 136
        var ypos = y > 100 ? 8 : 104 - 6
        var lines: [(label: Int, value: String)] = []
        let nameIndex: Int
        if isGDI {
            guard let s = Data_.gdiStats[safe: input] else { return }
            nameIndex = s[0]
            lines = [
                (Data_.gdiStatNames[0], strings[s[1]]),
                (Data_.gdiStatNames[1], strings[s[2]]),
                (Data_.gdiStatNames[2], strings[s[3]]),
                (Data_.gdiStatNames[3], strings[Data_.govtNames[s[4]]]),
                (Data_.gdiStatNames[4], strings[s[5]]),
                (Data_.gdiStatNames[5], strings[s[6]]),
                (Data_.gdiStatNames[6], strings[Data_.armyNames[s[7]]]),
            ]
        } else {
            var c = input
            if c > 30 { c = 15 } else if c >= 15 { c += 1 }   // the Egypt hacks
            c += 1
            guard let s = Data_.nodStats[safe: c] else { return }
            nameIndex = s[0]
            lines = [
                (Data_.nodStatNames[0], strings[s[1]]),
                (Data_.nodStatNames[1], "\(s[2])%"),
                (Data_.nodStatNames[2], strings[s[3]]),
                (Data_.nodStatNames[3], strings[Data_.govtNames[s[4]]]),
                (Data_.nodStatNames[4], "\(s[5])%"),
                (Data_.nodStatNames[5], strings[s[6]]),
                (Data_.nodStatNames[6], strings[s[7]]),
                (Data_.nodStatNames[7], strings[Data_.militaryNames[s[8]]]),
                (Data_.nodStatNames[8], "\(s[9])%"),
            ]
        }
        let name = strings[Data_.countryNames[nameIndex]]
        let headY = ypos
        run { [self] in typeText(name, x: xpos, y: headY, remap: Self.greenPal) }
        wait(name.count * 3)
        ypos += 16
        for line in lines {
            let label = strings[line.label]
            let lineY = ypos
            run { [self] in typeText(label, x: xpos, y: lineY, remap: Self.greenPal) }
            // The original waits strlen(Text_String(id + 3)) — an off-by-
            // pointer slip kept for timing fidelity (MAPSEL.CPP:930).
            wait(strings[line.label + 3].count)
            let value = line.value
            let valueX = xpos + 6 * label.count
            run { [self] in typeText(value, x: valueX, y: lineY, remap: Self.greenPal) }
            ypos += 8
        }
        run { [self] in typeText(strings[Data_.mapClick2], x: 160 - 17 * 3, y: 193 - 6, remap: Self.greenPal) }
        until { [self] in printJobs.isEmpty }
        run { [self] in phase = .awaitingContinue; skipping = false }
    }

    /// After the click: music off, fade to black, commit the choice (794-801).
    private func leave() {
        guard phase == .awaitingContinue else { return }
        phase = .leaving
        run { [self] in
            gameAudio.stopMusic()
            startFade(to: [UInt8](repeating: 0, count: 768))
        }
        until { [self] in fade == nil }
        run { [self] in
            guard !finished else { return }
            finished = true
            let choice = choices[safe: selection] ?? choices[0]
            session.campaignState.advance(choosing: choice)
            session.campaign.pendingChoices = []
            showPreMissionMovies()
        }
    }

    // MARK: Step engine

    private func run(_ f: @escaping () -> Void) { steps.append(.run(f)) }
    private func wait(_ ticks: Int) { if ticks > 0 { steps.append(.wait(ticks)) } }
    private func until(_ cond: @escaping () -> Bool) { steps.append(.until(cond)) }

    /// One 60 Hz timer tick (Call_Back + one tick of Call_Back_Delay).
    private func tick() {
        updatePrintJobs()
        updateFade()
        updateDissolve()
        if cycling { cyclePalette() }

        if waitLeft > 0 {
            waitLeft -= 1
            if waitLeft > 0 && !skipping { return }
            waitLeft = 0
        }
        while !steps.isEmpty {
            switch steps[0] {
            case .run(let f):
                steps.removeFirst()
                f()
            case .wait(let n):
                steps.removeFirst()
                if skipping { continue }
                waitLeft = n
                return
            case .until(let cond):
                if cond() { steps.removeFirst() } else { return }
            }
        }
    }

    /// Esc / Space: run the intro out to the country prompt at once, quietly.
    private func fastForward() {
        guard phase == .intro || phase == .stats else { return }
        skipping = true
        var guardTicks = 100_000
        while skipping && guardTicks > 0 && !steps.isEmpty {
            tick()
            guardTicks -= 1
        }
        skipping = false
        dirty = true
    }

    // MARK: Drawing primitives

    /// Animate_Frame onto a page: the original XORs each delta into whatever
    /// page it is given, so changes land on top of anything drawn there.
    private func animate(_ player: inout WSAPlayer, frame: Int, onto target: inout [UInt8]) {
        let old = player.buffer
        player.seek(to: frame)
        let wsa = player.wsa
        player.buffer.withUnsafeBufferPointer { new in
            old.withUnsafeBufferPointer { old in
                for y in 0..<wsa.height {
                    let ty = wsa.y + y
                    guard ty >= 0 && ty < Self.h else { continue }
                    for x in 0..<wsa.width {
                        let tx = wsa.x + x
                        guard tx >= 0 && tx < Self.w else { continue }
                        let d = old[y * wsa.width + x] ^ new[y * wsa.width + x]
                        if d != 0 { target[ty * Self.w + tx] ^= d }
                    }
                }
            }
        }
        dirty = true
    }

    private func copyRect(from src: [UInt8], x: Int, y: Int, w: Int, h: Int, into dst: inout [UInt8]) {
        for row in 0..<h {
            for col in 0..<w { dst[row * w + col] = src[(y + row) * Self.w + x + col] }
        }
    }

    private func pasteRect(_ src: [UInt8], w: Int, h: Int, into dst: inout [UInt8], x: Int, y: Int) {
        for row in 0..<h {
            for col in 0..<w { dst[(y + row) * Self.w + x + col] = src[row * w + col] }
        }
    }

    private func sample(_ name: String, _ volume: Int) {
        if !skipping { gameAudio.playSample(name, volume: volume) }
    }

    // MARK: Pixel dissolve (Bit_It_In_Scale, MAPSEL.CPP:1207-1270)

    private var dissolve: (line: Int, xIndex: [Int], yIndex: [Int])?

    /// Dissolve sysPage into page over ~100 ticks (one tick per two lines,
    /// delay = 1), with the "dagger" wedge spreading down from the top centre.
    private func beginDissolve() {
        var xi = Array(0..<Self.w), yi = Array(0..<Self.h)
        for i in 0..<Self.w { xi.swapAt(Int.random(in: 0..<Self.w), i) }
        for i in 0..<Self.h { yi.swapAt(Int.random(in: 0..<Self.h), i) }
        dissolve = (0, xi, yi)
        if skipping { while dissolve != nil { updateDissolve() } }
    }

    private func updateDissolve() {
        guard var d = dissolve else { return }
        repeat {
            let j = d.line
            var j1 = j
            for i in 0..<Self.w {
                let k = d.xIndex[i], m = d.yIndex[j1]
                j1 += 1
                if j1 >= Self.h { j1 = 0 }
                page[m * Self.w + k] = sysPage[m * Self.w + k]
            }
            for q in stride(from: j, through: 0, by: -1) where q < Self.h {
                for x in [160 - (j - q), 160 + (j - q)] where x >= 0 && x < Self.w {
                    page[q * Self.w + x] = sysPage[q * Self.w + x]
                }
            }
            d.line += 1
        } while d.line < Self.h && d.line % 2 == 1
        dissolve = d.line >= Self.h ? nil : d
        dirty = true
    }

    // MARK: Text (ScorePrintClass::Update, SCORE.CPP:291-344)

    private func typeText(_ text: String, x: Int, y: Int, remap: [UInt8], perTick: Int = 1) {
        let job = PrintJob(chars: Array(text.utf8), x: x, y: y, remap: remap, perTick: perTick)
        printJobs.append(job)
        if skipping { while !printJobs.isEmpty { updatePrintJobs() } }
    }

    private func updatePrintJobs() {
        guard !printJobs.isEmpty else { return }
        for j in printJobs.indices {
            for _ in 0..<printJobs[j].perTick {
                let job = printJobs[j]
                let s = job.stage
                if s > job.chars.count { break }
                let pos = job.x + s * 6
                if s > 0 {
                    // Settle the previous letter: black shadow, then colour.
                    let ch = String(UnicodeScalar(job.chars[s - 1]))
                    drawText(ch, x: pos - 6, y: job.y - 1, remap: Self.blackPal)
                    drawText(ch, x: pos - 6, y: job.y + 1, remap: Self.blackPal)
                    drawText(ch, x: pos - 6 + 1, y: job.y, remap: Self.blackPal)
                    drawText(ch, x: pos - 6, y: job.y, remap: job.remap)
                }
                if s < job.chars.count {
                    // The leading letter glows white.
                    let ch = String(UnicodeScalar(job.chars[s]))
                    drawText(ch, x: pos, y: job.y - 1, remap: Self.whitePal)
                    drawText(ch, x: pos, y: job.y + 1, remap: Self.whitePal)
                    drawText(ch, x: pos + 1, y: job.y, remap: Self.whitePal)
                }
                printJobs[j].stage += 1
            }
        }
        printJobs.removeAll { $0.stage > $0.chars.count }
        dirty = true
    }

    private func drawText(_ text: String, x: Int, y: Int, remap: [UInt8]) {
        font.draw(text, into: &textLayer, pageWidth: Self.w, pageHeight: Self.h, x: x, y: y, remap: remap)
    }

    // MARK: Palette

    private func setPalette(_ p: [UInt8]?) {
        guard let p, p.count == 768 else { return }
        palette = p
        fade = nil
        dirty = true
    }

    /// Fade_Palette_To(…, FADE_PALETTE_MEDIUM): a quarter second.
    private func startFade(to p: [UInt8]?) {
        guard let p, p.count == 768 else { return }
        if skipping { setPalette(p); return }
        fade = (palette, p, 0, 15)
    }

    private func updateFade() {
        guard var f = fade else { return }
        f.tick += 1
        let t = Double(f.tick) / Double(f.length)
        for i in 0..<768 {
            palette[i] = UInt8(Double(f.from[i]) + (Double(f.to[i]) - Double(f.from[i])) * min(1, t))
        }
        fade = f.tick >= f.length ? nil : f
        dirty = true
    }

    /// Cycle_Call_Back_Delay: rotate entries 249-254 every fourth tick — the
    /// flashing target markers.
    private func cyclePalette() {
        cycleCounter = (cycleCounter + 1) & 3
        guard cycleCounter == 0 else { return }
        let first = Array(palette[249 * 3..<249 * 3 + 3])
        for i in 249..<254 {
            for c in 0..<3 { palette[i * 3 + c] = palette[(i + 1) * 3 + c] }
        }
        for c in 0..<3 { palette[254 * 3 + c] = first[c] }
        dirty = true
    }

    // MARK: MenuScreen

    func render(_ renderer: OpaquePointer?) {
        // 60 Hz timer ticks, independent of the render rate.
        let now = SDL_GetPerformanceCounter()
        if lastTicks == 0 { lastTicks = now }
        tickAccumulator += Double(now - lastTicks) / Double(SDL_GetPerformanceFrequency()) * 60
        lastTicks = now
        var budget = 8  // don't spiral after a stall
        while tickAccumulator >= 1 && budget > 0 && !finished {
            tick()
            tickAccumulator -= 1
            budget -= 1
        }
        if budget == 0 { tickAccumulator = 0 }
        if finished { return }

        if dirty { compose(renderer); dirty = false }
        if let texture {
            var dst = displayRect()
            SDL_RenderCopy(renderer, texture, nil, &dst)
        }
    }

    /// 640x400 shown at 4:3, letterboxed.
    private func displayRect() -> SDL_Rect {
        let ww = Double(renderState.windowWidth), wh = Double(renderState.windowHeight)
        let srcW = 640.0, srcH = 480.0
        let scale = min(ww / srcW, wh / srcH)
        let w = srcW * scale, h = srcH * scale
        return SDL_Rect(x: Int32((ww - w) / 2), y: Int32((wh - h) / 2), w: Int32(w), h: Int32(h))
    }

    private func compose(_ renderer: OpaquePointer?) {
        if texture == nil {
            texture = SDL_CreateTexture(renderer, 0x16762004 /* ABGR8888 = RGBA bytes */,
                                        Int32(SDL_TEXTUREACCESS_STREAMING.rawValue), Int32(Self.tw), Int32(Self.th))
            SDL_SetTextureScaleMode(texture, SDL_ScaleModeLinear)
        }
        let out = composeRGBA()
        out.withUnsafeBytes { _ = SDL_UpdateTexture(texture, nil, $0.baseAddress, Int32(Self.tw * 4)) }
    }

    /// 640x400 RGBA: page doubled with Interpolate_2X_Scale-style averaging,
    /// text pixel-doubled on top.
    private func composeRGBA() -> [UInt8] {
        var out = [UInt8](repeating: 255, count: Self.tw * Self.th * 4)
        let w = Self.w, h = Self.h, tw = Self.tw
        page.withUnsafeBufferPointer { pg in
            palette.withUnsafeBufferPointer { pal in
                textLayer.withUnsafeBufferPointer { txt in
                    out.withUnsafeMutableBufferPointer { o in
                        for Y in 0..<Self.th {
                            let sy = Y >> 1, sy2 = (Y & 1 == 1 && sy + 1 < h) ? sy + 1 : sy
                            for X in 0..<tw {
                                let di = (Y * tw + X) * 4
                                let t = txt[(Y >> 1) * w + (X >> 1)]
                                if t != 0 {
                                    o[di] = pal[Int(t) * 3]; o[di + 1] = pal[Int(t) * 3 + 1]; o[di + 2] = pal[Int(t) * 3 + 2]
                                    continue
                                }
                                let sx = X >> 1, sx2 = (X & 1 == 1 && sx + 1 < w) ? sx + 1 : sx
                                let a = Int(pg[sy * w + sx]) * 3, b = Int(pg[sy * w + sx2]) * 3
                                let c = Int(pg[sy2 * w + sx]) * 3, d = Int(pg[sy2 * w + sx2]) * 3
                                for k in 0..<3 {
                                    o[di + k] = UInt8((Int(pal[a + k]) + Int(pal[b + k]) + Int(pal[c + k]) + Int(pal[d + k]) + 2) >> 2)
                                }
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        switch phase {
        case .selecting:
            let r = displayRect()
            guard r.w > 0, r.h > 0 else { return }
            let px = Int(Double(x - r.x) * 320 / Double(r.w))
            let py = Int(Double(y - r.y) * 200 / Double(r.h))
            guard px >= 0, px < Self.w, py >= 0, py < Self.h else { return }
            select(atPageX: px, y: py)
        case .awaitingContinue:
            leave()
        case .intro, .stats, .leaving:
            break
        }
    }

    func handleKeyDown(_ key: Int32) {
        switch phase {
        case .intro, .stats:
            if key == Int32(SDLK_ESCAPE.rawValue) || key == Int32(SDLK_SPACE.rawValue) { fastForward() }
        case .awaitingContinue:
            leave()
        case .selecting, .leaving:
            break
        }
    }
}

// MARK: - Headless driving (--test-map-select)

extension MapSelectionScreen {
    static func makeForTesting(choices: [CampaignChoice]) -> MapSelectionScreen? {
        MapSelectionScreen(choices: choices)
    }

    var testPhase: String { "\(phase)" }
    var testFrameSize: (width: Int, height: Int) { (Self.tw, Self.th) }

    func testAdvance(ticks: Int) {
        for _ in 0..<ticks where !finished { tick() }
    }

    func testSnapshot() -> [UInt8] { composeRGBA() }

    /// Click the first click-map pixel of choice `index`'s colour (or of a
    /// colour that matches none, when `index` is nil). Returns false if the
    /// colour isn't on the map.
    func testClick(choice index: Int?) -> Bool {
        let wanted: Set<Int>
        if let index {
            let c = country.colors[dirIdx][index]
            wanted = c == 0xA0 ? [0xA0, 0x80, 0x81] : [c]
        } else {
            wanted = Set(0...255).subtracting(country.colors[dirIdx])
        }
        for y in 0..<Self.h {
            for x in 0..<Self.w where wanted.contains(Int(clickCPS.index(x: x, y: y) ?? 0)) {
                select(atPageX: x, y: y)
                return true
            }
        }
        return false
    }

    func testContinue() { leave() }
}

// MARK: - Plain list fallback

/// The territory pick as a list, for installs without the map-selection art.
final class MapSelectionListScreen: MenuScreen {
    private let choices: [CampaignChoice]

    init(choices: [CampaignChoice]) {
        // Defensive: an empty list would strand the screen; the graph never
        // returns one for an unfinished campaign (it defaults to E/A).
        self.choices = choices.isEmpty ? [CampaignChoice(dir: "E", variant: "A")] : choices
    }

    private func buttons() -> [Button] {
        let bw: Int32 = 360
        let bh: Int32 = 44
        let gap: Int32 = 16
        let cx = renderState.windowWidth / 2 - bw / 2
        let total = Int32(choices.count) * (bh + gap) - gap
        var y = renderState.windowHeight / 2 - total / 2

        var result: [Button] = []
        for (i, choice) in choices.enumerated() {
            let state = session.campaignState
            let prefix = state.currentFaction == "GDI" ? "SCG" : "SCB"
            let num = String(format: "%02d", state.currentMission)
            let label = "Territory \(i + 1)  (\(prefix)\(num)\(choice.suffix))"
            result.append(Button(label: label, x: cx, y: y, w: bw, h: bh) {
                session.campaignState.advance(choosing: choice)
                session.campaign.pendingChoices = []
                showPreMissionMovies()
            })
            y += bh + gap
        }
        return result
    }

    func render(_ renderer: OpaquePointer?) {
        drawText(renderer, "SELECT THE NEXT AREA OF CONFLICT",
                 centerX: renderState.windowWidth / 2, centerY: 100, color: .amber, scale: 2)
        for btn in buttons() {
            btn.draw(renderer, highlighted: btn.contains(input.mouseX, input.mouseY))
        }
        drawText(renderer, "Click a territory to continue",
                 centerX: renderState.windowWidth / 2,
                 centerY: renderState.windowHeight - 40, color: .gray, scale: 1)
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        for btn in buttons() where btn.contains(x, y) {
            btn.action()
            return
        }
    }

    func handleKeyDown(_ key: Int32) {
        // Number keys pick directly; no escape — the original loops until a
        // territory is chosen (MAPSEL.CPP:693-716).
        let idx = Int(key) - Int(SDLK_1.rawValue)
        if idx >= 0 && idx < choices.count {
            session.campaignState.advance(choosing: choices[idx])
            session.campaign.pendingChoices = []
            showPreMissionMovies()
        }
    }
}

// MARK: - Page helpers

private extension Array where Element == UInt8 {
    mutating func fill(_ v: UInt8) {
        for i in indices { self[i] = v }
    }

    /// Fill_Rect: inclusive corners, clipped.
    mutating func fillRect(x1: Int, y1: Int, x2: Int, y2: Int, color: UInt8, width: Int) {
        let height = count / width
        let xa = Swift.max(0, x1), xb = Swift.min(width - 1, x2)
        let ya = Swift.max(0, y1), yb = Swift.min(height - 1, y2)
        guard xa <= xb, ya <= yb else { return }
        for y in ya...yb {
            for x in xa...xb { self[y * width + x] = color }
        }
    }

    /// CC_Draw_Shape with SHAPE_CENTER: index 0 is transparent.
    mutating func drawShape(_ f: SHPFrame, centerX: Int, centerY: Int, width: Int, height: Int) {
        let ox = centerX - f.width / 2, oy = centerY - f.height / 2
        for y in 0..<f.height {
            let ty = oy + y
            guard ty >= 0 && ty < height else { continue }
            for x in 0..<f.width {
                let tx = ox + x
                guard tx >= 0 && tx < width else { continue }
                let p = f.pixels[y * f.width + x]
                if p != 0 { self[ty * width + tx] = p }
            }
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
