import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// MARK: - Score Screen (end of a won campaign mission)
//
// Ported from ScoreClass::Presentation (SCORE.CPP:571-998) as the Win95 build
// runs it: the background WSA (S-GDIIN2 / SCRSCN1) plays, the clock and
// hall-of-fame animations start, TIME / LEADERSHIP / EFFICIENCY / TOTAL SCORE
// count up with a beep per tick, then casualties and buildings lost — GDI as
// yellow/red bar graphs, Nod with a firing-squad of infantrymen and a
// commando running from an exploding construction yard — ending credits on
// the credits counter, and the hall of fame, where a placing player types a
// name letter by letter with the zooming-letter effect.
//
// Like MapSelectionScreen, the original's blocking function becomes a list of
// steps run by a 60 Hz tick. Pages mirror the original's: `page` =
// PseudoSeenBuff (320x200, shown doubled with interpolation), `sysPage` =
// SysMemPage (scratch), `text` = the 640x400 TextPrintBuffer in the hi-res
// 12GRNGRD.FNT (index 0 transparent), shown only inside the rectangles the
// original adds to its BlitList, `zoom` = the scaled letters drawn straight
// onto the hi-res page. ScoreObjs[8] are `objs`, with the original's
// eight-slot limit.
//
// Deviations: Esc / Space fast-forward to the hall of fame (the original sped
// up some loops on a key press instead); the zooming letter's trail is erased
// cleanly; the hall of fame is kept per side in UserDefaults rather than in
// one HALLFAME.DAT; the shake when the yard blows up doesn't pause the
// screen.

final class ScorePresentationScreen: MenuScreen {

    private typealias D = ScorePresentationData

    /// The score screen, or nil when its art isn't installed.
    static func make(inputs: ScoreInputs, fameKey: String? = nil,
                     then done: @escaping () -> Void) -> ScorePresentationScreen? {
        ScorePresentationScreen(inputs: inputs, fameKey: fameKey, done: done)
    }

    /// The inputs for the mission that just ended, read from the live game.
    static func inputsFromSession() -> ScoreInputs {
        let state = session.campaignState
        let isGDI = state.currentFaction == "GDI"
        let world = session.world
        let player = world?.playerHouse ?? (isGDI ? .goodGuy : .badGuy)
        let survivors = world?.objects.filter { $0.house == player && $0.strength > 0 && !$0.isInLimbo }.count ?? 0
        func lost(_ h: House) -> (units: Int, buildings: Int) {
            let s = session.houseStates[h]
            return (s?.unitsLost ?? 0, s?.buildingsLost ?? 0)
        }
        let g = lost(.goodGuy), n = lost(.badGuy), c = lost(.neutral)
        let ps = session.houseStates[player]
        return ScoreInputs(isGDI: isGDI, scenario: state.currentMission,
                           elapsedTicks: world?.tickCount ?? 0, survivingObjects: survivors,
                           gdiUnitsLost: g.units, nodUnitsLost: n.units, civUnitsLost: c.units,
                           gdiBuildingsLost: g.buildings, nodBuildingsLost: n.buildings,
                           civBuildingsLost: c.buildings,
                           harvestedCredits: ps?.harvestedCredits ?? 0,
                           initialCredits: ps?.initialCredits ?? 0,
                           credits: session.sidebarCredits)
    }

    // MARK: Setup

    private let inputs: ScoreInputs
    private let result: ScoreResult
    private let isGDI: Bool
    private let house: Int          // 0 = GDI, 1 = Nod: the original's array index
    private let done: () -> Void
    private let fameKey: String

    private let strings: StringTable
    private let font: WWFont
    private let background: WSAFile
    private let timeShape: SHPFile, hiscore1: SHPFile, hiscore2: SHPFile, credsShape: SHPFile
    private let logos: SHPFile?, yellowBar: SHPFile?, redBar: SHPFile?
    private let fact: SHPFile?, rambo: SHPFile?, fireball: SHPFile?, e1: SHPFile?, c1: SHPFile?

    private static let w = 320, h = 200, tw = 640, th = 400
    private var page = [UInt8](repeating: 0, count: w * h)
    private var sysPage = [UInt8](repeating: 0, count: w * h)
    private var text = [UInt8](repeating: 0, count: tw * th)
    private var blitMask = [Bool](repeating: false, count: tw * th)
    private var zoom = [UInt8](repeating: 0, count: tw * th)
    private var bg: WSAPlayer

    private var palette = [UInt8](repeating: 0, count: 768)
    private var fade: (from: [UInt8], to: [UInt8], tick: Int, length: Int)?
    private var shakeTicks = 0
    /// The font palette last set (Set_Font_Palette is global state).
    private var fontPal = D.greenPal

    // Step engine.
    private enum Step {
        case run(() -> Void)
        case wait(Int)
        case until(() -> Bool)
        /// One iteration of a loop; returns the ticks to wait after it, or
        /// nil when the loop is over.
        case loop(() -> Int?)
    }
    private var steps: [Step] = []
    private var waitLeft = 0
    private var skipping = false
    private var tickAccumulator: Double = 0
    private var lastTicks: UInt64 = 0

    // ScoreObjs[MAXSCOREOBJS].
    private var objs = [ScoreObj?](repeating: nil, count: 8)
    private var stillUpdating = false

    // Interaction.
    private enum Phase { case presenting, nameEntry, awaitingClick, leaving }
    private var phase = Phase.presenting
    private var fame: [FameEntry] = []
    private var fameIndex: Int?
    private var name: [UInt8] = []
    private var nameIndex = 0
    private var scaleSlot: Int?
    private var cursorLast = 0, cursorState = 0, cursorTimer = 0
    private var clickWait = 0, cycleCounter = 0
    private var finished = false

    private var texture: OpaquePointer?
    private var dirty = true

    private init?(inputs: ScoreInputs, fameKey: String?, done: @escaping () -> Void) {
        func shp(_ n: String) -> SHPFile? { mixManager.retrieve(n).flatMap { try? SHPFile(data: $0) } }
        let gdi = inputs.isGDI
        guard let strData = mixManager.retrieve("CONQUER.ENG"), let strings = StringTable(data: strData),
              let font = ClassicDialogArt.shared.scoreFont,
              let bgData = mixManager.retrieve(gdi ? "S-GDIIN2.WSA" : "SCRSCN1.WSA"),
              let bg = try? WSAFile(data: bgData),
              let time = shp("TIME.SHP"), let h1 = shp("HISCORE1.SHP"), let h2 = shp("HISCORE2.SHP"),
              let creds = shp("CREDS.SHP") else {
            print("ScoreScreen: art not installed — skipping the score presentation")
            return nil
        }
        self.inputs = inputs
        self.result = ScoreResult(inputs)
        self.isGDI = gdi
        self.house = gdi ? 0 : 1
        self.done = done
        self.fameKey = fameKey ?? "TDMax.hallOfFame.\(gdi ? "GDI" : "NOD")"
        self.strings = strings
        self.font = font
        self.background = bg
        self.bg = WSAPlayer(bg)
        self.timeShape = time
        self.hiscore1 = h1
        self.hiscore2 = h2
        self.credsShape = creds
        self.logos = gdi ? nil : shp("LOGOS.SHP")
        self.yellowBar = gdi ? shp("BAR3YLW.SHP") : nil
        self.redBar = gdi ? shp("BAR3RED.SHP") : nil
        self.fact = gdi ? nil : shp("FACT.SHP")
        self.rambo = gdi ? nil : shp("RMBO.SHP")
        self.fireball = gdi ? nil : shp("FBALL1.SHP")
        self.e1 = gdi ? nil : shp("E1.SHP")
        self.c1 = gdi ? nil : shp("C1.SHP")
        buildScript()
    }

    deinit {
        if let texture { SDL_DestroyTexture(texture) }
    }

    // MARK: Script (SCORE.CPP:620-998)

    private func buildScript() {
        let gdi = isGDI, house = self.house
        let lead = result.leadership, eff = result.efficiency, total = result.total

        run { gameAudio.playTheme(.win1) }

        // Background up, faded in from black, then its animation (708-730).
        run { [self] in
            animate(frame: 1, onto: &sysPage)
            page = sysPage
            startFade(to: brightened(background.palette), ticks: 7)
        }
        until { [self] in fade == nil }
        run { [self] in sample("COUNTRY4", 90) }
        for frame in 1..<background.frameCount {
            run { [self] in animate(frame: frame, onto: &page) }
            wait(2)
        }

        // The clock and hall-of-fame animations (735-741).
        run { [self] in
            objs[0] = AnimObj(x: 233, y: 2, shape: timeShape, maxStage: 30, reset: 4)
            objs[1] = AnimObj(x: 4, y: 97, shape: hiscore1, maxStage: 10, reset: 4)
            objs[2] = AnimObj(x: 8, y: 172, shape: hiscore2, maxStage: 10, reset: 4)
            sysPage = page
        }

        // Nod: the logo bits in (747-756).
        if !gdi {
            run { [self] in
                if let f = logos?.frames[safe: 1] { sysPage.drawShape(f, x: 0, y: 0, width: Self.w, height: Self.h) }
            }
            dissolve(x: 0, y: 0, w: 128, h: 104 - 16)
        }

        // TIME / LEADERSHIP / EFFICIENCY / TOTAL SCORE (761-797).
        run { [self] in
            alloc(PrintObj(strings[D.txtTime], x: 206, y: 3, pal: D.greenPal))
            alloc(PrintObj(strings[D.txtLead], x: 182, y: 26, pal: D.greenPal))
            alloc(PrintObj(strings[D.txtEffi], x: 182, y: 38, pal: D.greenPal))
            alloc(PrintObj(strings[D.txtTota], x: 182, y: 50, pal: D.greenPal))
            sample("SFX4", 120)
        }
        wait(13)
        run { [self] in
            addBlit(264 * 2, 26 * 2, 4 * 12, 12)
            addBlit(264 * 2, 38 * 2, 4 * 12, 12)
            addBlit(264 * 2, 50 * 2, 4 * 12, 12)
            addBlit(275 * 2, 9 * 2, 64, 12)      // minutes
        }
        var i = 0, scoreCounter = 0
        loop { [self] in
            guard i <= 160 else { return nil }
            fontPal = D.greenPal
            countUp("%3d%%", i, lead, x: 264, y: 26)
            if i >= 30 { countUp("%3d%%", i - 30, eff, x: 264, y: 38) }
            if i >= 60 {
                countUp("%3d", scoreCounter, total, x: 264, y: 50)
                scoreCounter += total / 100
            }
            printMinutes(result.minutes)
            sample("BEEPY6", 60)
            i += 1
            return 1
        }
        run { [self] in countUp("%3d", total, total, x: 264, y: 50) }
        wait(60)
        if !gdi { showCredits() }
        wait(60)

        // Casualties (806-824).
        let casuaX = [144, 146], casuaY = [78, 90]
        let gdiTxX = [150, 224], gdiTxY = [90, 90], nodTxX = [150, 224], nodTxY = [102, 102]
        run { [self] in
            sample("SFX4", 90)
            alloc(PrintObj(strings[D.txtCasu], x: casuaX[house], y: casuaY[house], pal: D.redPal))
        }
        wait(9)
        if !gdi {
            run { [self] in alloc(PrintObj(strings[D.txtNeut], x: 200, y: 114, pal: D.redPal)) }
            wait(4)
        }
        run { [self] in
            alloc(PrintObj(strings[D.txtGDI], x: gdiTxX[house], y: gdiTxY[house], pal: D.redPal))
            alloc(PrintObj(strings[D.txtNod], x: nodTxX[house], y: nodTxY[house], pal: D.redPal))
        }
        wait(6)
        run { [self] in fontPal = D.redPal }
        if gdi {
            gdiGraph(gKilled: inputs.gdiUnitsLost + inputs.civUnitsLost, nKilled: inputs.nodUnitsLost, ypos: 88)
        } else {
            nodCasualtiesGraph()
        }

        // Buildings lost (831-852).
        let bldgGY = [138, 128], bldgNY = [150, 140]
        run { [self] in sample("SFX4", 90) }
        if gdi {
            run { [self] in alloc(PrintObj(strings[D.txtBuil], x: 144, y: 126, pal: D.greenPal)) }
            wait(9)
        } else {
            run { [self] in
                alloc(PrintObj(strings[D.txtBuil1], x: 146, y: 128, pal: D.greenPal))
                alloc(PrintObj(strings[D.txtBuil2], x: 146, y: 136, pal: D.greenPal))
            }
            wait(9)
            run { [self] in alloc(PrintObj(strings[D.txtNeut], x: 200, y: 152, pal: D.greenPal)) }
            wait(4)
        }
        run { [self] in
            alloc(PrintObj(strings[D.txtGDI], x: gdiTxX[house], y: bldgGY[house], pal: D.greenPal))
            alloc(PrintObj(strings[D.txtNod], x: gdiTxX[house], y: bldgNY[house], pal: D.greenPal))
        }
        wait(7)
        if gdi {
            gdiGraph(gKilled: inputs.gdiBuildingsLost + inputs.civBuildingsLost,
                     nKilled: inputs.nodBuildingsLost, ypos: 136)
        } else {
            wait(6)
            run { [self] in fontPal = D.greenPal }
            nodBuildingsGraph()
        }
        until { [self] in !stillUpdating }
        if gdi { showCredits() }

        // Hall of fame (866-958).
        run { [self] in
            sample("SFX4", 90)
            alloc(PrintObj(strings[D.txtTop], x: 28, y: 110, pal: D.bluePal))
        }
        wait(9)
        run { [self] in
            fame = loadFame()
            fameIndex = HallOfFame.insert(total: total, level: inputs.scenario, into: &fame)
        }
        for row in 0..<HallOfFame.count {
            let y = 120 + row * 8
            run { [self] in
                let e = fame[row]
                alloc(PrintObj(e.name, x: 19, y: y, pal: D.bluePal))
                if e.score != 0 {
                    alloc(PrintObj("\(e.score)", x: 19 + 6 * 15, y: y, pal: D.bluePal))
                    alloc(PrintObj(e.level < 20 ? "\(e.level)" : "**", x: 19 + 6 * 12, y: y, pal: D.bluePal))
                }
            }
            // Call_Back_Delay(13), only after a row with a score.
            var waited = false
            loop { [self] in
                if waited || fame[row].score == 0 { return nil }
                waited = true
                return 13
            }
        }
        until { [self] in !stillUpdating }
        run { [self] in
            if let idx = fameIndex {
                name = Array(fame[idx].name.utf8)
                nameIndex = 0
                sysPage = page
                phase = .nameEntry
            } else {
                alloc(PrintObj(strings[D.txtClick2], x: 149, y: 190, pal: D.yellowPal))
                clickWait = 20
                phase = .awaitingClick
            }
            skipping = false
        }
    }

    /// Fade out, stop the music and hand over (968-998).
    private func leave() {
        guard phase == .nameEntry || phase == .awaitingClick else { return }
        if phase == .nameEntry, let idx = fameIndex {
            fame[idx].name = String(decoding: name.prefix { $0 != 0 }, as: UTF8.self)
            saveFame(fame)
        }
        phase = .leaving
        steps.removeAll()
        waitLeft = 0
        run { [self] in
            objs = [ScoreObj?](repeating: nil, count: 8)
            startFade(to: [UInt8](repeating: 0, count: 768), ticks: 7)
        }
        until { [self] in fade == nil }
        run { [self] in
            guard !finished else { return }
            finished = true
            gameAudio.stopMusic()
            done()
        }
    }

    // MARK: Graphs

    /// Do_GDI_Graph (1190-1256): a yellow bar for GDI, a red one for Nod,
    /// each with a white flash at its growing tip.
    private func gdiGraph(gKilled: Int, nKilled: Int, ypos: Int) {
        var maxK = max(gKilled, nKilled, 1)
        var gdiK = gKilled * 119 / maxK, nodK = nKilled * 119 / maxK
        if maxK < 20 { gdiK = gKilled * 5; nodK = nKilled * 5 }
        maxK = max(gdiK, nodK, 1)
        let m = maxK

        run { [self] in
            sysPage.fillRect(x1: 0, y1: 0, x2: 124, y2: 9, color: 0, width: Self.w)
            if let f = redBar?.frames[safe: 120] { sysPage.drawShape(f, x: 0, y: 0, width: Self.w, height: Self.h) }
            addBlit(2 * 297, 2 * (ypos + 2), 5 * 12, 12)
        }
        bar(shape: { [self] in yellowBar }, length: gdiK, killed: gKilled, max: m, y: ypos)
        run { [self] in addBlit(2 * 297, 2 * (ypos + 14), 5 * 12, 12) }
        bar(shape: { [self] in redBar }, length: nodK, killed: nKilled, max: m, y: ypos + 12)
    }

    private func bar(shape: @escaping () -> SHPFile?, length: Int, killed: Int, max m: Int, y: Int) {
        var i = 1
        loop { [self] in
            guard i <= length else { return nil }
            if i != length {
                if let f = shape()?.frames[safe: i] { page.drawShape(f, x: 172, y: y, width: Self.w, height: Self.h) }
            } else {
                copy(sysPage, x: 0, y: 0, w: 3 + length, h: 9, to: &page, x: 172, y: y)
            }
            countUp("%d", i * killed / m, killed, x: 297, y: y + 2)
            sample("BEEPY6", 110)
            i += 1
            return 2
        }
        run { [self] in
            if let f = shape()?.frames[safe: length] { page.drawShape(f, x: 172, y: y, width: Self.w, height: Self.h) }
            countUp("%d", killed, killed, x: 297, y: y + 2)
        }
        wait(40)
    }

    // Nod's casualties: fifteen infantrymen in three rows who die as the bars
    // pass them (Do_Nod_Casualties_Graph, 1259-1372).

    private struct InfantryMan {
        var x: Int, y: Int
        var civilian: Bool
        var remap: [UInt8]
        var anim: Int, stage: Int, delay: Int
    }
    private var men: [InfantryMan] = []
    private static let barX = 266, casualtyY = 88

    private func nodCasualtiesGraph() {
        let gK = inputs.gdiUnitsLost, nK = inputs.nodUnitsLost, cK = inputs.civUnitsLost
        var maxK = max(gK, nK, cK, 1)
        var g = gK, n = nK, c = cK
        let room = 318 - Self.barX
        if g > room || n > room || c > room {
            g = g * room / maxK; n = n * room / maxK; c = c * room / maxK
        }
        maxK = max(g, n, c, 1)
        let m = maxK

        run { [self] in
            men = []
            for row in 0..<3 {
                for i in 0..<5 {
                    men.append(InfantryMan(x: i * 10 + 7, y: 11 + row * 10, civilian: row == 2,
                                           remap: [D.remapYellow, D.remapGrey, D.remapCiv][row],
                                           anim: 0, stage: 0, delay: Int.random(in: 0...0x1F)))
                }
            }
            drawInfantryMen()
            copy(sysPage, x: 0, y: 0, w: 320 - Self.barX, h: 34, to: &page, x: Self.barX, y: Self.casualtyY)
        }
        wait(40)
        run { [self] in
            for dy in [2, 14, 26] { addBlit(2 * (184 + 64), 2 * (Self.casualtyY + dy), 5 * 12, 12) }
        }
        var i = 1, q = 0
        loop { [self] in
            guard i <= m else { return nil }
            drawInfantryMen()
            drawBarGraphs(i, g, n, c)
            copy(sysPage, x: 0, y: 0, w: 320 - Self.barX, h: 34, to: &page, x: Self.barX, y: Self.casualtyY)
            countUp("%d", i * gK / m, gK, x: 248, y: Self.casualtyY + 2)
            countUp("%d", i * nK / m, nK, x: 248, y: Self.casualtyY + 14)
            countUp("%d", i * cK / m, cK, x: 248, y: Self.casualtyY + 26)
            q += 1
            if q == 3 {
                q = 0
                i += 1
                sample("BEEPY6", 110)
            }
            return 3
        }
        run { [self] in
            countUp("%d", gK, gK, x: 248, y: Self.casualtyY + 2)
            countUp("%d", nK, nK, x: 248, y: Self.casualtyY + 14)
            countUp("%d", cK, cK, x: 248, y: Self.casualtyY + 26)
        }
        // Let the death animations finish.
        var more = true
        loop { [self] in
            guard more else { return nil }
            more = men.contains { $0.anim >= D.doGunDeath }
            if more { drawInfantryMen() }
            drawBarGraphs(m, g, n, c)
            copy(sysPage, x: 0, y: 0, w: 320 - Self.barX, h: 34, to: &page, x: Self.barX, y: Self.casualtyY)
            return 1
        }
    }

    private func dos(_ man: InfantryMan) -> (frame: Int, count: Int) {
        (man.civilian ? D.civilianDos : D.minigunnerDos)[man.anim] ?? (0, 1)
    }

    /// Draw_InfantryMen / Draw_InfantryMan (1644-1714): restore the scratch
    /// copy of the background, draw everyone, step their animations.
    private func drawInfantryMen() {
        copy(sysPage, x: Self.barX, y: Self.casualtyY, w: 320 - Self.barX, h: 34, to: &sysPage, x: 0, y: 0)
        for k in men.indices where men[k].anim != -1 {
            let d = dos(men[k])
            let shapes = men[k].civilian ? c1 : e1
            if let f = shapes?.frames[safe: men[k].stage + d.frame] {
                sysPage.drawShape(f, centerX: men[k].x, centerY: men[k].y, remap: men[k].remap,
                                  width: Self.w, height: Self.h)
            }
            men[k].delay -= 1
            if men[k].delay < 0 {
                men[k].delay = 3
                men[k].stage += 1
                if men[k].stage >= d.count {
                    if men[k].anim >= D.doGunDeath { men[k].anim = -1 } else { newAnim(k, D.doStandReady) }
                }
            }
        }
    }

    private func newAnim(_ k: Int, _ anim: Int) {
        men[k].anim = anim
        men[k].stage = 0
        men[k].delay = anim >= D.doGunDeath ? 1 : Int.random(in: 0...15)
    }

    /// Draw_Bar_Graphs (1759-1810), on the scratch at the page's top left.
    private func drawBarGraphs(_ i: Int, _ g: Int, _ n: Int, _ c: Int) {
        for (row, killed, color) in [(0, g, D.ltCyan), (1, n, D.red), (2, c, D.red)] where killed > 0 {
            let y = 4 + row * 12, len = min(i, killed)
            sysPage.fillRect(x1: 0, y1: y, x2: len, y2: y + 1, color: color, width: Self.w)
            sysPage.fillRect(x1: 1, y1: y + 2, x2: len + 1, y2: y + 2, color: 0, width: Self.w)
            sysPage.fillRect(x1: len + 1, y1: y + 1, x2: len + 1, y2: y + 1, color: 0, width: Self.w)
            if i <= killed {
                let k = row * 5 + i / 11
                if k < men.count, men[k].anim != -1, men[k].anim < D.doGunDeath {
                    newAnim(k, i / 11 != 0 ? D.doGunDeath + Int.random(in: 0...3) : D.doGunDeath)
                }
            }
        }
    }

    /// Do_Nod_Buildings_Graph (1068-1172): a commando runs from the
    /// construction yard as it blows, then the counts tick up.
    private func nodBuildingsGraph() {
        let bx = 256, by = 128
        run { [self] in sysPage = page }
        wait(30)
        run { [self] in
            for dy in [0, 12, 24] { addBlit(2 * (bx + 8), 2 * (by + dy), 5 * 12, 12) }
        }
        var i = 0
        loop { [self] in
            guard i < 98 else { return nil }
            copy(sysPage, x: bx, y: by, w: 320 - bx, h: 48, to: &sysPage, x: 0, y: 0)
            let count = fact?.frames.count ?? 0
            var shapenum = 0
            if i >= 60 {
                shapenum = count - 2
                if i == 60 {
                    shakeTicks = 12
                    sample("CRUMBLE", 255)
                }
                if i > 65 { shapenum = count - 1 }
            }
            if i < 68, let f = fact?.frames[safe: shapenum] {
                sysPage.drawShape(f, x: 0, y: 0, remap: D.remapBldg, width: Self.w, height: Self.h)
            }
            if i >= 61, let fb = fireball {
                if let f = fb.frames[safe: (i - 61) >> 1] {
                    sysPage.drawShape(f, centerX: 10, centerY: 10, remap: D.remapFBall, width: Self.w, height: Self.h)
                }
                if i > 64, let f = fb.frames[safe: (i - 64) >> 1] {
                    sysPage.drawShape(f, centerX: 50, centerY: 30, remap: D.remapFBall, width: Self.w, height: Self.h)
                }
            }
            let walk = D.ramboWalk
            if let f = rambo?.frames[safe: walk.frame + walk.jump * 6 + (i >> 1) % walk.count] {
                sysPage.drawShape(f, centerX: i + 32, centerY: 40, remap: D.remapYellow, width: Self.w, height: Self.h)
            }
            copy(sysPage, x: 0, y: 0, w: 320 - bx, h: 48, to: &page, x: bx, y: by)
            i += 1
            return 1
        }
        let gb = inputs.gdiBuildingsLost, nb = inputs.nodBuildingsLost, cb = inputs.civBuildingsLost
        let top = max(gb, nb, cb)
        var q = 0
        loop { [self] in
            guard q <= top else { return nil }
            countUp("%d", q, gb, x: bx + 8, y: by)
            countUp("%d", q, nb, x: bx + 8, y: by + 12)
            countUp("%d", q, cb, x: bx + 8, y: by + 24)
            sample("BEEPY6", 110)
            q += 1
            return 1
        }
    }

    /// Show_Credits (1375-1432): the credits counter spins up to the money
    /// left at the end of the mission.
    private func showCredits() {
        let credsX = [276, 276], credsY = [173, 58]
        let credPX = [228, 236], credPY = [189 - 12, 74]
        let credTX = [182, 182], credTY = [179 - 12, 62]
        let h = house
        let money = inputs.credits
        run { [self] in alloc(PrintObj(strings[D.txtEndCred], x: credTX[h], y: credTY[h], pal: D.greenPal)) }
        wait(15)
        var slot = 0
        var i = -50
        run { [self] in
            slot = alloc(CredsObj(x: credsX[h], y: credsY[h], shape: credsShape, maxStage: 32, reset: 2))
            addBlit(2 * credPX[h], 2 * credPY[h], 5 * 12, 12)
        }
        let minAdd = money / 100
        var started = false
        loop { [self] in
            // do { ... } while (i < money)
            guard !started || i < money else { return nil }
            started = true
            var add = 5
            if money - i > 100 { add += 15 }
            if money - i > 1000 { add += 30 }
            if add < minAdd { add = minAdd }
            i += add
            if i < 0 { i = 0 }
            fontPal = D.greenPal
            countUp("%d", i, money, x: credPX[h], y: credPY[h])
            return 2
        }
        // Don't stop the counter on its white frames.
        until { [self] in ((objs[slot] as? CredsObj)?.stage ?? 0) < 20 }
        run { [self] in objs[slot] = nil }
    }

    // MARK: Step engine

    private func run(_ f: @escaping () -> Void) { steps.append(.run(f)) }
    private func wait(_ ticks: Int) { if ticks > 0 { steps.append(.wait(ticks)) } }
    private func until(_ cond: @escaping () -> Bool) { steps.append(.until(cond)) }
    private func loop(_ body: @escaping () -> Int?) { steps.append(.loop(body)) }

    /// One 60 Hz tick: Animate_Score_Objs, then the script.
    private func tick() {
        animateObjs()
        updateFade()
        if shakeTicks > 0 { shakeTicks -= 1; dirty = true }
        switch phase {
        case .nameEntry: animateCursor()
        case .awaitingClick: cycleClickPalette()
        default: break
        }

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
            case .loop(let body):
                guard let d = body() else { steps.removeFirst(); continue }
                if d > 0 && !skipping { waitLeft = d; return }
            }
        }
    }

    /// Esc / Space: run everything out to the hall of fame at once, quietly.
    private func fastForward() {
        guard phase == .presenting else { return }
        skipping = true
        var guardTicks = 200_000
        while skipping && guardTicks > 0 && !steps.isEmpty {
            tick()
            guardTicks -= 1
        }
        skipping = false
        dirty = true
    }

    // MARK: Score objects (ScoreAnimClass and friends, 209-477)

    @discardableResult
    private func alloc(_ obj: ScoreObj) -> Int {
        // Alloc_Object: the first free slot; a full table drops the object.
        if let print = obj as? PrintObj {
            addBlit(print.x * 2, print.y * 2, 2 * font.width(of: print.textString), 16)
        }
        guard let i = objs.firstIndex(where: { $0 == nil }) else { return 0 }
        objs[i] = obj
        if skipping, let print = obj as? PrintObj {
            while objs[i] === print { animateObj(i) }
        }
        return i
    }

    private func animateObjs() {
        stillUpdating = false
        for i in objs.indices { animateObj(i) }
    }

    private func animateObj(_ i: Int) {
        guard let o = objs[i] else { return }
        if o.timer > 0 { o.timer -= 1 }
        if o is PrintObj { stillUpdating = true }
        if o.timer == 0 && !o.update(self) { objs[i] = nil }
        dirty = true
    }

    fileprivate func drawObjShape(_ shape: SHPFile, frame: Int, x: Int, y: Int) {
        if let f = shape.frames[safe: frame] { page.drawShape(f, x: x, y: y, width: Self.w, height: Self.h) }
    }

    /// ScorePrintClass::Update (291-338): the next letter glows white, the
    /// previous one settles into its colour over a black drop shadow.
    fileprivate func printStage(_ p: PrintObj) -> Bool {
        let chars = p.chars, s = p.stage
        if s > 0 && (s - 1 >= chars.count) {
            addBlit(p.x * 2, p.y * 2, s * 6 + 14, 16)
            return false
        }
        stillUpdating = true
        let pos = p.x + s * 6
        if s > 0 {
            let ch = String(UnicodeScalar(chars[s - 1]))
            fontPal = D.blackPal
            hiPrint(ch, 2 * (pos - 6), 2 * (p.y - 1), fore: 0)
            hiPrint(ch, 2 * (pos - 6), 2 * (p.y + 1), fore: 0)
            hiPrint(ch, 2 * (pos - 6 + 1), 2 * p.y, fore: 0)
            fontPal = p.pal
            hiPrint(ch, 2 * (pos - 6), 2 * p.y, fore: 0)
        }
        if s < chars.count {
            let ch = String(UnicodeScalar(chars[s]))
            fontPal = D.whitePal
            hiPrint(ch, pos * 2, 2 * (p.y - 1), fore: 0)
            hiPrint(ch, pos * 2, 2 * (p.y + 1), fore: 0)
            hiPrint(ch, (pos + 1) * 2, 2 * p.y, fore: 0)
        }
        p.stage += 1
        p.timer = 1
        return true
    }

    /// ScoreScaleClass::Update (438-477): a typed letter zooms in from the
    /// right, shrinking until it lands in place.
    fileprivate func scaleStage(_ o: ScaleObj) -> Bool {
        let destX = [0, 80, 107, 134, 180, 228], destW = [6, 20, 30, 40, 60, 80]
        if o.stage != 5 { zoom.fill(0) }
        let ch = String(UnicodeScalar(o.char))
        if o.stage > 0 {
            // Print the letter at the text page's corner, then scale its
            // 10x10 cell up onto the screen.
            var cell = [UInt8](repeating: 0, count: 14 * 14)
            var remap = o.pal
            remap[0] = 0; remap[1] = 0
            _ = font.draw(ch, into: &cell, pageWidth: 14, pageHeight: 14, x: 0, y: 0, remap: remap)
            let size = destW[o.stage] * 2, ox = destX[o.stage] * 2, oy = o.y * 2
            for dy in 0..<size {
                for dx in 0..<size {
                    let v = cell[(dy * 10 / size) * 14 + dx * 10 / size]
                    let X = ox + dx, Y = oy + dy
                    if v != 0 && X < Self.tw && Y < Self.th { zoom[Y * Self.tw + X] = v }
                }
            }
            o.stage -= 1
            o.timer = 1
            return true
        }
        fontPal = o.pal
        hiPrint(ch, o.x * 2, o.y * 2, fore: 0)
        return false
    }

    // MARK: Text (hi-res TextPrintBuffer)

    /// Buffer_Print with the current font palette; `fore` replaces colour 1
    /// and the background is always TBLACK.
    private func hiPrint(_ s: String, _ x: Int, _ y: Int, fore: UInt8) {
        var remap = fontPal
        remap[0] = 0
        remap[1] = fore
        _ = font.draw(s, into: &text, pageWidth: Self.tw, pageHeight: Self.th, x: x, y: y, remap: remap)
        dirty = true
    }

    /// Count_Up_Print (1482-1509): erase a cell to BLACK, print in white.
    private func countUp(_ format: String, _ value: Int, _ maxValue: Int, x: Int, y: Int) {
        let str = String(format: format.replacingOccurrences(of: "d", with: "ld"), value <= maxValue ? value : maxValue)
        let width = str.utf8.count * 7
        text.fillRect(x1: x * 2, y1: y * 2, x2: (x + width) * 2, y2: (y + 7) * 2, color: D.black, width: Self.tw)
        hiPrint(str, x * 2, y * 2, fore: D.white)
    }

    /// Print_Minutes (1449-1459).
    private func printMinutes(_ m: Int) {
        var minutes = m
        let s: String
        if minutes >= 60 {
            if minutes / 60 > 9 { minutes = 9 * 60 + 59 }
            s = cFormat(strings[D.txtTimeFormat1], minutes / 60, minutes % 60)
        } else {
            s = cFormat(strings[D.txtTimeFormat2], minutes)
        }
        hiPrint(s, 275 * 2, 9 * 2, fore: 0)
    }

    private func cFormat(_ fmt: String, _ args: Int...) -> String {
        String(format: fmt.replacingOccurrences(of: "%d", with: "%ld"), arguments: args.map { $0 as CVarArg })
    }

    /// BlitList.Add: only these hi-res rectangles of the text page show.
    private func addBlit(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        guard w > 0, h > 0 else { return }
        for yy in max(0, y)..<min(Self.th, y + h) {
            for xx in max(0, x)..<min(Self.tw, x + w) { blitMask[yy * Self.tw + xx] = true }
        }
    }

    // MARK: Hall of fame input (Input_Name, Animate_Cursor: 1529-1627)

    private func animateCursor() {
        guard let idx = fameIndex else { return }
        let y = 120 + idx * 8 + 7
        if nameIndex != cursorLast {
            let ox = 19 + cursorLast * 6
            page.fillRect(x1: ox, y1: y, x2: ox + 5, y2: y, color: 0, width: Self.w)
            text.fillRect(x1: 2 * ox, y1: 2 * y, x2: 2 * (ox + 5), y2: 2 * y + 1, color: D.black, width: Self.tw)
            cursorLast = nameIndex
            cursorState = 0
        }
        let x = 19 + nameIndex * 6
        page.fillRect(x1: x, y1: y, x2: x + 5, y2: y, color: cursorState != 0 ? D.ltBlue : 0, width: Self.w)
        text.fillRect(x1: 2 * x, y1: 2 * y, x2: 2 * (x + 5), y2: 2 * y + 1,
                      color: cursorState != 0 ? D.ltBlue : D.black, width: Self.tw)
        if cursorTimer > 0 { cursorTimer -= 1 }
        if cursorTimer == 0 {
            cursorState ^= 1
            cursorTimer = 5
        }
        dirty = true
    }

    private func typeKey(_ keyIn: Int) {
        guard phase == .nameEntry, let idx = fameIndex else { return }
        if let s = scaleSlot, objs[s] is ScaleObj { return }   // still zooming
        let xpos = 19, ypos = 120 + idx * 8
        let last = HallOfFame.nameLength - 2
        var key = keyIn
        if key == 8 && nameIndex == last, nameIndex < name.count, name[nameIndex] != 0, name[nameIndex] != 32 {
            key = 32
        }
        if key == 8 {
            guard nameIndex > 0 else { return }
            nameIndex -= 1
            name = Array(name.prefix(nameIndex))
            let x6 = xpos + nameIndex * 6
            page.fillRect(x1: x6, y1: ypos, x2: x6 + 6, y2: ypos + 6, color: 0, width: Self.w)
            sysPage.fillRect(x1: x6, y1: ypos, x2: x6 + 6, y2: ypos + 6, color: 0, width: Self.w)
            text.fillRect(x1: x6 * 2, y1: ypos * 2, x2: (x6 + 6) * 2, y2: (ypos + 6) * 2, color: D.black, width: Self.tw)
            dirty = true
            return
        }
        var ascii = key
        if ascii >= 97 && ascii <= 122 { ascii -= 32 }
        guard (ascii >= 33 && ascii <= 126) || ascii == 32 else { return }
        let x6 = xpos + nameIndex * 6
        page.fillRect(x1: x6, y1: ypos, x2: x6 + 6, y2: ypos + 5, color: 0, width: Self.w)
        sysPage.fillRect(x1: x6, y1: ypos, x2: x6 + 6, y2: ypos + 5, color: 0, width: Self.w)
        text.fillRect(x1: 2 * x6, y1: ypos * 2, x2: 2 * (x6 + 6), y2: 2 * (ypos + 6), color: D.black, width: Self.tw)
        name = Array(name.prefix(nameIndex)) + [UInt8(ascii)]
        sample("KEYSTROK", 255)
        scaleSlot = alloc(ScaleObj(char: UInt8(ascii), x: x6, y: ypos, pal: D.bluePal))
        if nameIndex < last { nameIndex += 1 }
    }

    /// Cycle_Wait_Click's palette cycle of 233-237, every eighth tick.
    private func cycleClickPalette() {
        if clickWait > 0 { clickWait -= 1 }
        cycleCounter = (cycleCounter + 1) & 7
        guard cycleCounter == 0 else { return }
        let first = Array(palette[233 * 3..<233 * 3 + 3])
        for i in 233..<237 {
            for c in 0..<3 { palette[i * 3 + c] = palette[(i + 1) * 3 + c] }
        }
        for c in 0..<3 { palette[237 * 3 + c] = first[c] }
        dirty = true
    }

    private func loadFame() -> [FameEntry] {
        guard let data = UserDefaults.standard.data(forKey: fameKey),
              let list = try? JSONDecoder().decode([FameEntry].self, from: data) else { return [] }
        return list
    }

    private func saveFame(_ list: [FameEntry]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: fameKey) }
    }

    // MARK: Pages and palette

    /// Animate_Frame: XOR the frame's change into whatever page it's given.
    private func animate(frame: Int, onto target: inout [UInt8]) {
        let old = bg.buffer
        bg.seek(to: frame)
        let wsa = bg.wsa
        for y in 0..<wsa.height {
            let ty = wsa.y + y
            guard ty >= 0 && ty < Self.h else { continue }
            for x in 0..<wsa.width {
                let tx = wsa.x + x
                guard tx >= 0 && tx < Self.w else { continue }
                let d = old[y * wsa.width + x] ^ bg.buffer[y * wsa.width + x]
                if d != 0 { target[ty * Self.w + tx] ^= d }
            }
        }
        dirty = true
    }

    private func copy(_ src: [UInt8], x: Int, y: Int, w: Int, h: Int, to dst: inout [UInt8], x dx: Int, y dy: Int) {
        let rows = (0..<h).map { r in Array(src[((y + r) * Self.w + x)..<((y + r) * Self.w + x + min(w, Self.w - x))]) }
        for (r, row) in rows.enumerated() where dy + r < Self.h {
            for (c, v) in row.enumerated() where dx + c < Self.w { dst[(dy + r) * Self.w + dx + c] = v }
        }
        dirty = true
    }

    /// Bit_It_In_Scale (MAPSEL.CPP:1207-1270), delay 1, no dagger.
    private func dissolve(x: Int, y: Int, w: Int, h: Int) {
        var xi = Array(0..<w), yi = Array(0..<h), j = 0
        run {
            for i in 0..<w { xi.swapAt(Int.random(in: 0..<w), i) }
            for i in 0..<h { yi.swapAt(Int.random(in: 0..<h), i) }
        }
        loop { [self] in
            guard j < h else { return nil }
            var j1 = j
            for i in 0..<w {
                let k = x + xi[i], m = y + yi[j1]
                j1 += 1
                if j1 >= h { j1 = 0 }
                page[m * Self.w + k] = sysPage[m * Self.w + k]
            }
            j += 1
            dirty = true
            return j % 2 == 1 ? 1 : 0   // Call_Back_Delay(1) before every odd line
        }
    }

    /// The WSA palette with Increase_Palette_Luminance(30, 30, 30, 63).
    private func brightened(_ p: VGAPalette?) -> [UInt8]? {
        guard let p else { return nil }
        return p.raw6.map { v in VGAPalette.expand6(UInt8(min(63, Int(v) + Int(v) * 30 / 100))) }
    }

    private func startFade(to p: [UInt8]?, ticks: Int) {
        guard let p, p.count == 768 else { return }
        if skipping { palette = p; fade = nil; dirty = true; return }
        fade = (palette, p, 0, ticks)
    }

    private func updateFade() {
        guard var f = fade else { return }
        f.tick += 1
        let t = min(1, Double(f.tick) / Double(f.length))
        for i in 0..<768 { palette[i] = UInt8(Double(f.from[i]) + (Double(f.to[i]) - Double(f.from[i])) * t) }
        fade = f.tick >= f.length ? nil : f
        dirty = true
    }

    private func sample(_ name: String, _ volume: Int) {
        if !skipping { gameAudio.playSample(name, volume: volume) }
    }

    // MARK: MenuScreen

    func render(_ renderer: OpaquePointer?) {
        let now = SDL_GetPerformanceCounter()
        if lastTicks == 0 { lastTicks = now }
        tickAccumulator += Double(now - lastTicks) / Double(SDL_GetPerformanceFrequency()) * 60
        lastTicks = now
        var budget = 8
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

    private func displayRect() -> SDL_Rect {
        let ww = Double(renderState.windowWidth), wh = Double(renderState.windowHeight)
        let scale = min(ww / 640, wh / 480)
        let w = 640 * scale, h = 480 * scale
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

    /// 640x400 RGBA: the page doubled with Interpolate_2X_Scale-style
    /// averaging, the zooming letters, then the text inside the BlitList.
    private func composeRGBA() -> [UInt8] {
        var out = [UInt8](repeating: 255, count: Self.tw * Self.th * 4)
        let w = Self.w, h = Self.h, tw = Self.tw
        let shake = shakeTicks % 2 == 1 ? 2 : 0
        page.withUnsafeBufferPointer { pg in
            palette.withUnsafeBufferPointer { pal in
                text.withUnsafeBufferPointer { txt in
                    zoom.withUnsafeBufferPointer { zm in
                        blitMask.withUnsafeBufferPointer { mask in
                            out.withUnsafeMutableBufferPointer { o in
                                for Y in 0..<Self.th {
                                    let SY = max(0, Y - shake)
                                    let sy = SY >> 1, sy2 = (SY & 1 == 1 && sy + 1 < h) ? sy + 1 : sy
                                    for X in 0..<tw {
                                        let di = (Y * tw + X) * 4
                                        let t = txt[Y * tw + X]
                                        if t != 0 && mask[Y * tw + X] {
                                            o[di] = pal[Int(t) * 3]; o[di + 1] = pal[Int(t) * 3 + 1]; o[di + 2] = pal[Int(t) * 3 + 2]
                                            continue
                                        }
                                        let z = zm[Y * tw + X]
                                        if z != 0 {
                                            o[di] = pal[Int(z) * 3]; o[di + 1] = pal[Int(z) * 3 + 1]; o[di + 2] = pal[Int(z) * 3 + 2]
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
            }
        }
        return out
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        if phase == .awaitingClick && clickWait == 0 { leave() }
    }

    func handleKeyDown(_ key: Int32) {
        switch phase {
        case .presenting:
            if key == Int32(SDLK_ESCAPE.rawValue) || key == Int32(SDLK_SPACE.rawValue) { fastForward() }
        case .nameEntry:
            if key == Int32(SDLK_RETURN.rawValue) || key == Int32(SDLK_KP_ENTER.rawValue) {
                if let s = scaleSlot, objs[s] is ScaleObj { return }
                leave()
            } else if key == Int32(SDLK_BACKSPACE.rawValue) {
                typeKey(8)
            } else if key >= 32 && key <= 126 {
                typeKey(Int(key))
            }
        case .awaitingClick:
            if clickWait == 0 { leave() }
        case .leaving:
            break
        }
    }
}

// MARK: - Score objects

private class ScoreObj {
    var timer = 0
    /// One timer firing; false when the object is finished.
    func update(_ s: ScorePresentationScreen) -> Bool { false }
}

/// ScoreTimeClass: a looping shape animation drawn onto the page.
private class AnimObj: ScoreObj {
    let x: Int, y: Int, shape: SHPFile, maxStage: Int, reset: Int
    var stage = 0
    init(x: Int, y: Int, shape: SHPFile, maxStage: Int, reset: Int) {
        self.x = x; self.y = y; self.shape = shape; self.maxStage = maxStage; self.reset = reset
    }
    override func update(_ s: ScorePresentationScreen) -> Bool {
        timer = reset
        stage += 1
        if stage >= maxStage { stage = 0 }
        s.drawObjShape(shape, frame: stage, x: x, y: y)
        return true
    }
}

/// ScoreCredsClass: the spinning credits counter, ticking and ka-chinging.
private final class CredsObj: AnimObj {
    override func update(_ s: ScorePresentationScreen) -> Bool {
        let alive = super.update(s)
        if stage < 22 {
            s.objSample("CLOCK1", 70)
        } else if stage == 24 {
            s.objSample("CASHTURN", 70)
        }
        return alive
    }
}

/// ScorePrintClass.
private final class PrintObj: ScoreObj {
    let chars: [UInt8]
    let textString: String
    let x: Int, y: Int, pal: [UInt8]
    var stage = 0
    init(_ text: String, x: Int, y: Int, pal: [UInt8]) {
        self.textString = text
        self.chars = Array(text.utf8)
        self.x = x; self.y = y; self.pal = pal
    }
    override func update(_ s: ScorePresentationScreen) -> Bool { s.printStage(self) }
}

/// ScoreScaleClass.
private final class ScaleObj: ScoreObj {
    let char: UInt8, x: Int, y: Int, pal: [UInt8]
    var stage = 5
    init(char: UInt8, x: Int, y: Int, pal: [UInt8]) {
        self.char = char; self.x = x; self.y = y; self.pal = pal
    }
    override func update(_ s: ScorePresentationScreen) -> Bool { s.scaleStage(self) }
}

private extension ScorePresentationScreen {
    func objSample(_ name: String, _ volume: Int) { sample(name, volume) }
}

// MARK: - Headless driving (--test-score)

extension ScorePresentationScreen {
    var testPhase: String { "\(phase)" }
    var testFrameSize: (width: Int, height: Int) { (Self.tw, Self.th) }
    var testResult: ScoreResult { result }
    func testAdvance(ticks: Int) { for _ in 0..<ticks where !finished { tick() } }
    func testSnapshot() -> [UInt8] { composeRGBA() }
    func testFastForward() { fastForward() }
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

    /// CC_Draw_Shape: index 0 transparent, optionally through a remap.
    mutating func drawShape(_ f: SHPFrame, x ox: Int, y oy: Int, remap: [UInt8]? = nil, width: Int, height: Int) {
        for y in 0..<f.height {
            let ty = oy + y
            guard ty >= 0 && ty < height else { continue }
            for x in 0..<f.width {
                let tx = ox + x
                guard tx >= 0 && tx < width else { continue }
                let p = f.pixels[y * f.width + x]
                if p != 0 { self[ty * width + tx] = remap.map { $0[Int(p)] } ?? p }
            }
        }
    }

    /// SHAPE_CENTER.
    mutating func drawShape(_ f: SHPFrame, centerX: Int, centerY: Int, remap: [UInt8]? = nil,
                            width: Int, height: Int) {
        drawShape(f, x: centerX - f.width / 2, y: centerY - f.height / 2, remap: remap, width: width, height: height)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
