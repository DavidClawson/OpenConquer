import CSDL2
import Foundation

// MARK: - M13: Audio System
// Ported from Vanilla Conquer audio.cpp, theme.cpp
// Uses SDL2's built-in audio queue API for sound playback

// MARK: - Sound Effect Types (VOC)

enum VocType: Int, CaseIterable {
    case none = -1

    // Commando/Rambo responses
    case ramboPresent = 0
    case ramboCmon
    case ramboUgotit
    case ramboComin
    case ramboLaugh
    case ramboLefty
    case ramboNoprob
    case ramboOnit
    case ramboYell
    case ramboRock
    case ramboTuff
    case ramboYea
    case ramboYes
    case ramboYo

    // Civilian
    case girlOkay
    case girlYeah
    case guyOkay
    case guyYeah

    // Unit responses
    case danger
    case acknowl
    case affirm
    case await_
    case moveout
    case negative
    case noProb
    case ready
    case report
    case rightAway
    case roger
    case ugotit
    case unit_
    case vehic
    case yessir

    // Weapon sounds
    case bazooka
    case bleep
    case bomb1
    case button
    case radarOn
    case construction
    case crumble
    case flamer1
    case rifle
    case m60
    case gun20
    case m60a
    case mini
    case reload
    case slam
    case hvygun10
    case ionCannon
    case mgun11
    case mgun2
    case nukeFire
    case nukeExplode
    case laser
    case laserPower
    case radarOff
    case sniper
    case rocket1
    case rocket2
    case motor
    case scold
    case sidebarOpen
    case sidebarClose
    case squish2
    case tank1
    case tank2
    case tank3
    case tank4
    case up
    case down
    case target
    case sonar
    case toss
    case cloak
    case burn
    case turret
    case xplobig4
    case xplobig6
    case xplobig7
    case xplode
    case xplos
    case xplosml2

    // Infantry screams
    case scream1
    case scream3
    case scream4
    case scream5
    case scream6
    case scream7
    case scream10
    case scream11
    case scream12
    case yell1

    // EVA/Advisor
    case yes_
    case commander
    case hello
    case hmmm

    // Special
    case cashturn
    case beacon

    /// Filename (without extension) used to look up the AUD file in MIX archives
    var filename: String {
        switch self {
        case .none: return ""
        case .ramboPresent: return "BOMBIT1" // VC TD commando — "I've got a present for ya"
        case .ramboCmon: return "CMON1"
        case .ramboUgotit: return "GOTIT1" // commando "you got it" (distinct from unit UGOTIT)
        case .ramboComin: return "KEEPEM1" // "keep 'em comin'"
        case .ramboLaugh: return "LAUGH1"
        case .ramboLefty: return "LEFTY1"
        case .ramboNoprob: return "NOPRBLM1"
        case .ramboOnit: return "ONIT1"
        case .ramboYell: return "RAMYELL1"
        case .ramboRock: return "ROKROLL1"
        case .ramboTuff: return "TUFFGUY1"
        case .ramboYea: return "YEAH1"
        case .ramboYes: return "YES1"
        case .ramboYo: return "YO1"
        case .girlOkay: return "GIRLOKAY"
        case .girlYeah: return "GIRLYEAH"
        case .guyOkay: return "GUYOKAY1"
        case .guyYeah: return "GUYYEAH1"
        case .danger: return "2DANGR1"
        case .acknowl: return "ACKNO"
        case .affirm: return "AFFIRM1"
        case .await_: return "AWAIT1"
        case .moveout: return "MOVOUT1"
        case .negative: return "NEGATV1"
        case .noProb: return "NOPROB"
        case .ready: return "READY"
        case .report: return "REPORT1"
        case .rightAway: return "RITAWAY"
        case .roger: return "ROGER"
        case .ugotit: return "UGOTIT"
        case .unit_: return "UNIT1"
        case .vehic: return "VEHIC1"
        case .yessir: return "YESSIR1"
        case .bazooka: return "BAZOOK1"
        case .bleep: return "BLEEP2"
        case .bomb1: return "BOMB1"
        case .button: return "BUTTON"
        case .radarOn: return "COMCNTR1"
        case .construction: return "CONSTRU2"
        case .crumble: return "CRUMBLE"
        case .flamer1: return "FLAMER2"
        case .rifle: return "GUN18"
        case .m60: return "GUN19"
        case .gun20: return "GUN20"
        case .m60a: return "GUN5"
        case .mini: return "GUN8"
        case .reload: return "GUNCLIP1"
        case .slam: return "HVYDOOR1"
        case .hvygun10: return "HVYGUN10"
        case .ionCannon: return "ION1"
        case .mgun11: return "MGUN11"
        case .mgun2: return "MGUN2"
        case .nukeFire: return "NUKEMISL"
        case .nukeExplode: return "NUKEXPLO"
        case .laser: return "OBELRAY1"
        case .laserPower: return "OBELPOWR"
        case .radarOff: return "POWRDN1"
        case .sniper: return "RAMGUN2"
        case .rocket1: return "ROCKET1"
        case .rocket2: return "ROCKET2"
        case .motor: return "SAMMOTR2"
        case .scold: return "SCOLD2"
        case .sidebarOpen: return "SIDBAR1C"
        case .sidebarClose: return "SIDBAR2C"
        case .squish2: return "SQUISH2"
        case .tank1: return "TNKFIRE2"
        case .tank2: return "TNKFIRE3"
        case .tank3: return "TNKFIRE4"
        case .tank4: return "TNKFIRE6"
        case .up: return "TONE15"
        case .down: return "TONE16"
        case .target: return "TONE2"
        case .sonar: return "TONE5"
        case .toss: return "TOSS1"
        case .cloak: return "TRANS1"
        case .burn: return "TREEBRN1"
        case .turret: return "TURRFIR5"
        case .xplobig4: return "XPLOBIG4"
        case .xplobig6: return "XPLOBIG6"
        case .xplobig7: return "XPLOBIG7"
        case .xplode: return "XPLODE"
        case .xplos: return "XPLOS"
        case .xplosml2: return "XPLOSML2"
        case .scream1: return "NUYELL1"
        case .scream3: return "NUYELL3"
        case .scream4: return "NUYELL4"
        case .scream5: return "NUYELL5"
        case .scream6: return "NUYELL6"
        case .scream7: return "NUYELL7"
        case .scream10: return "NUYELL10"
        case .scream11: return "NUYELL11"
        case .scream12: return "NUYELL12"
        case .yell1: return "YELL1"
        case .yes_: return "MYES1"
        case .commander: return "MCOMND1"
        case .hello: return "MHELLO1"
        case .hmmm: return "MHMMM1"
        case .cashturn: return "CASHTURN"
        case .beacon: return "BEACON"
        }
    }
}

// MARK: - EVA Speech Types (VOX)

enum VoxType: Int, CaseIterable {
    case none = -1
    case accomplished = 0
    case fail
    case noFactory
    case construction
    case unitReady
    case newConstruct
    case deploy
    case deadGDI
    case deadNod
    case deadCiv
    case noCash
    case controlExit
    case reinforcements
    case canceled
    case building
    case lowPower
    case noPower
    case needMoMoney
    case baseUnderAttack
    case incomingMissile
    case enemyPlanes
    case incomingNuke
    case unableToBuild
    case primarySelected
    case nodCaptured
    case gdiCaptured
    case ionCharging
    case ionReady
    case nukeAvailable
    case nukeLaunched
    case unitLost
    case structureLost
    case needHarvester
    case selectTarget
    case airstrikeReady
    case notReady
    case transportSighted
    case transportLoaded
    case prepare
    case needMoCapacity
    case suspended
    case repairing
    case enemyStructure
    case gdiStructure
    case nodStructure
    case enemyUnit

    var filename: String {
        switch self {
        case .none: return ""
        case .accomplished: return "ACCOM1"
        case .fail: return "FAIL1"
        case .noFactory: return "BLDG1"
        case .construction: return "CONSTRU1"
        case .unitReady: return "UNITREDY"
        case .newConstruct: return "NEWOPT1"
        case .deploy: return "DEPLOY1"
        case .deadGDI: return "GDIDEAD1"
        case .deadNod: return "NODDEAD1"
        case .deadCiv: return "CIVDEAD1"
        case .noCash: return "NOCASH1"
        case .controlExit: return "BATLCON1"
        case .reinforcements: return "REINFOR1"
        case .canceled: return "CANCEL1"
        case .building: return "BLDGING1"
        case .lowPower: return "LOPOWER1"
        case .noPower: return "NOPOWER1"
        case .needMoMoney: return "MOCASH1"
        case .baseUnderAttack: return "BASEATK1"
        case .incomingMissile: return "INCOME1"
        case .enemyPlanes: return "ENEMYA"
        case .incomingNuke: return "NUKE1"
        case .unableToBuild: return "NOBUILD1"
        case .primarySelected: return "PRIBLDG1"
        case .nodCaptured: return "NODCAPT1"
        case .gdiCaptured: return "GDICAPT1"
        case .ionCharging: return "IONCHRG1"
        case .ionReady: return "IONREDY1"
        case .nukeAvailable: return "NUKAVAIL"
        case .nukeLaunched: return "NUKLNCH1"
        case .unitLost: return "UNITLOST"
        case .structureLost: return "STRCLOST"
        case .needHarvester: return "NEEDHARV"
        case .selectTarget: return "SELECT1"
        case .airstrikeReady: return "AIRREDY1"
        case .notReady: return "NOREDY1"
        case .transportSighted: return "TRANSSEE"
        case .transportLoaded: return "TRANLOAD"
        case .prepare: return "ENMYAPP1"
        case .needMoCapacity: return "SILOS1"
        case .suspended: return "ONHOLD1"
        case .repairing: return "REPAIR1"
        case .enemyStructure: return "ESTRUCX"
        case .gdiStructure: return "GSTRUC1"
        case .nodStructure: return "NSTRUC1"
        case .enemyUnit: return "ENMYUNIT"
        }
    }
}

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

// MARK: - Audio Manager

class AudioManager {
    var audioDevice: SDL_AudioDeviceID = 0
    var isInitialized = false
    var masterVolume: Float = 0.8
    var sfxVolume: Float = 1.0
    var musicVolume: Float = 0.3

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
    var isMusicPlaying: Bool = false
    var isMusicLooping: Bool = false  // Don't loop single tracks; advance playlist
    var musicEnabled: Bool = true
    var musicLoading: Bool = false  // True while async loading in progress
    var needsNextTrack: Bool = false  // Flag to advance track outside tick()

    // Playlist
    var musicPlaylist: [ThemeType] = []
    var currentTrackIndex: Int = 0

    // Active sound mixing
    var activeSounds: [ActiveSound] = []
    let maxActiveSounds = 24
    let outputSampleRate = 22050

    // EVA speech queue
    var speechQueue: [VoxType] = []
    var activeSpeech: ActiveSound? = nil

    struct ActiveSound {
        var samples: [Int16]
        var offset: Int
        var volume: Float
        var pan: Float  // -1.0 left, 0.0 center, 1.0 right
        var sourceSampleRate: Int
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
        desired.channels = 1  // Mono output for simplicity
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
        guard isInitialized && voc != .none else { return }

        let name = voc.filename
        guard !name.isEmpty else { return }

        if !loadSound(name) { return }
        guard let samples = soundCache[name], let rate = soundSampleRates[name] else { return }

        // Calculate volume and pan based on world position
        var volume = sfxVolume * masterVolume
        var pan: Float = 0.0

        if let wx = worldX, let wy = worldY {
            // Distance from camera center (in world coordinates)
            let zoom = max(1.0, renderState.gameZoomLevel)
            let visibleWorldW = Double(renderState.windowWidth - sidebarWidth) / zoom
            let visibleWorldH = Double(renderState.windowHeight) / zoom
            let camCenterX = renderState.gameCameraX + visibleWorldW / 2.0
            let camCenterY = renderState.gameCameraY + visibleWorldH / 2.0
            let dx = wx - camCenterX
            let dy = wy - camCenterY
            let dist = sqrt(dx * dx + dy * dy)

            // Viewport-based attenuation in world coordinates
            let viewRadius = sqrt(visibleWorldW * visibleWorldW + visibleWorldH * visibleWorldH) / 2.0
            let minDist = viewRadius        // Full volume within the viewport
            let maxDist = viewRadius * 2.0  // Fade to zero at 2x viewport radius
            if dist > maxDist {
                return  // Too far, don't play
            } else if dist > minDist {
                let falloff = Float(1.0 - (dist - minDist) / (maxDist - minDist))
                volume *= falloff
            }

            // Stereo panning (in world coordinates)
            if visibleWorldW > 0 {
                pan = Float(dx / (visibleWorldW / 2.0))
                pan = max(-1.0, min(1.0, pan))
            }
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

    /// Play EVA speech (queued, one at a time)
    func speak(_ vox: VoxType) {
        guard isInitialized && vox != .none else { return }

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

            // Apply on main thread
            DispatchQueue.main.async {
                if loaded && self.currentTheme == theme {
                    self.soundCache[name] = decodedSamples
                    self.soundSampleRates[name] = sampleRate
                    self.musicSamples = decodedSamples
                    self.musicSampleRate = sampleRate
                    self.musicOffset = 0
                    self.musicLoading = false
                    self.isMusicPlaying = true
                    print("AudioManager: Playing theme '\(theme.title)' (\(decodedSamples.count) samples, \(sampleRate)Hz)")
                } else {
                    self.musicLoading = false
                    if !loaded {
                        print("AudioManager: Theme '\(name)' not found")
                    }
                }
            }
        }
    }

    /// Stop music
    func stopMusic() {
        isMusicPlaying = false
        currentTheme = .none
        musicSamples = []
        musicOffset = 0
    }

    /// Advance to the next track in the playlist
    func nextTrack() {
        guard musicEnabled, !musicPlaylist.isEmpty else { return }
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

        // Handle deferred track advance (loaded outside the mixing loop)
        if needsNextTrack && !musicLoading {
            needsNextTrack = false
            nextTrack()
        }

        // Only queue audio when there's something to play — avoids latency buildup
        let hasAudio = !activeSounds.isEmpty || activeSpeech != nil ||
                       (isMusicPlaying && !musicSamples.isEmpty)
        guard hasAudio else { return }

        // Keep the queue fed but not overstuffed — target ~100ms of buffered audio.
        // If the queue already has enough, skip this frame to avoid latency buildup.
        let queued = SDL_GetQueuedAudioSize(audioDevice)
        let targetQueueBytes = UInt32(outputSampleRate / 5 * 2)  // ~200ms in bytes
        if queued > targetQueueBytes { return }

        // Generate enough audio to cover the gap until next tick.
        // At 15 FPS game loop, we need ~67ms of audio per tick.
        // Generate ~100ms to provide headroom against frame time variation.
        let bufferSize = outputSampleRate / 10
        var mixBuffer = [Float](repeating: 0.0, count: bufferSize)

        // Mix active sound effects
        var completedIndices = [Int]()
        for (i, _) in activeSounds.enumerated() {
            mixSoundInto(&mixBuffer, sound: &activeSounds[i])
            if activeSounds[i].offset >= activeSounds[i].samples.count {
                completedIndices.append(i)
            }
        }
        for i in completedIndices.reversed() {
            activeSounds.remove(at: i)
        }

        // Mix EVA speech
        if var speech = activeSpeech {
            mixSoundInto(&mixBuffer, sound: &speech)
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

        // Mix music (with proper resampling for sample rate differences)
        if isMusicPlaying && !musicSamples.isEmpty {
            let musicVol = musicVolume * masterVolume
            let ratio = Double(musicSampleRate) / Double(outputSampleRate)
            var srcPos = Double(musicOffset)

            for i in 0..<bufferSize {
                let srcIdx = Int(srcPos)
                if srcIdx < musicSamples.count {
                    // Linear interpolation for smoother resampling
                    let frac = Float(srcPos - Double(srcIdx))
                    let s0 = Float(musicSamples[srcIdx])
                    let s1 = srcIdx + 1 < musicSamples.count ? Float(musicSamples[srcIdx + 1]) : s0
                    mixBuffer[i] += (s0 + (s1 - s0) * frac) * musicVol
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
        }

        // Convert to Int16 and queue
        var output = [Int16](repeating: 0, count: bufferSize)
        for i in 0..<bufferSize {
            let clamped = max(-32767.0, min(32767.0, mixBuffer[i]))
            output[i] = Int16(clamped)
        }

        _ = output.withUnsafeBufferPointer { buf in
            SDL_QueueAudio(audioDevice, buf.baseAddress, UInt32(bufferSize * 2))
        }
    }

    // MARK: - Convenience Methods

    /// Play a sound effect (convenience alias for playSoundEffect)
    func play(_ voc: VocType, worldX: Double? = nil, worldY: Double? = nil) {
        playSoundEffect(voc, worldX: worldX, worldY: worldY)
    }

    /// Get the weapon fire sound for a weapon type
    func weaponFireSound(_ weapon: WeaponType) -> VocType {
        switch weapon {
        case .mammothTusk, .dragon: return .rocket2
        case .mlrs, .honestJohn: return .rocket1
        case .flamethrower, .flameTongue: return .flamer1
        case .chainGun, .m16, .m60mg: return .mgun2
        case .obeliskLaser: return .laser
        case .tomahawk, .towTwo: return .rocket1
        case .turretGun: return .turret
        case .rifle: return .sniper
        case .pistol: return .rifle
        case .grenade: return .toss
        case .chemspray: return .flamer1
        case .napalm: return .bomb1
        case .nike: return .rocket2
        case .w75mm, .w105mm, .w120mm: return .tank1
        case .w155mm: return .hvygun10
        default: return .tank1
        }
    }

    /// Get an explosion sound for a warhead type
    func explosionSound(_ warhead: WarheadType) -> VocType {
        switch warhead {
        case .he: return .xplobig4
        case .ap: return .xplos
        case .fire: return .xplobig6
        case .laser: return .laser
        case .pb: return .xplobig7
        case .hollowPoint: return .xplode
        default: return .xplos
        }
    }

    /// Get an infantry death scream
    func infantryDeathScream() -> VocType {
        let screams: [VocType] = [.scream1, .scream3, .scream4, .scream5, .scream6, .scream7, .scream10, .scream11, .scream12]
        return screams[Int.random(in: 0..<screams.count)]
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

    /// Mix a single sound into the output buffer with resampling
    private func mixSoundInto(_ buffer: inout [Float], sound: inout ActiveSound) {
        let vol = sound.volume

        // Fast path: same sample rate (most sounds are 22050Hz = outputSampleRate)
        if sound.sourceSampleRate == outputSampleRate {
            let remaining = sound.samples.count - sound.offset
            let count = min(buffer.count, remaining)
            for i in 0..<count {
                buffer[i] += Float(sound.samples[sound.offset + i]) * vol
            }
            sound.offset += count
            return
        }

        // Resampling path: use Double for precision
        let ratio = Double(sound.sourceSampleRate) / Double(outputSampleRate)
        var srcPos = Double(sound.offset)

        for i in 0..<buffer.count {
            let srcIdx = Int(srcPos)
            if srcIdx >= sound.samples.count {
                sound.offset = sound.samples.count
                return
            }

            // Linear interpolation between adjacent samples for smoother output
            let frac = Float(srcPos - Double(srcIdx))
            let s0 = Float(sound.samples[srcIdx])
            let s1 = srcIdx + 1 < sound.samples.count ? Float(sound.samples[srcIdx + 1]) : s0
            buffer[i] += (s0 + (s1 - s0) * frac) * vol

            srcPos += ratio
        }

        sound.offset = Int(srcPos)
    }
}

// MARK: - Global Audio Instance

let audioManager = AudioManager()

