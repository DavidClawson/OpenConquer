import CSDL2
import Foundation
import OpenConquerAssets

// MARK: - Classic 640x400 page (the Win95 build's SeenBuff)
//
// The title, choose-your-side and other classic screens draw into an 8-bit
// 640x400 page through a 256-colour palette, as the Win95 build did, and the
// page is shown at 4:3 (640x480), letterboxed. This holds the page, the
// palette (with Fade_Palette_To), the SDL texture and the window↔page mapping,
// plus ports of the original's dialog primitives: Draw_Box, Dialog_Box /
// Draw_Caption, TextButtonClass and Simple_Text_Print (DIALOG.CPP,
// GOPTIONS.CPP, TEXTBTN.CPP).

/// TD's fixed UI colours — the first 16 palette entries (WWLIB's ColorType;
/// COMPAT.H aliases DKGREY = GREY).
enum ClassicColor {
    static let tblack: UInt8 = 0, green: UInt8 = 3, ltgreen: UInt8 = 4, yellow: UInt8 = 5, red: UInt8 = 8
    static let black: UInt8 = 12, grey: UInt8 = 13, ltgrey: UInt8 = 14, white: UInt8 = 15
}

final class ClassicPage {
    static let width = 640, height = 400

    var pixels = [UInt8](repeating: 0, count: width * height)
    /// The palette being shown, 768 bytes of 8-bit RGB.
    private(set) var palette = [UInt8](repeating: 0, count: 768)
    private var fade: (from: [UInt8], to: [UInt8], tick: Int, length: Int)?
    private var texture: OpaquePointer?
    private var dirty = true

    deinit {
        if let texture { SDL_DestroyTexture(texture) }
    }

    func markDirty() { dirty = true }

    // MARK: Palette

    func setPalette(_ rgb8: [UInt8]) {
        guard rgb8.count == 768 else { return }
        palette = rgb8
        fade = nil
        dirty = true
    }

    /// Fade_Palette_To over `ticks` 60 Hz ticks (FADE_PALETTE_SLOW = 30,
    /// MEDIUM = 15, FAST = 7).
    func fade(to rgb8: [UInt8], ticks: Int) {
        guard rgb8.count == 768 else { return }
        if ticks <= 0 { setPalette(rgb8); return }
        fade = (palette, rgb8, 0, ticks)
    }

    static let blackPalette = [UInt8](repeating: 0, count: 768)

    var isFading: Bool { fade != nil }

    /// Advance a palette fade by one 60 Hz tick.
    func tick() {
        guard var f = fade else { return }
        f.tick += 1
        let t = min(1, Double(f.tick) / Double(f.length))
        for i in 0..<768 {
            palette[i] = UInt8(Double(f.from[i]) + (Double(f.to[i]) - Double(f.from[i])) * t)
        }
        fade = f.tick >= f.length ? nil : f
        dirty = true
    }

    // MARK: Display

    /// 640x400 shown at 4:3, letterboxed in the window.
    static func displayRect() -> SDL_Rect {
        let ww = Double(renderState.windowWidth), wh = Double(renderState.windowHeight)
        let scale = min(ww / 640, wh / 480)
        let w = 640 * scale, h = 480 * scale
        return SDL_Rect(x: Int32((ww - w) / 2), y: Int32((wh - h) / 2), w: Int32(w), h: Int32(h))
    }

    /// A window point in page coordinates, or nil outside the page.
    static func pagePoint(_ x: Int32, _ y: Int32) -> (x: Int, y: Int)? {
        let r = displayRect()
        guard r.w > 0, r.h > 0 else { return nil }
        let px = Int(Double(x - r.x) * Double(width) / Double(r.w))
        let py = Int(Double(y - r.y) * Double(height) / Double(r.h))
        guard px >= 0, px < width, py >= 0, py < height else { return nil }
        return (px, py)
    }

    func present(_ renderer: OpaquePointer?) {
        if texture == nil {
            texture = SDL_CreateTexture(renderer, 0x16762004 /* ABGR8888 = RGBA bytes */,
                                        Int32(SDL_TEXTUREACCESS_STREAMING.rawValue),
                                        Int32(Self.width), Int32(Self.height))
            SDL_SetTextureScaleMode(texture, SDL_ScaleModeLinear)
            dirty = true
        }
        if dirty {
            let out = rgba()
            out.withUnsafeBytes { _ = SDL_UpdateTexture(texture, nil, $0.baseAddress, Int32(Self.width * 4)) }
            dirty = false
        }
        var dst = Self.displayRect()
        SDL_RenderCopy(renderer, texture, nil, &dst)
    }

    func rgba() -> [UInt8] {
        var out = [UInt8](repeating: 255, count: Self.width * Self.height * 4)
        pixels.withUnsafeBufferPointer { px in
            palette.withUnsafeBufferPointer { pal in
                out.withUnsafeMutableBufferPointer { o in
                    for i in 0..<px.count {
                        let c = Int(px[i]) * 3
                        o[i * 4] = pal[c]; o[i * 4 + 1] = pal[c + 1]; o[i * 4 + 2] = pal[c + 2]
                    }
                }
            }
        }
        return out
    }

    // MARK: Primitives

    func putPixel(_ x: Int, _ y: Int, _ c: UInt8) {
        guard x >= 0, x < Self.width, y >= 0, y < Self.height else { return }
        pixels[y * Self.width + x] = c
        dirty = true
    }

    /// Fill_Rect: inclusive corners, clipped.
    func fillRect(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, _ c: UInt8) {
        let xa = max(0, x1), xb = min(Self.width - 1, x2)
        let ya = max(0, y1), yb = min(Self.height - 1, y2)
        guard xa <= xb, ya <= yb else { return }
        for y in ya...yb {
            for x in xa...xb { pixels[y * Self.width + x] = c }
        }
        dirty = true
    }

    /// Draw_Rect: a one-pixel outline, inclusive corners.
    func drawRect(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, _ c: UInt8) {
        fillRect(x1, y1, x2, y1, c)
        fillRect(x1, y2, x2, y2, c)
        fillRect(x1, y1, x1, y2, c)
        fillRect(x2, y1, x2, y2, c)
    }

    /// Blit an indexed image at (x, y); `transparent` index skipped if given.
    func blit(_ src: [UInt8], width w: Int, height h: Int, x: Int, y: Int, transparent: UInt8? = nil) {
        for row in 0..<h {
            let ty = y + row
            guard ty >= 0, ty < Self.height else { continue }
            for col in 0..<w {
                let tx = x + col
                guard tx >= 0, tx < Self.width else { continue }
                let p = src[row * w + col]
                if let transparent, p == transparent { continue }
                pixels[ty * Self.width + tx] = p
            }
        }
        dirty = true
    }

    /// A 320x200 picture pixel-doubled onto the whole page (the DOS art when
    /// the Win95 hi-res version isn't installed).
    func blitDoubled(_ src: [UInt8]) {
        guard src.count >= 320 * 200 else { return }
        for y in 0..<Self.height {
            for x in 0..<Self.width { pixels[y * Self.width + x] = src[(y >> 1) * 320 + (x >> 1)] }
        }
        dirty = true
    }

    /// CC_Draw_Shape with SHAPE_CENTER: index 0 transparent.
    func drawShapeCentered(_ f: SHPFrame, x: Int, y: Int) {
        blit(f.pixels, width: f.width, height: f.height, x: x - f.width / 2, y: y - f.height / 2, transparent: 0)
    }

    /// Texture_Fill_Rect: the source tiled from the page origin.
    func textureFill(_ f: SHPFrame, x: Int, y: Int, w: Int, h: Int) {
        guard f.width > 0, f.height > 0 else { return }
        for ty in max(0, y)..<min(Self.height, y + h) {
            for tx in max(0, x)..<min(Self.width, x + w) {
                pixels[ty * Self.width + tx] = f.pixels[(ty % f.height) * f.width + (tx % f.width)]
            }
        }
        dirty = true
    }
}

// MARK: - Dialog art (fonts, button texture, filigree)

/// The Win95 build's dialog resources, loaded once. Hi-res fonts come from
/// CCLOCAL.MIX, BTEXTURE.SHP from UPDATEC.MIX, OPTIONS.SHP from CONQUER.MIX.
final class ClassicDialogArt {
    static let shared = ClassicDialogArt()

    let strings: StringTable?
    let gradFont6: WWFont?   // GRAD6FNT.FNT (TPF_6PT_GRAD)
    let font6: WWFont?       // 6POINT.FNT (TPF_6POINT)
    let scoreFont: WWFont?   // 12GRNGRD.FNT (the Win95 ScoreFontPtr)
    let buttonTexture: SHPFrame?
    let options: SHPFile?

    private init() {
        func font(_ n: String) -> WWFont? { mixManager.retrieve(n).flatMap { WWFont(data: $0) } }
        strings = mixManager.retrieve("CONQUER.ENG").flatMap { StringTable(data: $0) }
        gradFont6 = font("GRAD6FNT.FNT")
        font6 = font("6POINT.FNT")
        scoreFont = font("12GRNGRD.FNT")
        buttonTexture = mixManager.retrieve("BTEXTURE.SHP").flatMap { try? SHPFile(data: $0) }?.frames.first
        options = mixManager.retrieve("OPTIONS.SHP").flatMap { try? SHPFile(data: $0) }
    }

    func text(_ id: Int, _ fallback: String) -> String {
        guard let strings, id < strings.count else { return fallback }
        let s = strings[id]
        return s.isEmpty ? fallback : s
    }
}

/// Text print flags used here (TextPrintType, DEFINES.H).
struct TextPrintFlags: OptionSet {
    let rawValue: Int
    static let center = TextPrintFlags(rawValue: 1 << 0)
    static let right = TextPrintFlags(rawValue: 1 << 1)
    static let noShadow = TextPrintFlags(rawValue: 1 << 2)
    static let fullShadow = TextPrintFlags(rawValue: 1 << 3)
    static let dropShadow = TextPrintFlags(rawValue: 1 << 4)
    static let useGradPal = TextPrintFlags(rawValue: 1 << 5)
    static let mediumColor = TextPrintFlags(rawValue: 1 << 6)
    static let brightColor = TextPrintFlags(rawValue: 1 << 7)
}

enum ClassicFont { case grad6, point6 }

/// Draw_Box styles (BoxStyleEnum, DEFINES.H) with their ButtonColors entries.
enum ClassicBoxStyle {
    case greenDown, greenRaised, greenBorder

    /// Filler (nil = BTEXTURE.SHP), shadow, highlight, corner.
    fileprivate var colors: (filler: UInt8?, shadow: UInt8, highlight: UInt8, corner: UInt8) {
        switch self {
        case .greenDown: return (nil, 14, 12, 13)
        case .greenRaised: return (nil, 12, 14, 13)
        case .greenBorder: return (ClassicColor.black, 14, 14, ClassicColor.black)
        }
    }
}

extension ClassicPage {
    /// Draw_Box (DIALOG.CPP:99).
    func drawBox(x: Int, y: Int, w: Int, h: Int, style: ClassicBoxStyle, filled: Bool = true) {
        let w = w - 1, h = h - 1
        let c = style.colors
        if filled {
            if let filler = c.filler {
                fillRect(x, y, x + w, y + h, filler)
            } else if let tex = ClassicDialogArt.shared.buttonTexture {
                textureFill(tex, x: x, y: y, w: w, h: h)
            } else {
                fillRect(x, y, x + w, y + h, 141)  // CC_GREEN_BKGD
            }
        }
        switch style {
        case .greenBorder:
            drawRect(x + 1, y + 1, x + w - 1, y + h - 1, c.highlight)
        case .greenDown, .greenRaised:
            fillRect(x, y + h, x + w, y + h, c.shadow)
            fillRect(x + w, y, x + w, y + h, c.shadow)
            fillRect(x, y, x + w, y, c.highlight)
            fillRect(x, y, x, y + h, c.highlight)
            putPixel(x, y + h, c.corner)
            putPixel(x + w, y, c.corner)
        }
    }

    /// Dialog_Box + Draw_Caption(TXT_NONE, ...): the main dialog frame with
    /// the OPTION_DIALOG filigree in its top corners (GOPTIONS.CPP).
    func dialogBox(x: Int, y: Int, w: Int, h: Int) {
        drawBox(x: x, y: y, w: w, h: h, style: .greenBorder)
        if let opts = ClassicDialogArt.shared.options, opts.frames.count >= 2 {
            drawShapeCentered(opts.frames[0], x: x + 12, y: y + 11)
            drawShapeCentered(opts.frames[1], x: x + w - 14, y: y + 11)
        }
    }

    /// Simple_Text_Print (DIALOG.CPP:318) for the fonts the classic screens use.
    @discardableResult
    func fancyText(_ text: String, x: Int, y: Int, fore: UInt8, back: UInt8 = ClassicColor.tblack,
                   font kind: ClassicFont, flags: TextPrintFlags) -> Int {
        // _textfontpal / _textpalmedium / _textpalbright rows, indexed by fore & 15.
        let gradPal: [UInt8] = fore & 15 == ClassicColor.green
            ? [0, 159, 0, 0, 0, 0, 0, 0, 0, 0, 0, 142, 143, 159, 41, 167]
            : [UInt8](repeating: fore, count: 16)
        let medium: [UInt8] = [0, 25, 119, 41, 0, 158, 0, 178, 125, 0, 202, 0, 0, 0, 0, 0]
        let bright: [UInt8] = [0, 24, 2, 4, 0, 5, 0, 176, 127, 0, 201, 0, 0, 0, 0, 0]

        var fore = fore
        var pal = [UInt8](repeating: back, count: 16)
        var xspace = 1
        let art = ClassicDialogArt.shared
        let font: WWFont?
        switch kind {
        case .grad6:
            font = art.gradFont6
            xspace -= 1
            pal = flags.contains(.useGradPal) ? gradPal : pal
            if !flags.contains(.useGradPal) { for i in 4..<16 { pal[i] = fore } }
            if flags.contains(.mediumColor) {
                fore = medium[Int(fore & 15)]
                for i in 4..<16 { pal[i] = fore }
            } else if flags.contains(.brightColor) {
                fore = bright[Int(fore & 15)]
                for i in 4..<16 { pal[i] = fore }
            } else {
                fore = pal[1]
            }
        case .point6:
            font = art.font6
            xspace -= 1
        }
        if flags.contains(.noShadow) {
            pal[2] = back; pal[3] = back; xspace -= 1
        } else if flags.contains(.dropShadow) {
            pal[2] = ClassicColor.black; pal[3] = back; xspace -= 1
        } else if flags.contains(.fullShadow) {
            pal[2] = ClassicColor.black; pal[3] = ClassicColor.black; xspace -= 1
        }
        pal[0] = back
        pal[1] = fore
        guard let font, !text.isEmpty else { return x }

        var x = x
        if flags.contains(.center) { x -= font.width(of: text, xSpacing: xspace) >> 1 }
        if flags.contains(.right) { x -= font.width(of: text, xSpacing: xspace) }
        markDirty()
        return font.draw(text, into: &pixels, pageWidth: Self.width, pageHeight: Self.height,
                         x: x, y: y, remap: pal, xSpacing: xspace)
    }
}

// MARK: - TextButtonClass (TEXTBTN.CPP), 6PT_GRAD style

struct ClassicTextButton {
    let label: String
    let x: Int, y: Int, w: Int, h: Int
    let action: () -> Void

    func contains(_ p: (x: Int, y: Int)) -> Bool {
        p.x >= x && p.x < x + w && p.y >= y && p.y < y + h
    }

    /// Draw_Background + Draw_Text: the textured green button; the label
    /// bright when it has focus (IsOn) or is held, medium otherwise.
    func draw(on page: ClassicPage, on: Bool, pressed: Bool) {
        page.drawBox(x: x, y: y, w: w, h: h, style: pressed ? .greenDown : .greenRaised)
        page.fancyText(label, x: x + (w >> 1) - 1, y: y + 1, fore: ClassicColor.green, font: .grad6,
                       flags: [.center, .noShadow, .useGradPal, on || pressed ? .brightColor : .mediumColor])
    }
}
