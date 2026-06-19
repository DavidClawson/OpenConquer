import Foundation

// MARK: - Deterministic game RNG
//
// The simulation must be reproducible: given the same seed and the same inputs,
// every tick must play out identically. That enables replays, AI lookahead, and
// a mission planner that can preview AI behavior. To get there, all
// *simulation* randomness flows through this single seeded generator instead of
// the system RNG.
//
// Purely cosmetic randomness (screen shake, debris/explosion offsets, sprite
// flicker, audio variation, menus) deliberately does NOT use this generator —
// it doesn't affect game state, and keeping it off the sim stream avoids
// perturbing the deterministic sequence when visual effects change.
//
// SplitMix64: tiny, fast, well-distributed, and trivially serializable (the
// whole state is one UInt64), which makes save/load resume the exact stream.

struct GameRandom: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        // Avoid an all-zero state producing a degenerate first few outputs.
        self.state = seed == 0 ? 0x2545F4914F6CDD1D : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// The single simulation RNG. Reseeded at scenario start; its state is persisted
/// by save/load so a reloaded game continues the identical random sequence.
var gameRng = GameRandom(seed: 0x2545F4914F6CDD1D)

/// Reseed the simulation RNG. Called at scenario init. Pass a fixed seed for
/// reproducible runs (tests / replays); pass a time-derived seed for variety.
func seedGameRandom(_ seed: UInt64) {
    gameRng = GameRandom(seed: seed)
}

/// When set, overrides the scenario-derived seed at the next `initGameWorld`.
/// The headless harness sets this so a run is bit-for-bit reproducible.
var forcedGameSeed: UInt64? = nil

/// Stable (process-independent) seed derived from a string via FNV-1a 64-bit.
/// Swift's `String.hashValue` is randomized per process, so we can't use it for
/// a reproducible seed — this is stable across launches.
func stableSeed(_ s: String) -> UInt64 {
    var hash: UInt64 = 0xCBF29CE484222325
    for byte in s.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001B3
    }
    return hash
}

// MARK: - Convenience wrappers
//
// Swift's `Int.random(in:using:)` needs an `inout` generator, which is awkward
// at every call site. These free functions thread the global generator so a
// call site only changes `Int.random(in: r)` -> `rndInt(r)`.

@inline(__always) func rndInt(_ range: Range<Int>) -> Int {
    Int.random(in: range, using: &gameRng)
}

@inline(__always) func rndInt(_ range: ClosedRange<Int>) -> Int {
    Int.random(in: range, using: &gameRng)
}

@inline(__always) func rndDouble(_ range: ClosedRange<Double>) -> Double {
    Double.random(in: range, using: &gameRng)
}

@inline(__always) func rndDouble(_ range: Range<Double>) -> Double {
    Double.random(in: range, using: &gameRng)
}

@inline(__always) func rndBool() -> Bool {
    Bool.random(using: &gameRng)
}

extension Array {
    /// Deterministic `randomElement()` using the simulation RNG.
    func rndElement() -> Element? {
        randomElement(using: &gameRng)
    }
}
