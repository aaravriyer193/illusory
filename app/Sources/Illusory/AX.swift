import AppKit
import ApplicationServices

/// Thin wrappers over the Accessibility API. Everything here is best-effort: if
/// permission hasn't been granted, or an app doesn't expose an attribute, the call
/// returns nil and Illusory works with less rather than failing the gesture.
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let value = copy(element, attribute) as? String, !value.isEmpty else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func range(_ element: AXUIElement, _ attribute: String) -> NSRange? {
        guard let value = copy(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &result) else { return nil }
        return NSRange(location: result.location, length: result.length)
    }

    /// Depth-limited hunt for an attribute somewhere in a window's subtree. Browsers
    /// hang the current URL off a web area rather than the window itself, so it has
    /// to be searched for rather than read directly.
    static func search(_ element: AXUIElement, for attribute: String, depth: Int = 4) -> String? {
        if let found = string(element, attribute) { return found }
        guard depth > 0,
              let children = copy(element, kAXChildrenAttribute as String) as? [AXUIElement]
        else { return nil }
        for child in children.prefix(24) {
            if let found = search(child, for: attribute, depth: depth - 1) { return found }
        }
        return nil
    }
}

/// Runs AppleScript for the few things Accessibility can't reach — chiefly Finder's
/// current folder and selection, which are what make "finish renaming the rest"
/// possible at all. Requires Automation permission, prompted once per target app.
enum Scripting {
    static func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            Log.info("applescript: \(error[NSAppleScript.errorMessage] ?? "failed")")
            return nil
        }
        guard let value = result.stringValue, !value.isEmpty else { return nil }
        return value
    }

    static func finderFolder() -> String? {
        run("""
        tell application "Finder"
            if (count of windows) is 0 then return ""
            return POSIX path of (target of front window as alias)
        end tell
        """)
    }

    static func finderSelection() -> [String] {
        guard let raw = run("""
        tell application "Finder"
            set out to ""
            repeat with f in (get selection)
                set out to out & POSIX path of (f as alias) & linefeed
            end repeat
            return out
        end tell
        """) else { return [] }
        return raw.split(separator: "\n").map(String.init)
    }
}

/// A thing on screen that can actually be clicked, with the frame the system says
/// it occupies.
///
/// This exists because vision models are bad at pixel-precise grounding: asked to
/// click a button, one confidently returned a coordinate in the bottom strip of the
/// screenshot and hit the Dock. The accessibility tree knows exactly where every
/// control is, so Illusory looks it up rather than letting the model estimate.
struct UIElement {
    let role: String
    let label: String
    let frame: CGRect

    var centre: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
}

extension AX {
    /// Roles worth offering as click targets. Static text and groups are excluded:
    /// they bloat the prompt and are almost never what someone means by "click".
    private static let clickableRoles: Set<String> = [
        "AXButton", "AXLink", "AXMenuItem", "AXMenuButton", "AXCheckBox",
        "AXRadioButton", "AXPopUpButton", "AXTextField", "AXTextArea",
        "AXDisclosureTriangle", "AXComboBox", "AXTab", "AXCell",
    ]

    private static func rect(_ element: AXUIElement) -> CGRect? {
        guard let posValue = copy(element, kAXPositionAttribute as String),
              let sizeValue = copy(element, kAXSizeAttribute as String),
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func describe(_ element: AXUIElement) -> String? {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute,
                          kAXValueAttribute, kAXHelpAttribute] {
            if let text = string(element, attribute as String) {
                return String(text.prefix(60))
            }
        }
        return nil
    }

    /// Walks the frontmost app's window for clickable controls. Depth- and
    /// count-limited: a Chrome window has thousands of nodes, and the whole point
    /// is to stay inside the gesture's latency budget.
    static func clickables(pid: pid_t, limit: Int = 60, maxDepth: Int = 12) -> [UIElement] {
        guard isTrusted else { return [] }
        let app = AXUIElementCreateApplication(pid)
        guard let window = element(app, kAXFocusedWindowAttribute as String) else { return [] }

        var found: [UIElement] = []
        var queue: [(AXUIElement, Int)] = [(window, 0)]

        while !queue.isEmpty, found.count < limit {
            let (node, depth) = queue.removeFirst()
            if depth > maxDepth { continue }

            if let role = string(node, kAXRoleAttribute as String),
               clickableRoles.contains(role),
               let frame = rect(node), frame.width > 4, frame.height > 4,
               let label = describe(node) {
                found.append(UIElement(role: role, label: label, frame: frame))
            }

            if let children = copy(node, kAXChildrenAttribute as String) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(40).map { ($0, depth + 1) })
            }
        }
        return found
    }
}
