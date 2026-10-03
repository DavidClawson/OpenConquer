import Foundation
import OpenConquerCore

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

/// Which sidebar to draw.
enum SidebarStyle: String, CaseIterable {
    /// The original hi-res sidebar from UPDATEC.MIX (falls back to Modern if
    /// that art isn't installed).
    case classic = "Classic"
    /// The procedural tabbed list.
    case modern = "Modern"

    var summary: String {
        switch self {
        case .classic: return "The 1995 sidebar: radar, two build strips, power bar."
        case .modern:  return "A single tabbed build list with unit details."
        }
    }
}

/// Width of the classic sidebar column: its 160 hi-res columns at 2x or 3x.
enum SidebarSize: String, CaseIterable {
    case standard = "2x"
    case large = "3x"

    var scale: Int32 { self == .standard ? 2 : 3 }
}

/// Whether and how the VQA movies play.
enum MovieMode: String, CaseIterable {
    case off = "Off"
    /// The 320x200 frame scaled with hard pixel edges.
    case pixels = "Pixels"
    /// Bilinear scaling — closest to the Win95 build's interpolated 2x.
    case smooth = "Smooth"
    /// Apple's low-latency super-resolution (macOS 26+); Smooth elsewhere.
    case enhanced = "Enhanced"

    var summary: String {
        switch self {
        case .off:      return "Skip the briefing and story movies."
        case .pixels:   return "Original 320x200 frames with hard pixel edges."
        case .smooth:   return "Original frames, smoothly scaled."
        case .enhanced: return movieEnhancementAvailable
            ? "Apple super-resolution upscaling, live (macOS 26+)."
            : "Needs macOS 26 - using Smooth."
        }
    }
}

enum UserSettings {
    private static let controlSchemeKey = "TDMax.controlScheme"
    private static let sidebarStyleKey = "TDMax.sidebarStyle"
    private static let sidebarSizeKey = "TDMax.sidebarSize"
    private static let movieModeKey = "TDMax.movieMode"

    /// Defaults to `.smooth`.
    static var movieMode: MovieMode {
        get {
            UserDefaults.standard.string(forKey: movieModeKey)
                .flatMap(MovieMode.init(rawValue:)) ?? .smooth
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: movieModeKey) }
    }

    /// Defaults to 2x (320px wide). Cached like `sidebarStyle`.
    static var sidebarSize: SidebarSize = UserDefaults.standard.string(forKey: sidebarSizeKey)
        .flatMap(SidebarSize.init(rawValue:)) ?? .standard {
        didSet { UserDefaults.standard.set(sidebarSize.rawValue, forKey: sidebarSizeKey) }
    }

    /// Defaults to `.classic`. Cached: the sidebar width reads it many times a frame.
    static var sidebarStyle: SidebarStyle = UserDefaults.standard.string(forKey: sidebarStyleKey)
        .flatMap(SidebarStyle.init(rawValue:)) ?? .classic {
        didSet { UserDefaults.standard.set(sidebarStyle.rawValue, forKey: sidebarStyleKey) }
    }

    /// Defaults to `.classic` on first launch.
    static var controlScheme: ControlScheme {
        get {
            UserDefaults.standard.string(forKey: controlSchemeKey)
                .flatMap(ControlScheme.init(rawValue:)) ?? .classic
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: controlSchemeKey) }
    }
}
