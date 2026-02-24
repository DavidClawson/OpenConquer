import CSDL2
import Foundation

// MARK: - Performance Monitor
// Tracks frame timing, FPS, and per-system costs.
// Toggle overlay with F3.


struct PerfMonitor {
    // Frame timing
    private var frameStart: UInt64 = 0
    private var frameTimesUs: [UInt64] = []  // last N frame times in microseconds
    private let maxSamples = 120

    // Per-system timing (current frame)
    private var sectionStart: UInt64 = 0
    var sections: [(name: String, us: UInt64)] = []

    // FPS tracking
    private var fpsFrameCount: Int = 0
    private var fpsLastTime: UInt32 = 0
    private(set) var currentFPS: Int = 0

    // Stats
    private(set) var avgFrameTimeMs: Double = 0
    private(set) var maxFrameTimeMs: Double = 0
    private(set) var minFrameTimeMs: Double = 0

    // SDL high-perf counter frequency
    private let perfFreq: UInt64

    init() {
        perfFreq = SDL_GetPerformanceFrequency()
    }

    // MARK: - Frame Lifecycle

    mutating func beginFrame() {
        frameStart = SDL_GetPerformanceCounter()
        sections.removeAll(keepingCapacity: true)

        // FPS counter
        let now = SDL_GetTicks()
        fpsFrameCount += 1
        if fpsLastTime == 0 { fpsLastTime = now }
        let elapsed = now - fpsLastTime
        if elapsed >= 1000 {
            currentFPS = fpsFrameCount
            fpsFrameCount = 0
            fpsLastTime = now
        }
    }

    mutating func endFrame() {
        let end = SDL_GetPerformanceCounter()
        let frameUs = (end - frameStart) * 1_000_000 / perfFreq

        frameTimesUs.append(frameUs)
        if frameTimesUs.count > maxSamples {
            frameTimesUs.removeFirst(frameTimesUs.count - maxSamples)
        }

        // Update stats
        if !frameTimesUs.isEmpty {
            let sum = frameTimesUs.reduce(0, +)
            avgFrameTimeMs = Double(sum) / Double(frameTimesUs.count) / 1000.0
            maxFrameTimeMs = Double(frameTimesUs.max() ?? 0) / 1000.0
            minFrameTimeMs = Double(frameTimesUs.min() ?? 0) / 1000.0
        }
    }

    // MARK: - Section Timing

    mutating func beginSection(_ name: String) {
        sectionStart = SDL_GetPerformanceCounter()
    }

    mutating func endSection(_ name: String) {
        let end = SDL_GetPerformanceCounter()
        let us = (end - sectionStart) * 1_000_000 / perfFreq
        sections.append((name: name, us: us))
    }

    // MARK: - Render Overlay

    func renderOverlay(_ renderer: OpaquePointer?) {
        guard renderState.perfShowOverlay else { return }

        // Reset scale to 1:1 for UI overlay
        SDL_RenderSetScale(renderer, 1.0, 1.0)
        SDL_RenderSetClipRect(renderer, nil)

        // Background panel
        let panelW: Int32 = 220
        let lineH: Int32 = 14
        let lines = Int32(4 + sections.count)
        let panelH: Int32 = lines * lineH + 10
        let px: Int32 = renderState.windowWidth - panelW - 5
        let py: Int32 = 5

        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 200)
        var bg = SDL_Rect(x: px, y: py, w: panelW, h: panelH)
        SDL_RenderFillRect(renderer, &bg)
        SDL_SetRenderDrawColor(renderer, 0, 80, 0, 255)
        SDL_RenderDrawRect(renderer, &bg)

        var y = py + 5

        // FPS line
        let fpsColor: Color = currentFPS >= 55 ? .brightGreen : (currentFPS >= 30 ? .amber : .red)
        drawTextLeft(renderer, "FPS: \(currentFPS)", x: px + 5, y: y, color: fpsColor, scale: 1)
        y += lineH

        // Frame time
        let avgStr = String(format: "%.1f", avgFrameTimeMs)
        let maxStr = String(format: "%.1f", maxFrameTimeMs)
        drawTextLeft(renderer, "Frame: \(avgStr)ms avg  \(maxStr)ms max", x: px + 5, y: y, color: .green, scale: 1)
        y += lineH

        // Window size + sprite mode
        let spriteMode = renderState.hasRemasteredSprites ? "  HD Sprites" : ""
        drawTextLeft(renderer, "Window: \(renderState.windowWidth)x\(renderState.windowHeight)\(spriteMode)", x: px + 5, y: y, color: .green, scale: 1)
        y += lineH

        // Separator
        y += 3

        // Per-section breakdown
        for section in sections {
            let ms = String(format: "%.2f", Double(section.us) / 1000.0)
            let barLen = min(100, Int(section.us / 100))  // 1px per 0.1ms
            drawTextLeft(renderer, "\(section.name): \(ms)ms", x: px + 5, y: y, color: .green, scale: 1)

            // Mini bar graph
            if barLen > 0 {
                SDL_SetRenderDrawColor(renderer, 0, 150, 0, 200)
                var bar = SDL_Rect(x: px + 160, y: y + 2, w: Int32(barLen), h: 8)
                SDL_RenderFillRect(renderer, &bar)
            }
            y += lineH
        }

        // Active entity counts
        let projCount = session.activeProjectiles.count
        let animCount = session.activeAnimations.count
        if projCount > 0 || animCount > 0 {
            drawTextLeft(renderer, "Active: \(projCount) proj  \(animCount) anim", x: px + 5, y: y, color: .gray, scale: 1)
            y += lineH
        }

        // Memory indicator: texture cache sizes
        let rmCount = renderState.remasteredTextureCache.count
        let cacheInfo = rmCount > 0
            ? "Cache: \(renderState.objectTextureCache.count) obj  \(renderState.tileTextureCache.count) tile  \(rmCount) HD"
            : "Cache: \(renderState.objectTextureCache.count) obj  \(renderState.tileTextureCache.count) tile"
        drawTextLeft(renderer, cacheInfo, x: px + 5, y: y, color: .gray, scale: 1)
    }
}

var perf = PerfMonitor()
