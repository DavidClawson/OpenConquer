import Foundation
import OpenConquerAssets
#if canImport(VideoToolbox)
import CoreImage
import CoreVideo
import VideoToolbox
#endif

// MARK: - Movie frame enhancement
//
// The "Enhanced" movie mode: each decoded VQA frame goes through Apple's
// low-latency super-resolution scaler (VideoToolbox, macOS 26+) before it is
// shown. It runs on the user's machine against their own movies; nothing
// upscaled is stored or shipped. Elsewhere the mode falls back to Smooth.
// Findings and the (parked) high-quality scaler: docs/ROADMAP.md, Phase 4.

/// An upscaled frame: BGRA bytes, `bytesPerRow` apart.
struct EnhancedFrame {
    let pixels: [UInt8]
    let width: Int
    let height: Int
    let bytesPerRow: Int
}

protocol MovieFrameEnhancer: AnyObject {
    func enhance(_ frame: VQAFrame) -> EnhancedFrame?
}

/// Whether this Mac can run the enhanced movie mode.
var movieEnhancementAvailable: Bool {
    #if canImport(VideoToolbox)
    if #available(macOS 26.0, *) {
        return VTLowLatencySuperResolutionScalerConfiguration.isSupported
    }
    #endif
    return false
}

/// An enhancer for `width`x`height` movies, or nil if unsupported here.
func makeMovieFrameEnhancer(width: Int, height: Int) -> MovieFrameEnhancer? {
    #if canImport(VideoToolbox)
    if #available(macOS 26.0, *), movieEnhancementAvailable {
        return LowLatencySuperResolution(width: width, height: height)
    }
    #endif
    return nil
}

#if canImport(VideoToolbox)
@available(macOS 26.0, *)
private final class LowLatencySuperResolution: MovieFrameEnhancer {
    private let width: Int
    private let height: Int
    private let scale: Int
    private let processor = VTFrameProcessor()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let bgraIn: CVPixelBuffer
    private let source: CVPixelBuffer
    private let destination: CVPixelBuffer
    private let bgraOut: CVPixelBuffer
    private var frameIndex: Int64 = 0
    private var failed = false

    init?(width: Int, height: Int) {
        let factors = VTLowLatencySuperResolutionScalerConfiguration
            .supportedScaleFactors(frameWidth: width, frameHeight: height)
        // The largest whole factor on offer, 4x for TD's 320x156/200 movies.
        guard let factor = factors.filter({ $0 == $0.rounded() && $0 <= 4 }).max() else { return nil }
        let config = VTLowLatencySuperResolutionScalerConfiguration(
            frameWidth: width, frameHeight: height, scaleFactor: factor)
        self.width = width
        self.height = height
        self.scale = Int(factor)
        do {
            try processor.startSession(configuration: config)
        } catch {
            print("Movie: super-resolution session failed: \(error)")
            return nil
        }
        // The scaler wants buffers built from its own attributes (padding,
        // pixel format); plain BGRA buffers fail with -19730.
        guard let src = Self.buffer(width, height, attributes: config.sourcePixelBufferAttributes),
              let dst = Self.buffer(width * Int(factor), height * Int(factor),
                                    attributes: config.destinationPixelBufferAttributes),
              let inB = Self.buffer(width, height, format: kCVPixelFormatType_32BGRA),
              let outB = Self.buffer(width * Int(factor), height * Int(factor),
                                     format: kCVPixelFormatType_32BGRA) else { return nil }
        source = src
        destination = dst
        bgraIn = inB
        bgraOut = outB
    }

    deinit { processor.endSession() }

    func enhance(_ frame: VQAFrame) -> EnhancedFrame? {
        guard !failed, frame.width == width, frame.height == height else { return nil }

        // Palette-expand straight into the BGRA input buffer.
        CVPixelBufferLockBaseAddress(bgraIn, [])
        if let base = CVPixelBufferGetBaseAddress(bgraIn)?.assumingMemoryBound(to: UInt8.self) {
            let rowBytes = CVPixelBufferGetBytesPerRow(bgraIn)
            frame.palette.withUnsafeBufferPointer { pal in
                frame.pixels.withUnsafeBufferPointer { px in
                    for y in 0..<height {
                        let row = base + y * rowBytes
                        for x in 0..<width {
                            let p = Int(px[y * width + x]) * 3
                            row[x * 4] = pal[p + 2]
                            row[x * 4 + 1] = pal[p + 1]
                            row[x * 4 + 2] = pal[p]
                            row[x * 4 + 3] = 255
                        }
                    }
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(bgraIn, [])
        ciContext.render(CIImage(cvPixelBuffer: bgraIn), to: source)

        let pts = CMTime(value: frameIndex, timescale: 15)
        frameIndex += 1
        guard let sf = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: pts),
              let df = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: pts) else { return nil }
        let params = VTLowLatencySuperResolutionScalerParameters(sourceFrame: sf, destinationFrame: df)

        // The render loop is synchronous; wait for this one frame.
        let done = DispatchSemaphore(value: 0)
        var processError: Error?
        processor.process(parameters: params) { _, error in
            processError = error
            done.signal()
        }
        done.wait()
        if let processError {
            print("Movie: super-resolution failed, falling back to Smooth: \(processError)")
            failed = true
            return nil
        }

        ciContext.render(CIImage(cvPixelBuffer: destination), to: bgraOut)
        CVPixelBufferLockBaseAddress(bgraOut, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(bgraOut, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(bgraOut) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(bgraOut)
        let outH = height * scale
        let bytes = [UInt8](UnsafeRawBufferPointer(start: base, count: rowBytes * outH))
        return EnhancedFrame(pixels: bytes, width: width * scale, height: outH, bytesPerRow: rowBytes)
    }

    private static func buffer(_ w: Int, _ h: Int, attributes base: [String: Any]) -> CVPixelBuffer? {
        var attrs = base
        let format = (attrs[kCVPixelBufferPixelFormatTypeKey as String] as? NSNumber)?.uint32Value
            ?? kCVPixelFormatType_32BGRA
        for key in [kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferWidthKey, kCVPixelBufferHeightKey] {
            attrs.removeValue(forKey: key as String)
        }
        attrs[kCVPixelBufferIOSurfacePropertiesKey as String] = [:] as [String: Any]
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, format, attrs as CFDictionary, &pb)
        return pb
    }

    private static func buffer(_ w: Int, _ h: Int, format: OSType) -> CVPixelBuffer? {
        buffer(w, h, attributes: [kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: format)])
    }
}
#endif
