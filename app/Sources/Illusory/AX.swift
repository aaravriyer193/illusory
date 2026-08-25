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
    let value: String?
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

    /// What to call this control.
    ///
    /// Order matters more than it looks. A web form field usually has no AXTitle —
    /// its name comes from the <label> the browser exposes as AXTitleUIElement, or
    /// from its placeholder. Falling through to AXValue first meant a field was
    /// named after whatever was typed in it, and an empty field had no name at all
    /// and got dropped, which is precisely how "paste into the redirect URL field"
    /// ended up clicking the workspace token field instead.
    private static func describe(_ element: AXUIElement) -> String? {
        if let title = string(element, kAXTitleAttribute as String) {
            return String(title.prefix(70))
        }
        // The label element a form control is wired to.
        if let labelElement = self.element(element, kAXTitleUIElementAttribute as String),
           let label = string(labelElement, kAXValueAttribute as String)
                    ?? string(labelElement, kAXTitleAttribute as String) {
            return String(label.prefix(70))
        }
        for attribute in [kAXPlaceholderValueAttribute, kAXDescriptionAttribute,
                          kAXHelpAttribute] {
            if let text = string(element, attribute as String) {
                return String(text.prefix(70))
            }
        }
        return nil
    }

    /// Current contents, shown separately so the model never mistakes what a field
    /// contains for what the field is called.
    private static func contents(_ element: AXUIElement) -> String? {
        guard let value = string(element, kAXValueAttribute as String) else { return nil }
        return String(value.prefix(50))
    }

    /// Chromium and Electron apps hide their web content from accessibility until
    /// asked. Without this, a browser exposes only its own chrome — no links, no
    /// buttons, nothing on the page — which is exactly where clicking matters most.
    /// Setting it is idempotent and cheap after the first call.
    static func enableWebContent(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    /// Walks the frontmost app for clickable controls.
    ///
    /// Depth-first rather than breadth-first on purpose: a browser's chrome sits at
    /// the top of the tree and would fill the whole budget before the walk ever
    /// reached the page, so a breadth-first search returns toolbars and no content.
    static func clickables(pid: pid_t, limit: Int = 140, maxDepth: Int = 45) -> [UIElement] {
        guard isTrusted else { return [] }
        enableWebContent(pid: pid)

        let app = AXUIElementCreateApplication(pid)
        let roots = [element(app, kAXFocusedWindowAttribute as String), app].compactMap { $0 }
        guard let root = roots.first else { return [] }

        var found: [UIElement] = []
        var seen = Set<String>()
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var roles: [String] = []
        // Hard node budget: some pages have tens of thousands of nodes and the
        // gesture has a latency ceiling that matters more than completeness.
        var visited = 0

        while let (node, depth) = stack.popLast(), found.count < limit, visited < 6000 {
            visited += 1
            if depth > maxDepth { continue }

            let nodeRole = string(node, kAXRoleAttribute as String)
            if let nodeRole { roles.append(nodeRole) }

            if let role = nodeRole,
               clickableRoles.contains(role),
               let frame = rect(node), frame.width > 4, frame.height > 4,
               // An input with no name at all is still a candidate: empty fields
               // are usually exactly the ones being asked about.
               let label = describe(node) ?? (role.contains("Text") ? "(unnamed field)" : nil) {
                // Web pages repeat labels constantly; keep the first of each.
                let key = "\(role)|\(label)|\(Int(frame.midX)),\(Int(frame.midY))"
                if seen.insert(key).inserted {
                    found.append(UIElement(role: role, label: label,
                                          value: contents(node), frame: frame))
                }
            }

            if let children = copy(node, kAXChildrenAttribute as String) as? [AXUIElement] {
                stack.append(contentsOf: children.prefix(120).reversed().map { ($0, depth + 1) })
            }
        }
        if found.count < 12 {
            // Too few almost always means the tree isn't built, not that the
            // window is empty — so report what roles were actually reachable.
            let census = Dictionary(grouping: roles, by: { $0 }).mapValues(\.count)
                .sorted { $0.value > $1.value }.prefix(8)
                .map { "\($0.key)x\($0.value)" }.joined(separator: " ")
            Log.info("ax: only \(found.count) controls for pid \(pid) · "
                   + "trusted=\(isTrusted) visited=\(visited) · roles: \(census)")
        }
        return found
    }
}
