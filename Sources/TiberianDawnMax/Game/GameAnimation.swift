import Foundation

// MARK: - Animation System
// Ported from Vanilla Conquer anim.h/anim.cpp/adata.cpp

// MARK: - Animation Type Data

struct AnimTypeData {
    let name: String
    let size: Int               // Maximum dimension (edge to edge)
    let biggest: Int            // Frame where animation is biggest
    let isNormalized: Bool      // Constant rate regardless of game speed
    let isWhiteTrans: Bool      // Uses white translucent table
    let isScorcher: Bool        // Leaves scorch mark
    let isCrater: Bool          // Forms a crater
    let isSticky: Bool          // Sticks to unit in square
    let isGroundLayer: Bool     // Ground level animation
    let isTranslucent: Bool     // Translucent colors
    let isFlame: Bool           // Flame thrower animation
    let damage: Int             // Damage per tick (0 = none)
    let delay: Int              // Delay between frames (ticks)
    let startFrame: Int         // Starting frame
    let loopStart: Int          // Loop start frame
    let loopEnd: Int            // Loop end frame (-1 = no loop)
    let stages: Int             // Total stages (-1 = auto from SHP)
    let loops: Int              // Number of loops (0 = play once)
    let chainTo: GameAnimType?  // Chain-to animation when done
}

// MARK: - Animation Type Enum

enum GameAnimType: String, CaseIterable {
    // Explosions
    case fball1 = "FBALL1"
    case grenade = "VEH-HIT2"    // Grenade/dirt explosion
    case frag1 = "FRAG1"
    case frag2 = "FRAG2"
    case vehHit1 = "VEH-HIT1"
    case vehHit2 = "FRAG3"
    case vehHit3 = "VEH-HIT3"
    case artExp1 = "ART-EXP1"

    // Napalm
    case napalm1 = "NAPALM1"
    case napalm2 = "NAPALM2"
    case napalm3 = "NAPALM3"

    // Impact piffs
    case piff = "PIFF"
    case piffpiff = "PIFFPIFF"
    case smokePuff = "SMOKEY"

    // Fire
    case fireSmall = "FIRE1"
    case fireMed = "FIRE2"
    case fireMed2 = "FIRE3"
    case fireTiny = "FIRE4"

    // Burning (with trail)
    case burnSmall = "BURN-S"
    case burnMed = "BURN-M"
    case burnBig = "BURN-L"

    // Building on fire
    case onFireSmall = "ONIFIRE1"
    case onFireMed = "ONIFIRE3"
    case onFireBig = "ONIFIRE2"

    // Smoke
    case smokeM = "SMOKE_M"

    // Muzzle flash
    case muzzleFlash = "MUZZFLSH"

    // Special weapons
    case ionCannon = "YOURPOW"
    case atomBlast = "YOURPOW2"

    // Landing zone / misc
    case lzSmoke = "LZ-SMOKE"
}

// MARK: - Animation Type Data Table

let animTypeDataTable: [GameAnimType: AnimTypeData] = [
    .fball1: AnimTypeData(
        name: "FBALL1", size: 67, biggest: 6,
        isNormalized: true, isWhiteTrans: false, isScorcher: false, isCrater: true,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .frag1: AnimTypeData(
        name: "FRAG1", size: 45, biggest: 3,
        isNormalized: true, isWhiteTrans: false, isScorcher: false, isCrater: true,
        isSticky: true, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .frag2: AnimTypeData(
        name: "FRAG2", size: 41, biggest: 3,
        isNormalized: true, isWhiteTrans: false, isScorcher: false, isCrater: true,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .vehHit1: AnimTypeData(
        name: "VEH-HIT1", size: 30, biggest: 3,
        isNormalized: true, isWhiteTrans: false, isScorcher: false, isCrater: false,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .vehHit2: AnimTypeData(
        name: "VEH-HIT2", size: 21, biggest: 1,
        isNormalized: true, isWhiteTrans: false, isScorcher: false, isCrater: false,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .vehHit3: AnimTypeData(
        name: "VEH-HIT3", size: 24, biggest: 2,
        isNormalized: true, isWhiteTrans: false, isScorcher: false, isCrater: false,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .artExp1: AnimTypeData(
        name: "ART-EXP1", size: 41, biggest: 1,
        isNormalized: true, isWhiteTrans: false, isScorcher: false, isCrater: true,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .napalm1: AnimTypeData(
        name: "NAPALM1", size: 21, biggest: 5,
        isNormalized: false, isWhiteTrans: false, isScorcher: true, isCrater: false,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .napalm2: AnimTypeData(
        name: "NAPALM2", size: 41, biggest: 5,
        isNormalized: false, isWhiteTrans: false, isScorcher: true, isCrater: false,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .napalm3: AnimTypeData(
        name: "NAPALM3", size: 78, biggest: 5,
        isNormalized: false, isWhiteTrans: false, isScorcher: true, isCrater: false,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .piff: AnimTypeData(
        name: "PIFF", size: 13, biggest: 1,
        isNormalized: true, isWhiteTrans: false, isScorcher: false, isCrater: false,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .piffpiff: AnimTypeData(
        name: "PIFFPIFF", size: 20, biggest: 2,
        isNormalized: true, isWhiteTrans: false, isScorcher: false, isCrater: false,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .fireSmall: AnimTypeData(
        name: "FIRE1", size: 23, biggest: 0,
        isNormalized: false, isWhiteTrans: false, isScorcher: false, isCrater: false,
        isSticky: false, isGroundLayer: true, isTranslucent: false, isFlame: false,
        damage: 8, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 2, chainTo: nil
    ),
    .fireMed: AnimTypeData(
        name: "FIRE2", size: 23, biggest: 0,
        isNormalized: false, isWhiteTrans: false, isScorcher: true, isCrater: false,
        isSticky: false, isGroundLayer: true, isTranslucent: false, isFlame: false,
        damage: 16, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 3, chainTo: nil
    ),
    .burnSmall: AnimTypeData(
        name: "BURN-S", size: 11, biggest: 13,
        isNormalized: false, isWhiteTrans: false, isScorcher: false, isCrater: false,
        isSticky: false, isGroundLayer: true, isTranslucent: false, isFlame: false,
        damage: 8, delay: 1, startFrame: 0, loopStart: 30, loopEnd: 62,
        stages: -1, loops: 4, chainTo: nil
    ),
    .burnMed: AnimTypeData(
        name: "BURN-M", size: 14, biggest: 13,
        isNormalized: false, isWhiteTrans: false, isScorcher: false, isCrater: false,
        isSticky: false, isGroundLayer: true, isTranslucent: false, isFlame: false,
        damage: 16, delay: 1, startFrame: 0, loopStart: 30, loopEnd: 62,
        stages: -1, loops: 4, chainTo: nil
    ),
    .burnBig: AnimTypeData(
        name: "BURN-L", size: 23, biggest: 13,
        isNormalized: false, isWhiteTrans: false, isScorcher: true, isCrater: false,
        isSticky: false, isGroundLayer: true, isTranslucent: false, isFlame: false,
        damage: 24, delay: 1, startFrame: 0, loopStart: 30, loopEnd: 62,
        stages: -1, loops: 4, chainTo: nil
    ),
    .smokeM: AnimTypeData(
        name: "SMOKE_M", size: 32, biggest: 72,
        isNormalized: true, isWhiteTrans: false, isScorcher: false, isCrater: false,
        isSticky: false, isGroundLayer: true, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 72, loopEnd: 91,
        stages: -1, loops: 127, chainTo: nil
    ),
    .ionCannon: AnimTypeData(
        name: "YOURPOW", size: 48, biggest: 11,
        isNormalized: false, isWhiteTrans: false, isScorcher: true, isCrater: true,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: 15, loops: 0, chainTo: .artExp1
    ),
    .atomBlast: AnimTypeData(
        name: "YOURPOW2", size: 72, biggest: 19,
        isNormalized: false, isWhiteTrans: false, isScorcher: true, isCrater: true,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 0, chainTo: nil
    ),
    .smokePuff: AnimTypeData(
        name: "SMOKEY", size: 24, biggest: 2,
        isNormalized: true, isWhiteTrans: false, isScorcher: false, isCrater: false,
        isSticky: false, isGroundLayer: false, isTranslucent: false, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: -1, loops: 1, chainTo: nil
    ),
    .muzzleFlash: AnimTypeData(
        name: "MUZZFLSH", size: 16, biggest: 0,
        isNormalized: true, isWhiteTrans: true, isScorcher: false, isCrater: false,
        isSticky: false, isGroundLayer: false, isTranslucent: true, isFlame: false,
        damage: 0, delay: 1, startFrame: 0, loopStart: 0, loopEnd: -1,
        stages: 10, loops: 0, chainTo: nil
    ),
]

// MARK: - Smudge System

enum SmudgeType: String, CaseIterable {
    case crater1 = "CR1"
    case crater2 = "CR2"
    case crater3 = "CR3"
    case crater4 = "CR4"
    case crater5 = "CR5"
    case crater6 = "CR6"
    case scorch1 = "SC1"
    case scorch2 = "SC2"
    case scorch3 = "SC3"
    case scorch4 = "SC4"
    case scorch5 = "SC5"
    case scorch6 = "SC6"

    var isCrater: Bool {
        switch self {
        case .crater1, .crater2, .crater3, .crater4, .crater5, .crater6:
            return true
        default:
            return false
        }
    }
}

struct Smudge {
    let type: SmudgeType
    let cell: Int
}

// Backward-compatible computed property — smudges now live in GameMap
var mapSmudges: [Smudge] {
    get { session.world?.map.smudges ?? [] }
    set { session.world?.map.smudges = newValue }
}

// MARK: - Animation Instance

class GameAnimation {
    let type: GameAnimType
    let data: AnimTypeData
    var worldX: Double
    var worldY: Double
    var currentFrame: Int
    var loopsRemaining: Int
    var delayCounter: Int       // Counts down between frames
    var isFinished: Bool = false
    var attachedToId: Int? = nil // Stick to a unit if isSticky

    init(type: GameAnimType, worldX: Double, worldY: Double) {
        self.type = type
        self.data = animTypeDataTable[type] ?? animTypeDataTable[.piff]!
        self.worldX = worldX
        self.worldY = worldY
        self.currentFrame = data.startFrame
        self.loopsRemaining = data.loops
        self.delayCounter = data.delay
    }
}

// MARK: - Animation Manager


/// Spawn a new animation at world coordinates
func spawnAnimation(_ type: GameAnimType, worldX: Double, worldY: Double) {
    let anim = GameAnimation(type: type, worldX: worldX, worldY: worldY)
    session.activeAnimations.append(anim)
}

/// Spawn animation attached to a game object
func spawnAnimationOn(_ type: GameAnimType, target: GameObject) {
    let anim = GameAnimation(type: type, worldX: target.worldX, worldY: target.worldY)
    if animTypeDataTable[type]?.isSticky == true {
        anim.attachedToId = target.id
    }
    session.activeAnimations.append(anim)
}

/// Tick all active animations
func tickAnimations() {
    guard let world = session.world else { return }

    for anim in session.activeAnimations {
        guard !anim.isFinished else { continue }

        // Update position for sticky anims
        if let targetId = anim.attachedToId,
           let target = world.findObject(id: targetId) {
            anim.worldX = target.worldX
            anim.worldY = target.worldY
        }

        // Frame delay
        anim.delayCounter -= 1
        if anim.delayCounter > 0 { continue }
        anim.delayCounter = anim.data.delay

        // Advance frame
        anim.currentFrame += 1

        // Check loop points
        if anim.data.loopEnd > 0 && anim.currentFrame >= anim.data.loopEnd {
            if anim.loopsRemaining > 0 {
                anim.loopsRemaining -= 1
                anim.currentFrame = anim.data.loopStart
            } else {
                anim.isFinished = true
            }
        }

        // Check total stages
        let maxStages = anim.data.stages > 0 ? anim.data.stages : 30  // Default max
        if anim.currentFrame >= maxStages {
            if anim.loopsRemaining > 0 && anim.data.loopEnd <= 0 {
                anim.loopsRemaining -= 1
                anim.currentFrame = anim.data.startFrame
            } else {
                anim.isFinished = true
            }
        }

        // Apply damage to objects in cell (fire animations)
        if anim.data.damage > 0 && world.tickCount % 4 == 0 {
            let cellX = Int(anim.worldX) / 24
            let cellY = Int(anim.worldY) / 24
            for obj in world.objects {
                if obj.strength <= 0 { continue }
                if obj.cellX == cellX && obj.cellY == cellY {
                    obj.applyDamage(amount: anim.data.damage)
                }
            }
        }
    }

    // Handle chain-to animations and smudges for finished anims
    var newAnims: [GameAnimation] = []
    for anim in session.activeAnimations {
        guard anim.isFinished else { continue }

        // Chain to next animation
        if let chainType = anim.data.chainTo {
            let chainAnim = GameAnimation(type: chainType, worldX: anim.worldX, worldY: anim.worldY)
            newAnims.append(chainAnim)
        }

        // Leave scorch mark
        if anim.data.isScorcher {
            let cellX = Int(anim.worldX) / 24
            let cellY = Int(anim.worldY) / 24
            if cellX >= 0 && cellX < 64 && cellY >= 0 && cellY < 64 {
                let scorchTypes: [SmudgeType] = [.scorch1, .scorch2, .scorch3, .scorch4, .scorch5, .scorch6]
                let smudge = Smudge(type: scorchTypes.randomElement()!, cell: cellY * 64 + cellX)
                session.world?.map.smudges.append(smudge)
            }
        }

        // Leave crater
        if anim.data.isCrater {
            let cellX = Int(anim.worldX) / 24
            let cellY = Int(anim.worldY) / 24
            if cellX >= 0 && cellX < 64 && cellY >= 0 && cellY < 64 {
                let craterTypes: [SmudgeType] = [.crater1, .crater2, .crater3, .crater4, .crater5, .crater6]
                let smudge = Smudge(type: craterTypes.randomElement()!, cell: cellY * 64 + cellX)
                session.world?.map.smudges.append(smudge)
            }
        }
    }

    // Remove finished animations, add chain animations
    session.activeAnimations.removeAll { $0.isFinished }
    session.activeAnimations.append(contentsOf: newAnims)
}

// MARK: - Death Animation Selection

/// Select the appropriate explosion animation based on warhead type
func explosionAnimForWarhead(_ warhead: WarheadType) -> GameAnimType {
    switch warhead {
    case .fire:     return .napalm1
    case .he:       return .fball1
    case .ap:       return .frag1
    case .laser:    return .napalm2
    case .pb:       return .napalm3
    default:        return .vehHit1
    }
}

// MARK: - Death Effects Extensions

extension GameObject {
    /// Spawn death effects for a destroyed unit
    func spawnDeathEffects() {
        switch kind {
        case .unit:
            // Vehicle destruction: fireball + smoke
            spawnAnimation(.fball1, worldX: worldX, worldY: worldY)
            // Offset secondary explosion
            spawnAnimation(.frag1,
                           worldX: worldX + Double.random(in: -8...8),
                           worldY: worldY + Double.random(in: -8...8))

        case .infantry:
            // Infantry death: small piff + optional fire
            if let lastWarhead = warheadThatKilled() {
                switch lastWarhead {
                case .fire, .laser, .pb:
                    spawnAnimation(.napalm1, worldX: worldX, worldY: worldY)
                case .he:
                    spawnAnimation(.artExp1, worldX: worldX, worldY: worldY)
                default:
                    spawnAnimation(.piff, worldX: worldX, worldY: worldY)
                }
            } else {
                spawnAnimation(.piff, worldX: worldX, worldY: worldY)
            }

        case .structure:
            // Building destruction: large fireball + fires + smoke
            let size = buildingSize(typeName)
            let halfW = Double(size.w * 24) / 2.0
            let halfH = Double(size.h * 24) / 2.0

            // Multiple explosion points across the building footprint
            for _ in 0..<(size.w * size.h) {
                let ox = Double.random(in: -halfW...halfW)
                let oy = Double.random(in: -halfH...halfH)
                spawnAnimation(.fball1, worldX: worldX + ox, worldY: worldY + oy)
            }
            // Lingering fire
            spawnAnimation(.burnBig, worldX: worldX, worldY: worldY)
        }
    }

    /// Determine what warhead killed this object (for death anim selection)
    func warheadThatKilled() -> WarheadType? {
        // Find the last attacker by searching world for objects targeting this one
        guard let world = session.world else { return nil }
        for other in world.objects {
            if other.attackTarget == id, let weapon = other.primaryWeapon,
               let wData = weaponTypeData[weapon] {
                return bulletTypeData[wData.fires]?.warhead
            }
        }
        return nil
    }
}

/// Spawn impact effects at a target location (bullet/weapon hit)
func spawnImpactEffect(at worldX: Double, worldY: Double, warhead: WarheadType) {
    switch warhead {
    case .sa, .hollowPoint:
        spawnAnimation(.piff, worldX: worldX, worldY: worldY)
    case .he:
        spawnAnimation(.vehHit1, worldX: worldX, worldY: worldY)
    case .ap:
        spawnAnimation(.vehHit2, worldX: worldX, worldY: worldY)
    case .fire:
        spawnAnimation(.napalm1, worldX: worldX, worldY: worldY)
    case .laser:
        spawnAnimation(.napalm2, worldX: worldX, worldY: worldY)
    case .pb:
        spawnAnimation(.napalm3, worldX: worldX, worldY: worldY)
    default:
        spawnAnimation(.piff, worldX: worldX, worldY: worldY)
    }
}
