import Foundation

// MARK: - Asset Manager
// Wraps MIXFileManager with extracted-file-first loading.
// Checks extracted/ directory for pre-converted assets (WAV, PNG, etc.)
// before falling back to MIX archive lookup.

class AssetManager {
    let dataPath: URL
    let extractedPath: URL
    let mixManager: MIXFileManager

    init(dataPath: URL) {
        self.dataPath = dataPath
        self.extractedPath = dataPath.appendingPathComponent("extracted")
        self.mixManager = MIXFileManager()
    }

    // MARK: - Initialization

    /// Register MIX files and sub-archives (replaces loadGameData body)
    func initialize() {
        print("Loading game data from: \(dataPath.path)")

        do {
            try mixManager.registerAll(in: dataPath)

            let gdiDir = dataPath.appendingPathComponent("gdi")
            let nodDir = dataPath.appendingPathComponent("nod")
            if FileManager.default.fileExists(atPath: gdiDir.path) {
                try mixManager.registerAll(in: gdiDir)
            }
            if FileManager.default.fileExists(atPath: nodDir.path) {
                try mixManager.registerAll(in: nodDir)
            }
        } catch {
            print("Error loading MIX files: \(error)")
        }

        print("Total MIX files: \(mixManager.registeredFiles.count)")
        print("Total entries: \(mixManager.totalEntries)")

        let subArchives = ["SOUNDS.MIX", "SPEECH.MIX", "SCORES.MIX", "GENERAL.MIX", "CONQUER.MIX"]
        for sub in subArchives {
            mixManager.registerSubArchive(sub)
        }
        // Theater MIX files contain theater-specific sprites (tiberium TI1-TI12,
        // smudges CR1-CR6/SC1-SC6, building damage frames, etc.)
        // These are nested inside GENERAL.MIX in the original game data.
        let theaterArchives = ["TEMPERAT.MIX", "DESERT.MIX", "WINTER.MIX"]
        for sub in theaterArchives {
            mixManager.registerSubArchive(sub)
        }
        print("Total entries after sub-archives: \(mixManager.totalEntries)")

        if hasRemasteredAudio {
            print("Found remastered audio: \(extractedRemasteredAudioPath.path)")
        }
        if hasExtractedAudio {
            print("Found extracted audio: \(extractedAudioPath.path)")
        }
        print("")
    }

    // MARK: - Asset Retrieval

    /// Retrieve asset data: checks extracted/ first, then MIX archives
    func retrieve(_ filename: String) -> Data? {
        // Check extracted directory for loose files
        let upper = filename.uppercased()
        let loosePath = extractedPath.appendingPathComponent(subdirectory(for: upper))
            .appendingPathComponent(upper)
        if FileManager.default.fileExists(atPath: loosePath.path) {
            return try? Data(contentsOf: loosePath)
        }

        // Fall back to MIX archives
        return mixManager.retrieve(filename)
    }

    /// Check if an asset exists in extracted/ or MIX archives
    func contains(_ filename: String) -> Bool {
        let upper = filename.uppercased()
        let loosePath = extractedPath.appendingPathComponent(subdirectory(for: upper))
            .appendingPathComponent(upper)
        if FileManager.default.fileExists(atPath: loosePath.path) {
            return true
        }
        return mixManager.contains(filename)
    }

    // MARK: - Audio-specific

    var extractedAudioPath: URL {
        extractedPath.appendingPathComponent("audio")
    }

    var extractedRemasteredAudioPath: URL {
        extractedPath.appendingPathComponent("audio_remastered")
    }

    /// Check if extracted audio directory exists and has files
    var hasExtractedAudio: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: extractedAudioPath.path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Check if remastered audio directory exists
    var hasRemasteredAudio: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: extractedRemasteredAudioPath.path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Load a WAV file, checking remastered/ first, then extracted/audio/.
    /// Returns PCM samples + sample rate + whether it came from remastered.
    /// WAV must be 16-bit PCM mono.
    func loadWAV(_ name: String) -> (samples: [Int16], sampleRate: Int, remastered: Bool)? {
        let wavName = name.uppercased().hasSuffix(".WAV") ? name.uppercased() : "\(name.uppercased()).WAV"

        // Try remastered audio first
        let remasteredPath = extractedRemasteredAudioPath.appendingPathComponent(wavName)
        if let data = try? Data(contentsOf: remasteredPath),
           let result = parseWAV(data) {
            return (result.samples, result.sampleRate, true)
        }

        // Fall back to classic extracted audio
        let classicPath = extractedAudioPath.appendingPathComponent(wavName)
        if let data = try? Data(contentsOf: classicPath),
           let result = parseWAV(data) {
            return (result.samples, result.sampleRate, false)
        }

        return nil
    }

    // MARK: - WAV Parser

    /// Parse a standard RIFF WAV file (16-bit PCM) into samples
    private func parseWAV(_ data: Data) -> (samples: [Int16], sampleRate: Int)? {
        guard data.count >= 44 else { return nil }

        // RIFF header check
        guard data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46 else { return nil } // "RIFF"
        guard data[8] == 0x57, data[9] == 0x41, data[10] == 0x56, data[11] == 0x45 else { return nil } // "WAVE"

        // fmt chunk
        guard data[12] == 0x66, data[13] == 0x6D, data[14] == 0x74, data[15] == 0x20 else { return nil } // "fmt "

        let fmtSize = Int(data[16]) | (Int(data[17]) << 8) | (Int(data[18]) << 16) | (Int(data[19]) << 24)
        let audioFormat = Int(data[20]) | (Int(data[21]) << 8)
        guard audioFormat == 1 else { return nil } // PCM only

        let channels = Int(data[22]) | (Int(data[23]) << 8)
        let sampleRate = Int(data[24]) | (Int(data[25]) << 8) | (Int(data[26]) << 16) | (Int(data[27]) << 24)
        let bitsPerSample = Int(data[34]) | (Int(data[35]) << 8)

        guard bitsPerSample == 16 else { return nil }

        // Find data chunk (skip past fmt chunk)
        var offset = 20 + fmtSize
        while offset + 8 < data.count {
            let chunkID = String(bytes: [data[offset], data[offset+1], data[offset+2], data[offset+3]], encoding: .ascii)
            let chunkSize = Int(data[offset+4]) | (Int(data[offset+5]) << 8) | (Int(data[offset+6]) << 16) | (Int(data[offset+7]) << 24)
            offset += 8

            if chunkID == "data" {
                let sampleCount = min(chunkSize, data.count - offset) / (2 * channels)
                var samples = [Int16]()
                samples.reserveCapacity(sampleCount)

                var i = offset
                for _ in 0..<sampleCount {
                    if i + 1 >= data.count { break }
                    let sample = Int16(bitPattern: UInt16(data[i]) | (UInt16(data[i + 1]) << 8))
                    samples.append(sample)
                    i += 2 * channels  // skip extra channels if stereo
                }
                return (samples, sampleRate)
            }

            offset += chunkSize
        }

        return nil
    }

    // MARK: - Helpers

    /// Determine subdirectory for a file extension
    private func subdirectory(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.uppercased()
        switch ext {
        case "WAV", "AUD": return "audio"
        case "PNG", "SHP": return "sprites"
        default: return ""
        }
    }
}
