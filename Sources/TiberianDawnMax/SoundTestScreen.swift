import CSDL2
import Foundation

// MARK: - Sound Test Screen
// Browse and play all game sounds organized by category.
// Follows the SpriteViewer pattern (state vars + render + input).

// State
var soundTestCategory: Int = 0
var soundTestSelection: Int = 0
var soundTestScrollOffset: Int = 0
var soundTestPlaying: String? = nil
var soundTestPlayingTimer: UInt32 = 0

/// Initialize sound test screen state
func initSoundTest() {
    soundTestCategory = 0
    soundTestSelection = 0
    soundTestScrollOffset = 0
    soundTestPlaying = nil
}

/// Handle keyboard input for the sound test screen
func handleSoundTestKey(_ key: Int32) {
    let categories = SoundLibrary.categories
    guard !categories.isEmpty else { return }
    let cat = categories[soundTestCategory]

    if key == Int32(SDLK_TAB.rawValue) {
        // Cycle category
        soundTestCategory = (soundTestCategory + 1) % categories.count
        soundTestSelection = 0
        soundTestScrollOffset = 0
        soundTestPlaying = nil
    } else if key == Int32(SDLK_DOWN.rawValue) {
        // Move selection down
        if soundTestSelection < cat.sounds.count - 1 {
            soundTestSelection += 1
            // Scroll if needed
            let maxVisible = soundTestMaxVisible()
            if soundTestSelection >= soundTestScrollOffset + maxVisible {
                soundTestScrollOffset = soundTestSelection - maxVisible + 1
            }
        }
    } else if key == Int32(SDLK_UP.rawValue) {
        // Move selection up
        if soundTestSelection > 0 {
            soundTestSelection -= 1
            if soundTestSelection < soundTestScrollOffset {
                soundTestScrollOffset = soundTestSelection
            }
        }
    } else if key == Int32(SDLK_RETURN.rawValue) || key == Int32(SDLK_KP_ENTER.rawValue) {
        // Play selected sound
        guard soundTestSelection < cat.sounds.count else { return }
        let entry = cat.sounds[soundTestSelection]
        playSoundTestEntry(entry.id)
    } else if key == Int32(SDLK_SPACE.rawValue) {
        // Stop playback
        stopSoundTestPlayback()
    } else if key == Int32(SDLK_PAGEDOWN.rawValue) {
        let maxVisible = soundTestMaxVisible()
        soundTestSelection = min(cat.sounds.count - 1, soundTestSelection + maxVisible)
        if soundTestSelection >= soundTestScrollOffset + maxVisible {
            soundTestScrollOffset = soundTestSelection - maxVisible + 1
        }
    } else if key == Int32(SDLK_PAGEUP.rawValue) {
        let maxVisible = soundTestMaxVisible()
        soundTestSelection = max(0, soundTestSelection - maxVisible)
        if soundTestSelection < soundTestScrollOffset {
            soundTestScrollOffset = soundTestSelection
        }
    }
}

/// Maximum visible rows in the list area
private func soundTestMaxVisible() -> Int {
    return 18
}

/// Play a sound from the sound test
private func playSoundTestEntry(_ name: String) {
    // Stop everything first to prevent pops/overlap
    stopSoundTestPlayback()

    let categories = SoundLibrary.categories
    let cat = categories[soundTestCategory]
    let isTheme = cat.name == "MUSIC THEMES"

    guard audioManager.loadSound(name) else { return }
    guard let samples = audioManager.soundCache[name],
          let rate = audioManager.soundSampleRates[name] else { return }

    if isTheme {
        // Play as music
        audioManager.musicSamples = samples
        audioManager.musicOffset = 0
        audioManager.isMusicPlaying = true
        audioManager.isMusicLooping = false
    } else {
        // Play as sound effect (non-positional, full volume)
        audioManager.activeSounds.append(AudioManager.ActiveSound(
            samples: samples, offset: 0,
            volume: audioManager.masterVolume,
            pan: 0.0,
            sourceSampleRate: rate
        ))
    }

    soundTestPlaying = name
    soundTestPlayingTimer = SDL_GetTicks()
}

/// Stop current sound test playback
private func stopSoundTestPlayback() {
    audioManager.activeSounds.removeAll()
    audioManager.stopMusic()
    audioManager.activeSpeech = nil
    SDL_ClearQueuedAudio(audioManager.audioDevice)
    soundTestPlaying = nil
}

/// Render the sound test screen
func renderSoundTest(_ renderer: OpaquePointer?) {
    let categories = SoundLibrary.categories
    guard !categories.isEmpty else {
        drawText(renderer, "No sound categories", centerX: renderState.windowWidth / 2, centerY: renderState.windowHeight / 2,
                 color: .red, scale: 2)
        return
    }

    let cat = categories[soundTestCategory]

    // Title
    drawText(renderer, "SOUND TEST", centerX: renderState.windowWidth / 2, centerY: 30, color: .amber, scale: 3)

    // Category name
    let catLabel = "\(cat.name)  (\(soundTestCategory + 1)/\(categories.count))"
    drawText(renderer, catLabel, centerX: renderState.windowWidth / 2, centerY: 65, color: .green, scale: 2)

    // Source indicator
    if assetManager.hasRemasteredAudio {
        drawText(renderer, "Remastered audio available (44kHz)", centerX: renderState.windowWidth / 2, centerY: 88, color: .brightGreen, scale: 1)
    } else if assetManager.hasExtractedAudio {
        drawText(renderer, "Classic extracted WAV (22kHz)", centerX: renderState.windowWidth / 2, centerY: 88, color: .green, scale: 1)
    } else {
        drawText(renderer, "No extracted WAV - using AUD from MIX", centerX: renderState.windowWidth / 2, centerY: 88, color: .amber, scale: 1)
    }

    // List area
    let listX: Int32 = 60
    let listY: Int32 = 110
    let rowH: Int32 = 22
    let maxVisible = soundTestMaxVisible()
    let listW: Int32 = renderState.windowWidth - 120

    // Draw list background
    SDL_SetRenderDrawColor(renderer, 15, 15, 15, 255)
    var listBg = SDL_Rect(x: listX - 5, y: listY - 5, w: listW + 10, h: Int32(maxVisible) * rowH + 10)
    SDL_RenderFillRect(renderer, &listBg)

    // Draw list border
    SDL_SetRenderDrawColor(renderer, 0, 100, 0, 255)
    SDL_RenderDrawRect(renderer, &listBg)

    // Draw visible items
    let endIdx = min(cat.sounds.count, soundTestScrollOffset + maxVisible)
    for i in soundTestScrollOffset..<endIdx {
        let entry = cat.sounds[i]
        let rowY = listY + Int32(i - soundTestScrollOffset) * rowH
        let isSelected = (i == soundTestSelection)
        let isPlaying = (soundTestPlaying == entry.id)

        // Selection highlight
        if isSelected {
            SDL_SetRenderDrawColor(renderer, 0, 60, 0, 255)
            var selRect = SDL_Rect(x: listX - 3, y: rowY - 2, w: listW + 6, h: rowH)
            SDL_RenderFillRect(renderer, &selRect)
        }

        // Cursor
        let cursor = isSelected ? ">" : " "
        let textColor: Color = isPlaying ? .amber : (isSelected ? .brightGreen : .green)

        // Status indicator
        let status = isPlaying ? " [Playing]" : ""

        // Draw text
        let line = "\(cursor) \(entry.id)"
        drawTextLeft(renderer, line, x: listX + 5, y: rowY, color: textColor, scale: 1)
        drawTextLeft(renderer, entry.label, x: listX + 180, y: rowY, color: textColor, scale: 1)

        if !status.isEmpty {
            drawTextLeft(renderer, status, x: listX + listW - 130, y: rowY, color: Color.amber, scale: 1)
        }
    }

    // Scroll indicators
    if soundTestScrollOffset > 0 {
        drawText(renderer, "^ More above", centerX: renderState.windowWidth / 2, centerY: listY - 15, color: .gray, scale: 1)
    }
    if endIdx < cat.sounds.count {
        let bottomY = listY + Int32(maxVisible) * rowH + 10
        drawText(renderer, "v More below (\(cat.sounds.count - endIdx))", centerX: renderState.windowWidth / 2, centerY: bottomY, color: .gray, scale: 1)
    }

    // Info panel for selected sound
    let infoY = listY + Int32(maxVisible) * rowH + 30
    if soundTestSelection < cat.sounds.count {
        let entry = cat.sounds[soundTestSelection]
        if let lib = audioManager.soundLibrary, let audio = lib.load(entry.id) {
            let dur = String(format: "%.2fs", audio.duration)
            let info = "Rate: \(audio.sampleRate)Hz   Duration: \(dur)   Samples: \(audio.samples.count)   Source: \(audio.source.rawValue)"
            drawText(renderer, info, centerX: renderState.windowWidth / 2, centerY: infoY, color: .green, scale: 1)
        } else {
            drawText(renderer, "Sound not found: \(entry.id)", centerX: renderState.windowWidth / 2, centerY: infoY, color: .red, scale: 1)
        }
    }

    // Controls
    let ctrlY = renderState.windowHeight - 50
    drawText(renderer, "Tab: Category   Up/Down: Browse   Enter: Play   Space: Stop", centerX: renderState.windowWidth / 2, centerY: ctrlY, color: .gray, scale: 1)
    drawText(renderer, "PgUp/PgDn: Scroll   Esc: Back", centerX: renderState.windowWidth / 2, centerY: ctrlY + 20, color: .gray, scale: 1)
}
