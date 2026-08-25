import AppKit
import CoreGraphics

/// A downscaled JPEG of the screen at the moment the key was pressed.
///
/// Full-resolution retina frames are enormous and would blow both the token budget
/// and the one-second rule, so this scales down hard before encoding. Captured only
/// on a keypress, held only for the length of one request, never written to disk.
enum Screenshot {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static func captureBase64JPEG(maxWidth: CGFloat = 1200, quality: CGFloat = 0.45) -> String? {
        guard hasPermission else {
            Log.info("screenshot: no Screen Recording permission — requesting")
            requestPermission()
            return nil
        }
        guard let full = CGWindowListCreateImage(.infinite, .optionOnScreenOnly,
                                                 kCGNullWindowID, [.bestResolution]) else {
            Log.info("screenshot: capture returned nothing")
            return nil
        }

        let scale = min(1, maxWidth / CGFloat(full.width))
        let width = Int(CGFloat(full.width) * scale)
        let height = Int(CGFloat(full.height) * scale)

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let scaled = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: scaled)
        guard let data = rep.representation(using: .jpeg,
                                            properties: [.compressionFactor: quality]) else {
            return nil
        }
        Log.info("screenshot: \(width)x\(height), \(data.count / 1024)KB")
        return data.base64EncodedString()
    }
}
