import Foundation

// The "current map": the playing world's map, or the map viewer's when no
// mission is running. Older code reads these instead of session.world.map.

// MARK: - Map Viewer State

/// Standalone map used in map-viewer mode (no GameWorld)
package var mapViewerMap = GameMap()

/// Backward-compatible accessor — delegates to world.map when in game, mapViewerMap otherwise
package var mapCells: [MapCell] {
    get { session.world?.map.cells ?? mapViewerMap.cells }
    set {
        if let world = session.world {
            world.map.cells = newValue
        } else {
            mapViewerMap.cells = newValue
        }
    }
}

/// Backward-compatible accessor — delegates to world.map when in game, mapViewerMap otherwise
package var scenarioData: ScenarioData? {
    get { session.world?.map.scenarioData ?? mapViewerMap.scenarioData }
    set {
        if let world = session.world {
            world.map.scenarioData = newValue
        } else {
            mapViewerMap.scenarioData = newValue
        }
    }
}

// Info panel & overlay toggle state
