import Foundation

// MARK: - Simulation Audio
// The simulation's only line to the speakers. The sim names the sound and
// where it happened; the app's AudioManager plays it. Headless runs and tests
// keep the silent default. Picks that use randomness use the system RNG, never
// the seeded sim RNG, so audio can't affect determinism.

package protocol SimAudio: AnyObject {
    func play(_ voc: VocType, worldX: Double?, worldY: Double?)
    func speak(_ vox: VoxType)
    /// A commando just killed something (he quips about it a moment later).
    func commandoMadeKill(_ commando: GameObject, tick: Int)
}

/// No-op audio for headless runs and tests.
package final class SilentAudio: SimAudio {
    package func play(_ voc: VocType, worldX: Double?, worldY: Double?) {}
    package func speak(_ vox: VoxType) {}
    package func commandoMadeKill(_ commando: GameObject, tick: Int) {}
}

/// Set by the app at startup (App: `audioManager = gameAudio`).
package var audioManager: SimAudio = SilentAudio()

extension SimAudio {
    package func play(_ voc: VocType) { play(voc, worldX: nil, worldY: nil) }


    /// Get the weapon fire sound for a weapon type
    package func weaponFireSound(_ weapon: WeaponType) -> VocType {
        switch weapon {
        case .mammothTusk, .dragon: return .rocket2
        case .mlrs, .honestJohn: return .rocket1
        case .flamethrower, .flameTongue: return .flamer1
        case .chainGun, .m16, .m60mg: return .mgun2
        case .obeliskLaser: return .laser
        case .tomahawk, .towTwo: return .rocket1
        case .turretGun: return .turret
        case .rifle: return .sniper
        case .pistol: return .rifle
        case .grenade: return .toss
        case .chemspray: return .flamer1
        case .napalm: return .bomb1
        case .nike: return .rocket2
        case .w75mm, .w105mm, .w120mm: return .tank1
        case .w155mm: return .hvygun10
        default: return .tank1
        }
    }


    /// Get an explosion sound for a warhead type
    package func explosionSound(_ warhead: WarheadType) -> VocType {
        switch warhead {
        case .he: return .xplobig4
        case .ap: return .xplos
        case .fire: return .xplobig6
        case .laser: return .laser
        case .pb: return .xplobig7
        case .hollowPoint: return .xplode
        default: return .xplos
        }
    }


    /// Get an infantry death scream
    package func infantryDeathScream() -> VocType {
        let screams: [VocType] = [.scream1, .scream3, .scream4, .scream5, .scream6, .scream7, .scream10, .scream11, .scream12]
        return screams[Int.random(in: 0..<screams.count)]
    }

    /// Death cry: the commando's own yell (INFANTRY.CPP, VOC_RAMBO_YELL).
    package func deathScream(for obj: GameObject) -> VocType {
        obj.isCommando ? .ramboYell : infantryDeathScream()
    }
}
