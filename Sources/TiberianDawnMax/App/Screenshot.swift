import CSDL2
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Screenshots (F12)
//
// F12 (or Cmd+S) sets `screenshotPending`; the main loop captures the
// next fully rendered frame (before the F3 perf overlay is drawn) and writes it
// as a PNG to the Desktop. Pure presentation — never touches sim state.

var screenshotPending = false

/// On-screen confirmation for the last capture (a Finder-launched app has no
/// stdout, so the print alone is invisible). Shown until `screenshotToastUntil`.
var screenshotToast = ""
var screenshotToastUntil: UInt32 = 0

func renderScreenshotToast(_ renderer: OpaquePointer?) {
    guard SDL_GetTicks() < screenshotToastUntil else { return }
    let y = renderState.windowHeight - 40
    let w = Int32(screenshotToast.count) * 12 + 24
    var bg = SDL_Rect(x: renderState.windowWidth / 2 - w / 2, y: y - 14, w: w, h: 28)
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 200)
    SDL_RenderFillRect(renderer, &bg)
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE)
    drawText(renderer, screenshotToast, centerX: renderState.windowWidth / 2, centerY: y, color: .green, scale: 2)
}

private func showScreenshotToast(_ text: String) {
    screenshotToast = text
    screenshotToastUntil = SDL_GetTicks() + 2500
}

/// Reads the current render target and saves it as
/// `~/Desktop/OpenConquer-<timestamp>.png`. Returns the written URL, or nil.
@discardableResult
func captureScreenshot(_ renderer: OpaquePointer?) -> URL? {
    var w: Int32 = 0
    var h: Int32 = 0
    SDL_GetRendererOutputSize(renderer, &w, &h)
    guard w > 0, h > 0 else {
        showScreenshotToast("Screenshot failed")
        return nil
    }

    let format: UInt32 = 0x16362004  // SDL_PIXELFORMAT_ARGB8888
    let pitch = Int(w) * 4
    var pixels = [UInt8](repeating: 0, count: pitch * Int(h))
    let ok = pixels.withUnsafeMutableBytes { buf in
        SDL_RenderReadPixels(renderer, nil, format, buf.baseAddress, Int32(pitch))
    }
    guard ok == 0 else {
        print("Screenshot failed: \(String(cString: SDL_GetError()))")
        showScreenshotToast("Screenshot failed")
        return nil
    }

    // ARGB8888 is B,G,R,A in memory on little-endian.
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
        | CGImageAlphaInfo.noneSkipFirst.rawValue
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(
            width: Int(w), height: Int(h),
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pitch,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
    else {
        print("Screenshot failed: couldn't build image")
        showScreenshotToast("Screenshot failed")
        return nil
    }

    let stamp = DateFormatter()
    stamp.dateFormat = "yyyyMMdd-HHmmss"
    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser
    let url = desktop.appendingPathComponent("OpenConquer-\(stamp.string(from: Date())).png")

    guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        print("Screenshot failed: couldn't create \(url.path)")
        showScreenshotToast("Screenshot failed")
        return nil
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        print("Screenshot failed: couldn't write \(url.path)")
        showScreenshotToast("Screenshot failed")
        return nil
    }
    print("Screenshot saved: \(url.path)")
    showScreenshotToast("Screenshot saved to Desktop")
    return url
}
