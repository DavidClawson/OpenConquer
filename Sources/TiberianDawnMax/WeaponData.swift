import Foundation

// MARK: - Weapon Type Data
// Ported faithfully from Vanilla Conquer const.cpp Weapons[] array
// Structure: bullet type, damage (0-255), ROF (ticks), range (leptons), sound placeholder, muzzle anim

struct WeaponTypeData {
    let fires: BulletType
    let damage: Int
    let rof: Int           // Rate of fire in game ticks
    let range: Int         // Range in leptons (VC internal units)
    let anim: AnimType     // Muzzle flash animation

    /// Range converted to pixels (leptons / 256 * 24)
    var rangeInPixels: Double {
        return Double(range) / 256.0 * 24.0
    }

    /// Range in cells
    var rangeInCells: Int {
        return range / 256
    }
}

let weaponTypeData: [WeaponType: WeaponTypeData] = [
    //                               bullet            dmg  rof  range   anim
    .rifle:        WeaponTypeData(fires: .sniper,       damage: 125, rof: 40, range: 0x0580, anim: .none),
    .chainGun:     WeaponTypeData(fires: .spreadfire,   damage: 25,  rof: 50, range: 0x0400, anim: .gunN),
    .pistol:       WeaponTypeData(fires: .bullet,       damage: 1,   rof: 7,  range: 0x01C0, anim: .none),
    .m16:          WeaponTypeData(fires: .bullet,       damage: 15,  rof: 20, range: 0x0200, anim: .none),
    .dragon:       WeaponTypeData(fires: .tow,          damage: 30,  rof: 60, range: 0x0400, anim: .none),
    .flamethrower: WeaponTypeData(fires: .flame,        damage: 35,  rof: 50, range: 0x0200, anim: .flameN),
    .flameTongue:  WeaponTypeData(fires: .flame,        damage: 50,  rof: 50, range: 0x0200, anim: .flameN),
    .chemspray:    WeaponTypeData(fires: .chemspray,    damage: 80,  rof: 70, range: 0x0200, anim: .chemN),
    .grenade:      WeaponTypeData(fires: .grenade,      damage: 50,  rof: 60, range: 0x0340, anim: .none),
    .w75mm:        WeaponTypeData(fires: .apds,         damage: 25,  rof: 60, range: 0x0400, anim: .muzzleFlash),
    .w105mm:       WeaponTypeData(fires: .apds,         damage: 30,  rof: 50, range: 0x04C0, anim: .muzzleFlash),
    .w120mm:       WeaponTypeData(fires: .apds,         damage: 40,  rof: 80, range: 0x04C0, anim: .muzzleFlash),
    .turretGun:    WeaponTypeData(fires: .apds,         damage: 40,  rof: 60, range: 0x0600, anim: .muzzleFlash),
    .mammothTusk:  WeaponTypeData(fires: .ssm,          damage: 75,  rof: 80, range: 0x0500, anim: .none),
    .mlrs:         WeaponTypeData(fires: .ssm2,         damage: 75,  rof: 80, range: 0x0600, anim: .none),
    .w155mm:       WeaponTypeData(fires: .he,           damage: 150, rof: 65, range: 0x0600, anim: .muzzleFlash),
    .m60mg:        WeaponTypeData(fires: .bullet,       damage: 15,  rof: 30, range: 0x0400, anim: .gunN),
    .tomahawk:     WeaponTypeData(fires: .ssm,          damage: 60,  rof: 35, range: 0x0780, anim: .none),
    .towTwo:       WeaponTypeData(fires: .ssm,          damage: 60,  rof: 40, range: 0x0680, anim: .none),
    .napalm:       WeaponTypeData(fires: .napalm,       damage: 100, rof: 20, range: 0x0480, anim: .none),
    .obeliskLaser: WeaponTypeData(fires: .laser,        damage: 200, rof: 90, range: 0x0780, anim: .none),
    .nike:         WeaponTypeData(fires: .sam,           damage: 50,  rof: 50, range: 0x0780, anim: .none),
    .honestJohn:   WeaponTypeData(fires: .honestJohn,   damage: 100, rof: 200, range: 0x0A00, anim: .none),
    .steg:         WeaponTypeData(fires: .headbutt,     damage: 100, rof: 30, range: 0x0180, anim: .none),
    .trex:         WeaponTypeData(fires: .trexBite,     damage: 155, rof: 30, range: 0x0180, anim: .none),
]

// MARK: - Warhead Type Data
// Ported from const.cpp Warheads[] array
// Armor modifier values are fixed-point: 0x100 = 1.0x, 0x80 = 0.5x, etc.

struct WarheadTypeData {
    let spreadFactor: Int
    let isWallDestroyer: Bool
    let isWoodDestroyer: Bool
    let isTiberiumDestroyer: Bool
    /// Damage modifier per armor type [none, wood, aluminum, steel, concrete]
    /// Values are fixed-point with 0x100 = 1.0
    let modifiers: [Int]

    /// Get damage modifier for a given armor type as a Double
    func modifier(for armor: ArmorType) -> Double {
        guard armor.rawValue < modifiers.count else { return 1.0 }
        return Double(modifiers[armor.rawValue]) / 256.0
    }
}

let warheadTypeData: [WarheadType: WarheadTypeData] = [
    //                                                        spread  wall   wood   tib    none   wood   alum   steel  conc
    .sa:          WarheadTypeData(spreadFactor: 2,   isWallDestroyer: false, isWoodDestroyer: false, isTiberiumDestroyer: false, modifiers: [0x100, 0x80,  0x90,  0x40,  0x40]),
    .he:          WarheadTypeData(spreadFactor: 6,   isWallDestroyer: true,  isWoodDestroyer: true,  isTiberiumDestroyer: true,  modifiers: [0xE0,  0xC0,  0x90,  0x40,  0x100]),
    .ap:          WarheadTypeData(spreadFactor: 6,   isWallDestroyer: true,  isWoodDestroyer: true,  isTiberiumDestroyer: false, modifiers: [0x40,  0xC0,  0xC0,  0x100, 0x80]),
    .fire:        WarheadTypeData(spreadFactor: 8,   isWallDestroyer: false, isWoodDestroyer: true,  isTiberiumDestroyer: true,  modifiers: [0xE0,  0x100, 0xB0,  0x40,  0x80]),
    .laser:       WarheadTypeData(spreadFactor: 4,   isWallDestroyer: false, isWoodDestroyer: false, isTiberiumDestroyer: false, modifiers: [0x100, 0x100, 0x100, 0x100, 0x100]),
    .pb:          WarheadTypeData(spreadFactor: 7,   isWallDestroyer: true,  isWoodDestroyer: true,  isTiberiumDestroyer: true,  modifiers: [0x100, 0x100, 0xC0,  0xC0,  0xC0]),
    .fist:        WarheadTypeData(spreadFactor: 4,   isWallDestroyer: false, isWoodDestroyer: false, isTiberiumDestroyer: false, modifiers: [0x100, 0x20,  0x20,  0x10,  0x10]),
    .foot:        WarheadTypeData(spreadFactor: 4,   isWallDestroyer: false, isWoodDestroyer: false, isTiberiumDestroyer: false, modifiers: [0x100, 0x20,  0x20,  0x10,  0x10]),
    .hollowPoint: WarheadTypeData(spreadFactor: 4,   isWallDestroyer: false, isWoodDestroyer: false, isTiberiumDestroyer: false, modifiers: [0x100, 0x08,  0x08,  0x08,  0x08]),
    .spore:       WarheadTypeData(spreadFactor: 255, isWallDestroyer: false, isWoodDestroyer: false, isTiberiumDestroyer: false, modifiers: [0x100, 0x01,  0x01,  0x01,  0x01]),
    .headbutt:    WarheadTypeData(spreadFactor: 1,   isWallDestroyer: true,  isWoodDestroyer: true,  isTiberiumDestroyer: false, modifiers: [0x100, 0xC0,  0x80,  0x20,  0x08]),
    .feedme:      WarheadTypeData(spreadFactor: 1,   isWallDestroyer: true,  isWoodDestroyer: true,  isTiberiumDestroyer: false, modifiers: [0x100, 0xC0,  0x80,  0x20,  0x08]),
]

// MARK: - Bullet Type Data
// Ported from bbdata.cpp BulletTypeClass constructors

struct BulletTypeData {
    let iniName: String
    let isHigh: Bool            // Flies over tall walls
    let isHoming: Bool          // Homes in on target
    let isArcing: Bool          // Arcs to target
    let isDropping: Bool        // Dropping bomb
    let isInvisible: Bool       // No visible projectile
    let isProximityArmed: Bool  // Explodes near target
    let isFlameEquipped: Bool   // Flickering flame
    let isFueled: Bool          // Can run out of fuel
    let isFaceless: Bool        // No visual facing difference
    let isInaccurate: Bool      // Inherently inaccurate
    let isTranslucent: Bool     // Translucent colors
    let isAntiAircraft: Bool    // Good against aircraft
    let arming: Int             // Ticks to arm after launch
    let range: Int              // Override range factor
    let maxSpeed: MPHType       // Speed
    let rot: Int                // Rate of turn (degrees/tick)
    let warhead: WarheadType    // Warhead type
    let explosion: AnimType     // Impact animation
}

let bulletTypeData: [BulletType: BulletTypeData] = [
    .sniper: BulletTypeData(
        iniName: "SNIPER", isHigh: true, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: true, isProximityArmed: false, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 0, range: 0, maxSpeed: .lightSpeed, rot: 0, warhead: .hollowPoint, explosion: .none
    ),
    .bullet: BulletTypeData(
        iniName: "50CAL", isHigh: false, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: true, isProximityArmed: false, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 0, range: 0, maxSpeed: .lightSpeed, rot: 0, warhead: .sa, explosion: .none
    ),
    .apds: BulletTypeData(
        iniName: "120MM", isHigh: true, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: false, isProximityArmed: false, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 0, range: 0, maxSpeed: .veryFast, rot: 0, warhead: .ap, explosion: .artExp1
    ),
    .he: BulletTypeData(
        iniName: "120MM", isHigh: true, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: false, isProximityArmed: false, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: true, isTranslucent: false, isAntiAircraft: false,
        arming: 0, range: 0, maxSpeed: .mediumFast, rot: 0, warhead: .he, explosion: .artExp1
    ),
    .ssm: BulletTypeData(
        iniName: "MISSILE", isHigh: true, isHoming: true, isArcing: false, isDropping: false,
        isInvisible: false, isProximityArmed: true, isFlameEquipped: true, isFueled: true,
        isFaceless: false, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 10, range: 0, maxSpeed: .fast, rot: 10, warhead: .he, explosion: .frag1
    ),
    .ssm2: BulletTypeData(
        iniName: "MISSILE", isHigh: true, isHoming: true, isArcing: false, isDropping: false,
        isInvisible: false, isProximityArmed: true, isFlameEquipped: true, isFueled: true,
        isFaceless: false, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 10, range: 0, maxSpeed: .fast, rot: 10, warhead: .he, explosion: .frag2
    ),
    .sam: BulletTypeData(
        iniName: "MISSILE", isHigh: true, isHoming: true, isArcing: false, isDropping: false,
        isInvisible: false, isProximityArmed: true, isFlameEquipped: true, isFueled: true,
        isFaceless: false, isInaccurate: false, isTranslucent: false, isAntiAircraft: true,
        arming: 0, range: 0, maxSpeed: .veryFast, rot: 20, warhead: .ap, explosion: .vehHit1
    ),
    .tow: BulletTypeData(
        iniName: "DRAGON", isHigh: true, isHoming: true, isArcing: false, isDropping: false,
        isInvisible: false, isProximityArmed: true, isFlameEquipped: true, isFueled: true,
        isFaceless: false, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 8, range: 0, maxSpeed: .mediumFast, rot: 5, warhead: .ap, explosion: .vehHit1
    ),
    .flame: BulletTypeData(
        iniName: "FLAME", isHigh: false, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: false, isProximityArmed: false, isFlameEquipped: true, isFueled: true,
        isFaceless: true, isInaccurate: false, isTranslucent: true, isAntiAircraft: false,
        arming: 12, range: 12, maxSpeed: .mediumFast, rot: 0, warhead: .fire, explosion: .none
    ),
    .chemspray: BulletTypeData(
        iniName: "CHEM", isHigh: false, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: false, isProximityArmed: false, isFlameEquipped: true, isFueled: true,
        isFaceless: true, isInaccurate: false, isTranslucent: true, isAntiAircraft: false,
        arming: 12, range: 12, maxSpeed: .mediumFast, rot: 0, warhead: .he, explosion: .none
    ),
    .napalm: BulletTypeData(
        iniName: "BOMBLET", isHigh: true, isHoming: false, isArcing: false, isDropping: true,
        isInvisible: false, isProximityArmed: false, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: false, isTranslucent: true, isAntiAircraft: false,
        arming: 24, range: 24, maxSpeed: .mediumSlow, rot: 0, warhead: .fire, explosion: .napalm2
    ),
    .grenade: BulletTypeData(
        iniName: "BOMB", isHigh: true, isHoming: false, isArcing: true, isDropping: false,
        isInvisible: false, isProximityArmed: false, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: true, isTranslucent: true, isAntiAircraft: false,
        arming: 0, range: 0, maxSpeed: .mediumSlow, rot: 0, warhead: .he, explosion: .vehHit2
    ),
    .laser: BulletTypeData(
        iniName: "Laser", isHigh: true, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: true, isProximityArmed: false, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 0, range: 0, maxSpeed: .lightSpeed, rot: 0, warhead: .laser, explosion: .none
    ),
    .nukeUp: BulletTypeData(
        iniName: "ATOMICUP", isHigh: true, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: false, isProximityArmed: true, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 0, range: 0, maxSpeed: .veryFast, rot: 0, warhead: .he, explosion: .frag1
    ),
    .nukeDown: BulletTypeData(
        iniName: "ATOMICDN", isHigh: true, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: false, isProximityArmed: true, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 0, range: 0, maxSpeed: .veryFast, rot: 0, warhead: .he, explosion: .atomBomb
    ),
    .honestJohn: BulletTypeData(
        iniName: "MISSILE", isHigh: true, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: false, isProximityArmed: true, isFlameEquipped: true, isFueled: true,
        isFaceless: false, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 10, range: 0, maxSpeed: .fast, rot: 10, warhead: .fire, explosion: .napalm3
    ),
    .spreadfire: BulletTypeData(
        iniName: "50CAL", isHigh: false, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: true, isProximityArmed: false, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: true, isTranslucent: false, isAntiAircraft: false,
        arming: 0, range: 0, maxSpeed: .lightSpeed, rot: 0, warhead: .sa, explosion: .none
    ),
    .headbutt: BulletTypeData(
        iniName: "GORE", isHigh: false, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: true, isProximityArmed: false, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 0, range: 0, maxSpeed: .lightSpeed, rot: 0, warhead: .headbutt, explosion: .none
    ),
    .trexBite: BulletTypeData(
        iniName: "CHEW", isHigh: false, isHoming: false, isArcing: false, isDropping: false,
        isInvisible: true, isProximityArmed: false, isFlameEquipped: false, isFueled: false,
        isFaceless: true, isInaccurate: false, isTranslucent: false, isAntiAircraft: false,
        arming: 0, range: 0, maxSpeed: .lightSpeed, rot: 0, warhead: .feedme, explosion: .none
    ),
]

// MARK: - Ground Movement Speed Table
// From const.cpp Ground[] array
// Speed values: 0x00=impassable, 0x40=slow, 0x70=medium, 0xA0=medium-fast, 0xC0=fast, 0xFF=max

struct GroundTypeData {
    let color: Int
    /// Speed modifiers per SpeedType: [foot, track, harvester, wheel, winged, hover, float]
    let speeds: [UInt8]
    let isBuildable: Bool
}

let groundData: [LandType: GroundTypeData] = [
    .clear:    GroundTypeData(color: 66,  speeds: [0x70, 0x70, 0x70, 0xA0, 0xFF, 0xC0, 0x00], isBuildable: true),
    .road:     GroundTypeData(color: 68,  speeds: [0xC0, 0xA0, 0xA0, 0xA0, 0xFF, 0xC0, 0x00], isBuildable: true),
    .water:    GroundTypeData(color: 0,   speeds: [0x00, 0x00, 0x00, 0x00, 0xFF, 0xC0, 0xFF], isBuildable: false),
    .rock:     GroundTypeData(color: 0,   speeds: [0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00], isBuildable: false),
    .wall:     GroundTypeData(color: 0,   speeds: [0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00], isBuildable: false),
    .tiberium: GroundTypeData(color: 143, speeds: [0x70, 0x70, 0x70, 0xA0, 0xFF, 0xC0, 0x00], isBuildable: false),
    .beach:    GroundTypeData(color: 66,  speeds: [0x70, 0x70, 0x70, 0xA0, 0xFF, 0xC0, 0x00], isBuildable: false),
]

// MARK: - Damage Calculation (VC's Modify_Damage)

/// Apply warhead modifier against armor, then distance falloff.
/// Returns modified damage amount (always at least 1 if incoming > 0).
func modifyDamage(_ baseDamage: Int, warhead: WarheadType, armor: ArmorType, distance: Int = 0) -> Int {
    guard baseDamage > 0 else { return 0 }
    guard let whData = warheadTypeData[warhead] else { return baseDamage }

    // Apply armor modifier
    var damage = Double(baseDamage) * whData.modifier(for: armor)

    // Apply distance falloff via spread factor
    if distance > 0 && whData.spreadFactor > 0 {
        let falloff = max(0.0, 1.0 - Double(distance) / (Double(whData.spreadFactor) * 24.0))
        damage *= falloff
    }

    // Minimum 1 damage if any was incoming
    let result = Int(damage)
    return max(1, result)
}

// MARK: - Lookup Helpers

/// Get weapon data for a weapon type
func getWeaponData(_ weapon: WeaponType) -> WeaponTypeData? {
    return weaponTypeData[weapon]
}

/// Get warhead data for a warhead type
func getWarheadData(_ warhead: WarheadType) -> WarheadTypeData? {
    return warheadTypeData[warhead]
}

/// Get the warhead for a given weapon
func getWeaponWarhead(_ weapon: WeaponType) -> WarheadType? {
    guard let wData = weaponTypeData[weapon],
          let bData = bulletTypeData[wData.fires] else { return nil }
    return bData.warhead
}
