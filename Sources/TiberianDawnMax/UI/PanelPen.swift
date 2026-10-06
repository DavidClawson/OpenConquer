import CSDL2

// MARK: - Panel drawing

/// Lays out the side panel top to bottom: text, rows and grids of buttons,
/// steppers, check boxes. Each control registers its rectangle and action
/// through `hit` as it draws (immediate mode); the screen tests clicks against
/// the last frame's list.
final class PanelPen {
    let r: OpaquePointer?
    let x: Int32, w: Int32
    var y: Int32
    let clip: (top: Int32, bottom: Int32)
    let hit: (SDL_Rect, String, @escaping () -> Void) -> Void

    static let lineH: Int32 = 18
    static let smallLineH: Int32 = 11
    static let buttonH: Int32 = 26
    static let smallButtonH: Int32 = 20

    init(renderer: OpaquePointer?, x: Int32, w: Int32, y: Int32, clip: (Int32, Int32),
         hit: @escaping (SDL_Rect, String, @escaping () -> Void) -> Void) {
        r = renderer
        self.x = x
        self.w = w
        self.y = y
        self.clip = clip
        self.hit = hit
    }

    private func visible(_ top: Int32, _ h: Int32) -> Bool { top + h > clip.top && top < clip.bottom }

    static func wrap(_ text: String, chars: Int) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if line.isEmpty { line = String(word) } else if line.count + 1 + word.count <= chars { line += " " + word } else {
                lines.append(line)
                line = String(word)
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    func text(_ s: String, _ color: Color = .green) {
        for line in Self.wrap(s, chars: Int(w / 12)) {
            if visible(y, Self.lineH) { drawTextLeft(r, line, x: x, y: y, color: color, scale: 2) }
            y += Self.lineH
        }
    }

    /// Small grey explanatory text.
    func note(_ s: String) {
        for line in Self.wrap(s, chars: Int(w / 6)) {
            if visible(y, Self.smallLineH) { drawTextLeft(r, line, x: x, y: y, color: .gray, scale: 1) }
            y += Self.smallLineH
        }
        y += 4
    }

    func label(_ s: String) {
        y += 2
        if visible(y, Self.smallLineH) { drawTextLeft(r, s, x: x, y: y, color: .amber, scale: 1) }
        y += Self.smallLineH + 2
    }

    func heading(_ s: String) {
        y += 8
        text(s, .amber)
        SDL_SetRenderDrawColor(r, Color.darkGreen.r, Color.darkGreen.g, Color.darkGreen.b, 255)
        SDL_RenderDrawLine(r, x, y, x + w, y)
        y += 6
    }

    func gap(_ n: Int32) { y += n }

    func button(_ label: String, x bx: Int32, y by: Int32, w bw: Int32, h bh: Int32, selected: Bool,
                small: Bool, name: String? = nil, action: @escaping () -> Void) {
        guard visible(by, bh) else { return }
        let rect = SDL_Rect(x: bx, y: by, w: bw, h: bh)
        let over = input.mouseX >= bx && input.mouseX < bx + bw && input.mouseY >= by && input.mouseY < by + bh
        var rr = rect
        let fill = selected ? Color.darkGreen : (over ? Color(r: 0, g: 50, b: 0, a: 255) : Color.black)
        SDL_SetRenderDrawColor(r, fill.r, fill.g, fill.b, 255)
        SDL_RenderFillRect(r, &rr)
        let border = selected || over ? Color.brightGreen : Color.green
        SDL_SetRenderDrawColor(r, border.r, border.g, border.b, 255)
        SDL_RenderDrawRect(r, &rr)
        let scale: Int32 = small ? 1 : 2
        let maxChars = Int((bw - 8) / (6 * scale))
        var text = label.uppercased()
        if text.count > maxChars { text = String(text.prefix(max(1, maxChars - 1))) + "." }
        drawText(r, text, centerX: bx + bw / 2, centerY: by + bh / 2, color: selected ? .white : .green, scale: scale)
        if by >= clip.top && by + bh <= clip.bottom + bh { hit(rect, (name ?? label).uppercased(), action) }
    }

    func row(_ items: [(String, Bool, () -> Void)], small: Bool = false) {
        guard !items.isEmpty else { return }
        let gap: Int32 = 4
        let bw = (w - gap * Int32(items.count - 1)) / Int32(items.count)
        let bh = small ? Self.smallButtonH : Self.buttonH
        for (i, item) in items.enumerated() {
            button(item.0, x: x + Int32(i) * (bw + gap), y: y, w: bw, h: bh, selected: item.1, small: small, action: item.2)
        }
        y += bh + gap
    }

    func grid(_ items: [(String, Bool, () -> Void)], columns: Int, small: Bool = false) {
        var i = 0
        while i < items.count {
            var chunk = Array(items[i..<min(items.count, i + columns)])
            let real = chunk.count
            while chunk.count < columns { chunk.append(("", false, {})) }
            let gap: Int32 = 4
            let bw = (w - gap * Int32(columns - 1)) / Int32(columns)
            let bh = small ? Self.smallButtonH : Self.buttonH
            for (j, item) in chunk.enumerated() where j < real {
                button(item.0, x: x + Int32(j) * (bw + gap), y: y, w: bw, h: bh, selected: item.1, small: small, action: item.2)
            }
            y += bh + gap
            i += columns
        }
    }

    /// Picture tiles in a grid, each with a caption: `draw` paints the picture
    /// into the rect it's given.
    func thumbnails(_ items: [(String, Bool, (SDL_Rect) -> Void, () -> Void)], columns: Int, height: Int32) {
        let gap: Int32 = 4
        let bw = (w - gap * Int32(columns - 1)) / Int32(columns)
        for (i, item) in items.enumerated() {
            let col = Int32(i % columns)
            let top = y + Int32(i / columns) * (height + gap)
            let rect = SDL_Rect(x: x + col * (bw + gap), y: top, w: bw, h: height)
            guard visible(top, height) else { continue }
            var rr = rect
            let over = input.mouseX >= rect.x && input.mouseX < rect.x + bw && input.mouseY >= top && input.mouseY < top + height
            SDL_SetRenderDrawColor(r, 0, item.1 ? 60 : 0, 0, 255)
            SDL_RenderFillRect(r, &rr)
            item.2(SDL_Rect(x: rect.x, y: rect.y, w: rect.w, h: rect.h - 10))
            let border = item.1 ? Color.white : (over ? Color.brightGreen : Color.darkGreen)
            SDL_SetRenderDrawColor(r, border.r, border.g, border.b, 255)
            SDL_RenderDrawRect(r, &rr)
            if item.1 {
                var inner = SDL_Rect(x: rect.x + 1, y: rect.y + 1, w: rect.w - 2, h: rect.h - 2)
                SDL_RenderDrawRect(r, &inner)
            }
            drawText(r, item.0, centerX: rect.x + bw / 2, centerY: top + height - 7, color: item.1 ? .white : .green, scale: 1)
            if top >= clip.top { hit(rect, item.0.uppercased(), item.3) }
        }
        let rows = Int32((items.count + columns - 1) / columns)
        y += rows * (height + gap)
    }

    /// LABEL ........ [-] VALUE [+]
    func stepper(_ label: String, _ value: String, _ dec: @escaping () -> Void, _ inc: @escaping () -> Void) {
        let bh = Self.smallButtonH
        if visible(y, bh) {
            drawTextLeft(r, label, x: x, y: y + 6, color: .green, scale: 1)
            drawText(r, value, centerX: x + w - 60, centerY: y + bh / 2, color: .white, scale: 2)
        }
        button("-", x: x + w - 120, y: y, w: 28, h: bh, selected: false, small: false, name: label + " -", action: dec)
        button("+", x: x + w - 28, y: y, w: 28, h: bh, selected: false, small: false, name: label + " +", action: inc)
        y += bh + 4
    }

    /// [x] LABEL
    func toggle(_ label: String, _ on: Bool, _ set: @escaping (Bool) -> Void) {
        let h = Self.smallButtonH - 4
        if visible(y, h) {
            var box = SDL_Rect(x: x, y: y + 2, w: 12, h: 12)
            SDL_SetRenderDrawColor(r, Color.green.r, Color.green.g, Color.green.b, 255)
            SDL_RenderDrawRect(r, &box)
            if on {
                var inner = SDL_Rect(x: x + 3, y: y + 5, w: 6, h: 6)
                SDL_SetRenderDrawColor(r, Color.brightGreen.r, Color.brightGreen.g, Color.brightGreen.b, 255)
                SDL_RenderFillRect(r, &inner)
            }
            drawTextLeft(r, label, x: x + 20, y: y + 5, color: on ? .white : .green, scale: 1)
            if y >= clip.top { hit(SDL_Rect(x: x, y: y, w: w, h: h), label.uppercased()) { set(!on) } }
        }
        y += h + 2
    }
}
