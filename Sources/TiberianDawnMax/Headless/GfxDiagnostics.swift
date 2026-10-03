import CoreGraphics
import Foundation
import ImageIO
import OpenConquerAssets
import UniformTypeIdentifiers

// MARK: - CPS / WSA / PAL diagnostics (asset-backed)
//
//   --dump-gfx NAME OUTDIR [PALETTE]   decode a .CPS / .WSA / .SHP and write PNGs
//   --test-gfx                         decode the title + map-selection art, print
//                                      sizes / frame counts / digests
//
// PALETTE may be a raw .PAL, or a .CPS / .WSA whose embedded palette is used.
// Without one, embedded palettes are used; files with none (the CLICK_*.CPS
// hit-test maps) get a false-colour palette so each region index is visible.

private func fnv1a(_ bytes: [UInt8]) -> UInt64 {
    var h: UInt64 = 0xCBF2_9CE4_8422_2325
    for b in bytes { h = (h ^ UInt64(b)) &* 0x100_0000_01B3 }
    return h
}

private func hex(_ v: UInt64) -> String { String(format: "0x%016llX", v) }

/// Index 0 black; other indices get well-separated hues (golden-ratio walk).
private func falseColorPalette() -> VGAPalette {
    var raw = [UInt8](repeating: 0, count: 768)
    for i in 1..<256 {
        let h = (Double(i) * 0.618_033_988_75).truncatingRemainder(dividingBy: 1)
        let (r, g, b) = hsvToRGB(h, 0.85, 1.0)
        raw[i * 3] = UInt8(r * 63); raw[i * 3 + 1] = UInt8(g * 63); raw[i * 3 + 2] = UInt8(b * 63)
    }
    return try! VGAPalette(vga6: raw)
}

private func hsvToRGB(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
    let i = Int(h * 6) % 6
    let f = h * 6 - Double(Int(h * 6))
    let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
    switch i {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
}

/// A palette by name: a raw .PAL, or the palette embedded in a .CPS/.WSA.
private func loadNamedPalette(_ name: String) -> VGAPalette? {
    guard let data = assetManager.retrieve(name) else { return nil }
    switch (name as NSString).pathExtension.uppercased() {
    case "CPS": return (try? CPSFile(data: Data(data)))?.palette
    case "WSA": return (try? WSAFile(data: Data(data)))?.palette
    default: return try? VGAPalette(data: Data(data))
    }
}

/// Palette the game shows a file with when it carries none (MAPSEL.CPP:
/// COUNTRY*.SHP are drawn over the EUROPE/AFRICA progress map).
private func defaultPalette(for name: String) -> VGAPalette? {
    switch name.uppercased() {
    case "COUNTRYE.SHP": return loadNamedPalette("EUROPE.WSA")
    case "COUNTRYA.SHP": return loadNamedPalette("AFRICA.WSA")
    default: return nil
    }
}


/// Lays indexed frames out in a grid (1px gutter of index 0).
private func contactSheet(_ frames: [[UInt8]], w: Int, h: Int, columns: Int) -> (pixels: [UInt8], w: Int, h: Int) {
    let cols = max(1, min(columns, frames.count))
    let rows = (frames.count + cols - 1) / cols
    let sw = cols * (w + 1), sh = rows * (h + 1)
    var out = [UInt8](repeating: 0, count: sw * sh)
    for (i, f) in frames.enumerated() {
        let ox = (i % cols) * (w + 1), oy = (i / cols) * (h + 1)
        for y in 0..<h {
            let src = y * w, dst = (oy + y) * sw + ox
            for x in 0..<w { out[dst + x] = f[src + x] }
        }
    }
    return (out, sw, sh)
}

// MARK: - --dump-gfx

func runDumpGfx(name: String, outDir: String, paletteName: String?) -> Int32 {
    let upper = name.uppercased()
    guard let data = assetManager.retrieve(upper) else {
        print("dump-gfx: \(upper) not found"); return 1
    }
    let dir = URL(fileURLWithPath: outDir, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let base = (upper as NSString).deletingPathExtension

    var explicit: VGAPalette?
    if let p = paletteName {
        guard let pal = loadNamedPalette(p.uppercased()) else {
            print("dump-gfx: palette \(p) not found / not a palette"); return 1
        }
        explicit = pal
    }

    func pick(_ embedded: VGAPalette?) -> (VGAPalette, String) {
        if let e = explicit { return (e, paletteName!.uppercased()) }
        if let e = embedded { return (e, "embedded") }
        if let d = defaultPalette(for: upper) { return (d, "default for \(upper)") }
        return (falseColorPalette(), "false-colour (no palette)")
    }

    do {
        switch (upper as NSString).pathExtension {
        case "CPS":
            let cps = try CPSFile(data: Data(data))
            let (pal, src) = pick(cps.palette)
            let url = dir.appendingPathComponent("\(base).png")
            guard writeRGBAPNG(rgba: pal.rgba(cps.pixels), width: cps.width, height: cps.height, to: url) else {
                print("dump-gfx: failed writing \(url.path)"); return 1
            }
            print("\(upper): \(cps.width)x\(cps.height) palette=\(src) -> \(url.path)")
        case "WSA":
            let wsa = try WSAFile(data: Data(data))
            let (pal, src) = pick(wsa.palette)
            let frames = wsa.decodeAllFrames()
            for (i, f) in frames.enumerated() {
                let url = dir.appendingPathComponent(String(format: "%@_%03d.png", base, i))
                guard writeRGBAPNG(rgba: pal.rgba(f), width: wsa.width, height: wsa.height, to: url) else {
                    print("dump-gfx: failed writing \(url.path)"); return 1
                }
            }
            // Sheet: at most 24 evenly sampled frames, so long anims stay viewable.
            let step = max(1, (frames.count + 23) / 24)
            let sampled = stride(from: 0, to: frames.count, by: step).map { frames[$0] }
            let sheet = contactSheet(sampled, w: wsa.width, h: wsa.height, columns: wsa.width <= 160 ? 8 : 4)
            let sheetURL = dir.appendingPathComponent("\(base)_sheet.png")
            _ = writeRGBAPNG(rgba: pal.rgba(sheet.pixels), width: sheet.w, height: sheet.h, to: sheetURL)
            print("\(upper): \(frames.count) frames \(wsa.width)x\(wsa.height) at (\(wsa.x),\(wsa.y)) palette=\(src) -> \(dir.path)/\(base)_NNN.png + \(base)_sheet.png (every \(step) frame(s))")
        case "SHP":
            let shp = try SHPFile(data: Data(data))
            let (pal, src) = pick(nil)
            for (i, f) in shp.frames.enumerated() where f.width > 0 && f.height > 0 {
                let url = dir.appendingPathComponent(String(format: "%@_%03d.png", base, i))
                _ = writeRGBAPNG(rgba: pal.rgba(f.pixels, transparentIndex: 0), width: f.width, height: f.height, to: url)
            }
            print("\(upper): \(shp.frames.count) frames palette=\(src) -> \(dir.path)/\(base)_NNN.png")
        default:
            print("dump-gfx: unsupported extension (want .CPS, .WSA or .SHP)"); return 1
        }
    } catch {
        print("dump-gfx: \(upper): \(error)"); return 1
    }
    return 0
}

// MARK: - --test-gfx

func runTestGfx() -> Int32 {
    var failures = 0
    func loc(_ n: String) -> String { mixManager.locate(n) ?? "loose/extracted" }

    print("== CPS ==")
    for name in ["TITLE.CPS", "CLICK_E.CPS", "CLICK_A.CPS", "CLICK_EB.CPS", "CLICK_SA.CPS"] {
        guard let data = assetManager.retrieve(name) else { print("  \(name): MISSING"); failures += 1; continue }
        do {
            let cps = try CPSFile(data: Data(data))
            var hist: [UInt8: Int] = [:]
            for p in cps.pixels { hist[p, default: 0] += 1 }
            let regions = hist.keys.sorted().filter { $0 != 0 }
                .map { String(format: "%02X:%d", $0, hist[$0]!) }.joined(separator: " ")
            print("  \(name) [\(loc(name))]: \(cps.width)x\(cps.height) method=\(cps.compressionMethod) palette=\(cps.palette != nil ? "embedded" : "none") digest=\(hex(fnv1a(cps.pixels))) colours=\(hist.count)")
            if name.hasPrefix("CLICK") { print("    indices: \(regions)") }
        } catch { print("  \(name): DECODE FAILED \(error)"); failures += 1 }
    }

    print("== WSA ==")
    let required = ["EARTH_E.WSA", "EARTH_A.WSA", "GREYERTH.WSA", "EUROPE.WSA", "AFRICA.WSA", "BOSNIA.WSA", "S_AFRICA.WSA"]
    // What the shipped MAPSEL.CPP / INTRO.CPP actually open.
    let extra = ["HEARTH_E.WSA", "HEARTH_A.WSA", "E-BWTOCL.WSA", "HBOSNIA.WSA", "HSAFRICA.WSA", "CHOOSE.WSA"]
    for name in required + extra {
        guard let data = assetManager.retrieve(name) else {
            print("  \(name): MISSING")
            if required.contains(name) { failures += 1 }
            continue
        }
        do {
            let wsa = try WSAFile(data: Data(data))
            let frames = wsa.decodeAllFrames()
            var all: [UInt8] = []
            for f in frames { all += f }
            var loopNote = "linear"
            if wsa.hasLoopFrame, let last = frames.last {
                var b = last
                wsa.applyDelta(wsa.frameCount, to: &b)
                loopNote = b == frames[0] ? "loop->frame0 OK" : "loop MISMATCH"
                if b != frames[0] { failures += 1 }
            }
            print("  \(name) [\(loc(name))]: \(wsa.frameCount) frames \(wsa.width)x\(wsa.height) at (\(wsa.x),\(wsa.y)) flags=\(wsa.flags) palette=\(wsa.palette != nil ? "embedded" : "none") frame0=\(wsa.frame0OnPage ? "on-page" : (wsa.frame0IsDelta ? "xor" : "copy")) \(loopNote) digest=\(hex(fnv1a(all)))")
        } catch {
            print("  \(name): DECODE FAILED \(error)")
            failures += 1
        }
    }

    print("== SHP ==")
    for name in ["COUNTRYE.SHP", "COUNTRYA.SHP"] {
        guard let data = assetManager.retrieve(name) else { print("  \(name): MISSING"); failures += 1; continue }
        do {
            let shp = try SHPFile(data: Data(data))
            let sizes = shp.frames.map { "\($0.width)x\($0.height)" }.joined(separator: " ")
            var all: [UInt8] = []
            for f in shp.frames { all += f.pixels }
            print("  \(name) [\(loc(name))]: \(shp.frames.count) frames digest=\(hex(fnv1a(all)))")
            print("    sizes: \(sizes)")
        } catch { print("  \(name): DECODE FAILED \(error)"); failures += 1 }
    }

    print("== PAL ==")
    for name in ["DARK_E.PAL", "DARK_B.PAL", "DARK_SA.PAL", "TEMPERAT.PAL",
                 "MAP1.PAL", "MAP_LOCL.PAL", "MAP_GRY2.PAL", "MAP_PROG.PAL", "MAP_LOC2.PAL",
                 "MAP_LOC3.PAL", "LASTSCNG.PAL", "LASTSCNB.PAL", "SIDES.PAL"] {
        guard let data = assetManager.retrieve(name) else { print("  \(name): MISSING"); continue }
        if let pal = try? VGAPalette(data: Data(data)) {
            let max6 = pal.raw6.max() ?? 0
            print("  \(name) [\(loc(name))]: \(data.count) bytes, max 6-bit component \(max6), digest=\(hex(fnv1a(pal.raw6)))")
        } else {
            print("  \(name) [\(loc(name))]: \(data.count) bytes — not a 768-byte palette")
        }
    }

    print(failures == 0 ? "test-gfx: PASS" : "test-gfx: \(failures) FAILURE(S)")
    return failures == 0 ? 0 : 1
}
