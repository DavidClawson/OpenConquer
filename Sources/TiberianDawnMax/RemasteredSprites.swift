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
var remasteredTextureCache: [String: OpaquePointer] = [:]

/// Scale factor: remastered uses 128px tiles, classic uses 24px tiles.
/// At zoom 1.0 this maps remastered sprites to classic-compatible sizes.
/// The hi-res textures are preserved at full resolution — as you zoom in,
/// you see the extra detail. On Retina displays, the 2x pixel density
/// also benefits from the higher source resolution.
let remasteredScale: Double = 24.0 / 128.0

/// Whether remastered sprites are available
var hasRemasteredSprites: Bool = false

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
        hasRemasteredSprites = false
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

    hasRemasteredSprites = totalFound > 0
    if hasRemasteredSprites {
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

// MARK: - Texture Loading

/// Try to load a remastered sprite texture for the given type and frame.
/// Returns (texture, displayWidth, displayHeight) where display dimensions
/// are scaled to match the classic 24px tile grid.
func getRemasteredTexture(_ renderer: OpaquePointer?, typeName: String, frame: Int)
    -> (texture: OpaquePointer, width: Int, height: Int)? {

    guard hasRemasteredSprites else { return nil }

    let upperName = typeName.uppercased()
    let key = "RM_\(upperName)_\(frame)"

    // Check texture cache
    if let cached = remasteredTextureCache[key] {
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

    remasteredTextureCache[key] = texture

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

// MARK: - Cache Management

/// Clear all remastered sprite textures (e.g., on theater change)
func clearRemasteredTextureCache() {
    for (_, texture) in remasteredTextureCache {
        SDL_DestroyTexture(texture)
    }
    remasteredTextureCache.removeAll()
}
