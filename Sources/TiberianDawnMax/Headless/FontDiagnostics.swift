import CoreGraphics
import Foundation
import ImageIO
import OpenConquerAssets
import UniformTypeIdentifiers

// MARK: - String table / .FNT font diagnostics (asset-backed)
//
//   --test-fonts                     load CONQUER.ENG (check three known TXT_*
//                                    strings) and every TD font; print heights,
//                                    widths and the font colours each one uses
//   --dump-font NAME OUT.png "TEXT" [--colors]
//                                    render TEXT white-on-black, scaled 4x
//                                    (--colors: false-colour every font colour)

private let fontNames = ["SCOREFNT.FNT", "6POINT.FNT", "8POINT.FNT", "3POINT.FNT", "GRAD6FNT.FNT", "12GRNGRD.FNT", "12GREEN.FNT"]

/// Runs the font diagnostic named on the command line, if any; nil otherwise.
func runFontDiagnosticsIfRequested() -> Int32? {
    let args = CommandLine.arguments
    if args.contains("--test-fonts") { return testFonts() }
    if let i = args.firstIndex(of: "--dump-font") {
        guard i + 3 < args.count else {
            print("usage: --dump-font NAME OUT.png \"TEXT\"")
            return 2
        }
        return dumpFont(args[i + 1], to: URL(fileURLWithPath: args[i + 2]), text: args[i + 3])
    }
    return nil
}

private func loadFont(_ name: String) -> WWFont? {
    let file = name.uppercased().hasSuffix(".FNT") ? name.uppercased() : name.uppercased() + ".FNT"
    guard let data = mixManager.retrieve(file) else { return nil }
    return WWFont(data: data)
}

private func testFonts() -> Int32 {
    var failures = 0
    guard let eng = mixManager.retrieve("CONQUER.ENG"), let table = StringTable(data: eng) else {
        print("FAIL: cannot load CONQUER.ENG")
        return 1
    }
    print("CONQUER.ENG: \(table.count) strings")
    for (id, want) in [(502, "LOCATING COORDINATES"), (576, "CLICK TO CONTINUE"), (742, "READING IMAGE DATA")] {
        let ok = table[id] == want
        if !ok { failures += 1 }
        let note = id >= table.count ? " (not in this file: mapsel.cpp fallback)" : ""
        print("  [\(id)] \"\(table[id])\" \(ok ? "ok" : "FAIL (want \"\(want)\")")\(note)")
    }
    for name in fontNames {
        guard let font = loadFont(name) else {
            print("FAIL: \(name) missing or invalid")
            failures += 1
            continue
        }
        let hist = font.colorHistogram()
        let used = (1..<16).filter { hist[$0] > 0 }.map { "\($0):\(hist[$0])" }.joined(separator: " ")
        print("\(name): height=\(font.height) maxWidth=\(font.maxWidth) glyphs=\(font.glyphCount) "
              + "width(\"LOCATING COORDINATES\")=\(font.width(of: "LOCATING COORDINATES")) "
              + "width('A')=\(font.width(of: UInt8(ascii: "A"))) colours[\(used)]")
    }
    print(failures == 0 ? "PASS" : "FAIL (\(failures))")
    return failures == 0 ? 0 : 1
}

private func dumpFont(_ name: String, to url: URL, text: String) -> Int32 {
    guard let font = loadFont(name) else {
        print("FAIL: cannot load font \(name)")
        return 1
    }
    let pad = 2, scale = 4
    let w = font.width(of: text) + pad * 2, h = font.height + pad * 2
    var page = [UInt8](repeating: 0, count: w * h)
    // Font colour c → page index c. The 3-colour fonts (6POINT, 8POINT, 3POINT)
    // use 1 = text, 2 = drop shadow, 3 = outline (Simple_Text_Print's font
    // palette); by default they draw as TPF_NOSHADOW (2 and 3 transparent).
    // --colors keeps every colour and false-colours it.
    let falseColor = CommandLine.arguments.contains("--colors")
    let shadowFont = font.colorHistogram()[4...].allSatisfy { $0 == 0 }
    let remap: [UInt8] = (0..<16).map { c in !falseColor && shadowFont && c >= 2 ? 0 : UInt8(c) }
    let end = font.draw(text, into: &page, pageWidth: w, pageHeight: h, x: pad, y: pad, remap: remap)
    var rgba = [UInt8](repeating: 0, count: w * scale * h * scale * 4)
    for y in 0..<(h * scale) {
        for x in 0..<(w * scale) {
            let c = Int(page[(y / scale) * w + x / scale])
            var rgb: (UInt8, UInt8, UInt8) = (0, 0, 0)
            if c == 1 {
                rgb = (255, 255, 255)
            } else if c > 1 && falseColor {
                let hue = [(255, 64, 64), (64, 255, 64), (64, 128, 255), (255, 255, 64), (255, 64, 255), (64, 255, 255)][(c - 2) % 6]
                rgb = (UInt8(hue.0), UInt8(hue.1), UInt8(hue.2))
            } else if c > 1 {
                // Gradient fonts (SCOREFNT, GRAD6FNT): a grey ramp, 2 brightest.
                let v = UInt8(255 - (c - 2) * 12)
                rgb = (v, v, v)
            }
            let d = (y * w * scale + x) * 4
            rgba[d] = rgb.0; rgba[d + 1] = rgb.1; rgba[d + 2] = rgb.2; rgba[d + 3] = 255
        }
    }
    guard writeRGBAPNG(rgba: rgba, width: w * scale, height: h * scale, to: url) else {
        print("FAIL: cannot write \(url.path)")
        return 1
    }
    print("\(name): height=\(font.height) text width=\(end - pad) → \(url.path) (\(w)x\(h) @\(scale)x)")
    return 0
}

