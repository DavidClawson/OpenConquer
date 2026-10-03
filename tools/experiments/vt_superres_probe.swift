// Experiment: Apple's VideoToolbox super-resolution scalers (macOS 26+) on movie frames.
// Not part of the build. See docs/ROADMAP.md (Phase 4, movie upscaling) for findings.
//
//   swiftc -O tools/experiments/vt_superres_probe.swift -o /tmp/vtsr
//   /tmp/vtsr probe                         # capabilities + model status
//   /tmp/vtsr ll <inDir> <outDir> 4         # low-latency scaler (works)
//   /tmp/vtsr sr <inDir> <outDir> 4         # high-quality scaler (outputs zeros as of macOS 27.0.1)
//   SR_IMAGE=1 /tmp/vtsr sr ...             # high-quality scaler in image mode
//
// Input frames: e.g. `ffmpeg -i GDI1.VQA -frames:v 90 in/%04d.png`.
import Foundation
import VideoToolbox
import CoreVideo
import CoreImage
import ImageIO
import UniformTypeIdentifiers

func fourcc(_ v: OSType) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "\(v)"
}

let args = CommandLine.arguments
let ctx = CIContext()

func loadCG(_ url: URL) -> CGImage {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

var srcAttrs: [String: Any] = [:], dstAttrs: [String: Any] = [:]
func makeBuffer(w: Int, h: Int, format: OSType, attrs base: [String: Any]) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    var attrs = base
    attrs[kCVPixelBufferIOSurfacePropertiesKey as String] = [:]
    attrs.removeValue(forKey: kCVPixelBufferWidthKey as String)
    attrs.removeValue(forKey: kCVPixelBufferHeightKey as String)
    let fmt = (attrs[kCVPixelBufferPixelFormatTypeKey as String] as? NSNumber)?.uint32Value ?? format
    attrs.removeValue(forKey: kCVPixelBufferPixelFormatTypeKey as String)
    let r = CVPixelBufferCreate(nil, w, h, fmt, attrs as CFDictionary, &pb)
    if r != 0 { print("CVPixelBufferCreate failed", r) }
    return pb!
}

func writePNG(_ pb: CVPixelBuffer, _ url: URL) {
    let ci = CIImage(cvPixelBuffer: pb)
    let cg = ctx.createCGImage(ci, from: ci.extent)!
    let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, cg, nil)
    CGImageDestinationFinalize(dst)
}

if args[1] == "probe" {
    print("SR supported:", VTSuperResolutionScalerConfiguration.isSupported)
    print("SR scale factors:", VTSuperResolutionScalerConfiguration.supportedScaleFactors)
    print("LL supported:", VTLowLatencySuperResolutionScalerConfiguration.isSupported)
    print("LL min/max dims:", VTLowLatencySuperResolutionScalerConfiguration.minimumDimensions,
          VTLowLatencySuperResolutionScalerConfiguration.maximumDimensions)
    for (w, h) in [(320, 156), (640, 312), (640, 480)] {
        print("LL scale factors for \(w)x\(h):",
              VTLowLatencySuperResolutionScalerConfiguration.supportedScaleFactors(frameWidth: w, frameHeight: h))
    }
    for s in VTSuperResolutionScalerConfiguration.supportedScaleFactors {
        if let c = VTSuperResolutionScalerConfiguration(frameWidth: 320, frameHeight: 156, scaleFactor: s,
                                                        inputType: .video, usePrecomputedFlow: false,
                                                        qualityPrioritization: .normal, revision: .revision1) {
            print("SR x\(s) for 320x156: ok, model status \(c.configurationModelStatus.rawValue),",
                  "formats", c.__frameSupportedPixelFormats.map { fourcc($0.uint32Value) })
        } else {
            print("SR x\(s) for 320x156: config nil")
        }
    }
    exit(0)
}

let mode = args[1]
let inDir = URL(fileURLWithPath: args[2]), outDir = URL(fileURLWithPath: args[3])
let scale = Int(args[4])!
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let files = try! FileManager.default.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
let first = loadCG(files[0])
let w = first.width, h = first.height

let processor = VTFrameProcessor()
let itype_isImage = ProcessInfo.processInfo.environment["SR_IMAGE"] != nil
let format: OSType
if mode == "sr" {
    let itype: VTSuperResolutionScalerConfiguration.InputType = ProcessInfo.processInfo.environment["SR_IMAGE"] != nil ? .image : .video
    guard let cfg = VTSuperResolutionScalerConfiguration(frameWidth: w, frameHeight: h, scaleFactor: scale,
                                                         inputType: itype, usePrecomputedFlow: false,
                                                         qualityPrioritization: .normal, revision: .revision1)
    else { print("config nil"); exit(1) }
    if cfg.configurationModelStatus != .ready {
        print("downloading model…")
        let sem = DispatchSemaphore(value: 0)
        cfg.downloadConfigurationModel { err in print("download done:", err as Any); sem.signal() }
        sem.wait()
    }
    print("model status", cfg.configurationModelStatus.rawValue, "available", cfg.configurationModelPercentageAvailable)
    format = cfg.__frameSupportedPixelFormats.first!.uint32Value
    srcAttrs = cfg.sourcePixelBufferAttributes; dstAttrs = cfg.destinationPixelBufferAttributes
    print("src attrs", srcAttrs); print("dst attrs", dstAttrs)
    try! processor.startSession(configuration: cfg)
} else {
    let cfg = VTLowLatencySuperResolutionScalerConfiguration(frameWidth: w, frameHeight: h, scaleFactor: Float(scale))
    format = cfg.__frameSupportedPixelFormats.first!.uint32Value
    srcAttrs = cfg.sourcePixelBufferAttributes; dstAttrs = cfg.destinationPixelBufferAttributes
    print("src attrs", srcAttrs); print("dst attrs", dstAttrs)
    try! processor.startSession(configuration: cfg)
}
print("format", fourcc(format))

var prevSrc: VTFrameProcessorFrame?
var prevOut: VTFrameProcessorFrame?
let start = Date()
for (i, f) in files.enumerated() {
    let cg = loadCG(f)
    let src = makeBuffer(w: w, h: h, format: format, attrs: srcAttrs)
    ctx.render(CIImage(cgImage: cg), to: src)
    if i == 0 { writePNG(src, outDir.appendingPathComponent("_src_check.png")) }
    let dst = makeBuffer(w: w * scale, h: h * scale, format: format, attrs: dstAttrs)
    let pts = CMTime(value: CMTimeValue(i), timescale: 15)
    let sf = VTFrameProcessorFrame(buffer: src, presentationTimeStamp: pts)!
    let df = VTFrameProcessorFrame(buffer: dst, presentationTimeStamp: pts)!
    let params: VTFrameProcessorParameters
    if mode == "sr" {
        params = VTSuperResolutionScalerParameters(sourceFrame: sf, previousFrame: itype_isImage ? nil : prevSrc, previousOutputFrame: itype_isImage ? nil : prevOut,
                                                   opticalFlow: nil, submissionMode: itype_isImage ? .random : .sequential, destinationFrame: df)!
    } else {
        params = VTLowLatencySuperResolutionScalerParameters(sourceFrame: sf, destinationFrame: df)
    }
    var got = 0
    do {
        for try await out in processor.process(parameters: params) {
            got += 1
            out.frame.withUnsafeBuffer { pb in
                if i == 0 { print("out", CVPixelBufferGetWidth(pb), "x", CVPixelBufferGetHeight(pb), fourcc(CVPixelBufferGetPixelFormatType(pb)), "same as dst:", pb === dst) }
                if i == 2 {
                    CVPixelBufferLockBaseAddress(pb, .readOnly)
                    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: Float16.self)
                    let rb = CVPixelBufferGetBytesPerRow(pb) / 2
                    for (x, y) in [(640, 100), (640, 312), (100, 500)] {
                        let o = y * rb + x * 4
                        print("px", x, y, base[o], base[o+1], base[o+2], base[o+3])
                    }
                    CVPixelBufferUnlockBaseAddress(pb, .readOnly)
                    CVPixelBufferLockBaseAddress(src, .readOnly)
                    let sb = CVPixelBufferGetBaseAddress(src)!.assumingMemoryBound(to: Float16.self)
                    let srb = CVPixelBufferGetBytesPerRow(src) / 2
                    print("src px", sb[78 * srb + 160 * 4], sb[78 * srb + 160 * 4 + 1], sb[78 * srb + 160 * 4 + 2], sb[78 * srb + 160 * 4 + 3])
                    CVPixelBufferUnlockBaseAddress(src, .readOnly)
                }
                writePNG(pb, outDir.appendingPathComponent(f.lastPathComponent))
            }
        }
    } catch { print("frame \(i) error:", error); exit(1) }
    if got == 0 { writePNG(dst, outDir.appendingPathComponent(f.lastPathComponent)) }
    if i == 0 { print("outputs yielded for frame 0:", got) }
    prevSrc = sf; prevOut = df
}
let dt = Date().timeIntervalSince(start)
print(String(format: "%d frames in %.1fs (%.1f fps incl. PNG I/O)", files.count, dt, Double(files.count) / dt))
processor.endSession()
