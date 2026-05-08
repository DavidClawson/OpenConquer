import CSDL2
import Foundation

// MARK: - RenderState Sub-Containers

/// Texture and SHP caches for tiles, terrain, objects, and remastered sprites.
class TextureCaches {
    // Tile / ICN
    var icnCache: [String: ICNFile] = [:]
    var tileTextureCache: [String: OpaquePointer] = [:]
    var mapFailedICNs: Set<String> = []

    // Terrain SHP
    var terrainSHPCache: [String: SHPFile] = [:]
    var terrainTextureCache: [String: OpaquePointer] = [:]
    var terrainFailedSHPs: Set<String> = []

    // Object SHP
    var objectSHPCache: [String: SHPFile] = [:]
    var objectTextureCache: [String: OpaquePointer] = [:]
    var objectFailedSHPs: Set<String> = []

    // Remastered
    var remasteredTextureCache: [String: OpaquePointer] = [:]
    var hasRemasteredSprites: Bool = false
}

/// UI sprite assets: selection box, pips, mouse cursor.
class UISprites {
    var selectSHP: SHPFile? = nil
    var selectTextures: [Int: OpaquePointer] = [:]
    var pipsSHP: SHPFile? = nil
    var pipsTextures: [Int: OpaquePointer] = [:]
    var mouseSHP: SHPFile? = nil
    var mouseTextures: [Int: OpaquePointer] = [:]
    var isLoaded: Bool = false
}

// MARK: - RenderState

/// Consolidates all rendering-related global variables into one object.
class RenderState {
    // MARK: - Window
    var windowWidth: Int32 = 1920
    var windowHeight: Int32 = 1200
    var displayScale: Double = 1.0  // HiDPI scale factor (2.0 on Retina)
    var sdlRenderer: OpaquePointer? = nil  // SDL_Renderer* for logical size updates

    // MARK: - Palette
    var gamePalette: [(r: UInt8, g: UInt8, b: UInt8)] = []

    // MARK: - Sub-Containers
    var caches = TextureCaches()
    var uiSprites = UISprites()

    // MARK: - Game Camera (playing mode)
    var gameCameraX: Double = 0.0
    var gameCameraY: Double = 0.0
    var gameZoomLevel: Double = 1.0

    // MARK: - Map Viewer Camera
    var cameraX: Int = 0
    var cameraY: Int = 0
    var zoomLevel: Double = 1.0

    // MARK: - Cursor State
    var cursorAnimFrame: Int = 0
    var cursorAnimTimer: UInt32 = 0
    var systemCursorHidden: Bool = false

    // MARK: - Animation Frame Counter
    var animationFrame: Int = 0

    // MARK: - Screen Effects
    var screenFlashAlpha: UInt8 = 0       // Full-screen white flash (fades each frame)
    var screenFlashR: UInt8 = 255
    var screenFlashG: UInt8 = 255
    var screenFlashB: UInt8 = 255
    var screenShakeOffsetX: Int32 = 0     // Camera shake offset (pixels)
    var screenShakeOffsetY: Int32 = 0
    var screenShakeDuration: Int = 0      // Remaining shake ticks
    var screenShakeIntensity: Double = 0  // Max offset in pixels

    // Ion cannon beam effect
    var ionBeamWorldX: Double = 0         // Target world position
    var ionBeamWorldY: Double = 0
    var ionBeamTimer: Int = 0             // Remaining ticks for beam visual (0 = inactive)

    // MARK: - Debug Overlay Flags
    var showGrid: Bool = false
    var showInfoPanel: Bool = false
    var showCellTriggers: Bool = false
    var showBaseList: Bool = false
    var perfShowOverlay: Bool = false

    // MARK: - Sprite Viewer State
    var spriteViewerIndex: Int = 0
    var spriteViewerFrame: Int = 0
    var currentSHP: SHPFile? = nil
    var spriteViewerAnimating: Bool = true
    var spriteViewerFrameTimer: UInt32 = 0

    // MARK: - Forwarding Properties (caches)

    var icnCache: [String: ICNFile] {
        get { caches.icnCache }
        set { caches.icnCache = newValue }
    }
    var tileTextureCache: [String: OpaquePointer] {
        get { caches.tileTextureCache }
        set { caches.tileTextureCache = newValue }
    }
    var mapFailedICNs: Set<String> {
        get { caches.mapFailedICNs }
        set { caches.mapFailedICNs = newValue }
    }
    var terrainSHPCache: [String: SHPFile] {
        get { caches.terrainSHPCache }
        set { caches.terrainSHPCache = newValue }
    }
    var terrainTextureCache: [String: OpaquePointer] {
        get { caches.terrainTextureCache }
        set { caches.terrainTextureCache = newValue }
    }
    var terrainFailedSHPs: Set<String> {
        get { caches.terrainFailedSHPs }
        set { caches.terrainFailedSHPs = newValue }
    }
    var objectSHPCache: [String: SHPFile] {
        get { caches.objectSHPCache }
        set { caches.objectSHPCache = newValue }
    }
    var objectTextureCache: [String: OpaquePointer] {
        get { caches.objectTextureCache }
        set { caches.objectTextureCache = newValue }
    }
    var objectFailedSHPs: Set<String> {
        get { caches.objectFailedSHPs }
        set { caches.objectFailedSHPs = newValue }
    }
    var remasteredTextureCache: [String: OpaquePointer] {
        get { caches.remasteredTextureCache }
        set { caches.remasteredTextureCache = newValue }
    }
    var hasRemasteredSprites: Bool {
        get { caches.hasRemasteredSprites }
        set { caches.hasRemasteredSprites = newValue }
    }

    // MARK: - Forwarding Properties (uiSprites)

    var selectSHP: SHPFile? {
        get { uiSprites.selectSHP }
        set { uiSprites.selectSHP = newValue }
    }
    var selectTextures: [Int: OpaquePointer] {
        get { uiSprites.selectTextures }
        set { uiSprites.selectTextures = newValue }
    }
    var pipsSHP: SHPFile? {
        get { uiSprites.pipsSHP }
        set { uiSprites.pipsSHP = newValue }
    }
    var pipsTextures: [Int: OpaquePointer] {
        get { uiSprites.pipsTextures }
        set { uiSprites.pipsTextures = newValue }
    }
    var mouseSHP: SHPFile? {
        get { uiSprites.mouseSHP }
        set { uiSprites.mouseSHP = newValue }
    }
    var mouseTextures: [Int: OpaquePointer] {
        get { uiSprites.mouseTextures }
        set { uiSprites.mouseTextures = newValue }
    }
    var uiSpritesLoaded: Bool {
        get { uiSprites.isLoaded }
        set { uiSprites.isLoaded = newValue }
    }
}

var renderState = RenderState()
