import AppKit
import CoreGraphics

/// Synthesised keyboard and mouse input — the part that lets Illusory drive apps
/// that expose no scripting interface at all.
///
/// All of it needs Accessibility permission. Events are posted to the HID tap so
/// they behave exactly like real input, which also means they go wherever the
/// focus currently is: callers are responsible for making sure that is the right
/// place before posting anything.
enum Input {
    private static var source: CGEventSource? {
        CGEventSource(stateID: .combinedSessionState)
    }

    // MARK: - Keyboard

    /// Types text as unicode rather than as key codes, so it is layout-independent
    /// and handles characters that have no key on the user's keyboard.
    static func type(_ text: String) {
        let src = source
        for offset in stride(from: 0, to: text.count, by: 16) {
            let start = text.index(text.startIndex, offsetBy: offset)
            let end = text.index(start, offsetBy: min(16, text.count - offset))
            var units = Array(text[start..<end].utf16)

            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: src,
                                          virtualKey: 0, keyDown: isDown) else { continue }
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                event.post(tap: .cghidEventTap)
            }
            usleep(1200)
        }
    }

    /// Named keys and shortcuts, e.g. `press("return")` or `press("c", ["command"])`.
    static func press(_ key: String, _ modifiers: [String] = []) {
        guard let code = keyCode(for: key) else {
            Log.info("input: unknown key \(key)")
            return
        }
        var flags: CGEventFlags = []
        for modifier in modifiers.map({ $0.lowercased() }) {
            switch modifier {
            case "command", "cmd", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧":          flags.insert(.maskShift)
            case "option", "alt", "⌥":  flags.insert(.maskAlternate)
            case "control", "ctrl", "⌃":flags.insert(.maskControl)
            case "fn":                  flags.insert(.maskSecondaryFn)
            default: break
            }
        }

        let src = source
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: src,
                                      virtualKey: code, keyDown: isDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        usleep(2000)
    }

    private static func keyCode(for key: String) -> CGKeyCode? {
        let named: [String: CGKeyCode] = [
            "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
            "backspace": 51, "escape": 53, "esc": 53, "forwarddelete": 117,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
            "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31,
            "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9,
            "w": 13, "x": 7, "y": 16, "z": 6,
            "0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
            "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
        ]
        return named[key.lowercased()]
    }

    // MARK: - Mouse

    static var cursor: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func move(to point: CGPoint) {
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(4000)
    }

    static func click(at point: CGPoint? = nil, button: CGMouseButton = .left, count: Int = 1) {
        let location = point ?? cursor
        if point != nil { move(to: location) }

        let down: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp

        for click in 1...max(1, count) {
            for (kind, isDown) in [(down, true), (up, false)] {
                guard let event = CGEvent(mouseEventSource: source, mouseType: kind,
                                          mouseCursorPosition: location, mouseButton: button)
                else { continue }
                // Click count is what turns two clicks into a double-click rather
                // than two unrelated ones.
                event.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                event.post(tap: .cghidEventTap)
                _ = isDown
            }
            usleep(40_000)
        }
    }

    static func drag(from: CGPoint, to: CGPoint) {
        move(to: from)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                mouseCursorPosition: from, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(30_000)

        // Stepped rather than teleported: many drop targets only register a drag
        // once they have seen intermediate movement.
        let steps = 18
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: from.x + (to.x - from.x) * progress,
                                y: from.y + (to.y - from.y) * progress)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged,
                    mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(8000)
        }

        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                mouseCursorPosition: to, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    static func scroll(dx: Int = 0, dy: Int = 0) {
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)?.post(tap: .cghidEventTap)
        usleep(8000)
    }
}
