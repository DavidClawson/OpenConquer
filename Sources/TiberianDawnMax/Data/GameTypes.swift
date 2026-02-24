import Foundation

// MARK: - Unit Types
// Ported from Vanilla Conquer defines.h UnitType enum

enum UnitType: Int, CaseIterable {
    case htank = 0    // Heavy tank (Mammoth)
    case mtank        // Medium tank
    case ltank        // Light tank
    case stank        // Stealth tank
    case ftank        // Flame tank
    case vice         // Visceroid
    case apc          // APC
    case mlrs         // MLRS rocket launcher
    case jeep         // Humvee
    case buggy        // Nod buggy
    case harvester    // Harvester
    case arty         // Artillery
    case msam         // Mobile SAM (MLRS)
    case hover        // Hovercraft
    case mhq          // Mobile HQ
    case gunboat      // Gunboat
    case mcv          // Mobile Construction Vehicle
    case bike         // Nod recon bike
    case tric         // Triceratops
    case trex         // Tyrannosaurus Rex
    case rapt         // Velociraptor
    case steg         // Stegosaurus

    var iniName: String {
        switch self {
        case .htank:     return "HTNK"
        case .mtank:     return "MTNK"
        case .ltank:     return "LTNK"
        case .stank:     return "STNK"
        case .ftank:     return "FTNK"
        case .vice:      return "VICE"
        case .apc:       return "APC"
        case .mlrs:      return "MLRS"
        case .jeep:      return "JEEP"
        case .buggy:     return "BGGY"
        case .harvester: return "HARV"
        case .arty:      return "ARTY"
        case .msam:      return "MSAM"
        case .hover:     return "LST"
        case .mhq:       return "MHQ"
        case .gunboat:   return "BOAT"
        case .mcv:       return "MCV"
        case .bike:      return "BIKE"
        case .tric:      return "TRIC"
        case .trex:      return "TREX"
        case .rapt:      return "RAPT"
        case .steg:      return "STEG"
        }
    }

    static func from(iniName: String) -> UnitType? {
        let upper = iniName.uppercased()
        return UnitType.allCases.first { $0.iniName == upper }
    }
}

// MARK: - Infantry Types

enum InfantryType: Int, CaseIterable {
    case e1 = 0       // Minigunner
    case e2            // Grenadier
    case e3            // Rocket soldier
    case e4            // Flamethrower
    case e5            // Chem warrior
    case e7            // Engineer
    case rambo         // Commando
    case c1            // Civilian
    case c2
    case c3
    case c4
    case c5
    case c6
    case c7
    case c8
    case c9
    case c10           // Nikoomba
    case moebius       // Dr. Moebius
    case delphi        // Agent Delphi
    case chan           // Dr. Chan

    var iniName: String {
        switch self {
        case .e1:      return "E1"
        case .e2:      return "E2"
        case .e3:      return "E3"
        case .e4:      return "E4"
        case .e5:      return "E5"
        case .e7:      return "E6"  // VC uses "E6" as INI name for engineer
        case .rambo:   return "RMBO"
        case .c1:      return "C1"
        case .c2:      return "C2"
        case .c3:      return "C3"
        case .c4:      return "C4"
        case .c5:      return "C5"
        case .c6:      return "C6"
        case .c7:      return "C7"
        case .c8:      return "C8"
        case .c9:      return "C9"
        case .c10:     return "C10"
        case .moebius: return "MOEBIUS"
        case .delphi:  return "DELPHI"
        case .chan:     return "CHAN"
        }
    }

    static func from(iniName: String) -> InfantryType? {
        let upper = iniName.uppercased()
        return InfantryType.allCases.first { $0.iniName == upper }
    }
}

// MARK: - Structure Types

enum StructType: Int, CaseIterable {
    case weap = 0         // Weapons Factory
    case gtower           // Guard Tower
    case atower           // Advanced Guard Tower
    case obelisk          // Obelisk of Light
    case radar            // Communications Center
    case turret           // Gun Turret
    case const_           // Construction Yard
    case refinery         // Tiberium Refinery
    case storage          // Tiberium Silo
    case helipad          // Helipad
    case sam              // SAM Site
    case airstrip         // Airstrip
    case power            // Power Plant
    case advancedPower    // Advanced Power Plant
    case hospital         // Hospital
    case barracks         // Barracks (GDI)
    case tanker           // Tanker
    case repair           // Repair Facility
    case bioLab           // Bio Lab
    case hand             // Hand of Nod
    case temple           // Temple of Nod
    case eye              // Advanced Comm Center
    case mission          // Mission building
    // Civilian structures
    case v01, v02, v03, v04, v05, v06, v07, v08
    case v09, v10, v11, v12, v13, v14, v15, v16
    case v17, v18, v19, v20, v21, v22, v23, v24
    case v25, v26, v27, v28, v29, v30, v31, v32
    case v33, v34, v35, v36, v37
    // Walls
    case sandbagWall
    case cycloneWall
    case brickWall
    case barbwireWall
    case woodWall

    var iniName: String {
        switch self {
        case .weap:         return "WEAP"
        case .gtower:       return "GTWR"
        case .atower:       return "ATWR"
        case .obelisk:      return "OBLI"
        case .radar:        return "HQ"
        case .turret:       return "GUN"
        case .const_:       return "FACT"
        case .refinery:     return "PROC"
        case .storage:      return "SILO"
        case .helipad:      return "HPAD"
        case .sam:          return "SAM"
        case .airstrip:     return "AFLD"
        case .power:        return "NUKE"
        case .advancedPower: return "NUK2"
        case .hospital:     return "HOSP"
        case .barracks:     return "PYLE"
        case .tanker:       return "ARCO"
        case .repair:       return "FIX"
        case .bioLab:       return "BIO"
        case .hand:         return "HAND"
        case .temple:       return "TMPL"
        case .eye:          return "EYE"
        case .mission:      return "MISS"
        case .v01:          return "V01"
        case .v02:          return "V02"
        case .v03:          return "V03"
        case .v04:          return "V04"
        case .v05:          return "V05"
        case .v06:          return "V06"
        case .v07:          return "V07"
        case .v08:          return "V08"
        case .v09:          return "V09"
        case .v10:          return "V10"
        case .v11:          return "V11"
        case .v12:          return "V12"
        case .v13:          return "V13"
        case .v14:          return "V14"
        case .v15:          return "V15"
        case .v16:          return "V16"
        case .v17:          return "V17"
        case .v18:          return "V18"
        case .v19:          return "V19"
        case .v20:          return "V20"
        case .v21:          return "V21"
        case .v22:          return "V22"
        case .v23:          return "V23"
        case .v24:          return "V24"
        case .v25:          return "V25"
        case .v26:          return "V26"
        case .v27:          return "V27"
        case .v28:          return "V28"
        case .v29:          return "V29"
        case .v30:          return "V30"
        case .v31:          return "V31"
        case .v32:          return "V32"
        case .v33:          return "V33"
        case .v34:          return "V34"
        case .v35:          return "V35"
        case .v36:          return "V36"
        case .v37:          return "V37"
        case .sandbagWall:  return "SBAG"
        case .cycloneWall:  return "CYCL"
        case .brickWall:    return "BRIK"
        case .barbwireWall: return "BARB"
        case .woodWall:     return "WOOD"
        }
    }

    static func from(iniName: String) -> StructType? {
        let upper = iniName.uppercased()
        return StructType.allCases.first { $0.iniName == upper }
    }
}

// MARK: - Aircraft Types

enum AircraftType: Int, CaseIterable {
    case transport = 0   // Transport helicopter (Chinook)
    case a10             // A-10 ground attack
    case helicopter      // Apache/Orca
    case cargo           // Cargo plane (reinforcements)
    case orca            // Orca

    var iniName: String {
        switch self {
        case .transport:  return "TRAN"
        case .a10:        return "A10"
        case .helicopter: return "HELI"
        case .cargo:      return "C17"
        case .orca:       return "ORCA"
        }
    }

    static func from(iniName: String) -> AircraftType? {
        let upper = iniName.uppercased()
        return AircraftType.allCases.first { $0.iniName == upper }
    }
}

// MARK: - Weapon Types
// From const.cpp Weapons[] array

enum WeaponType: Int, CaseIterable {
    case rifle = 0         // Sniper rifle (Commando)
    case chainGun          // Chain gun (Guard Tower)
    case pistol            // Civilian pistol
    case m16               // M16 (Minigunner)
    case dragon            // Dragon TOW missile
    case flamethrower      // Flamethrower
    case flameTongue       // Flame tank weapon
    case chemspray         // Chemical spray
    case grenade           // Hand grenade
    case w75mm             // 75mm cannon (Light tank)
    case w105mm            // 105mm cannon (Medium tank)
    case w120mm            // 120mm cannon (Mammoth)
    case turretGun         // Gun turret weapon
    case mammothTusk       // Mammoth tusk missiles
    case mlrs              // MLRS rockets
    case w155mm            // 155mm (Artillery)
    case m60mg             // M60 machine gun (APC/Humvee)
    case tomahawk          // Tomahawk missile (Gunboat)
    case towTwo            // TOW Two (Adv Guard Tower)
    case napalm            // Napalm bomb (A-10)
    case obeliskLaser      // Obelisk laser
    case nike              // SAM missile
    case honestJohn        // Honest John SSM
    case steg              // Stegosaurus headbutt
    case trex              // T-Rex bite
}

// MARK: - Warhead Types

enum WarheadType: Int, CaseIterable {
    case sa = 0        // Small arms - good vs infantry
    case he            // High explosive - good vs buildings & infantry
    case ap            // Armor piercing - good vs armor
    case fire          // Incendiary - good vs flammables
    case laser         // Laser
    case pb            // Particle beam (neutron)
    case fist          // Punching
    case foot          // Kicking
    case hollowPoint   // Sniper bullet
    case spore         // Blossom tree spore
    case headbutt      // Dinosaur headbutt
    case feedme        // T-Rex bite
}

// MARK: - Bullet (Projectile) Types

enum BulletType: Int, CaseIterable {
    case sniper = 0    // Sniper bullet
    case bullet        // Small arms
    case apds          // Armor piercing
    case he            // High explosive shell
    case ssm           // Surface-to-surface missile
    case ssm2          // MLRS missile
    case sam           // SAM missile
    case tow           // TOW missile
    case flame         // Flame
    case chemspray     // Chemical spray
    case napalm        // Napalm bomblet
    case grenade       // Hand grenade
    case laser         // Laser beam
    case nukeUp        // Nuke going up
    case nukeDown      // Nuke coming down
    case honestJohn    // SSM with napalm warhead
    case spreadfire    // Chain gun bullets
    case headbutt      // Dino headbutt
    case trexBite      // T-Rex bite
}

// MARK: - Armor Types

enum ArmorType: Int, CaseIterable {
    case none = 0      // No armor (infantry)
    case wood          // Wood (buildings)
    case aluminum      // Aluminum (light vehicles)
    case steel         // Steel (heavy vehicles)
    case concrete      // Concrete (fortifications)

    static let count = 5
}

// MARK: - Speed (Locomotion) Types

enum SpeedType: Int, CaseIterable {
    case foot = 0      // Infantry
    case track         // Tracked vehicles
    case harvester     // Harvester
    case wheel         // Wheeled vehicles
    case winged        // Aircraft
    case hover         // Hovercraft
    case float_        // Ships
}

// MARK: - MPH Speed Values
// From VC defines.h — internal speed rating

enum MPHType: UInt8 {
    case immobile     = 0
    case verySlow     = 5
    case kindaSlow    = 6
    case slow         = 8
    case slowIsh      = 10
    case mediumSlow   = 12
    case medium       = 18
    case mediumFast   = 30
    case mediumFaster = 35
    case fast         = 40
    case rocket       = 60
    case veryFast     = 100
    case lightSpeed   = 255
}

// MARK: - Animation Types (subset — full list in AnimationData.swift)

enum AnimType: Int, CaseIterable {
    case none = -1
    case fball1 = 0     // Large fireball
    case grenade        // Grenade explosion
    case frag1          // Medium fragment - short decay
    case frag2          // Medium fragment - long decay
    case vehHit1        // Small fireball
    case vehHit2        // Small fragment
    case vehHit3        // Small fragment - burn mix
    case artExp1        // Large fragment
    case napalm1        // Small napalm
    case napalm2        // Medium napalm
    case napalm3        // Large napalm
    case smokePuff      // Rocket smoke trail
    case piff           // MG impact
    case piffpiff       // Chain gun impact
    case flameN         // Flame north
    case flameNE
    case flameE
    case flameSE
    case flameS
    case flameSW
    case flameW
    case flameNW
    case chemN          // Chem spray north
    case chemNE
    case chemE
    case chemSE
    case chemS
    case chemSW
    case chemW
    case chemNW
    case fireSmall      // Small fire
    case fireMed        // Medium fire
    case fireMed2       // Medium fire 2
    case fireTiny       // Tiny fire
    case muzzleFlash    // Muzzle flash
    case smokeMSmall    // Small smoke
    case smokeM         // Medium smoke
    case smokeMBig      // Big smoke
    case gunN           // Gun fire north
    case gunNE
    case gunE
    case gunSE
    case gunS
    case gunSW
    case gunW
    case gunNW
    case samN           // SAM fire animations
    case samNW
    case samW
    case samSW
    case samS
    case samSE
    case samE
    case samNE
    case lzSmoke
    case burnSmall
    case burnMed
    case burnBig
    case onFireSmall
    case onFireMed
    case onFireBig
    case oilfieldBurn
    case atomBomb       // Nuclear explosion
    case tricDie
    case trexDie
    case stegDie
    case raptDie
    case ionCannon      // Ion cannon beam
    case fireSmallVirtual
    case fireMedVirtual
    case fireMed2Virtual
}

// MARK: - Houses Type (matches VC HousesType)

enum HousesType: Int, CaseIterable {
    case good = 0      // GDI
    case bad           // Nod
    case neutral       // Civilian
    case jp            // Special/Japan
    case multi1
    case multi2
    case multi3
    case multi4
    case multi5
    case multi6
}

// MARK: - Mission Type (expanded from current)

enum MissionType: Int, CaseIterable {
    case sleep = 0
    case attack
    case move
    case retreat
    case guard_
    case sticky        // Guard, don't chase
    case enter
    case capture
    case harvest
    case guardArea
    case return_
    case stop
    case ambush
    case hunt
    case timedHunt
    case unload
    case sabotage
    case construction
    case deconstruction
    case repair
    case missile
    case none

    var displayName: String {
        switch self {
        case .sleep:           return "Sleep"
        case .attack:          return "Attack"
        case .move:            return "Move"
        case .retreat:         return "Retreat"
        case .guard_:          return "Guard"
        case .sticky:          return "Sticky"
        case .enter:           return "Enter"
        case .capture:         return "Capture"
        case .harvest:         return "Harvest"
        case .guardArea:       return "Area Guard"
        case .return_:         return "Return"
        case .stop:            return "Stop"
        case .ambush:          return "Ambush"
        case .hunt:            return "Hunt"
        case .timedHunt:       return "Timed Hunt"
        case .unload:          return "Unload"
        case .sabotage:        return "Sabotage"
        case .construction:    return "Construction"
        case .deconstruction:  return "Deconstruction"
        case .repair:          return "Repair"
        case .missile:         return "Missile"
        case .none:            return "None"
        }
    }

    /// Convert to the runtime Mission enum used by GameObject
    var toMission: Mission {
        switch self {
        case .sleep:          return .sleep
        case .attack:         return .attack
        case .move:           return .move
        case .retreat:        return .retreat
        case .guard_:         return .guard_
        case .sticky:         return .sticky
        case .enter:          return .enter
        case .capture:        return .capture
        case .harvest:        return .harvest
        case .guardArea:      return .guardArea
        case .return_:        return .return_
        case .stop:           return .stop
        case .ambush:         return .ambush
        case .hunt:           return .hunt
        case .timedHunt:      return .timedHunt
        case .unload:         return .unload
        case .sabotage:       return .guard_  // No runtime sabotage; fallback to guard
        case .construction:   return .construction
        case .deconstruction: return .deconstruction
        case .repair:         return .repair
        case .missile:        return .missile
        case .none:           return .guard_  // No runtime "none"; fallback to guard
        }
    }
}

extension Mission {
    /// Convert to the type-data MissionType enum (returns nil for missions not in MissionType)
    var toMissionType: MissionType? {
        switch self {
        case .sleep:          return .sleep
        case .attack:         return .attack
        case .move:           return .move
        case .retreat:        return .retreat
        case .guard_:         return .guard_
        case .sticky:         return .sticky
        case .enter:          return .enter
        case .capture:        return .capture
        case .harvest:        return .harvest
        case .guardArea:      return .guardArea
        case .return_:        return .return_
        case .stop:           return .stop
        case .ambush:         return .ambush
        case .hunt:           return .hunt
        case .timedHunt:      return .timedHunt
        case .unload:         return .unload
        case .construction:   return .construction
        case .deconstruction: return .deconstruction
        case .repair:         return .repair
        case .missile:        return .missile
        case .selling:        return nil  // No MissionType equivalent
        case .sabotage:       return nil  // No MissionType equivalent
        }
    }
}

// MARK: - Facing Type

enum FacingType: Int {
    case north = 0
    case northEast
    case east
    case southEast
    case south
    case southWest
    case west
    case northWest

    static let count = 8
}

// MARK: - Land Type (terrain movement categories)

enum LandType: Int, CaseIterable {
    case clear = 0
    case road
    case water
    case rock
    case wall
    case tiberium
    case beach
}

// MARK: - House Ownership Flags (for buildability)

struct HouseFlag: OptionSet {
    let rawValue: UInt16

    static let good   = HouseFlag(rawValue: 1 << 0)
    static let bad    = HouseFlag(rawValue: 1 << 1)
    static let neutral = HouseFlag(rawValue: 1 << 2)
    static let jp     = HouseFlag(rawValue: 1 << 3)
    static let multi1 = HouseFlag(rawValue: 1 << 4)
    static let multi2 = HouseFlag(rawValue: 1 << 5)
    static let multi3 = HouseFlag(rawValue: 1 << 6)
    static let multi4 = HouseFlag(rawValue: 1 << 7)
    static let multi5 = HouseFlag(rawValue: 1 << 8)
    static let multi6 = HouseFlag(rawValue: 1 << 9)

    static let allMulti: HouseFlag = [.multi1, .multi2, .multi3, .multi4, .multi5, .multi6]
    static let gdiAll: HouseFlag   = [.allMulti, .jp, .good]
    static let nodAll: HouseFlag   = [.allMulti, .jp, .bad]
    static let bothAll: HouseFlag  = [.allMulti, .jp, .good, .bad]
    static let civAll: HouseFlag   = [.allMulti, .jp, .good, .bad, .neutral]
}

// MARK: - Building prerequisite flags

struct StructFlag: OptionSet {
    let rawValue: UInt64

    static let none         = StructFlag([])
    static let weap         = StructFlag(rawValue: 1 << 0)
    static let gtower       = StructFlag(rawValue: 1 << 1)
    static let atower       = StructFlag(rawValue: 1 << 2)
    static let obelisk      = StructFlag(rawValue: 1 << 3)
    static let radar        = StructFlag(rawValue: 1 << 4)
    static let turret       = StructFlag(rawValue: 1 << 5)
    static let const_       = StructFlag(rawValue: 1 << 6)
    static let refinery     = StructFlag(rawValue: 1 << 7)
    static let storage      = StructFlag(rawValue: 1 << 8)
    static let helipad      = StructFlag(rawValue: 1 << 9)
    static let sam          = StructFlag(rawValue: 1 << 10)
    static let airstrip     = StructFlag(rawValue: 1 << 11)
    static let power        = StructFlag(rawValue: 1 << 12)
    static let advancedPower = StructFlag(rawValue: 1 << 13)
    static let hospital     = StructFlag(rawValue: 1 << 14)
    static let barracks     = StructFlag(rawValue: 1 << 15)  // Includes PYLE and HAND
    static let tanker       = StructFlag(rawValue: 1 << 16)
    static let repair       = StructFlag(rawValue: 1 << 17)
    static let bioLab       = StructFlag(rawValue: 1 << 18)
    static let hand         = StructFlag(rawValue: 1 << 19)
    static let temple       = StructFlag(rawValue: 1 << 20)
    static let eye          = StructFlag(rawValue: 1 << 21)
}

// MARK: - Type Lookup Helpers

/// Resolve any INI name (unit/infantry/building/aircraft) to its ObjectKind
func resolveObjectKind(iniName: String) -> ObjectKind? {
    let upper = iniName.uppercased()
    if UnitType.from(iniName: upper) != nil { return .unit }
    if AircraftType.from(iniName: upper) != nil { return .unit }  // Aircraft use unit kind
    if InfantryType.from(iniName: upper) != nil { return .infantry }
    if StructType.from(iniName: upper) != nil { return .structure }
    return nil
}
