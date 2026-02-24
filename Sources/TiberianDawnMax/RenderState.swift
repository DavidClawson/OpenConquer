import CSDL2
import Foundation

// MARK: - RenderState
// Consolidates all rendering-related global variables into one object.

class RenderState {
    // MARK: - Window
    var windowWidth: Int32 = 960
    var windowHeight: Int32 = 600

    // MARK: - Palette
    var gamePalette: [(r: UInt8, g: UInt8, b: UInt8)] = []

    // MARK: - Game Camera (playing mode)
    var gameCameraX: Double = 0.0
    var gameCameraY: Double = 0.0
    var gameZoomLevel: Double = 1.0

    // MARK: - Map Viewer Camera
    var cameraX: Int = 0
    var cameraY: Int = 0
    var zoomLevel: Double = 1.0

    // MARK: - Tile / ICN Caches
    var icnCache: [String: ICNFile] = [:]
    var tileTextureCache: [String: OpaquePointer] = [:]
    var mapFailedICNs: Set<String> = []

    // MARK: - Terrain SHP Caches
    var terrainSHPCache: [String: SHPFile] = [:]
    var terrainTextureCache: [String: OpaquePointer] = [:]
    var terrainFailedSHPs: Set<String> = []

    // MARK: - Object SHP Caches
    var objectSHPCache: [String: SHPFile] = [:]
    var objectTextureCache: [String: OpaquePointer] = [:]
    var objectFailedSHPs: Set<String> = []

    // MARK: - UI Sprite Caches
    var selectSHP: SHPFile? = nil
    var selectTextures: [Int: OpaquePointer] = [:]
    var pipsSHP: SHPFile? = nil
    var pipsTextures: [Int: OpaquePointer] = [:]
    var mouseSHP: SHPFile? = nil
    var mouseTextures: [Int: OpaquePointer] = [:]
    var uiSpritesLoaded: Bool = false

    // MARK: - Cursor State
    var cursorAnimFrame: Int = 0
    var cursorAnimTimer: UInt32 = 0
    var systemCursorHidden: Bool = false

    // MARK: - Remastered Sprites
    var remasteredTextureCache: [String: OpaquePointer] = [:]
    var hasRemasteredSprites: Bool = false

    // MARK: - Animation Frame Counter
    var animationFrame: Int = 0

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
}

var renderState = RenderState()
