import Foundation

// MARK: - Game Object Types

enum ObjectKind {
    case unit
    case infantry
    case structure
}

enum Mission: String {
    case guard_ = "Guard"
    case move = "Move"
    case stop = "Stop"
    case sleep = "Sleep"

    static func from(_ string: String) -> Mission {
        switch string.lowercased() {
        case "guard":  return .guard_
        case "move":   return .move
        case "stop":   return .stop
        case "sleep":  return .sleep
        default:       return .guard_
        }
    }
}

// MARK: - Game Object

class GameObject {
    let id: Int
    let typeName: String
    let house: House
    let kind: ObjectKind

    // Position in double-pixel coordinates (sub-pixel smooth)
    var worldX: Double
    var worldY: Double
    var facing: Int          // 0-255 C&C facing (0=N, 64=E, 128=S, 192=W)
    var strength: Int        // Hit points (0-256)

    // State
    var mission: Mission
    var isSelected: Bool = false

    // Movement
    var moveTargetX: Double? = nil
    var moveTargetY: Double? = nil
    var speed: Double        // Pixels per tick
    var movePath: [(cellX: Int, cellY: Int)] = []

    // Infantry sub-cell
    var subCell: Int

    // Computed cell position
    var cellX: Int { Int(worldX) / 24 }
    var cellY: Int { Int(worldY) / 24 }
    var cell: Int { cellY * 64 + cellX }

    init(id: Int, typeName: String, house: House, kind: ObjectKind,
         worldX: Double, worldY: Double, facing: Int, strength: Int,
         mission: Mission, speed: Double, subCell: Int = 0) {
        self.id = id
        self.typeName = typeName
        self.house = house
        self.kind = kind
        self.worldX = worldX
        self.worldY = worldY
        self.facing = facing
        self.strength = strength
        self.mission = mission
        self.speed = speed
        self.subCell = subCell
    }
}

// MARK: - Game World

class GameWorld {
    var objects: [GameObject] = []
    var nextObjectId: Int = 0
    var tickCount: Int = 0
    var theater: TheaterType = .temperate
    var mapBounds: MapBounds?
    var occupancy: [Int: Int] = [:]  // cell -> object id occupying it

    func addObject(_ obj: GameObject) {
        objects.append(obj)
    }

    func allocateId() -> Int {
        let id = nextObjectId
        nextObjectId += 1
        return id
    }

    func selectedObjects() -> [GameObject] {
        objects.filter { $0.isSelected }
    }

    func deselectAll() {
        for obj in objects {
            obj.isSelected = false
        }
    }
}

// Module-level game world instance
var gameWorld: GameWorld? = nil
