import Foundation

// MARK: - Production Queue
// Extracted from raw tuples on GameSession.
// Encapsulates build progress for a single production line (units or structures).

class ProductionQueue {
    var item: (typeName: String, progress: Int, cost: Int, totalTicks: Int)? = nil
    var isOnHold: Bool = false

    /// Advance production by one tick. Returns true when the item completes.
    func tick(hasPower: Bool, worldTickCount: Int) -> Bool {
        guard var current = item else { return false }
        if current.progress >= current.totalTicks { return false }

        // Low power slows production: skip every other tick (doubles build time)
        let lowPowerSkip = !hasPower && (worldTickCount % 2 == 0)
        if !lowPowerSkip {
            current.progress += 1
        }
        item = current
        return current.progress >= current.totalTicks
    }

    /// Start building an item. Does not deduct credits — caller handles that.
    func start(typeName: String, cost: Int, buildTime: Int) {
        item = (typeName: typeName, progress: 0, cost: cost, totalTicks: buildTime)
        isOnHold = false
    }

    /// Cancel the current build. Returns the cost for refund (caller decides refund amount).
    func cancel() -> Int {
        let refund = item?.cost ?? 0
        item = nil
        isOnHold = false
        return refund
    }

    /// Fraction of progress completed (0.0 to 1.0).
    var progressFraction: Double {
        guard let current = item, current.totalTicks > 0 else { return 0.0 }
        return Double(current.progress) / Double(current.totalTicks)
    }

    /// Whether the current item has finished building.
    var isComplete: Bool {
        guard let current = item else { return false }
        return current.progress >= current.totalTicks
    }

    /// Clear the queue (e.g. after spawning the completed unit).
    func clear() {
        item = nil
        isOnHold = false
    }
}
