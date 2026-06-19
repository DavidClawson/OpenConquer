import CSDL2
import Foundation
import CoreGraphics
import ImageIO

// MARK: - Remastered Sprite Loader
// Loads hi-res PNG sprites extracted from C&C Remastered Collection.
// Falls back gracefully when remastered sprites aren't available.

/// Remastered sprites directory categories
private let remasteredCategories = ["units", "structures", "vfx"]

/// Cache of loaded remastered sprite manifests
private var remasteredManifests: [String: RemasteredManifest] = [:]
private var remasteredManifestFailed: Set<String> = []

/// Cache of remastered SDL textures: "TYPENAME_frame" -> texture

/// Scale factor: remastered uses 128px tiles, classic uses 24px tiles.
/// At zoom 1.0 this maps remastered sprites to classic-compatible sizes.
/// The hi-res textures are preserved at full resolution — as you zoom in,
/// you see the extra detail. On Retina displays, the 2x pixel density
/// also benefits from the higher source resolution.
let remasteredScale: Double = 24.0 / 128.0

/// Whether remastered sprites are available

struct RemasteredManifest {
    let name: String
    let canvasWidth: Int
    let canvasHeight: Int
    let frameCount: Int
    let category: String  // "units", "structures", "vfx"
    let basePath: String  // directory containing individual frame PNGs
}

// MARK: - Initialization

/// Check for remastered sprites and index available manifests
func initRemasteredSprites() {
    let spritesPath = assetManager.extractedPath
        .appendingPathComponent("sprites_remastered")

    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: spritesPath.path, isDirectory: &isDir),
          isDir.boolValue else {
        renderState.hasRemasteredSprites = false
        return
    }

    // Check each category
    var totalFound = 0
    for category in remasteredCategories {
        let catPath = spritesPath.appendingPathComponent(category)
        guard FileManager.default.fileExists(atPath: catPath.path) else { continue }

        // Scan for .json manifests
        if let files = try? FileManager.default.contentsOfDirectory(atPath: catPath.path) {
            for file in files where file.hasSuffix(".json") {
                let name = String(file.dropLast(5)).uppercased()  // strip .json
                if loadManifest(name: name, category: category, catPath: catPath) {
                    totalFound += 1
                }
            }
        }
    }

    renderState.hasRemasteredSprites = totalFound > 0
    if renderState.hasRemasteredSprites {
        print("Remastered sprites: \(totalFound) manifests loaded")
    }
}

/// Load a manifest JSON file
private func loadManifest(name: String, category: String, catPath: URL) -> Bool {
    let jsonPath = catPath.appendingPathComponent("\(name).json")
    guard let data = try? Data(contentsOf: jsonPath),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let canvasW = json["canvas_width"] as? Int,
          let canvasH = json["canvas_height"] as? Int,
          let frameCount = json["frame_count"] as? Int else {
        return false
    }

    let framePath = catPath.appendingPathComponent(name).path
    remasteredManifests[name] = RemasteredManifest(
        name: name,
        canvasWidth: canvasW,
        canvasHeight: canvasH,
        frameCount: frameCount,
        category: category,
        basePath: framePath
    )
    return true
}

/// Total frame count for a sprite's remastered manifest, if one is loaded.
/// Used by frame-selection logic (e.g. building damage frames) which needs the
/// full frame count even when the classic SHP is never loaded because the
/// remastered HD sprite is drawn instead.
func remasteredFrameCount(_ typeName: String) -> Int? {
    guard renderState.hasRemasteredSprites else { return nil }
    return remasteredManifests[typeName.uppercased()]?.frameCount
}

// MARK: - Texture Loading

/// Try to load a remastered sprite texture for the given type and frame.
/// Returns (texture, displayWidth, displayHeight) where display dimensions
/// are scaled to match the classic 24px tile grid.
func getRemasteredTexture(_ renderer: OpaquePointer?, typeName: String, frame: Int)
    -> (texture: OpaquePointer, width: Int, height: Int)? {

    guard renderState.hasRemasteredSprites else { return nil }

    let upperName = typeName.uppercased()
    let key = "RM_\(upperName)_\(frame)"

    // Check texture cache
    if let cached = renderState.remasteredTextureCache[key] {
        if let manifest = remasteredManifests[upperName] {
            let displayW = Int(Double(manifest.canvasWidth) * remasteredScale)
            let displayH = Int(Double(manifest.canvasHeight) * remasteredScale)
            return (texture: cached, width: displayW, height: displayH)
        }
    }

    // Check if we already know this sprite doesn't exist
    if remasteredManifestFailed.contains(upperName) { return nil }

    // Get manifest
    guard let manifest = remasteredManifests[upperName] else {
        remasteredManifestFailed.insert(upperName)
        return nil
    }

    // Check frame bounds
    guard frame < manifest.frameCount else { return nil }

    // Load PNG file
    let pngPath = "\(manifest.basePath)/\(upperName)-\(String(format: "%04d", frame)).png"
    guard let texture = loadPNGTexture(renderer, path: pngPath) else { return nil }

    renderState.remasteredTextureCache[key] = texture

    let displayW = Int(Double(manifest.canvasWidth) * remasteredScale)
    let displayH = Int(Double(manifest.canvasHeight) * remasteredScale)
    return (texture: texture, width: displayW, height: displayH)
}

/// Load a PNG file and create an SDL texture from it using CoreGraphics
private func loadPNGTexture(_ renderer: OpaquePointer?, path: String) -> OpaquePointer? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return nil
    }

    let width = cgImage.width
    let height = cgImage.height
    guard width > 0 && height > 0 else { return nil }

    // Render CGImage into an ARGB8888 pixel buffer
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    // Use premultiplied alpha for CoreGraphics rendering, then convert to straight alpha for SDL
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return nil }

    // Clear to transparent and draw the image
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Convert premultiplied alpha → straight alpha for SDL_BLENDMODE_BLEND
    // ARGB layout in memory (little-endian): B, G, R, A
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let a = pixels[i + 3]
        if a > 0 && a < 255 {
            pixels[i]     = UInt8(min(255, Int(pixels[i]) * 255 / Int(a)))     // B
            pixels[i + 1] = UInt8(min(255, Int(pixels[i + 1]) * 255 / Int(a))) // G
            pixels[i + 2] = UInt8(min(255, Int(pixels[i + 2]) * 255 / Int(a))) // R
        }
    }

    // Create SDL texture
    let format: UInt32 = 0x16362004  // SDL_PIXELFORMAT_ARGB8888
    guard let texture = SDL_CreateTexture(
        renderer, format,
        Int32(SDL_TEXTUREACCESS_STATIC.rawValue),
        Int32(width), Int32(height)
    ) else { return nil }

    _ = pixels.withUnsafeMutableBufferPointer { buf in
        SDL_UpdateTexture(texture, nil, buf.baseAddress, Int32(bytesPerRow))
    }

    SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)
    // Enable linear filtering for smooth downscaling
    SDL_SetTextureScaleMode(texture, SDL_ScaleModeLinear)

    return texture
}

// MARK: - House-Colored Remastered Textures (Hue Shift)

/// The remastered sprites use bright green (hue ~105-120°) as the team color.
/// This function loads a remastered PNG and shifts green team-color pixels to
/// the target house's hue, matching how the C&C Remastered game uses shaders.
/// Widened range to catch all green variants including darker/lighter shades.
private let teamColorHueMin: Float = 80.0 / 360.0    // ~0.222 — catches yellow-green
private let teamColorHueMax: Float = 160.0 / 360.0   // ~0.444 — catches cyan-green
private let teamColorSatMin: Float = 0.20             // lower threshold for paler greens

/// Target hue (0-360) for each house color
private func houseTargetHue(_ house: House) -> Float? {
    switch house {
    case .goodGuy: return 45.0 / 360.0    // Gold/yellow
    case .badGuy:  return 0.0 / 360.0     // Red
    case .neutral: return nil              // Gray — desaturate instead
    case .special: return 55.0 / 360.0    // Yellow-ish
    case .multi1:  return 210.0 / 360.0   // Light blue
    case .multi2:  return 30.0 / 360.0    // Orange
    case .multi3:  return nil              // Green — already green, no shift needed
    case .multi4:  return 45.0 / 360.0    // Gold (same as GDI)
    case .multi5:  return 0.0 / 360.0     // Red (same as Nod)
    case .multi6:  return 240.0 / 360.0   // Blue
    }
}

/// Get a remastered sprite texture with house color hue-shifting applied.
/// For the default green team color (multi3), returns the normal texture.
/// Returns (texture, displayWidth, displayHeight) or nil.
func getRemasteredTextureWithHouse(_ renderer: OpaquePointer?, typeName: String, frame: Int, house: House)
    -> (texture: OpaquePointer, width: Int, height: Int)? {

    guard renderState.hasRemasteredSprites else { return nil }

    // If house is multi3 (green) or neutral with no shift, use normal texture
    let targetHue = houseTargetHue(house)
    let isNeutral = house == .neutral
    if targetHue == nil && !isNeutral {
        return getRemasteredTexture(renderer, typeName: typeName, frame: frame)
    }

    let upperName = typeName.uppercased()
    let key = "RMH_\(upperName)_\(frame)_\(house.rawValue)"

    // Check cache
    if let cached = renderState.remasteredTextureCache[key] {
        if let manifest = remasteredManifests[upperName] {
            let displayW = Int(Double(manifest.canvasWidth) * remasteredScale)
            let displayH = Int(Double(manifest.canvasHeight) * remasteredScale)
            return (texture: cached, width: displayW, height: displayH)
        }
    }

    // Check if sprite doesn't exist
    if remasteredManifestFailed.contains(upperName) { return nil }

    guard let manifest = remasteredManifests[upperName] else {
        remasteredManifestFailed.insert(upperName)
        return nil
    }
    guard frame < manifest.frameCount else { return nil }

    let pngPath = "\(manifest.basePath)/\(upperName)-\(String(format: "%04d", frame)).png"
    guard let texture = loadPNGTextureWithHueShift(renderer, path: pngPath,
                                                    targetHue: targetHue, desaturate: isNeutral) else {
        return nil
    }

    renderState.remasteredTextureCache[key] = texture

    let displayW = Int(Double(manifest.canvasWidth) * remasteredScale)
    let displayH = Int(Double(manifest.canvasHeight) * remasteredScale)
    return (texture: texture, width: displayW, height: displayH)
}

/// Load a PNG and apply hue-shift to team-colored pixels.
/// If desaturate is true, team-color pixels are converted to grayscale instead.
private func loadPNGTextureWithHueShift(_ renderer: OpaquePointer?, path: String,
                                         targetHue: Float?, desaturate: Bool) -> OpaquePointer? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return nil
    }

    let width = cgImage.width
    let height = cgImage.height
    guard width > 0 && height > 0 else { return nil }

    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return nil }

    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Convert premultiplied alpha → straight alpha AND apply hue shift
    // ARGB layout in memory (little-endian): B, G, R, A
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let a = pixels[i + 3]
        guard a > 0 else { continue }

        var bf = Float(pixels[i])
        var gf = Float(pixels[i + 1])
        var rf = Float(pixels[i + 2])

        // Un-premultiply alpha
        if a < 255 {
            let aInv = 255.0 / Float(a)
            bf = min(255, bf * aInv)
            gf = min(255, gf * aInv)
            rf = min(255, rf * aInv)
        }

        // Convert to HSV to check if this is a team-color pixel
        let r01 = rf / 255.0, g01 = gf / 255.0, b01 = bf / 255.0
        let maxC = max(r01, g01, b01)
        let minC = min(r01, g01, b01)
        let delta = maxC - minC

        if delta > 0.001 {
            let sat = delta / maxC
            var hue: Float = 0
            if maxC == r01 {
                hue = (g01 - b01) / delta
                if hue < 0 { hue += 6 }
            } else if maxC == g01 {
                hue = 2 + (b01 - r01) / delta
            } else {
                hue = 4 + (r01 - g01) / delta
            }
            hue /= 6.0  // normalize to 0-1

            // Check if in team color range
            if hue >= teamColorHueMin && hue <= teamColorHueMax && sat >= teamColorSatMin {
                if desaturate {
                    // Convert to grayscale preserving value
                    let gray = UInt8(min(255, maxC * 255))
                    pixels[i] = gray     // B
                    pixels[i + 1] = gray // G
                    pixels[i + 2] = gray // R
                } else if let th = targetHue {
                    // Shift hue to target, preserve saturation and value
                    let newHue = th
                    let val = maxC

                    // HSV to RGB
                    let hi = Int(newHue * 6) % 6
                    let f = newHue * 6 - Float(hi)
                    let p = val * (1 - sat)
                    let q = val * (1 - f * sat)
                    let t = val * (1 - (1 - f) * sat)

                    var nr: Float, ng: Float, nb: Float
                    switch hi {
                    case 0: nr = val; ng = t;   nb = p
                    case 1: nr = q;   ng = val; nb = p
                    case 2: nr = p;   ng = val; nb = t
                    case 3: nr = p;   ng = q;   nb = val
                    case 4: nr = t;   ng = p;   nb = val
                    default: nr = val; ng = p;  nb = q
                    }

                    pixels[i]     = UInt8(min(255, nb * 255))  // B
                    pixels[i + 1] = UInt8(min(255, ng * 255))  // G
                    pixels[i + 2] = UInt8(min(255, nr * 255))  // R
                }
                continue
            }
        }

        // Non-team-color pixel: just store un-premultiplied values
        pixels[i]     = UInt8(bf)
        pixels[i + 1] = UInt8(gf)
        pixels[i + 2] = UInt8(rf)
    }

    // Create SDL texture
    let format: UInt32 = 0x16362004  // SDL_PIXELFORMAT_ARGB8888
    guard let texture = SDL_CreateTexture(
        renderer, format,
        Int32(SDL_TEXTUREACCESS_STATIC.rawValue),
        Int32(width), Int32(height)
    ) else { return nil }

    _ = pixels.withUnsafeMutableBufferPointer { buf in
        SDL_UpdateTexture(texture, nil, buf.baseAddress, Int32(bytesPerRow))
    }

    SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)
    SDL_SetTextureScaleMode(texture, SDL_ScaleModeLinear)

    return texture
}

// MARK: - Manifest Queries

/// Get all remastered manifests for a given category ("units", "structures", "vfx")
func getRemasteredManifests(category: String) -> [RemasteredManifest] {
    return remasteredManifests.values
        .filter { $0.category == category }
        .sorted { $0.name < $1.name }
}

/// Get a specific remastered manifest by name
func getRemasteredManifest(name: String) -> RemasteredManifest? {
    return remasteredManifests[name.uppercased()]
}

// MARK: - Cache Management

/// Clear all remastered sprite textures (e.g., on theater change)
func clearRemasteredTextureCache() {
    for (_, texture) in renderState.remasteredTextureCache {
        SDL_DestroyTexture(texture)
    }
    renderState.remasteredTextureCache.removeAll()
}
