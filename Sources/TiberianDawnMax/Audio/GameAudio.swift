import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// MARK: - M13: Audio System
// Ported from Vanilla Conquer audio.cpp, theme.cpp
// Uses SDL2's built-in audio queue API for sound playback

// MARK: - Theme/Music Types

enum ThemeType: Int, CaseIterable {
    case none = -1
    case airstrike = 0
    case eightyMX
    case chrg
    case crep
    case dril
    case dron
    case fist
    case recon
    case voice
    case heavyG
    case j1
    case jdiV2
    case radio
    case rain
    case aoi         // Act On Instinct
    case ccthang     // C&C Thang
    case die_
    case fwp         // Fight, Win, Prevail
    case ind         // Industrial
    case ind2
    case justDoIt
    case lineFire
    case march
    case noMercy
    case otp         // On The Prowl
    case prp         // Prepare For Battle
    case rout        // Reaching Out
    case heart
    case stopThem
    case trouble
    case warfare
    case bfeared     // Enemies To Be Feared
    case iam
    case win1
    case map1
    case valkyrie

    var filename: String {
        switch self {
        case .none: return ""
        case .airstrike: return "AIRSTRIK"
        case .eightyMX: return "80MX"
        case .chrg: return "CHRG"
        case .crep: return "CREP"
        case .dril: return "DRIL"
        case .dron: return "DRON"
        case .fist: return "FIST"
        case .recon: return "RECON"
        case .voice: return "VOICE"
        case .heavyG: return "HEAVYG"
        case .j1: return "J1"
        case .jdiV2: return "JDI_V2"
        case .radio: return "RADIO"
        case .rain: return "RAIN"
        case .aoi: return "AOI"
        case .ccthang: return "CCTHANG"
        case .die_: return "DIE"
        case .fwp: return "FWP"
        case .ind: return "IND"
        case .ind2: return "IND2"
        case .justDoIt: return "JUSTDOIT"
        case .lineFire: return "LINEFIRE"
        case .march: return "MARCH"
        case .noMercy: return "NOMERCY"
        case .otp: return "OTP"
        case .prp: return "PRP"
        case .rout: return "ROUT"
        case .heart: return "HEART"
        case .stopThem: return "STOPTHEM"
        case .trouble: return "TROUBLE"
        case .warfare: return "WARFARE"
        case .bfeared: return "BFEARED"
        case .iam: return "IAM"
        case .win1: return "WIN1"
        case .map1: return "MAP1"
        case .valkyrie: return "VALKYRIE"
        }
    }

    var title: String {
        switch self {
        case .aoi: return "Act On Instinct"
        case .ccthang: return "C&C Thang"
        case .die_: return "Die!!"
        case .fwp: return "Fight, Win, Prevail"
        case .ind, .ind2: return "Industrial"
        case .justDoIt: return "Just Do It!"
        case .lineFire: return "In The Line Of Fire"
        case .march: return "March To Your Doom"
        case .noMercy: return "No Mercy"
        case .otp: return "On The Prowl"
        case .prp: return "Prepare For Battle"
        case .rout: return "Reaching Out"
        case .stopThem: return "Stop Them"
        case .trouble: return "Looks Like Trouble"
        case .warfare: return "Warfare"
        case .bfeared: return "Enemies To Be Feared"
        case .win1: return "Great Shot!"
        case .valkyrie: return "Ride of the Valkyries"
        default: return filename
        }
    }

    /// Normal gameplay themes (used for shuffle)
    var isNormal: Bool {
        switch self {
        case .aoi, .ccthang, .die_, .fwp, .ind, .ind2, .justDoIt,
             .lineFire, .march, .noMercy, .otp, .prp, .rout,
             .stopThem, .trouble, .warfare, .bfeared:
            return true
        default:
            return false
        }
    }
}

/// Result of async music loading (thread-safe handoff from background to main)
private struct MusicLoadResult {
    let theme: ThemeType
    let name: String
    let samples: [Int16]
    let sampleRate: Int
    let loaded: Bool
}

// MARK: - Audio Manager

class AudioManager: SimAudio {
    var audioDevice: SDL_AudioDeviceID = 0
    var isInitialized = false
    var masterVolume: Float = 0.8
    var sfxVolume: Float = 1.0
    /// The Sound menu's switches. Muted, the mix still runs (silently), so
    /// music and movies keep their place.
    var isMuted = false
    var effectsMuted = false
    var musicVolume: Float = 0.6  // was 0.3 — with master 0.8 that was only ~0.24 (far too quiet for the remastered masters)

    // Sound library (set after AssetManager is initialized)
    var soundLibrary: SoundLibrary?

    // Sound cache (used when soundLibrary is not available)
    var soundCache: [String: [Int16]] = [:]
    var soundSampleRates: [String: Int] = [:]

    // Music state
    var currentTheme: ThemeType = .none
    var musicSamples: [Int16] = []
    var musicSampleRate: Int = 22050
    var musicOffset: Int = 0
    var musicOffsetFrac: Double = 0  // sub-sample resample phase carried across ticks
    var isMusicPlaying: Bool = false
    var isMusicLooping: Bool = false  // Don't loop single tracks; advance playlist
    var musicEnabled: Bool = true
    var musicLoading: Bool = false  // True while async loading in progress
    var needsNextTrack: Bool = false  // Flag to advance track outside tick()

    /// Thread-safe pending music load result (set by background thread, consumed by tick)
    private var pendingMusicResult: MusicLoadResult? = nil
    private let pendingMusicLock = NSLock()

    // Playlist
    var musicPlaylist: [ThemeType] = []
    var currentTrackIndex: Int = 0

    // Active sound mixing
    var activeSounds: [ActiveSound] = []
    let maxActiveSounds = 24
    // 44100 matches the remastered music masters (44100 Hz mono), so they play
    // with NO downsampling — the old 22050 device force-decimated 44100 music
    // 2:1 with no anti-alias filter, which aliased into audible fizz/crackle on
    // bright tracks. SFX (22050) now UPSAMPLE to 44100, which is clean.
    let outputSampleRate = 44100

    // Movie soundtrack (VQA audio): interleaved mono or stereo, mixed unpanned.
    // Its play position is the movie clock (`movieClock`).
    private(set) var movieSamples: [Int16] = []
    private(set) var movieChannels = 1
    private(set) var movieSampleRate = 22050
    private(set) var moviePos: Double = 0  // source sample frames mixed so far
    private(set) var isMoviePlaying = false
    var movieVolume: Float = 1.0

    // EVA speech queue
    var speechQueue: [VoxType] = []
    var activeSpeech: ActiveSound? = nil

    struct ActiveSound {
        var samples: [Int16]
        var offset: Int
        var volume: Float
        var pan: Float  // -1.0 left, 0.0 center, 1.0 right
        var sourceSampleRate: Int
        var offsetFrac: Float = 0  // sub-sample resample phase carried across ticks
        var handle: Int = 0        // playSample's handle; 0 = none
    }

    func initialize() {
        guard !isInitialized else { return }

        // Initialize SDL audio subsystem
        if SDL_WasInit(SDL_INIT_AUDIO) == 0 {
            guard SDL_InitSubSystem(SDL_INIT_AUDIO) == 0 else {
                print("AudioManager: Failed to init SDL audio: \(String(cString: SDL_GetError()))")
                return
            }
        }

        // Open audio device with desired spec
        var desired = SDL_AudioSpec()
        desired.freq = Int32(outputSampleRate)
        desired.format = UInt16(AUDIO_S16LSB)
        desired.channels = 2  // Stereo output for spatial panning
        desired.samples = 1024
        desired.callback = nil  // We'll use SDL_QueueAudio

        var obtained = SDL_AudioSpec()
        audioDevice = SDL_OpenAudioDevice(nil, 0, &desired, &obtained, 0)

        guard audioDevice > 0 else {
            print("AudioManager: Failed to open audio device: \(String(cString: SDL_GetError()))")
            return
        }

        // Unpause the device
        SDL_PauseAudioDevice(audioDevice, 0)
        isInitialized = true
        print("AudioManager: Initialized (device: \(audioDevice), rate: \(obtained.freq)Hz)")
    }

    func shutdown() {
        if audioDevice > 0 {
            SDL_CloseAudioDevice(audioDevice)
            audioDevice = 0
        }
        isInitialized = false
        soundCache.removeAll()
    }

    // MARK: - Sound Loading

    /// Load a sound by name. Uses SoundLibrary (WAV-first) when available,
    /// otherwise falls back to direct AUD decode from MIX.
    /// Also tries VC voice variation extensions (.V00-.V03) for unit responses.
    func loadSound(_ name: String) -> Bool {
        if soundCache[name] != nil { return true }

        // Try SoundLibrary first (WAV preference)
        if let lib = soundLibrary, let audio = lib.load(name) {
            soundCache[name] = audio.samples
            soundSampleRates[name] = audio.sampleRate
            return true
        }

        // Direct AUD fallback
        let audName = "\(name).AUD"
        if let data = mixManager.retrieve(audName) {
            if let decoded = decodeAUD(Data(data)) {
                soundCache[name] = decoded.samples
                soundSampleRates[name] = decoded.sampleRate
                return true
            }
        }

        // Try VC voice variation extensions (.V00-.V03)
        // Infantry/vehicle responses in TD use .V00/.V01/.V02/.V03 instead of .AUD
        for ext in [".V00", ".V01", ".V02", ".V03"] {
            let varName = "\(name)\(ext)"
            if let data = mixManager.retrieve(varName) {
                if let decoded = decodeAUD(Data(data)) {
                    soundCache[name] = decoded.samples
                    soundSampleRates[name] = decoded.sampleRate
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Sound Playback

    /// Play a sound effect at a world position (distance attenuation + panning)
    func playSoundEffect(_ voc: VocType, worldX: Double? = nil, worldY: Double? = nil) {
        guard isInitialized && voc != .none && !effectsMuted else { return }

        let name = voc.filename
        guard !name.isEmpty else { return }

        if !loadSound(name) { return }
        guard let samples = soundCache[name], let rate = soundSampleRates[name] else { return }

        // Calculate volume and pan based on world position
        var volume = sfxVolume * masterVolume
        var pan: Float = 0.0

        if let wx = worldX, let wy = worldY {
            let spatial = calculateSpatialAudio(worldX: wx, worldY: wy)
            if spatial.volume <= 0 {
                return  // Too far away, don't play
            }
            volume *= spatial.volume
            pan = spatial.pan
        }

        // Evict oldest sound if at limit
        if activeSounds.count >= maxActiveSounds {
            activeSounds.removeFirst()
        }

        activeSounds.append(ActiveSound(
            samples: samples, offset: 0,
            volume: volume, pan: pan,
            sourceSampleRate: rate
        ))
    }

    /// Play a non-positional UI sample by file name (e.g. "BEEPY6" for
    /// BEEPY6.AUD). `volume` is the original's 0-255 Play_Sample /
    /// Normalize_Sound level.
    /// Returns a handle for isSamplePlaying / stopSample (Play_Sample's), or 0
    /// if the sample isn't available.
    @discardableResult
    func playSample(_ name: String, volume: Int = 255) -> Int {
        guard isInitialized, !effectsMuted, loadSound(name),
              let samples = soundCache[name], let rate = soundSampleRates[name] else { return 0 }
        if activeSounds.count >= maxActiveSounds { activeSounds.removeFirst() }
        nextSampleHandle += 1
        activeSounds.append(ActiveSound(samples: samples, offset: 0,
                                        volume: sfxVolume * masterVolume * Float(volume) / 255,
                                        pan: 0, sourceSampleRate: rate, handle: nextSampleHandle))
        return nextSampleHandle
    }

    private var nextSampleHandle = 0

    /// Is_Sample_Playing for a playSample handle.
    func isSamplePlaying(_ handle: Int) -> Bool {
        handle != 0 && activeSounds.contains { $0.handle == handle }
    }

    /// Stop_Sample for a playSample handle.
    func stopSample(_ handle: Int) {
        guard handle != 0 else { return }
        activeSounds.removeAll { $0.handle == handle }
    }

    /// Play EVA speech (queued, one at a time)
    func speak(_ vox: VoxType) {
        guard isInitialized && vox != .none && !effectsMuted else { return }

        let name = vox.filename
        guard !name.isEmpty else { return }

        // Check if same speech is already queued
        if speechQueue.contains(vox) { return }
        if let active = activeSpeech, active.offset < active.samples.count {
            speechQueue.append(vox)
            return
        }

        if !loadSound(name) { return }
        guard let samples = soundCache[name], let rate = soundSampleRates[name] else { return }

        activeSpeech = ActiveSound(
            samples: samples, offset: 0,
            volume: masterVolume * 0.9, pan: 0.0,
            sourceSampleRate: rate
        )
    }

    // MARK: - Music

    /// Start playing a theme track (loads asynchronously to avoid blocking UI)
    func playTheme(_ theme: ThemeType) {
        guard isInitialized && theme != .none else { return }

        let name = theme.filename
        guard !name.isEmpty else { return }

        // Stop current music while loading
        isMusicPlaying = false
        musicLoading = true
        currentTheme = theme

        // Check cache first (already decoded)
        if let samples = soundCache[name] {
            musicSamples = samples
            musicSampleRate = soundSampleRates[name] ?? outputSampleRate
            musicOffset = 0
            musicOffsetFrac = 0
            musicLoading = false
            isMusicPlaying = true
            print("AudioManager: Playing theme '\(theme.title)' (cached)")
            return
        }

        // Load asynchronously on background thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            var loaded = false
            var decodedSamples: [Int16] = []
            var sampleRate = self.outputSampleRate

            // Try SoundLibrary (WAV) first
            if let lib = self.soundLibrary, let audio = lib.load(name) {
                decodedSamples = audio.samples
                sampleRate = audio.sampleRate
                loaded = true
                print("AudioManager: Loaded '\(name)' from \(audio.source.rawValue) (\(audio.samples.count) samples, \(audio.sampleRate)Hz)")
            }

            // Try AUD from MIX
            if !loaded {
                let audName = "\(name).AUD"
                if let data = mixManager.retrieve(audName) {
                    if let decoded = decodeAUD(Data(data)) {
                        decodedSamples = decoded.samples
                        sampleRate = decoded.sampleRate
                        loaded = true
                    }
                }
            }

            // Store result for main thread pickup (no DispatchQueue.main needed)
            self.pendingMusicLock.lock()
            self.pendingMusicResult = MusicLoadResult(
                theme: theme, name: name,
                samples: decodedSamples, sampleRate: sampleRate,
                loaded: loaded
            )
            self.pendingMusicLock.unlock()
        }
    }

    /// Stop music
    func stopMusic() {
        isMusicPlaying = false
        currentTheme = .none
        musicSamples = []
        musicOffset = 0
        musicOffsetFrac = 0
    }

    /// Track how many consecutive tracks failed to load (prevent infinite skip loop)
    private var consecutiveTrackFailures: Int = 0

    /// Advance to the next track in the playlist
    func nextTrack() {
        guard musicEnabled, !musicPlaylist.isEmpty else { return }
        // Safety: if too many tracks fail in a row, stop trying
        guard consecutiveTrackFailures < musicPlaylist.count else {
            print("AudioManager: All tracks failed to load, music disabled")
            consecutiveTrackFailures = 0
            return
        }
        currentTrackIndex = (currentTrackIndex + 1) % musicPlaylist.count
        // Re-shuffle when wrapping around to the start
        if currentTrackIndex == 0 {
            shufflePlaylist()
        }
        playTheme(musicPlaylist[currentTrackIndex])
    }

    /// Toggle music on/off
    func toggleMusic() {
        musicEnabled.toggle()
        if musicEnabled {
            // Resume: play next track if we have a playlist
            if !musicPlaylist.isEmpty {
                playTheme(musicPlaylist[currentTrackIndex])
            }
            print("AudioManager: Music ON")
        } else {
            stopMusic()
            print("AudioManager: Music OFF")
        }
    }

    /// Set music volume (0.0 - 1.0)
    func setMusicVolume(_ vol: Float) {
        musicVolume = max(0.0, min(1.0, vol))
    }

    /// Build and shuffle the gameplay playlist from normal themes
    func shufflePlaylist() {
        musicPlaylist = ThemeType.allCases.filter { $0.isNormal }
        musicPlaylist.shuffle()
    }

    /// Start playing the playlist from the beginning (shuffled)
    func startPlaylist() {
        guard musicEnabled else { return }
        shufflePlaylist()
        currentTrackIndex = 0
        guard !musicPlaylist.isEmpty else { return }
        playTheme(musicPlaylist[currentTrackIndex])
    }

    /// Start playing a specific theme as menu music (loops)
    func playMenuMusic(_ theme: ThemeType = .aoi) {
        guard musicEnabled else { return }
        isMusicLooping = true
        playTheme(theme)
    }

    /// Start gameplay music (playlist, no loop on individual tracks)
    func startGameplayMusic() {
        guard musicEnabled else { return }
        isMusicLooping = false
        startPlaylist()
    }

    // MARK: - Audio Tick (called each game frame)

    /// Mix all active audio and queue to SDL
    func tick() {
        guard isInitialized else { return }

        // Check for completed async music load
        pendingMusicLock.lock()
        let result = pendingMusicResult
        pendingMusicResult = nil
        pendingMusicLock.unlock()

        if let r = result {
            if r.loaded && currentTheme == r.theme {
                soundCache[r.name] = r.samples
                soundSampleRates[r.name] = r.sampleRate
                musicSamples = r.samples
                musicSampleRate = r.sampleRate
                musicOffset = 0
                musicOffsetFrac = 0
                musicLoading = false
                isMusicPlaying = true
                consecutiveTrackFailures = 0
                let maxAmp = r.samples.prefix(min(r.samples.count, 44100)).reduce(0) { max($0, Int($1.magnitude)) }  // magnitude: abs(Int16.min) traps
                print("AudioManager: Playing theme '\(r.theme.title)' (\(r.samples.count) samples, \(r.sampleRate)Hz, peak=\(maxAmp))")
            } else {
                musicLoading = false
                if !r.loaded {
                    consecutiveTrackFailures += 1
                    print("AudioManager: Theme '\(r.name)' not found (failure \(consecutiveTrackFailures)), trying next track")
                    needsNextTrack = !musicPlaylist.isEmpty
                }
            }
        }

        // Handle deferred track advance (loaded outside the mixing loop)
        if needsNextTrack && !musicLoading {
            needsNextTrack = false
            nextTrack()
        }

        // Only queue audio when there's something to play — avoids latency buildup
        let hasAudio = !activeSounds.isEmpty || activeSpeech != nil ||
                       (isMusicPlaying && !musicSamples.isEmpty) || isMoviePlaying
        // Keep ticking even while music is loading so the queue doesn't drain
        guard hasAudio || musicLoading else { return }

        // Keep the queue fed but not overstuffed — target ~100ms of buffered audio.
        // If the queue already has enough, skip this frame to avoid latency buildup.
        let queued = SDL_GetQueuedAudioSize(audioDevice)
        let targetQueueBytes = UInt32(outputSampleRate / 5 * 4)  // ~200ms in bytes (stereo Int16 = 4 bytes/frame)
        if queued > targetQueueBytes { return }

        // Generate enough audio to cover the gap until next tick.
        // At 15 FPS game loop, we need ~67ms of audio per tick.
        // Generate ~100ms to provide headroom against frame time variation.
        let frameCount = outputSampleRate / 10  // number of stereo frames
        let stereoSampleCount = frameCount * 2  // interleaved L/R samples
        var mixBuffer = [Float](repeating: 0.0, count: stereoSampleCount)

        // Mix active sound effects (stereo with panning)
        var completedIndices = [Int]()
        for (i, _) in activeSounds.enumerated() {
            mixSoundInto(&mixBuffer, frameCount: frameCount, sound: &activeSounds[i])
            if activeSounds[i].offset >= activeSounds[i].samples.count {
                completedIndices.append(i)
            }
        }
        for i in completedIndices.reversed() {
            activeSounds.remove(at: i)
        }

        // Mix EVA speech (center-panned, pan=0)
        if var speech = activeSpeech {
            mixSoundInto(&mixBuffer, frameCount: frameCount, sound: &speech)
            activeSpeech = speech
            if speech.offset >= speech.samples.count {
                activeSpeech = nil
                // Start next queued speech
                if !speechQueue.isEmpty {
                    let nextVox = speechQueue.removeFirst()
                    speak(nextVox)
                }
            }
        }

        // Mix music (center-panned, with proper resampling for sample rate differences)
        if isMusicPlaying && !musicSamples.isEmpty {
            let musicVol = musicVolume * masterVolume
            let ratio = Double(musicSampleRate) / Double(outputSampleRate)
            // Carry the fractional source position across ticks. Truncating it
            // (the old `Int(srcPos)`) dropped up to ~1 sample of phase every
            // 100ms tick, clicking on any non-integer ratio (e.g. 22050 source
            // upsampled to a 44100 device).
            var srcPos = Double(musicOffset) + musicOffsetFrac

            for i in 0..<frameCount {
                let srcIdx = Int(srcPos)
                if srcIdx < musicSamples.count {
                    // Linear interpolation for smoother resampling
                    let frac = Float(srcPos - Double(srcIdx))
                    let s0 = Float(musicSamples[srcIdx])
                    let s1 = srcIdx + 1 < musicSamples.count ? Float(musicSamples[srcIdx + 1]) : s0
                    let sample = (s0 + (s1 - s0) * frac) * musicVol
                    mixBuffer[i * 2] += sample      // Left
                    mixBuffer[i * 2 + 1] += sample  // Right
                    srcPos += ratio
                } else if isMusicLooping {
                    srcPos = 0
                } else {
                    isMusicPlaying = false
                    // Flag for next track — don't load synchronously inside tick()
                    needsNextTrack = !musicPlaylist.isEmpty
                    break
                }
            }
            musicOffset = Int(srcPos)
            musicOffsetFrac = srcPos - Double(musicOffset)
        }

        if isMoviePlaying {
            mixMovieInto(&mixBuffer, frameCount: frameCount)
        }

        // Convert to Int16 interleaved stereo and queue
        var output = [Int16](repeating: 0, count: stereoSampleCount)
        for i in 0..<stereoSampleCount {
            let clamped = isMuted ? 0 : max(-32767.0, min(32767.0, mixBuffer[i]))
            output[i] = Int16(clamped)
        }

        _ = output.withUnsafeBufferPointer { buf in
            SDL_QueueAudio(audioDevice, buf.baseAddress, UInt32(stereoSampleCount * 2))
        }
    }

    // MARK: - Movie Soundtrack

    /// Start a movie's soundtrack. Music stops, as in Play_Movie
    /// (`Theme.Queue_Song(THEME_NONE)`, CONQUER.CPP); the screen after the
    /// movie restarts whatever music it wants. Anything still queued from
    /// before is dropped so the movie clock starts at zero.
    func startMovieAudio(samples: [Int16], channels: Int, sampleRate: Int) {
        stopMusic()
        if audioDevice > 0 { SDL_ClearQueuedAudio(audioDevice) }
        movieSamples = samples
        movieChannels = max(1, channels)
        movieSampleRate = max(1, sampleRate)
        moviePos = 0
        isMoviePlaying = isInitialized && !samples.isEmpty
    }

    func stopMovieAudio() {
        guard isMoviePlaying || !movieSamples.isEmpty else { return }
        isMoviePlaying = false
        movieSamples = []
        moviePos = 0
        if audioDevice > 0 { SDL_ClearQueuedAudio(audioDevice) }
    }

    /// Seconds of the movie soundtrack the listener has actually heard: what
    /// has been mixed minus what is still waiting in the device queue. Nil
    /// when no soundtrack is playing (the player then falls back to a wall
    /// clock). Mirrors Westwood's player timing frames off the audio
    /// position (VQA_SelectFrame).
    var movieClock: Double? {
        guard isMoviePlaying || (!movieSamples.isEmpty && audioDevice > 0) else { return nil }
        let queuedSeconds = Double(SDL_GetQueuedAudioSize(audioDevice)) / Double(outputSampleRate * 4)
        return max(0, moviePos / Double(movieSampleRate) - queuedSeconds)
    }

    /// Length of the loaded soundtrack in seconds.
    var movieDuration: Double {
        Double(movieSamples.count / movieChannels) / Double(movieSampleRate)
    }

    private func mixMovieInto(_ buffer: inout [Float], frameCount: Int) {
        let vol = movieVolume * masterVolume
        let ratio = Double(movieSampleRate) / Double(outputSampleRate)
        let total = movieSamples.count / movieChannels
        let ch = movieChannels
        movieSamples.withUnsafeBufferPointer { src in
            for i in 0..<frameCount {
                let idx = Int(moviePos)
                guard idx < total else { isMoviePlaying = false; break }
                let frac = Float(moviePos - Double(idx))
                let next = min(idx + 1, total - 1)
                let l0 = Float(src[idx * ch]), l1 = Float(src[next * ch])
                let r0 = Float(src[idx * ch + ch - 1]), r1 = Float(src[next * ch + ch - 1])
                buffer[i * 2] += (l0 + (l1 - l0) * frac) * vol
                buffer[i * 2 + 1] += (r0 + (r1 - r0) * frac) * vol
                moviePos += ratio
            }
        }
    }

    // MARK: - Convenience Methods

    /// Play a sound effect (convenience alias for playSoundEffect)
    func play(_ voc: VocType, worldX: Double? = nil, worldY: Double? = nil) {
        playSoundEffect(voc, worldX: worldX, worldY: worldY)
    }

    /// Get a unit acknowledgment sound
    func unitAcknowledgeSound() -> VocType {
        let acks: [VocType] = [.acknowl, .affirm, .moveout, .noProb, .ready, .roger, .ugotit, .yessir]
        return acks[Int.random(in: 0..<acks.count)]
    }

    /// Get a unit report sound
    func unitReportSound() -> VocType {
        let reports: [VocType] = [.await_, .report, .unit_, .vehic, .yessir]
        return reports[Int.random(in: 0..<reports.count)]
    }

    // MARK: - Sound Spatialization

    /// Calculate volume attenuation and stereo pan for a world-position sound.
    /// Returns volume (0.0–1.0) and pan (-1.0 left .. +1.0 right, capped at ±0.25).
    private func calculateSpatialAudio(worldX: Double, worldY: Double) -> (volume: Float, pan: Float) {
        let zoom = max(1.0, renderState.gameZoomLevel)
        let viewportW = Double(renderState.windowWidth - sidebarWidth) / zoom
        let viewportH = Double(renderState.windowHeight) / zoom
        let camCenterX = renderState.gameCameraX + viewportW / 2.0
        let camCenterY = renderState.gameCameraY + viewportH / 2.0

        let dx = worldX - camCenterX
        let dy = worldY - camCenterY

        // Check if the sound source is within the visible viewport (full volume)
        let halfW = viewportW / 2.0
        let halfH = viewportH / 2.0
        let edgeDistX = max(0.0, abs(dx) - halfW)
        let edgeDistY = max(0.0, abs(dy) - halfH)
        let edgeDist = sqrt(edgeDistX * edgeDistX + edgeDistY * edgeDistY)

        // Linear falloff from viewport edge to ~360px (15 cells * 24px) beyond
        let falloffRange: Double = 360.0
        var volume: Float = 1.0
        if edgeDist > falloffRange {
            return (volume: 0.0, pan: 0.0)  // Beyond max hearing distance
        } else if edgeDist > 0 {
            volume = Float(1.0 - edgeDist / falloffRange)
        }

        // Stereo panning: map horizontal offset to ±0.25 max (subtle)
        var pan: Float = 0.0
        if halfW > 0 {
            pan = Float(dx / halfW) * 0.25
            pan = max(-0.25, min(0.25, pan))
        }

        return (volume: volume, pan: pan)
    }

    /// Mix a single sound into the stereo output buffer with resampling and panning.
    /// Buffer is interleaved stereo: [L0, R0, L1, R1, ...] with `frameCount` frames.
    private func mixSoundInto(_ buffer: inout [Float], frameCount: Int, sound: inout ActiveSound) {
        let vol = sound.volume
        // Convert pan (-1..+1) to left/right gain using constant-power-ish linear pan
        // pan = 0 -> both 1.0; pan = -0.25 -> left louder; pan = +0.25 -> right louder
        let leftGain = vol * min(1.0, 1.0 - sound.pan)
        let rightGain = vol * min(1.0, 1.0 + sound.pan)

        // Fast path: same sample rate (most sounds are 22050Hz = outputSampleRate)
        if sound.sourceSampleRate == outputSampleRate {
            let remaining = sound.samples.count - sound.offset
            let count = min(frameCount, remaining)
            for i in 0..<count {
                let sample = Float(sound.samples[sound.offset + i])
                buffer[i * 2] += sample * leftGain
                buffer[i * 2 + 1] += sample * rightGain
            }
            sound.offset += count
            return
        }

        // Resampling path: use Double for precision, carrying the sub-sample
        // phase across ticks so upsampling (e.g. 22050 SFX → 44100 device) has
        // no periodic click from truncating the fractional position.
        let ratio = Double(sound.sourceSampleRate) / Double(outputSampleRate)
        var srcPos = Double(sound.offset) + Double(sound.offsetFrac)

        for i in 0..<frameCount {
            let srcIdx = Int(srcPos)
            if srcIdx >= sound.samples.count {
                sound.offset = sound.samples.count
                return
            }

            // Linear interpolation between adjacent samples for smoother output
            let frac = Float(srcPos - Double(srcIdx))
            let s0 = Float(sound.samples[srcIdx])
            let s1 = srcIdx + 1 < sound.samples.count ? Float(sound.samples[srcIdx + 1]) : s0
            let sample = (s0 + (s1 - s0) * frac)
            buffer[i * 2] += sample * leftGain
            buffer[i * 2 + 1] += sample * rightGain

            srcPos += ratio
        }

        sound.offset = Int(srcPos)
        sound.offsetFrac = Float(srcPos - Double(sound.offset))
    }
}

// MARK: - Global Audio Instance

let gameAudio = AudioManager()

