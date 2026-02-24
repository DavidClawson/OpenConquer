import Foundation

// MARK: - OOP Protocol Foundation
// Aspirational patterns for incremental migration from procedural to OOP.
// NOT applied broadly yet — just the target types.

/// Something that can render itself given a renderer and camera state.
protocol Renderable {
    func render(to renderer: OpaquePointer?, camera: CameraState)
}

/// Camera/viewport state passed to renderable objects.
struct CameraState {
    let x: Double
    let y: Double
    let zoom: Double
    let viewportWidth: Int32
    let viewportHeight: Int32
}
