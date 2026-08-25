import AppKit
import ScreenCaptureKit

/// A downscaled JPEG of the screen at the moment the key was pressed.
///
/// Uses ScreenCaptureKit: `CGWindowListCreateImage` is deprecated and no longer a
/// reliable path on current macOS. Note that Screen Recording can only be granted
/// to a real bundle — a bare executable has no identity for TCC to attach the
/// permission to, so this silently fails unless Illusory runs as Illusory.app.
///
/// Full retina frames are enormous and would blow both the token budget and the
/// one-second rule, so this scales down before encoding. Captured only on a
/// keypress, held only for one request, never written to disk.
enum Screenshot {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func captureBase64JPEG(maxWidth: CGFloat = 1200,
                                  quality: CGFloat = 0.45) async -> String? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                Log.info("screenshot: no display")
                return nil
            }

            // Exclude Illusory's own overlay, or the model sees our sweep animation
            // rather than what the user was actually looking at.
            let ours = content.applications.filter {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            let filter = SCContentFilter(display: display,
                                         excludingApplications: ours,
                                         exceptingWindows: [])

            let scale = min(1, maxWidth / CGFloat(display.width))
            let config = SCStreamConfiguration()
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                   configuration: config)
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .jpeg,
                                                properties: [.compressionFactor: quality]) else {
                return nil
            }
            Log.info("screenshot: \(config.width)x\(config.height), \(data.count / 1024)KB")
            return data.base64EncodedString()
        } catch {
            Log.info("screenshot failed: \(error.localizedDescription) "
                   + "(permission: \(hasPermission), bundle: \(Bundle.main.bundleIdentifier ?? "none"))")
            return nil
        }
    }
}
