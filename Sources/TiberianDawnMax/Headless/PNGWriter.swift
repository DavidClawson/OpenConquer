import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Write packed RGBA8888 as a PNG (alpha kept: SHP dumps are transparent) — shared by the asset
/// diagnostics (--dump-gfx, --dump-vqa, --dump-font, --test-map-select).
@discardableResult
func writeRGBAPNG(rgba: [UInt8], width: Int, height: Int, to url: URL) -> Bool {
    guard let provider = CGDataProvider(data: Data(rgba) as CFData),
          let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}
