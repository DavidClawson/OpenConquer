import Foundation
import OpenConquerAssets

// MARK: - Native asset import, headless
//
//   --extract-assets REMASTERED_DATA_DIR OUT_DATA_DIR [--cancel-after SECONDS]
//       run the in-app importer (OpenConquerAssets/Import) from the Remastered
//       Collection's Data/ folder into OUT_DATA_DIR/extracted/, printing
//       progress and per-step timings. Same output as install-assets.sh's
//       python steps 3-4 (minus the unread sprite sheets and classic WAVs).
//       --cancel-after exercises the cancel path (expects a "cancelled" FAIL).

/// Runs the import named on the command line, if any; nil otherwise.
func runImportDiagnosticsIfRequested() -> Int32? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--extract-assets") else { return nil }
    guard i + 2 < args.count else {
        print("usage: --extract-assets REMASTERED_DATA_DIR OUT_DATA_DIR [--cancel-after SECONDS]")
        return 2
    }
    let source = URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath)
    let dest = URL(fileURLWithPath: (args[i + 2] as NSString).expandingTildeInPath)
    let missing = missingRemasteredArchives(in: source)
    guard missing.isEmpty else {
        print("FAIL: \(source.path) is missing \(missing.joined(separator: ", "))")
        return 1
    }

    let cancelAfter = args.firstIndex(of: "--cancel-after").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil }
    let start = Date()
    var stepStart = start
    var lastStep: ImportStep?
    var lastPrinted = Date.distantPast
    do {
        let summary = try extractRemasteredAssets(remasteredData: source, dataDir: dest, progress: { p in
            if p.step != lastStep {
                if let lastStep { print(String(format: "  %@ done in %.1fs", lastStep.rawValue, Date().timeIntervalSince(stepStart))) }
                lastStep = p.step
                stepStart = Date()
                print("\(p.step.rawValue): \(p.total) items")
            }
            // Throttle to ~4 lines a second, plus the final item.
            if p.done == p.total || Date().timeIntervalSince(lastPrinted) > 0.25 {
                lastPrinted = Date()
                print("  [\(p.done)/\(p.total)] \(p.item)")
            }
        }, isCancelled: { cancelAfter.map { Date().timeIntervalSince(start) > $0 } ?? false })
        if let lastStep { print(String(format: "  %@ done in %.1fs", lastStep.rawValue, Date().timeIntervalSince(stepStart))) }
        for step in ImportStep.allCases { print("\(step.rawValue): wrote \(summary.written[step] ?? 0)") }
        if !summary.failures.isEmpty { print("not extracted (\(summary.failures.count)): \(summary.failures.joined(separator: ", "))") }
        print(String(format: "OK: import finished in %.1fs -> %@", Date().timeIntervalSince(start), dest.appendingPathComponent("extracted").path))
        return 0
    } catch {
        print("FAIL: \(error)")
        return 1
    }
}
