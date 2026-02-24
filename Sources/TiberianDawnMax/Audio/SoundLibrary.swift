import Foundation

// MARK: - Sound Library
// Manages loading and caching of decoded audio.
// Prefers extracted WAV files, falls back to AUD decode from MIX.

class SoundLibrary {
    let assetManager: AssetManager

    struct DecodedAudio {
        let samples: [Int16]
        let sampleRate: Int
        var duration: Double {
            guard sampleRate > 0 else { return 0 }
            return Double(samples.count) / Double(sampleRate)
        }
        let source: AudioSource
    }

    enum AudioSource: String {
        case remasteredWav = "WAV-HD"
        case wav = "WAV"
        case aud = "AUD"
        case none = "N/A"
    }

    private var cache: [String: DecodedAudio] = [:]

    init(assetManager: AssetManager) {
        self.assetManager = assetManager
    }

    /// Load a sound by name (without extension).
    /// Tries WAV from extracted/ first, then AUD from MIX archives.
    func load(_ name: String) -> DecodedAudio? {
        let key = name.uppercased()
        if let cached = cache[key] { return cached }

        // Try WAV first (remastered, then classic extracted)
        if let wav = assetManager.loadWAV(key) {
            let source: AudioSource = wav.remastered ? .remasteredWav : .wav
            let audio = DecodedAudio(samples: wav.samples, sampleRate: wav.sampleRate, source: source)
            cache[key] = audio
            return audio
        }

        // Fall back to AUD decode from MIX
        let audName = "\(key).AUD"
        if let data = assetManager.mixManager.retrieve(audName),
           let decoded = decodeAUD(Data(data)) {
            let audio = DecodedAudio(samples: decoded.samples, sampleRate: decoded.sampleRate, source: .aud)
            cache[key] = audio
            return audio
        }

        // Try VC voice variation extensions (.V00-.V03)
        for ext in [".V00", ".V01", ".V02", ".V03"] {
            if let data = assetManager.mixManager.retrieve("\(key)\(ext)"),
               let decoded = decodeAUD(Data(data)) {
                let audio = DecodedAudio(samples: decoded.samples, sampleRate: decoded.sampleRate, source: .aud)
                cache[key] = audio
                return audio
            }
        }

        return nil
    }

    /// Clear cache
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Sound Categories (for Sound Test screen)

    struct SoundEntry {
        let id: String    // filename without extension
        let label: String // human-readable description
    }

    struct SoundCategory {
        let name: String
        let sounds: [SoundEntry]
    }

    static let categories: [SoundCategory] = [
        SoundCategory(name: "UNIT RESPONSES", sounds: [
            SoundEntry(id: "ACKNO", label: "Acknowledge"),
            SoundEntry(id: "AFFIRM1", label: "Affirmative"),
            SoundEntry(id: "AWAIT1", label: "Awaiting Orders"),
            SoundEntry(id: "MOVOUT1", label: "Move Out"),
            SoundEntry(id: "NEGATV1", label: "Negative"),
            SoundEntry(id: "NOPROB", label: "No Problem"),
            SoundEntry(id: "READY", label: "Ready"),
            SoundEntry(id: "REPORT1", label: "Reporting"),
            SoundEntry(id: "RITAWAY", label: "Right Away"),
            SoundEntry(id: "ROGER", label: "Roger"),
            SoundEntry(id: "UGOTIT", label: "You Got It"),
            SoundEntry(id: "UNIT1", label: "Unit Ready"),
            SoundEntry(id: "VEHIC1", label: "Vehicle Ready"),
            SoundEntry(id: "YESSIR1", label: "Yes Sir"),
            SoundEntry(id: "2DANGR1", label: "Danger"),
            SoundEntry(id: "GIRLOKAY", label: "Girl Okay"),
            SoundEntry(id: "GIRLYEAH", label: "Girl Yeah"),
            SoundEntry(id: "GUYOKAY1", label: "Guy Okay"),
            SoundEntry(id: "GUYYEAH1", label: "Guy Yeah"),
        ]),
        SoundCategory(name: "COMMANDO", sounds: [
            SoundEntry(id: "BOMBIT1", label: "Present"),
            SoundEntry(id: "CMON1", label: "C'mon"),
            SoundEntry(id: "KEEPEM1", label: "Keep Em Comin'"),
            SoundEntry(id: "LAUGH1", label: "Laugh"),
            SoundEntry(id: "LEFTY1", label: "Lefty"),
            SoundEntry(id: "NOPRBLM1", label: "No Problem"),
            SoundEntry(id: "ONIT1", label: "On It"),
            SoundEntry(id: "RAMYELL1", label: "Yell"),
            SoundEntry(id: "ROKROLL1", label: "Rock & Roll"),
            SoundEntry(id: "TUFFGUY1", label: "Tough Guy"),
            SoundEntry(id: "YEAH1", label: "Yeah"),
            SoundEntry(id: "YES1", label: "Yes"),
            SoundEntry(id: "YO1", label: "Yo"),
        ]),
        SoundCategory(name: "WEAPONS", sounds: [
            SoundEntry(id: "BAZOOK1", label: "Bazooka"),
            SoundEntry(id: "GUN18", label: "Rifle"),
            SoundEntry(id: "GUN19", label: "Machine Gun"),
            SoundEntry(id: "GUN20", label: "Gun"),
            SoundEntry(id: "GUN5", label: "M60"),
            SoundEntry(id: "GUN8", label: "Minigun"),
            SoundEntry(id: "GUNCLIP1", label: "Reload"),
            SoundEntry(id: "FLAMER2", label: "Flamethrower"),
            SoundEntry(id: "HVYGUN10", label: "Heavy Gun"),
            SoundEntry(id: "ION1", label: "Ion Cannon"),
            SoundEntry(id: "MGUN11", label: "Machine Gun 2"),
            SoundEntry(id: "MGUN2", label: "Machine Gun 3"),
            SoundEntry(id: "NUKEMISL", label: "Nuke Launch"),
            SoundEntry(id: "OBELRAY1", label: "Obelisk Laser"),
            SoundEntry(id: "OBELPOWR", label: "Obelisk Power"),
            SoundEntry(id: "RAMGUN2", label: "Sniper"),
            SoundEntry(id: "ROCKET1", label: "Rocket 1"),
            SoundEntry(id: "ROCKET2", label: "Rocket 2"),
            SoundEntry(id: "SAMMOTR2", label: "SAM Motor"),
            SoundEntry(id: "TNKFIRE2", label: "Tank Fire 1"),
            SoundEntry(id: "TNKFIRE3", label: "Tank Fire 2"),
            SoundEntry(id: "TNKFIRE4", label: "Tank Fire 3"),
            SoundEntry(id: "TNKFIRE6", label: "Tank Fire 4"),
            SoundEntry(id: "TOSS1", label: "Grenade Toss"),
            SoundEntry(id: "TURRFIR5", label: "Turret Fire"),
        ]),
        SoundCategory(name: "EXPLOSIONS", sounds: [
            SoundEntry(id: "XPLOBIG4", label: "Big Explosion 1"),
            SoundEntry(id: "XPLOBIG6", label: "Big Explosion 2"),
            SoundEntry(id: "XPLOBIG7", label: "Big Explosion 3"),
            SoundEntry(id: "XPLODE", label: "Explosion"),
            SoundEntry(id: "XPLOS", label: "Small Explosion 1"),
            SoundEntry(id: "XPLOSML2", label: "Small Explosion 2"),
            SoundEntry(id: "NUKEXPLO", label: "Nuke Explosion"),
            SoundEntry(id: "BOMB1", label: "Bomb"),
            SoundEntry(id: "CRUMBLE", label: "Crumble"),
        ]),
        SoundCategory(name: "SCREAMS", sounds: [
            SoundEntry(id: "NUYELL1", label: "Scream 1"),
            SoundEntry(id: "NUYELL3", label: "Scream 3"),
            SoundEntry(id: "NUYELL4", label: "Scream 4"),
            SoundEntry(id: "NUYELL5", label: "Scream 5"),
            SoundEntry(id: "NUYELL6", label: "Scream 6"),
            SoundEntry(id: "NUYELL7", label: "Scream 7"),
            SoundEntry(id: "NUYELL10", label: "Scream 10"),
            SoundEntry(id: "NUYELL11", label: "Scream 11"),
            SoundEntry(id: "NUYELL12", label: "Scream 12"),
            SoundEntry(id: "YELL1", label: "Yell"),
            SoundEntry(id: "SQUISH2", label: "Squish"),
        ]),
        SoundCategory(name: "UI SOUNDS", sounds: [
            SoundEntry(id: "BLEEP2", label: "Bleep"),
            SoundEntry(id: "BUTTON", label: "Button"),
            SoundEntry(id: "COMCNTR1", label: "Radar On"),
            SoundEntry(id: "POWRDN1", label: "Radar Off"),
            SoundEntry(id: "CONSTRU2", label: "Construction"),
            SoundEntry(id: "HVYDOOR1", label: "Heavy Door"),
            SoundEntry(id: "SCOLD2", label: "Scold"),
            SoundEntry(id: "SIDBAR1C", label: "Sidebar Open"),
            SoundEntry(id: "SIDBAR2C", label: "Sidebar Close"),
            SoundEntry(id: "TONE15", label: "Tone Up"),
            SoundEntry(id: "TONE16", label: "Tone Down"),
            SoundEntry(id: "TONE2", label: "Target"),
            SoundEntry(id: "TONE5", label: "Sonar"),
            SoundEntry(id: "TRANS1", label: "Cloak"),
            SoundEntry(id: "TREEBRN1", label: "Tree Burn"),
            SoundEntry(id: "CASHTURN", label: "Cash Turn"),
            SoundEntry(id: "BEACON", label: "Beacon"),
        ]),
        SoundCategory(name: "EVA SPEECH", sounds: [
            SoundEntry(id: "ACCOM1", label: "Accomplished"),
            SoundEntry(id: "FAIL1", label: "Mission Failed"),
            SoundEntry(id: "BLDG1", label: "No Factory"),
            SoundEntry(id: "CONSTRU1", label: "Construction"),
            SoundEntry(id: "UNITREDY", label: "Unit Ready"),
            SoundEntry(id: "NEWOPT1", label: "New Construction"),
            SoundEntry(id: "DEPLOY1", label: "Deploy"),
            SoundEntry(id: "NOCASH1", label: "Insufficient Funds"),
            SoundEntry(id: "REINFOR1", label: "Reinforcements"),
            SoundEntry(id: "CANCEL1", label: "Canceled"),
            SoundEntry(id: "BLDGING1", label: "Building"),
            SoundEntry(id: "LOPOWER1", label: "Low Power"),
            SoundEntry(id: "NOPOWER1", label: "No Power"),
            SoundEntry(id: "MOCASH1", label: "Need More Cash"),
            SoundEntry(id: "BASEATK1", label: "Base Under Attack"),
            SoundEntry(id: "INCOME1", label: "Incoming Missile"),
            SoundEntry(id: "NOBUILD1", label: "Unable to Build"),
            SoundEntry(id: "PRIBLDG1", label: "Primary Selected"),
            SoundEntry(id: "IONCHRG1", label: "Ion Charging"),
            SoundEntry(id: "IONREDY1", label: "Ion Ready"),
            SoundEntry(id: "NUKAVAIL", label: "Nuke Available"),
            SoundEntry(id: "NUKLNCH1", label: "Nuke Launched"),
            SoundEntry(id: "UNITLOST", label: "Unit Lost"),
            SoundEntry(id: "STRCLOST", label: "Structure Lost"),
            SoundEntry(id: "NEEDHARV", label: "Need Harvester"),
            SoundEntry(id: "SELECT1", label: "Select Target"),
            SoundEntry(id: "AIRREDY1", label: "Airstrike Ready"),
            SoundEntry(id: "REPAIR1", label: "Repairing"),
        ]),
        SoundCategory(name: "MUSIC THEMES", sounds: [
            SoundEntry(id: "AOI", label: "Act On Instinct"),
            SoundEntry(id: "CCTHANG", label: "C&C Thang"),
            SoundEntry(id: "DIE", label: "Die!!"),
            SoundEntry(id: "FWP", label: "Fight Win Prevail"),
            SoundEntry(id: "IND", label: "Industrial"),
            SoundEntry(id: "IND2", label: "Industrial 2"),
            SoundEntry(id: "JUSTDOIT", label: "Just Do It!"),
            SoundEntry(id: "LINEFIRE", label: "In The Line Of Fire"),
            SoundEntry(id: "MARCH", label: "March To Your Doom"),
            SoundEntry(id: "NOMERCY", label: "No Mercy"),
            SoundEntry(id: "OTP", label: "On The Prowl"),
            SoundEntry(id: "PRP", label: "Prepare For Battle"),
            SoundEntry(id: "ROUT", label: "Reaching Out"),
            SoundEntry(id: "STOPTHEM", label: "Stop Them"),
            SoundEntry(id: "TROUBLE", label: "Looks Like Trouble"),
            SoundEntry(id: "WARFARE", label: "Warfare"),
            SoundEntry(id: "BFEARED", label: "Enemies To Be Feared"),
        ]),
    ]
}
