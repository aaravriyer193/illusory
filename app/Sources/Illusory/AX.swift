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
