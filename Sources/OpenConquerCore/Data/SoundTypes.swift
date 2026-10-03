import Foundation

// Sound effect and EVA speech identifiers, with their archive file names.
// Pure data: the simulation names sounds, the audio engine plays them.

// MARK: - Sound Effect Types (VOC)

package enum VocType: Int, CaseIterable {
    case none = -1

    // Commando/Rambo responses
    case ramboPresent = 0
    case ramboCmon
    case ramboUgotit
    case ramboComin
    case ramboLaugh
    case ramboLefty
    case ramboNoprob
    case ramboOnit
    case ramboYell
    case ramboRock
    case ramboTuff
    case ramboYea
    case ramboYes
    case ramboYo

    // Civilian
    case girlOkay
    case girlYeah
    case guyOkay
    case guyYeah

    // Unit responses
    case danger
    case acknowl
    case affirm
    case await_
    case moveout
    case negative
    case noProb
    case ready
    case report
    case rightAway
    case roger
    case ugotit
    case unit_
    case vehic
    case yessir

    // Weapon sounds
    case bazooka
    case bleep
    case bomb1
    case button
    case radarOn
    case construction
    case crumble
    case flamer1
    case rifle
    case m60
    case gun20
    case m60a
    case mini
    case reload
    case slam
    case hvygun10
    case ionCannon
    case mgun11
    case mgun2
    case nukeFire
    case nukeExplode
    case laser
    case laserPower
    case radarOff
    case sniper
    case rocket1
    case rocket2
    case motor
    case scold
    case sidebarOpen
    case sidebarClose
    case squish2
    case tank1
    case tank2
    case tank3
    case tank4
    case up
    case down
    case target
    case sonar
    case toss
    case cloak
    case burn
    case turret
    case xplobig4
    case xplobig6
    case xplobig7
    case xplode
    case xplos
    case xplosml2

    // Infantry screams
    case scream1
    case scream3
    case scream4
    case scream5
    case scream6
    case scream7
    case scream10
    case scream11
    case scream12
    case yell1

    // EVA/Advisor
    case yes_
    case commander
    case hello
    case hmmm

    // Special
    case cashturn
    case beacon

    /// Filename (without extension) used to look up the AUD file in MIX archives
    package var filename: String {
        switch self {
        case .none: return ""
        case .ramboPresent: return "BOMBIT1" // VC TD commando — "I've got a present for ya"
        case .ramboCmon: return "CMON1"
        case .ramboUgotit: return "GOTIT1" // commando "you got it" (distinct from unit UGOTIT)
        case .ramboComin: return "KEEPEM1" // "keep 'em comin'"
        case .ramboLaugh: return "LAUGH1"
        case .ramboLefty: return "LEFTY1"
        case .ramboNoprob: return "NOPRBLM1"
        case .ramboOnit: return "ONIT1"
        case .ramboYell: return "RAMYELL1"
        case .ramboRock: return "ROKROLL1"
        case .ramboTuff: return "TUFFGUY1"
        case .ramboYea: return "YEAH1"
        case .ramboYes: return "YES1"
        case .ramboYo: return "YO1"
        case .girlOkay: return "GIRLOKAY"
        case .girlYeah: return "GIRLYEAH"
        case .guyOkay: return "GUYOKAY1"
        case .guyYeah: return "GUYYEAH1"
        case .danger: return "2DANGR1"
        case .acknowl: return "ACKNO"
        case .affirm: return "AFFIRM1"
        case .await_: return "AWAIT1"
        case .moveout: return "MOVOUT1"
        case .negative: return "NEGATV1"
        case .noProb: return "NOPROB"
        case .ready: return "READY"
        case .report: return "REPORT1"
        case .rightAway: return "RITAWAY"
        case .roger: return "ROGER"
        case .ugotit: return "UGOTIT"
        case .unit_: return "UNIT1"
        case .vehic: return "VEHIC1"
        case .yessir: return "YESSIR1"
        case .bazooka: return "BAZOOK1"
        case .bleep: return "BLEEP2"
        case .bomb1: return "BOMB1"
        case .button: return "BUTTON"
        case .radarOn: return "COMCNTR1"
        case .construction: return "CONSTRU2"
        case .crumble: return "CRUMBLE"
        case .flamer1: return "FLAMER2"
        case .rifle: return "GUN18"
        case .m60: return "GUN19"
        case .gun20: return "GUN20"
        case .m60a: return "GUN5"
        case .mini: return "GUN8"
        case .reload: return "GUNCLIP1"
        case .slam: return "HVYDOOR1"
        case .hvygun10: return "HVYGUN10"
        case .ionCannon: return "ION1"
        case .mgun11: return "MGUN11"
        case .mgun2: return "MGUN2"
        case .nukeFire: return "NUKEMISL"
        case .nukeExplode: return "NUKEXPLO"
        case .laser: return "OBELRAY1"
        case .laserPower: return "OBELPOWR"
        case .radarOff: return "POWRDN1"
        case .sniper: return "RAMGUN2"
        case .rocket1: return "ROCKET1"
        case .rocket2: return "ROCKET2"
        case .motor: return "SAMMOTR2"
        case .scold: return "SCOLD2"
        case .sidebarOpen: return "SIDBAR1C"
        case .sidebarClose: return "SIDBAR2C"
        case .squish2: return "SQUISH2"
        case .tank1: return "TNKFIRE2"
        case .tank2: return "TNKFIRE3"
        case .tank3: return "TNKFIRE4"
        case .tank4: return "TNKFIRE6"
        case .up: return "TONE15"
        case .down: return "TONE16"
        case .target: return "TONE2"
        case .sonar: return "TONE5"
        case .toss: return "TOSS1"
        case .cloak: return "TRANS1"
        case .burn: return "TREEBRN1"
        case .turret: return "TURRFIR5"
        case .xplobig4: return "XPLOBIG4"
        case .xplobig6: return "XPLOBIG6"
        case .xplobig7: return "XPLOBIG7"
        case .xplode: return "XPLODE"
        case .xplos: return "XPLOS"
        case .xplosml2: return "XPLOSML2"
        case .scream1: return "NUYELL1"
        case .scream3: return "NUYELL3"
        case .scream4: return "NUYELL4"
        case .scream5: return "NUYELL5"
        case .scream6: return "NUYELL6"
        case .scream7: return "NUYELL7"
        case .scream10: return "NUYELL10"
        case .scream11: return "NUYELL11"
        case .scream12: return "NUYELL12"
        case .yell1: return "YELL1"
        case .yes_: return "MYES1"
        case .commander: return "MCOMND1"
        case .hello: return "MHELLO1"
        case .hmmm: return "MHMMM1"
        case .cashturn: return "CASHTURN"
        case .beacon: return "BEACON"
        }
    }
}

// MARK: - EVA Speech Types (VOX)

package enum VoxType: Int, CaseIterable {
    case none = -1
    case accomplished = 0
    case fail
    case noFactory
    case construction
    case unitReady
    case newConstruct
    case deploy
    case deadGDI
    case deadNod
    case deadCiv
    case noCash
    case controlExit
    case reinforcements
    case canceled
    case building
    case lowPower
    case noPower
    case needMoMoney
    case baseUnderAttack
    case incomingMissile
    case enemyPlanes
    case incomingNuke
    case unableToBuild
    case primarySelected
    case nodCaptured
    case gdiCaptured
    case ionCharging
    case ionReady
    case nukeAvailable
    case nukeLaunched
    case unitLost
    case structureLost
    case needHarvester
    case selectTarget
    case airstrikeReady
    case notReady
    case transportSighted
    case transportLoaded
    case prepare
    case needMoCapacity
    case suspended
    case repairing
    case enemyStructure
    case gdiStructure
    case nodStructure
    case enemyUnit

    package var filename: String {
        switch self {
        case .none: return ""
        case .accomplished: return "ACCOM1"
        case .fail: return "FAIL1"
        case .noFactory: return "BLDG1"
        case .construction: return "CONSTRU1"
        case .unitReady: return "UNITREDY"
        case .newConstruct: return "NEWOPT1"
        case .deploy: return "DEPLOY1"
        case .deadGDI: return "GDIDEAD1"
        case .deadNod: return "NODDEAD1"
        case .deadCiv: return "CIVDEAD1"
        case .noCash: return "NOCASH1"
        case .controlExit: return "BATLCON1"
        case .reinforcements: return "REINFOR1"
        case .canceled: return "CANCEL1"
        case .building: return "BLDGING1"
        case .lowPower: return "LOPOWER1"
        case .noPower: return "NOPOWER1"
        case .needMoMoney: return "MOCASH1"
        case .baseUnderAttack: return "BASEATK1"
        case .incomingMissile: return "INCOME1"
        case .enemyPlanes: return "ENEMYA"
        case .incomingNuke: return "NUKE1"
        case .unableToBuild: return "NOBUILD1"
        case .primarySelected: return "PRIBLDG1"
        case .nodCaptured: return "NODCAPT1"
        case .gdiCaptured: return "GDICAPT1"
        case .ionCharging: return "IONCHRG1"
        case .ionReady: return "IONREDY1"
        case .nukeAvailable: return "NUKAVAIL"
        case .nukeLaunched: return "NUKLNCH1"
        case .unitLost: return "UNITLOST"
        case .structureLost: return "STRCLOST"
        case .needHarvester: return "NEEDHARV"
        case .selectTarget: return "SELECT1"
        case .airstrikeReady: return "AIRREDY1"
        case .notReady: return "NOREDY1"
        case .transportSighted: return "TRANSSEE"
        case .transportLoaded: return "TRANLOAD"
        case .prepare: return "ENMYAPP1"
        case .needMoCapacity: return "SILOS1"
        case .suspended: return "ONHOLD1"
        case .repairing: return "REPAIR1"
        case .enemyStructure: return "ESTRUCX"
        case .gdiStructure: return "GSTRUC1"
        case .nodStructure: return "NSTRUC1"
        case .enemyUnit: return "ENMYUNIT"
        }
    }
}
