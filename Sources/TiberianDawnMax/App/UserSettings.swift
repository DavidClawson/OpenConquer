import Foundation

// MARK: - User Settings
// Presentation/input preferences persisted between sessions. These are NOT
// sim rules — they never touch the world, so they live outside `Ruleset` and
// don't affect determinism baselines.

/// How mouse buttons map to commands.
enum ControlScheme: String, CaseIterable {
    /// 1995 behavior: left-click selects *and* commands (move/attack/enter,
    /// chosen by what's under the cursor); right-click deselects or cancels a
    /// mode (DISPLAY.CPP What_Action / Mouse_Right_Press).
    case classic = "Classic"
    /// Left-click selects, right-click commands.
    case modern = "Modern"

    var summary: String {
        switch self {
        case .classic: return "Left-click selects and commands. Right-click deselects."
        case .modern:  return "Left-click selects. Right-click commands."
        }
    }
}

enum UserSettings {
    private static let controlSchemeKey = "TDMax.controlScheme"

    /// Defaults to `.classic` on first launch.
    static var controlScheme: ControlScheme {
        get {
            UserDefaults.standard.string(forKey: controlSchemeKey)
                .flatMap(ControlScheme.init(rawValue:)) ?? .classic
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: controlSchemeKey) }
    }
}
