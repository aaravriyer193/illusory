import AppKit
import ScreenCaptureKit

/// A downscaled JPEG of the screen at the moment the key was pressed.
///
/// Uses ScreenCaptureKit: `CGWindowListCreateImage` is deprecated and no longer a
/// reliable path on current macOS. Screen Recording can only be granted to a real
/// bundle — a bare executable has no identity for TCC to attach the permission to,
/// so this silently fails unless Illusory runs as Illusory.app.
///
/// Full retina frames are enormous and would blow both the token budget and the
/// one-second rule, so this scales down before encoding. Captured only on a
/// keypress, held only for one request, never written to disk.
enum Screenshot {
    /// The frame handed to the model, plus everything needed to map a coordinate
    /// in that image back onto the actual display.
    struct Capture {
        let base64: String
        let width: Int
        let height: Int
        /// Display bounds in points — the coordinate space input events live in.
        let displayOrigin: CGPoint
        let displaySize: CGSize
    }

    /// The most recent capture. Clicks arrive in screenshot pixels and have to be
    /// converted, so the transform has to outlive the capture call.
    private(set) static var last: Capture?

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Converts a point in the last screenshot's pixel space into screen points.
    /// Without this every click lands short by the downscale factor — a 3024px
    /// display shrunk to 1200px means the model's coordinates are ~2.5x too small.
    static func toScreen(_ point: CGPoint) -> CGPoint {
        guard let last, last.width > 0, last.height > 0 else { return point }
        let sx = last.displaySize.width / CGFloat(last.width)
        let sy = last.displaySize.height / CGFloat(last.height)
        return CGPoint(x: last.displayOrigin.x + point.x * sx,
                       y: last.displayOrigin.y + point.y * sy)
    }

    static func capture(maxWidth: CGFloat = 1200, quality: CGFloat = 0.45) async -> Capture? {
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

            let capture = Capture(base64: data.base64EncodedString(),
                                  width: config.width,
                                  height: config.height,
                                  displayOrigin: display.frame.origin,
                                  displaySize: display.frame.size)
            last = capture
            Log.info("screenshot: \(config.width)x\(config.height) of "
                   + "\(Int(display.frame.width))x\(Int(display.frame.height))pt, "
                   + "\(data.count / 1024)KB")
            return capture
        } catch {
            Log.info("screenshot failed: \(error.localizedDescription) "
                   + "(permission: \(hasPermission), bundle: \(Bundle.main.bundleIdentifier ?? "none"))")
            return nil
        }
    }
}
