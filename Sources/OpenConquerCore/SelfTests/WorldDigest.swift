import Foundation

// MARK: - World-state digest and summary
//
// Shared by the headless harness (`--headless`, `--determinism`) and the
// self-tests.

/// Stable FNV-1a digest of the simulation state. Sorted by object id and house
/// name so the result is independent of collection iteration order. Includes the
/// RNG stream position so any divergence in random consumption is caught too.
package func headlessWorldDigest() -> UInt64 {
    var h: UInt64 = 0xCBF29CE484222325
    func mix(_ v: UInt64) { h ^= v; h = h &* 0x100000001B3 }
    func mixInt(_ i: Int) { mix(UInt64(bitPattern: Int64(i))) }
    func mixStr(_ s: String) { for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001B3 } }

    guard let world = session.world else { return h }
    mixInt(world.tickCount)

    for obj in world.objects.sorted(by: { $0.id < $1.id }) {
        mixInt(obj.id)
        mixStr(obj.typeName)
        mixStr(String(describing: obj.house))
        mixStr(String(describing: obj.mission))
        mixInt(obj.strength)
        mix(obj.worldX.bitPattern)
        mix(obj.worldY.bitPattern)
        mixInt(obj.facing)
        mixInt(obj.tiberiumLoad)
    }

    for (house, state) in session.houseStates.sorted(by: { String(describing: $0.key) < String(describing: $1.key) }) {
        mixStr(String(describing: house))
        mixInt(state.credits)
        mixInt(state.tiberium)
    }

    mix(gameRng.state)
    return h
}

/// One-line human-readable summary of the current world.
package func headlessWorldSummary() -> String {
    guard let world = session.world else { return "(no world)" }
    let byKind = Dictionary(grouping: world.objects, by: { $0.kind })
        .map { "\($0.key)=\($0.value.count)" }
        .sorted()
        .joined(separator: " ")
    let credits = session.houseStates
        .sorted(by: { String(describing: $0.key) < String(describing: $1.key) })
        .map { "\($0.key):\($0.value.credits)" }
        .joined(separator: " ")
    return "tick=\(world.tickCount) objects=\(world.objects.count) [\(byKind)] credits[\(credits)]"
}
