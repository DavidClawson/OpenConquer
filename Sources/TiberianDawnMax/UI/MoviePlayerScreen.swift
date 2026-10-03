import CSDL2
import Foundation
import OpenConquerAssets

// MARK: - Movie Player Screen
//
// Plays a sequence of VQA movies (Play_Movie, CONQUER.CPP:2306), then hands
// off to `completion`. Frames are timed off the soundtrack's play position,
// like Westwood's player (VQA_SelectFrame); a silent movie falls back to the
// wall clock. Any key or a click skips the current movie; Esc skips the rest.
// The 320x200 frame is shown at 4:3 (pixels 1.2x tall), as on a 1995 monitor.

final class MoviePlayerScreen: MenuScreen {
    private var queue: [String]
    private let completion: () -> Void
    private var finished = false

    private var decoder: VQADecoder?
    private var texture: OpaquePointer?
    private var textureSize = (w: 0, h: 0)
    private var shownFrame = -1
    private var videoDone = false
    private var audioDuration: Double = 0
    private var wallStart: UInt64 = 0
    private var currentName = ""
    private var enhancer: MovieFrameEnhancer?

    /// Play `names` (those that exist, if movies are enabled), then call
    /// `completion`. Calls it straight away when there is nothing to play.
    static func play(_ names: [String], then completion: @escaping () -> Void) {
        let playable = UserSettings.movieMode == .off ? [] : names.filter(movieExists)
        if playable.isEmpty {
            completion()
        } else {
            app.currentScreen = MoviePlayerScreen(movies: playable, then: completion)
        }
    }

    static func movieExists(_ name: String) -> Bool {
        mixManager.contains("\(name.uppercased()).VQA")
    }

    private init(movies: [String], then completion: @escaping () -> Void) {
        self.queue = movies
        self.completion = completion
    }

    deinit {
        if let texture { SDL_DestroyTexture(texture) }
    }

    // MARK: Playback

    /// Load the next movie in the queue; false when the queue is empty.
    private func startNext() -> Bool {
        decoder = nil
        while !queue.isEmpty {
            let name = queue.removeFirst().uppercased()
            guard let data = mixManager.retrieve("\(name).VQA"),
                  let dec = VQADecoder(data: data) else {
                print("Movie: \(name).VQA missing or unreadable — skipped")
                continue
            }
            decoder = dec
            currentName = name
            shownFrame = -1
            videoDone = false
            wallStart = SDL_GetPerformanceCounter()
            if let track = VQADecoder.decodeAudioTrack(data: data) {
                gameAudio.startMovieAudio(samples: track.samples, channels: track.channels,
                                          sampleRate: track.sampleRate)
                audioDuration = track.duration
            } else {
                gameAudio.stopMovieAudio()
                audioDuration = 0
            }
            enhancer = UserSettings.movieMode == .enhanced
                ? makeMovieFrameEnhancer(width: dec.width, height: dec.height) : nil
            return true
        }
        return false
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        gameAudio.stopMovieAudio()
        completion()
    }

    private func skipCurrent() {
        gameAudio.stopMovieAudio()
        decoder = nil
        if !startNext() { finish() }
    }

    /// Seconds since this movie started, on the audio clock when there is one.
    private var clock: Double {
        if audioDuration > 0, let t = gameAudio.movieClock { return t }
        let ticks = SDL_GetPerformanceCounter() - wallStart
        return Double(ticks) / Double(SDL_GetPerformanceFrequency())
    }

    func render(_ renderer: OpaquePointer?) {
        if finished { return }
        if decoder == nil && !startNext() { finish(); return }
        guard let dec = decoder else { return }

        // Decode up to the frame that is due; only the newest one is shown.
        let due = Int(clock * Double(dec.frameRate))
        var latest: VQAFrame?
        while !videoDone && shownFrame < due {
            if let f = dec.nextFrame() {
                latest = f
                shownFrame += 1
            } else {
                videoDone = true
            }
        }
        if let latest { upload(latest, renderer) }

        if let texture {
            // 4:3 frame: width × (height × 1.2), letterboxed in the window.
            let srcW = Double(dec.width), srcH = Double(dec.height) * 1.2
            let ww = Double(renderState.windowWidth), wh = Double(renderState.windowHeight)
            let scale = min(ww / srcW, wh / srcH)
            let w = srcW * scale, h = srcH * scale
            var dst = SDL_Rect(x: Int32((ww - w) / 2), y: Int32((wh - h) / 2), w: Int32(w), h: Int32(h))
            SDL_RenderCopy(renderer, texture, nil, &dst)
        }

        // Done once the picture has run out and the soundtrack has played out
        // (the audio runs ~0.5 s past the last frame: the pre-roll chunk).
        if videoDone && (audioDuration == 0 || clock >= audioDuration) {
            if !startNext() { finish() }
        }
    }

    private func upload(_ frame: VQAFrame, _ renderer: OpaquePointer?) {
        if let enhancer, let out = enhancer.enhance(frame) {
            uploadBGRA(out, renderer)
            return
        }
        // RGBA bytes → SDL_PIXELFORMAT_ABGR8888 (byte order R,G,B,A on little-endian).
        ensureTexture(width: frame.width, height: frame.height, format: 0x16762004, renderer)
        let rgba = frame.rgba()
        rgba.withUnsafeBytes { buf in
            _ = SDL_UpdateTexture(texture, nil, buf.baseAddress, Int32(frame.width * 4))
        }
    }

    private func uploadBGRA(_ frame: EnhancedFrame, _ renderer: OpaquePointer?) {
        // BGRA bytes → SDL_PIXELFORMAT_ARGB8888 on little-endian.
        ensureTexture(width: frame.width, height: frame.height, format: 0x16362004, renderer)
        frame.pixels.withUnsafeBytes { buf in
            _ = SDL_UpdateTexture(texture, nil, buf.baseAddress, Int32(frame.bytesPerRow))
        }
    }

    private func ensureTexture(width: Int, height: Int, format: UInt32, _ renderer: OpaquePointer?) {
        var curFormat: UInt32 = 0
        if let texture { SDL_QueryTexture(texture, &curFormat, nil, nil, nil) }
        if texture == nil || textureSize.w != width || textureSize.h != height || curFormat != format {
            if let texture { SDL_DestroyTexture(texture) }
            texture = SDL_CreateTexture(renderer, format, Int32(SDL_TEXTUREACCESS_STREAMING.rawValue),
                                        Int32(width), Int32(height))
            textureSize = (width, height)
        }
        SDL_SetTextureScaleMode(texture, UserSettings.movieMode == .pixels ? SDL_ScaleModeNearest
                                                                           : SDL_ScaleModeLinear)
    }

    // MARK: Input

    func handleKeyDown(_ key: Int32) {
        if key == Int32(SDLK_ESCAPE.rawValue) {
            queue.removeAll()
            gameAudio.stopMovieAudio()
            finish()
        } else {
            skipCurrent()
        }
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        skipCurrent()
    }
}
