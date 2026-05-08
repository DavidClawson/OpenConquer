import Foundation

// MARK: - Window Sizing
// Persists the user's window size between sessions and enforces a sensible
// minimum so the sidebar + minimap + HUD never overlap into illegible layout.

enum WindowConfig {
    /// Smallest window the layout assumes — sidebar is 160px and HUD/minimap
    /// need viewport space. Below this things start clipping each other.
    static let minWidth: Int32 = 800
    static let minHeight: Int32 = 600

    /// Default size used on first launch.
    static let defaultWidth: Int32 = 1920
    static let defaultHeight: Int32 = 1200

    private static let widthKey = "TDMax.windowWidth"
    private static let heightKey = "TDMax.windowHeight"

    /// Returns the saved window size if both dimensions are present and at
    /// least `minWidth × minHeight`; nil otherwise.
    static func loadSaved() -> (width: Int32, height: Int32)? {
        let defaults = UserDefaults.standard
        let w = defaults.integer(forKey: widthKey)
        let h = defaults.integer(forKey: heightKey)
        guard w >= Int(minWidth), h >= Int(minHeight) else { return nil }
        return (Int32(w), Int32(h))
    }

    /// Persist the current window size (logical points, not pixels).
    static func save(width: Int32, height: Int32) {
        guard width >= minWidth, height >= minHeight else { return }
        let defaults = UserDefaults.standard
        defaults.set(Int(width), forKey: widthKey)
        defaults.set(Int(height), forKey: heightKey)
    }
}
