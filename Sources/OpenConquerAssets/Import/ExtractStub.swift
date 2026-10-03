import Foundation

// TEMPORARY: stands in for the Swift extractor port (being written on another
// branch) so the importer UI can be built and tested. Replaced at merge.

package enum ImportStep: String { case classicAudio, hdSprites, hdUI, hdAudio }

package struct ImportProgress {
    package let step: ImportStep
    package let done: Int
    package let total: Int
    package let item: String
}

package func extractRemasteredAssets(remasteredData: URL, dataDir: URL,
                                     progress: @escaping (ImportProgress) -> Void,
                                     isCancelled: () -> Bool) throws {}
