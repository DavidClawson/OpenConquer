import Foundation
import OpenConquerCore

// MARK: - App State
// Everything about the running app that isn't the simulation: which screen is
// up, menu selections, tool screens, and the real-time frame clock. The
// simulation's state lives in `session` (Game/GameSession.swift) and never
// refers back to this.

final class AppState {
    // MARK: - Menu / UI State
    var currentScreen: MenuScreen = ModernMainMenuScreen()  // replaced at startup, once data is loaded
    var running: Bool = true
    var isPlaying: Bool { currentScreen is PlayingScreen }
    var selectedDifficulty: Difficulty = .normal
    var selectedFaction: Faction = .gdi
    var scenarioList: [String] = []
    var scenarioIndex: Int = 0
    /// The mission editor a play-test came from: leaving the game for the
    /// main menu goes back to it instead (`makeMainMenu`).
    var playTestReturn: MenuScreen? = nil
    var soundTest = SoundTestState()
    var spritePlayground = SpritePlaygroundState()

    // MARK: - Frame Clock (see App/FrameClock.swift)
    var tickAccumulator: UInt32 = 0
    var lastTickTime: UInt32 = 0
    /// 0.0-1.0 between game ticks, for smooth rendering.
    var renderInterpolation: Double = 0.0
    /// The world the presentation was last set up for (palette, caches,
    /// clock); a different one means a mission started, restarted or loaded.
    weak var presentedWorld: GameWorld? = nil
}

var app = AppState()
