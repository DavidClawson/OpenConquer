import XCTest
@testable import OpenConquerCore

/// Selection is the local player's UI state (`session.selection`), not part
/// of the world: GameObject.isSelected and the world's selection helpers are
/// views onto it, and a new world starts with nothing selected.
final class SelectionTests: XCTestCase {
    private func tank(_ id: Int, _ house: House, in world: GameWorld) -> GameObject {
        let obj = GameObject(id: id, typeName: "MTNK", house: house, kind: .unit,
                             worldX: 100, worldY: 100, facing: 0, strength: 100,
                             mission: .guard_, speed: 1)
        world.addObject(obj)
        return obj
    }

    func testSelectionLivesOutsideTheWorld() {
        let world = GameWorld()
        let a = tank(1, .goodGuy, in: world), b = tank(2, .goodGuy, in: world), c = tank(3, .badGuy, in: world)
        c.isSelected = true
        a.isSelected = true
        XCTAssertEqual(session.selection.ids, [1, 3])
        XCTAssertEqual(world.selectedObjects().map(\.id), [1, 3])  // world order, not click order
        XCTAssertFalse(b.isSelected)

        world.controlGroups[2] = [1, 2]
        XCTAssertEqual(session.selection.controlGroups[2], [1, 2])

        world.deselectAll()
        XCTAssertTrue(world.selectedObjects().isEmpty)
        XCTAssertFalse(a.isSelected)

        a.isSelected = true
        _ = GameWorld()  // a new world resets the local player's selection
        XCTAssertTrue(session.selection.ids.isEmpty)
        XCTAssertEqual(session.selection.controlGroups, Array(repeating: [], count: 10))
    }
}
