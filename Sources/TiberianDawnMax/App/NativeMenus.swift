import AppKit
import CSDL2
import OpenConquerAssets

// MARK: - The macOS menu bar
//
// SDL gives the app menu (About, Hide, Quit) and the Window menu. We add:
//   Sound   mute everything, music on/off, effects and voices on/off, next track
//   View    full screen
//   Editor  the mission editor's commands, with their usual shortcuts
// A menu item's shortcut is handled by AppKit before SDL sees the key, so the
// Editor items are enabled only while the editor is up; otherwise ⌘S, ⌘Z and
// the rest go on to the game as before. The Sound switches are remembered.

final class NativeMenus: NSObject, NSMenuItemValidation {
    static let shared = NativeMenus()

    private var window: OpaquePointer?

    private enum Key {
        static let muted = "TDMax.soundMuted"
        static let effectsOff = "TDMax.effectsMuted"
        static let musicOff = "TDMax.musicOff"
    }

    /// Adds the menus and applies the remembered Sound switches.
    func install(window: OpaquePointer?) {
        self.window = window
        let defaults = UserDefaults.standard
        gameAudio.isMuted = defaults.bool(forKey: Key.muted)
        gameAudio.effectsMuted = defaults.bool(forKey: Key.effectsOff)
        if defaults.bool(forKey: Key.musicOff) { gameAudio.musicEnabled = false }

        guard let main = NSApp.mainMenu else { return }
        // Before SDL's Window menu, which stays last by convention.
        let at = max(1, main.items.count - 1)
        main.insertItem(menu("Sound", [
            item("Mute All Sound", #selector(toggleMuteAll(_:)), "m", [.command, .shift]),
            .separator(),
            item("Music", #selector(toggleMusic(_:))),
            item("Sound Effects and Voices", #selector(toggleEffects(_:))),
            item("Next Track", #selector(nextTrack(_:))),
        ]), at: at)
        main.insertItem(menu("View", [
            item("Toggle Full Screen", #selector(toggleFullScreen(_:)), "f", [.command, .control]),
        ]), at: at + 1)
        main.insertItem(menu("Editor", [
            item("Open Mission Editor", #selector(openEditor(_:)), "e", [.command, .shift]),
            .separator(),
            item("Save Mission", #selector(editorSave(_:)), "s"),
            item("Play-Test", #selector(editorPlayTest(_:)), "r"),
            .separator(),
            item("Undo", #selector(editorUndo(_:)), "z"),
            item("Redo", #selector(editorRedo(_:)), "z", [.command, .shift]),
            .separator(),
            item("Show Grid", #selector(editorGrid(_:)), "g"),
            item("Zoom In", #selector(editorZoomIn(_:)), "="),
            item("Zoom Out", #selector(editorZoomOut(_:)), "-"),
            .separator(),
        ] + MissionEditorScreen.Tab.allCases.enumerated().map { i, tab in
            let it = item("\(tab.rawValue.capitalized.replacingOccurrences(of: ".", with: "")) Tab",
                          #selector(editorTab(_:)), "\(i + 1)")
            it.tag = i
            return it
        } + [
            .separator(),
            item("Leave Editor", #selector(editorExit(_:))),
        ]), at: at + 2)
    }

    private func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let m = NSMenu(title: title)
        items.forEach(m.addItem)
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        top.submenu = m
        return top
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        it.target = self
        return it
    }

    private var editor: MissionEditorScreen? { app.currentScreen as? MissionEditorScreen }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleMuteAll(_:)):
            item.state = gameAudio.isMuted ? .on : .off
        case #selector(toggleMusic(_:)):
            item.state = gameAudio.musicEnabled ? .on : .off
        case #selector(toggleEffects(_:)):
            item.state = gameAudio.effectsMuted ? .off : .on
        case #selector(nextTrack(_:)):
            return gameAudio.musicEnabled
        case #selector(toggleFullScreen(_:)):
            return true
        case #selector(openEditor(_:)):
            return editor == nil && !app.isPlaying && assetManager.mixManager.totalEntries > 0
        case #selector(editorGrid(_:)):
            item.state = renderState.showGrid ? .on : .off
            return editor != nil
        case #selector(editorUndo(_:)):
            return editor.map { !$0.undoStack.isEmpty } ?? false
        case #selector(editorRedo(_:)):
            return editor.map { !$0.redoStack.isEmpty } ?? false
        case #selector(editorTab(_:)):
            item.state = editor.map { MissionEditorScreen.Tab.allCases.firstIndex(of: $0.tab) == item.tag } == true ? .on : .off
            return editor != nil
        default:
            return editor != nil
        }
        return true
    }

    // MARK: Sound

    @objc func toggleMuteAll(_ sender: Any?) {
        gameAudio.isMuted.toggle()
        UserDefaults.standard.set(gameAudio.isMuted, forKey: Key.muted)
    }

    @objc func toggleMusic(_ sender: Any?) {
        gameAudio.toggleMusic()
        if gameAudio.musicEnabled && !gameAudio.isMusicPlaying {
            if app.isPlaying { gameAudio.startGameplayMusic() } else { gameAudio.playMenuMusic() }
        }
        UserDefaults.standard.set(!gameAudio.musicEnabled, forKey: Key.musicOff)
    }

    @objc func toggleEffects(_ sender: Any?) {
        gameAudio.effectsMuted.toggle()
        UserDefaults.standard.set(gameAudio.effectsMuted, forKey: Key.effectsOff)
    }

    @objc func nextTrack(_ sender: Any?) { gameAudio.nextTrack() }

    // MARK: View

    @objc func toggleFullScreen(_ sender: Any?) {
        guard let window else { return }
        let full = SDL_GetWindowFlags(window) & SDL_WINDOW_FULLSCREEN_DESKTOP.rawValue != 0
        SDL_SetWindowFullscreen(window, full ? 0 : SDL_WINDOW_FULLSCREEN_DESKTOP.rawValue)
    }

    // MARK: Editor

    @objc func openEditor(_ sender: Any?) {
        app.currentScreen = MissionEditorScreen.openCampaign(app.scenarioList.first ?? "SCG01EA")
            ?? MissionEditorScreen.blank(.temperate)
    }

    @objc func editorSave(_ sender: Any?) { editor?.save() }
    @objc func editorPlayTest(_ sender: Any?) { editor?.playTest() }
    @objc func editorUndo(_ sender: Any?) { editor?.undo() }
    @objc func editorRedo(_ sender: Any?) { editor?.redo() }
    @objc func editorGrid(_ sender: Any?) { renderState.showGrid.toggle() }
    @objc func editorZoomIn(_ sender: Any?) { editor?.zoom(by: 0.25) }
    @objc func editorZoomOut(_ sender: Any?) { editor?.zoom(by: -0.25) }
    @objc func editorExit(_ sender: Any?) { editor?.exit() }

    @objc func editorTab(_ sender: NSMenuItem) {
        let tabs = MissionEditorScreen.Tab.allCases
        guard sender.tag < tabs.count else { return }
        editor?.switchTab(tabs[sender.tag])
    }
}
