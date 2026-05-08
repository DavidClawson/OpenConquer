import Foundation

// MARK: - Game Event Bus
// Centralized event system for decoupling game subsystems.
// Events are queued during the tick and flushed at the end.

enum GameEvent {
    case unitDestroyed(objectId: Int, typeName: String, house: House, killerHouse: House?)
    case buildingDestroyed(objectId: Int, typeName: String, house: House, killerHouse: House?)
    case unitDamaged(objectId: Int, attackerHouse: House?, damageAmount: Int)
    case buildingDamaged(objectId: Int, attackerHouse: House?, damageAmount: Int)
    case buildingCaptured(objectId: Int, typeName: String, previousHouse: House, newHouse: House)
    case buildingSold(objectId: Int, typeName: String, house: House, refundAmount: Int)
    case unitProduced(objectId: Int, typeName: String, house: House)
    case buildingPlaced(objectId: Int, typeName: String, house: House)
    case tiberiumHarvested(house: House, amount: Int)
    case superWeaponReady(house: House, weaponType: String)
    case superWeaponFired(house: House, weaponType: String, targetX: Double, targetY: Double)
    case cratePickedUp(objectId: Int, house: House, effect: String)
}

class GameEventBus {
    typealias Handler = (GameEvent) -> Void
    private var subscribers: [(id: String, handler: Handler)] = []
    private var pendingEvents: [GameEvent] = []

    func subscribe(id: String, handler: @escaping Handler) {
        subscribers.append((id: id, handler: handler))
    }

    func unsubscribe(id: String) {
        subscribers.removeAll { $0.id == id }
    }

    func emit(_ event: GameEvent) {
        pendingEvents.append(event)
    }

    func flush() {
        let events = pendingEvents
        pendingEvents = []
        for event in events {
            for subscriber in subscribers {
                subscriber.handler(event)
            }
        }
    }
}

// MARK: - Global Instance

let eventBus = GameEventBus()

// MARK: - Debug Logging

func setupEventBusDebugLogging() {
    #if DEBUG
    eventBus.subscribe(id: "debug-logger") { event in
        switch event {
        case .unitDestroyed(_, let typeName, let house, _):
            print("[EVENT] Unit destroyed: \(typeName) (\(house.rawValue))")
        case .buildingDestroyed(_, let typeName, let house, _):
            print("[EVENT] Building destroyed: \(typeName) (\(house.rawValue))")
        case .buildingCaptured(_, let typeName, _, let newHouse):
            print("[EVENT] Building captured: \(typeName) by \(newHouse.rawValue)")
        case .buildingSold(_, let typeName, let house, let refundAmount):
            print("[EVENT] Building sold: \(typeName) (\(house.rawValue)) for $\(refundAmount)")
        default:
            break  // Don't log high-frequency events
        }
    }
    #endif
}
