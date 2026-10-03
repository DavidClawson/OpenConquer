import AppKit
import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// MARK: - Setup: importing the game data

/// Shown instead of the main menu when no game data could be loaded, and from
/// the title's Developer Tools to import again. It shows the two things the
/// game can use — the classic 1995 data (required) and the Remastered
/// Collection's HD art and audio (optional) — with where each was found, or
/// how to get it. The classic data comes from the Remastered Collection or
/// from the original game's discs (the 1995 CDs, or EA's 2007 freeware
/// release); the HD art only from the Remastered Collection. Import copies
/// the classic archives and extracts the HD art and audio — what
/// install-assets.sh does, with no terminal or Python.
///
/// Without the Remastered Collection, Get Free Game opens the fan site that
/// still hosts EA's freeware disc images in the player's browser, and the
/// screen watches Downloads: it shows a download in progress and picks the
/// finished GDI95.zip / NOD95.zip (or .iso) up by itself.
///
/// This screen must render with **zero assets**: on a first launch there is no
/// palette, SHP or font yet, so everything is SDL primitives plus the built-in
/// 5x7 pixel font (`TextRenderer`). A Finder-launched app has no stdout, so
/// every failure is said on screen.
final class SetupScreen: MenuScreen {
    private enum Phase {
        /// Looking for an install, or waiting for the player to pick one.
        case choose
        case importing
        case failed(String)
    }

    private var phase: Phase = .choose
    fileprivate var remastered: RemasteredInstall?
    /// Original game discs, one per side.
    fileprivate var discs: [OriginalDisc] = []
    /// Disc images (.zip or .iso), one per side, opened at import.
    fileprivate var images: [DiscImage] = []
    /// Disc downloads still in progress in Downloads.
    private var downloading: [String] = []
    private var lastDownloadsCheck: UInt64 = 0
    /// A note under the choice: why a picked folder was refused, etc.
    private var note: String?
    /// From the title's tools menu: Back instead of Quit, and the game data is
    /// already there.
    private let reimport: Bool
    private var job: ImportJob?
    /// Where disc images are unzipped and mounted during an import.
    private var importScratch: URL { dataPath.appendingPathComponent(".import") }

    /// What the failure screen says, if the import failed.
    var failureMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    init(reimport: Bool = false) {
        self.reimport = reimport
        search()
    }

    private func search() {
        remastered = RemasteredLocator.search().first
        discs = remastered == nil ? RemasteredLocator.searchDiscs() : []
        images = []
        checkDownloads()
        note = nil
    }

    /// Picks up finished disc downloads and notes ones in progress, for the
    /// sides no disc covers yet.
    private func checkDownloads() {
        guard remastered == nil else { downloading = []; return }
        for image in DiscImage.searchDownloads() where !has(image.side) {
            images.append(image)
        }
        downloading = DiscImage.downloadsInProgress()
    }

    private func has(_ side: OriginalDisc.Side?) -> Bool {
        discs.contains { $0.side == side } || images.contains { $0.side == side }
    }

    private var hasClassic: Bool { remastered != nil || has(.gdi) }

    /// The Remastered Collection's Steam page, for players without it.
    private static let storeURL = URL(string: "https://store.steampowered.com/app/1213210/")!

    // MARK: Layout

    private var bodyScale: Int32 { max(1, min(3, min(renderState.windowWidth / 640, renderState.windowHeight / 400))) }

    private struct Line {
        let text: String
        let color: Color
        let scale: Int32
        let gapAfter: Int32
        let rule: Bool

        init(_ text: String, _ color: Color, _ scale: Int32, gapAfter: Int32 = 0, rule: Bool = false) {
            self.text = text; self.color = color; self.scale = scale
            self.gapAfter = gapAfter; self.rule = rule
        }

        var height: Int32 { (rule ? 1 : 7 * scale) + gapAfter }
    }

    private func display(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func pathLines(_ url: URL, gapAfter: Int32) -> [Line] {
        let b = bodyScale
        var lines = wrap(display(url), width: 46).map { Line($0, .green, b, gapAfter: 3 * b) }
        lines[lines.count - 1] = Line(lines[lines.count - 1].text, .green, b, gapAfter: gapAfter)
        return lines
    }

    private func makeLines() -> [Line] {
        let b = bodyScale
        var lines: [Line] = [
            Line("OPENCONQUER", .amber, b * 2, gapAfter: 10 * b),
            Line("", .darkGreen, 0, gapAfter: 12 * b, rule: true),
        ]
        switch phase {
        case .choose:
            lines += [
                Line(reimport ? "IMPORT GAME DATA" : "GAME DATA NEEDED", reimport ? .amber : .red, b + 1, gapAfter: 8 * b),
                Line("OPENCONQUER SHIPS NO GAME ASSETS. IT IMPORTS", .gray, b, gapAfter: 4 * b),
                Line("THEM FROM YOUR OWN COPY OF THE GAME.", .gray, b, gapAfter: 16 * b),
            ]
            lines += classicLines() + hdLines()
            if let note {
                lines.append(Line(note, .red, b, gapAfter: 0))
            }
        case .importing:
            let p = job?.snapshot() ?? ImportJob.Snapshot()
            lines += [
                Line("IMPORTING", .amber, b + 1, gapAfter: 14 * b),
                Line(p.stepTitle, .white, b, gapAfter: 6 * b),
                Line(p.item.isEmpty ? " " : String(p.item.uppercased().suffix(46)), .gray, b, gapAfter: 40 * b),
                Line("THIS TAKES UP TO A MINUTE.", .gray, b, gapAfter: 0),
            ]
        case .failed(let message):
            lines.append(Line("THE IMPORT DIDN'T FINISH", .red, b + 1, gapAfter: 14 * b))
            for l in wrap(message.uppercased(), width: 46) {
                lines.append(Line(l, .white, b, gapAfter: 4 * b))
            }
        }
        return lines
    }

    /// Button labels are drawn at text scale 2 (12 px a character), whatever
    /// the body scale.
    /// The classic data: where it was found, or where it can come from.
    private func classicLines() -> [Line] {
        let b = bodyScale
        var lines = [Line("1. CLASSIC 1995 GAME DATA - REQUIRED", .white, b, gapAfter: 6 * b)]
        if let remastered {
            lines.append(Line("FOUND IN YOUR REMASTERED COLLECTION:", .green, b, gapAfter: 4 * b))
            lines += pathLines(remastered.dataDir, gapAfter: 16 * b)
        } else if !discs.isEmpty || !images.isEmpty {
            for side in [OriginalDisc.Side.gdi, .nod] {
                let label = side == .gdi ? "GDI" : "NOD"
                if let disc = discs.first(where: { $0.side == side }) {
                    lines.append(Line("FOUND THE \(label) DISC:", .green, b, gapAfter: 4 * b))
                    lines += pathLines(disc.folder, gapAfter: 8 * b)
                } else if let image = images.first(where: { $0.side == side }) {
                    lines.append(Line("FOUND THE \(label) DISC IMAGE:", .green, b, gapAfter: 4 * b))
                    lines += pathLines(image.file, gapAfter: 8 * b)
                }
            }
            lines += downloadingLines()
            if !has(.gdi) {
                lines.append(Line("STILL NEEDED: THE GDI DISC.", .amber, b, gapAfter: 8 * b))
            } else if !has(.nod) && downloading.isEmpty {
                lines.append(Line("ADD THE NOD DISC TOO FOR THE NOD CAMPAIGN.", .amber, b, gapAfter: 8 * b))
            }
            lines[lines.count - 1] = Line(lines[lines.count - 1].text, lines[lines.count - 1].color, b, gapAfter: 16 * b)
        } else {
            lines += [
                Line("NOT FOUND. IT COMES WITH THE REMASTERED", .red, b, gapAfter: 4 * b),
                Line("COLLECTION, OR GET THE ORIGINAL GAME FREE:", .gray, b, gapAfter: 4 * b),
                Line("EA RELEASED ITS GDI AND NOD DISCS IN 2007.", .gray, b, gapAfter: 4 * b),
                Line("GET FREE GAME OPENS A SITE THAT HAS THEM.", .gray, b, gapAfter: 4 * b),
                Line("DOWNLOAD BOTH AND THEY'LL SHOW UP HERE.", .gray, b, gapAfter: 8 * b),
            ]
            lines += downloadingLines()
            lines[lines.count - 1] = Line(lines[lines.count - 1].text, lines[lines.count - 1].color, b, gapAfter: 16 * b)
        }
        return lines
    }

    private func downloadingLines() -> [Line] {
        downloading.map { Line("DOWNLOADING \($0.uppercased()) ...", .amber, bodyScale, gapAfter: 4 * bodyScale) }
    }

    /// The HD art and audio: found, incomplete, or how to get it.
    private func hdLines() -> [Line] {
        let b = bodyScale
        var lines = [Line("2. HD ART AND AUDIO - OPTIONAL", .white, b, gapAfter: 6 * b)]
        if let remastered, remastered.hasHD {
            lines.append(Line("FOUND IN YOUR REMASTERED COLLECTION.", .green, b, gapAfter: 16 * b))
        } else if let remastered {
            let missing = remastered.missingHD
            lines += [
                Line("YOUR REMASTERED COLLECTION IS MISSING", .amber, b, gapAfter: 4 * b),
                Line(missing.prefix(2).joined(separator: ", ") + (missing.count > 2 ? " ..." : ""), .amber, b, gapAfter: 4 * b),
                Line("LET STEAM OR THE EA APP FINISH DOWNLOADING IT.", .gray, b, gapAfter: 16 * b),
            ]
        } else {
            lines += [
                Line("ONLY IN THE C&C REMASTERED COLLECTION", .gray, b, gapAfter: 4 * b),
                Line("(STEAM OR THE EA APP, FOR WINDOWS). ON A MAC,", .gray, b, gapAfter: 4 * b),
                Line("INSTALL IT WITH CROSSOVER OR WHISKY, OR COPY", .gray, b, gapAfter: 4 * b),
                Line("ITS FOLDER FROM A PC, THEN CHOOSE IT HERE.", .gray, b, gapAfter: 16 * b),
            ]
        }
        if remastered == nil || !(remastered?.hasHD ?? false) {
            // Without HD the game uses the 1995 art; say so before Import.
            if hasClassic {
                lines.append(Line("WITHOUT IT YOU GET THE ORIGINAL 1995 ART.", .gray, b, gapAfter: 8 * b))
            }
        }
        lines.append(Line("YOU CAN ALSO DRAG A FOLDER ONTO THIS WINDOW.", .darkGreen, b, gapAfter: 8 * b))
        return lines
    }

    private var buttonMetrics: (h: Int32, gap: Int32) { (h: 32, gap: 14) }

    private func makeButtons() -> [Button] {
        let leave: Button.Action = reimport ? ("BACK", { app.currentScreen = makeMainMenu() })
                                            : ("QUIT", { app.running = false })
        var specs: [Button.Action]
        switch phase {
        case .choose:
            specs = [leave, ("CHOOSE FOLDER", { [weak self] in self?.chooseFolder() })]
            if remastered == nil && !(has(.gdi) && has(.nod)) {
                specs.append(("GET FREE GAME", { NSWorkspace.shared.open(DiscImage.freewarePage) }))
            }
            if !(remastered?.hasHD ?? false) {
                specs.append(("GET HD ART", { NSWorkspace.shared.open(Self.storeURL) }))
            }
            if hasClassic {
                specs.append(("IMPORT", { [weak self] in self?.startImport() }))
            } else {
                specs.append(("SEARCH AGAIN", { [weak self] in self?.search() }))
            }
        case .importing:
            specs = [("CANCEL", { [weak self] in self?.job?.cancel() })]
        case .failed:
            specs = [leave, ("TRY AGAIN", { [weak self] in self?.phase = .choose })]
        }
        let m = buttonMetrics
        let bw = Int32(specs.map(\.0.count).max() ?? 0) * 12 + 28
        let totalW = Int32(specs.count) * bw + Int32(specs.count - 1) * m.gap
        var x = renderState.windowWidth / 2 - totalW / 2
        let y = textBlockBottom() + 26 * bodyScale
        return specs.map { spec in
            defer { x += bw + m.gap }
            return Button(label: spec.0, x: x, y: y, w: bw, h: m.h, action: spec.1)
        }
    }

    private func blockHeight() -> Int32 {
        makeLines().reduce(0) { $0 + $1.height } + 26 * bodyScale + buttonMetrics.h
    }

    private func textBlockTop() -> Int32 { max(20, (renderState.windowHeight - blockHeight()) / 2) }

    private func textBlockBottom() -> Int32 { textBlockTop() + makeLines().reduce(0) { $0 + $1.height } }

    // MARK: Render

    func render(_ renderer: OpaquePointer?) {
        pollJob()
        if case .choose = phase {
            let now = SDL_GetTicks64()
            if now - lastDownloadsCheck > 2000 {
                lastDownloadsCheck = now
                checkDownloads()
            }
        }
        let cx = renderState.windowWidth / 2
        var y = textBlockTop()
        let lines = makeLines()
        for (i, line) in lines.enumerated() {
            if line.rule {
                SDL_SetRenderDrawColor(renderer, Color.darkGreen.r, Color.darkGreen.g, Color.darkGreen.b, 255)
                let w = 130 * bodyScale
                var rect = SDL_Rect(x: cx - w / 2, y: y, w: w, h: 1)
                SDL_RenderFillRect(renderer, &rect)
            } else {
                drawText(renderer, line.text, centerX: cx, centerY: y + (7 * line.scale) / 2,
                         color: line.color, scale: line.scale)
            }
            // The progress bar sits in the gap after the item line.
            if case .importing = phase, i == lines.count - 2 {
                drawProgressBar(renderer, top: y + 7 * line.scale + 14 * bodyScale)
            }
            y += line.height
        }
        for btn in makeButtons() {
            btn.draw(renderer, highlighted: btn.contains(input.mouseX, input.mouseY))
        }
    }

    private func drawProgressBar(_ renderer: OpaquePointer?, top: Int32) {
        let b = bodyScale
        let w = 220 * b, h = 8 * b
        let x = renderState.windowWidth / 2 - w / 2
        var frame = SDL_Rect(x: x, y: top, w: w, h: h)
        SDL_SetRenderDrawColor(renderer, Color.green.r, Color.green.g, Color.green.b, 255)
        SDL_RenderDrawRect(renderer, &frame)
        let fraction = job?.snapshot().overall ?? 0
        var fill = SDL_Rect(x: x + 2, y: top + 2, w: Int32(Double(w - 4) * min(1, max(0, fraction))), h: h - 4)
        SDL_SetRenderDrawColor(renderer, Color.brightGreen.r, Color.brightGreen.g, Color.brightGreen.b, 255)
        SDL_RenderFillRect(renderer, &fill)
    }

    // MARK: Choosing

    /// The macOS folder picker. SDL's window keeps running behind it.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose your game data"
        panel.message = "Choose the C&C Remastered Collection's install folder, or the original game: a disc folder, or the freeware GDI95.zip / NOD95.zip (or .iso)."
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .diskImage, .folder]
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        let response = panel.runModal()
        NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
        guard response == .OK, let url = panel.url else { return }
        use(url)
    }

    /// A folder dropped on the window (SDL_DROPFILE).
    func handleDrop(_ path: String) {
        guard case .choose = phase else { return }
        use(URL(fileURLWithPath: path))
    }

    fileprivate func use(_ url: URL) {
        note = nil
        if let install = RemasteredLocator.resolve(url) {
            remastered = install
            discs = []
        } else if let disc = OriginalDisc.resolve(url) {
            remastered = nil
            discs.removeAll { $0.side == disc.side }
            images.removeAll { $0.side == disc.side }
            discs.append(disc)
        } else if var image = DiscImage.identify(url) {
            if image.side == nil {
                // An .iso not named for its side: open it to see which it is.
                guard let opened = try? image.open(scratch: importScratch, progress: { _ in }, isCancelled: { false }) else {
                    note = "THAT DISC IMAGE ISN'T A C&C GDI OR NOD DISC."
                    return
                }
                image = DiscImage(file: url, side: opened.disc.side)
                opened.close()
            }
            remastered = nil
            discs.removeAll { $0.side == image.side }
            images.removeAll { $0.side == image.side }
            images.append(image)
        } else {
            note = "THAT FOLDER HAS NO C&C GAME DATA IN IT."
        }
    }

    // MARK: Importing

    func startImport() {
        guard hasClassic else { return }
        let plan: [(URL, URL)]
        var images: [DiscImage] = []
        if let remastered {
            let missing = ClassicArchiveImport.missing(in: remastered)
            guard missing.isEmpty else {
                phase = .failed("Files missing from that install: " + missing.prefix(3).joined(separator: ", ")
                                + ". Make sure the Remastered Collection is fully downloaded.")
                return
            }
            plan = ClassicArchiveImport.plan(from: remastered, to: dataPath)
        } else {
            plan = ClassicArchiveImport.plan(from: discs, to: dataPath)
            images = self.images
        }
        let job = ImportJob(plan: plan, discs: discs, images: images, scratch: importScratch,
                            hd: remastered?.hasHD == true ? remastered : nil, dataDir: dataPath)
        self.job = job
        phase = .importing
        job.start()
    }

    private func pollJob() {
        guard case .importing = phase, let job, let result = job.snapshot().result else { return }
        self.job = nil
        switch result {
        case .success:
            finish()
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled || error is CancellationError
                || { if case .cancelled? = error as? AssetImportError { return true }; return false }() {
                phase = .choose
                note = "IMPORT CANCELLED."
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Replaces what happens after a successful import (the headless test).
    var onImported: (() -> Void)?

    /// Loads what was just imported and carries on as a normal launch would.
    private func finish() {
        if let onImported { return onImported() }
        assetManager.initialize()
        guard assetManager.mixManager.totalEntries > 0 else {
            phase = .failed("The files were copied, but the game still can't read them from \(display(dataPath)).")
            return
        }
        loadDataOverrides()
        initRemasteredSprites()
        gameAudio.soundLibrary = SoundLibrary(assetManager: assetManager)
        MoviePlayerScreen.play(["LOGO"]) { app.currentScreen = makeMainMenu(fadeIn: true) }
    }

    /// Break a long line at spaces where it can, mid-word (paths) where it can't.
    private func wrap(_ text: String, width: Int) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while rest.count > width {
            let head = rest.prefix(width)
            if let space = head.lastIndex(of: " "), space > head.startIndex {
                out.append(String(rest[..<space]))
                rest = rest[rest.index(after: space)...]
            } else {
                out.append(String(head))
                rest = rest.dropFirst(width)
            }
        }
        if !rest.isEmpty { out.append(String(rest)) }
        return out
    }

    // MARK: Input

    func handleKeyDown(_ key: Int32) {
        switch key {
        case Int32(SDLK_ESCAPE.rawValue):
            if case .importing = phase { job?.cancel() } else if reimport { app.currentScreen = makeMainMenu() }
            else { app.running = false }
        case Int32(SDLK_RETURN.rawValue):
            if case .choose = phase { hasClassic ? startImport() : chooseFolder() }
        default:
            break
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

extension Button {
    typealias Action = (String, () -> Void)
}

// MARK: - The import, on a background thread

/// Runs the copy and the extraction off the main thread; the screen polls a
/// snapshot each frame.
final class ImportJob {
    struct Snapshot {
        var stepTitle = "STARTING"
        var item = ""
        /// 0...1 across all the steps.
        var overall = 0.0
        var result: Result<Void, Error>?
    }

    private enum Step: CaseIterable {
        case openImages, copy, hdSprites, hdUI, hdAudio

        var title: String {
            switch self {
            case .openImages: return "UNPACKING THE DISC IMAGES"
            case .copy: return "COPYING THE CLASSIC GAME FILES"
            case .hdSprites: return "EXTRACTING THE HD UNITS AND BUILDINGS"
            case .hdUI: return "EXTRACTING THE HD INTERFACE"
            case .hdAudio: return "EXTRACTING THE HD MUSIC AND SOUNDS"
            }
        }

        /// Roughly how long each takes, for the bar.
        var weight: Double {
            switch self {
            case .openImages: return 4
            case .copy: return 1
            case .hdSprites: return 2.6
            case .hdUI: return 0.2
            case .hdAudio: return 1.4
            }
        }
    }

    private let plan: [(URL, URL)]
    private let discs: [OriginalDisc]
    private let images: [DiscImage]
    private let scratch: URL
    /// The install to extract the HD art and audio from, if it has them.
    private let hd: RemasteredInstall?
    private let dataDir: URL
    private let steps: [Step]
    private let lock = NSLock()
    private var state = Snapshot()
    private var cancelled = false

    init(plan: [(URL, URL)], discs: [OriginalDisc], images: [DiscImage], scratch: URL,
         hd: RemasteredInstall?, dataDir: URL) {
        self.plan = plan
        self.discs = discs
        self.images = images
        self.scratch = scratch
        self.hd = hd
        self.dataDir = dataDir
        steps = Step.allCases.filter {
            switch $0 {
            case .openImages: return !images.isEmpty
            case .copy: return true
            case .hdSprites, .hdUI, .hdAudio: return hd != nil
            }
        }
    }

    func snapshot() -> Snapshot { lock.withLock { state } }

    func cancel() { lock.withLock { cancelled = true } }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    private func report(_ step: Step, fraction: Double, item: String) {
        let total = steps.reduce(0) { $0 + $1.weight }
        let before = steps.prefix { $0 != step }.reduce(0) { $0 + $1.weight }
        lock.withLock {
            state.stepTitle = step.title
            state.item = item
            state.overall = (before + step.weight * min(1, max(0, fraction))) / total
        }
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result<Void, Error> { try run() }
            lock.withLock { state.result = result }
        }
    }

    private func run() throws {
        // The disc images, opened as disc folders for the copy.
        var opened: [DiscImage.Opened] = []
        defer {
            opened.forEach { $0.close() }
            try? FileManager.default.removeItem(at: scratch)
        }
        var plan = self.plan
        if !images.isEmpty {
            for (i, image) in images.enumerated() {
                let share = 1 / Double(images.count)
                let o = try image.open(scratch: scratch, progress: { f in
                    self.report(.openImages, fraction: (Double(i) + f) * share, item: image.file.lastPathComponent)
                }, isCancelled: { self.isCancelled })
                opened.append(o)
            }
            plan = ClassicArchiveImport.plan(from: discs + opened.map(\.disc), to: dataDir)
        }

        try ClassicArchiveImport.run(plan, to: dataDir, progress: { done, total, name in
            self.report(.copy, fraction: total > 0 ? Double(done) / Double(total) : 1, item: name)
        }, isCancelled: { self.isCancelled })

        guard let hd else { return }
        try extractRemasteredAssets(remasteredData: hd.dataDir, dataDir: dataDir, progress: { p in
            let step: Step
            switch p.step {
            case .hdSprites: step = .hdSprites
            case .hdUI: step = .hdUI
            case .hdAudio: step = .hdAudio
            }
            self.report(step, fraction: p.total > 0 ? Double(p.done) / Double(p.total) : 1, item: p.item)
        }, isCancelled: { self.isCancelled })
    }
}

// MARK: - Headless (--test-setup)

extension SetupScreen {
    /// As if the player had picked or dropped `url`.
    func testUse(_ url: URL) { use(url) }

    /// As if nothing had been found.
    func testClear() {
        remastered = nil
        discs = []
        images = []
    }
}
