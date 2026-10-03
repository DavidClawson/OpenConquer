import CSDL2
import Foundation
import OpenConquerAssets

// MARK: - More of the Win95 build's dialog gadgets, on ClassicPage
//
// Draw_Caption with its per-dialog filigree (GOPTIONS.CPP), clipped and
// tabbed text (Conquer_Clip_Text_Print, DIALOG.CPP), ListClass with its
// scroll bar (LIST.CPP, SLIDER.CPP, SHAPEBTN.CPP), and the title picture
// the front-end dialogs sit on (Load_Title_Screen("HTITLE.PCX")).

/// The title picture behind the front-end dialogs: HTITLE.PCX, or the DOS
/// TITLE.CPS doubled. Nil if neither is installed.
enum ClassicTitleBackground {
    static func load() -> (pixels: [UInt8], palette: [UInt8])? {
        if let data = mixManager.retrieve("HTITLE.PCX"), let pcx = try? PCXFile(data: data),
           pcx.width == ClassicPage.width, pcx.height == ClassicPage.height, let pal = pcx.palette {
            return (pcx.pixels, pal.rgb8)
        }
        if let data = mixManager.retrieve("TITLE.CPS"), let cps = try? CPSFile(data: data),
           cps.pixels.count >= 320 * 200, let pal = cps.palette {
            let doubled = ClassicPage()
            doubled.blitDoubled(cps.pixels)
            return (doubled.pixels, pal.rgb8)
        }
        return nil
    }
}

/// OptionControlType (DEFINES.H): the OPTIONS.SHP frame pair Draw_Caption puts
/// in a dialog's top corners.
enum ClassicFiligree: Int {
    case dialog = 0, controls = 2, delete = 4, visual = 10, sound = 16
}

extension ClassicPage {
    /// Pixel width of `text` as Simple_Text_Print lays it out for `font`
    /// with `flags` (String_Pixel_Width with that FontXSpacing).
    static func textWidth(_ text: String, font kind: ClassicFont, flags: TextPrintFlags) -> Int {
        let art = ClassicDialogArt.shared
        var xspace = 0  // 1, less 1 for both 6-point fonts
        if !flags.isDisjoint(with: [.noShadow, .dropShadow, .fullShadow]) { xspace -= 1 }
        let font = kind == .grad6 ? art.gradFont6 : art.font6
        return font?.width(of: text, xSpacing: xspace) ?? 0
    }

    /// Line height a gadget computes from the font: FontHeight + FontYSpacing
    /// (TPF_NOSHADOW makes the Y spacing -2).
    static func lineHeight(font kind: ClassicFont, flags: TextPrintFlags) -> Int {
        let art = ClassicDialogArt.shared
        let h = (kind == .grad6 ? art.gradFont6 : art.font6)?.height ?? 12
        return h + (flags.contains(.noShadow) ? -2 : 0)
    }

    /// Dialog_Box + Draw_Caption(text, x, y, w) (GOPTIONS.CPP): the frame,
    /// the filigree pair, the caption in the light gradient green, underlined
    /// in CC_GREEN.
    func captionedDialog(x: Int, y: Int, w: Int, h: Int, caption: String?, filigree: ClassicFiligree) {
        drawBox(x: x, y: y, w: w, h: h, style: .greenBorder)
        if let opts = ClassicDialogArt.shared.options, opts.frames.count > filigree.rawValue + 1 {
            drawShapeCentered(opts.frames[filigree.rawValue], x: x + 12, y: y + 11)
            drawShapeCentered(opts.frames[filigree.rawValue + 1], x: x + w - 14, y: y + 11)
        }
        guard let caption, !caption.isEmpty else { return }
        let flags: TextPrintFlags = [.center, .noShadow, .useGradPal]
        fancyText(caption, x: x + w / 2, y: y + 10, fore: ClassicColor.green, font: .grad6, flags: flags)
        let len = Self.textWidth(caption, font: .grad6, flags: flags)
        let ly = y + Self.lineHeight(font: .grad6, flags: flags) + 10
        fillRect(x + w / 2 - len / 2, ly, x + w / 2 + len / 2, ly, ClassicColor.green)
    }

    /// Format_Window_String (DIALOG.CPP): break `text` into lines no wider
    /// than `width`, at spaces where possible.
    static func wrapText(_ text: String, font kind: ClassicFont, flags: TextPrintFlags, width: Int) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let candidate = line.isEmpty ? String(word) : line + " " + word
            if !line.isEmpty && textWidth(candidate, font: kind, flags: flags) >= width {
                lines.append(line)
                line = String(word)
            } else {
                line = candidate
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    /// Conquer_Clip_Text_Print: text clipped to `width`; a tab jumps to the
    /// next stop in `tabs` (offsets from x), or the next 50 pixels.
    func clipText(_ text: String, x: Int, y: Int, fore: UInt8, font kind: ClassicFont,
                  flags: TextPrintFlags, width: Int, tabs: [Int] = []) {
        var offset = 0
        var stops = tabs[...]
        let blocks = text.split(separator: "\t", omittingEmptySubsequences: false)
        for (i, block) in blocks.enumerated() {
            guard offset < width else { break }
            var s = String(block)
            while !s.isEmpty && offset + Self.textWidth(s, font: kind, flags: flags) >= width { s.removeLast() }
            if !s.isEmpty {
                fancyText(s, x: x + offset, y: y, fore: fore, font: kind, flags: flags)
                offset += Self.textWidth(s, font: kind, flags: flags)
            }
            if s.count < block.count { break }
            if i < blocks.count - 1 {
                while let t = stops.first, offset > t { stops = stops.dropFirst() }
                offset = stops.first ?? ((offset / 50) + 1) * 50
            }
        }
    }
}

// MARK: - ListClass (LIST.CPP) with its scroll bar

/// A TPF_6PT_GRAD | TPF_NOSHADOW list box: a BOXSTYLE_GREEN_BOX frame, entries
/// in medium green, the selected one bright on a CC_GREEN_SHADOW bar. When the
/// list overflows it narrows for a scroll bar: the up / down shape buttons
/// (HBTN-UP / HBTN-DN.SHP) and a slider between them (SliderClass: a sunken
/// track with a raised thumb).
struct ClassicListBox {
    let x: Int, y: Int, w: Int, h: Int
    var items: [String] = []
    var tabs: [Int] = []
    var selected = 0
    var top = 0
    /// Scroll button held down (for the pressed frame): -1 up, 1 down.
    var pressedArrow: Int?

    private static let flags: TextPrintFlags = [.noShadow]
    private static let upShape = ClassicListBox.shape("HBTN-UP.SHP") ?? ClassicListBox.shape("BTN-UP.SHP")
    private static let downShape = ClassicListBox.shape("HBTN-DN.SHP") ?? ClassicListBox.shape("BTN-DN.SHP")

    private static func shape(_ name: String) -> SHPFile? {
        mixManager.retrieve(name).flatMap { try? SHPFile(data: $0) }
    }

    init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    /// LineHeight = FontHeight + FontYSpacing - 1.
    var lineHeight: Int { ClassicPage.lineHeight(font: .grad6, flags: Self.flags) - 1 }
    var lineCount: Int { max(1, (h - 1) / lineHeight) }
    var scrollActive: Bool { items.count > lineCount }

    private var arrowSize: (w: Int, h: Int, dw: Int, dh: Int) {
        let u = Self.upShape?.frames.first, d = Self.downShape?.frames.first
        return (u?.width ?? 16, u?.height ?? 16, d?.width ?? 16, d?.height ?? 16)
    }
    private var scrollWidth: Int { max(arrowSize.w, arrowSize.dw) }
    /// The list's own width: narrowed by the scroll bar when it's active.
    private var listWidth: Int { scrollActive ? w - scrollWidth : w }
    private var track: (x: Int, y: Int, w: Int, h: Int) {
        let a = arrowSize
        return (x + w - scrollWidth, y + a.h, scrollWidth, h - a.h - a.dh)
    }

    func draw(on page: ClassicPage) {
        page.drawBox(x: x, y: y, w: listWidth, h: h, style: .greenBox)
        for i in 0..<lineCount {
            let line = top + i
            guard line < items.count else { break }
            let ex = x + 1, ey = y + lineHeight * i + 1, ew = listWidth - 2
            var flags = Self.flags
            if line == selected {
                flags.insert(.brightColor)
                page.fillRect(ex, ey, ex + ew - 1, ey + lineHeight - 1, 140)  // CC_GREEN_SHADOW
            } else {
                flags.insert(.mediumColor)
            }
            page.clipText(items[line], x: ex, y: ey, fore: ClassicColor.green, font: .grad6,
                          flags: flags, width: ew, tabs: tabs)
        }
        guard scrollActive else { return }
        let a = arrowSize
        if let f = Self.upShape?.frames[safe: pressedArrow == -1 ? 1 : 0] {
            page.blit(f.pixels, width: f.width, height: f.height, x: x + w - a.w, y: y, transparent: 0)
        }
        if let f = Self.downShape?.frames[safe: pressedArrow == 1 ? 1 : 0] {
            page.blit(f.pixels, width: f.width, height: f.height, x: x + w - a.dw, y: y + h - a.dh, transparent: 0)
        }
        let t = track
        page.drawBox(x: t.x, y: t.y, w: t.w, h: t.h, style: .greenDown)
        let thumb = thumbSpan()
        page.drawBox(x: t.x, y: t.y + thumb.start, w: t.w, h: thumb.size, style: .greenRaised)
    }

    /// SliderClass::Recalc_Thumb: size and start scaled from the list.
    private func thumbSpan() -> (start: Int, size: Int) {
        let length = track.h
        let size = max(4, length * lineCount / max(1, items.count))
        let start = min(length * top / max(1, items.count), length - size)
        return (start, size)
    }

    private func contains(_ p: (x: Int, y: Int), _ rx: Int, _ ry: Int, _ rw: Int, _ rh: Int) -> Bool {
        p.x >= rx && p.x < rx + rw && p.y >= ry && p.y < ry + rh
    }

    enum Hit { case entry(Int), arrow(Int), track(Int) }

    func hit(_ p: (x: Int, y: Int)) -> Hit? {
        if contains(p, x, y, listWidth, h) {
            // ListClass::Action: the row under the mouse, clamped to the list.
            let index = min(top + (p.y - (y + 1)) / lineHeight, items.count - 1)
            return index >= 0 ? .entry(index) : nil
        }
        guard scrollActive else { return nil }
        let a = arrowSize
        if contains(p, x + w - a.w, y, a.w, a.h) { return .arrow(-1) }
        if contains(p, x + w - a.dw, y + h - a.dh, a.dw, a.dh) { return .arrow(1) }
        let t = track
        if contains(p, t.x, t.y, t.w, t.h) {
            let thumb = thumbSpan()
            return .track(p.y - t.y < thumb.start ? -1 : 1)
        }
        return nil
    }

    /// ListClass::Step: move the view one line.
    mutating func step(_ dir: Int) {
        top = max(0, min(max(0, items.count - lineCount), top + dir))
    }

    /// Bump: move the view one page (a click on the track).
    mutating func bump(_ dir: Int) {
        step(dir * lineCount)
    }

    /// Step_Selected_Index: move the selection, scrolling it into view.
    mutating func stepSelection(_ dir: Int) {
        guard !items.isEmpty else { return }
        selected = max(0, min(items.count - 1, selected + dir))
        if selected < top { top = selected }
        if selected >= top + lineCount { top = selected - lineCount + 1 }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
