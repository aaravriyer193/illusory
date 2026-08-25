import AppKit
import CoreGraphics

/// Synthesised keyboard and mouse input — the part that lets Illusory drive apps
/// that expose no scripting interface at all.
///
/// Everything here is paced. Posted events go onto the HID tap and are delivered
/// as fast as they are created, but applications need real time to process them:
/// a browser has to run its event handlers, move focus, fire JavaScript. Firing a
/// burst of keystrokes with microsecond gaps means most of them land somewhere
/// that isn't ready for them and are simply lost, which looks exactly like typing
/// "not working".
///
/// These are async and sleep rather than blocking, because they run on the main
/// actor and `usleep` there freezes the UI for the whole duration.
enum Input {
    /// Between a key going down and coming up. Real keypresses are tens of
    /// milliseconds; apps that debounce input ignore anything much shorter.
    static let keyHold = Duration.milliseconds(5)
    /// Between one character and the next.
    static let keyGap = Duration.milliseconds(7)
    /// Between mouse down and mouse up.
    static let clickHold = Duration.milliseconds(60)
    /// After anything that can move focus or start navigation, before the next
    /// step assumes the change has happened. Generous on purpose: this is where
    /// a page actually re-renders, and a step that reads the screen too early is
    /// reading the previous screen.
    static let settle = Duration.milliseconds(700)

    private static var source: CGEventSource? {
        CGEventSource(stateID: .combinedSessionState)
    }

    // MARK: - Keyboard

    /// Types text as unicode rather than key codes, so it is layout-independent and
    /// handles characters with no key on the user's keyboard.
    ///
    /// One character at a time: batching sixteen into a single event was faster but
    /// many apps only read the first of a multi-character unicode payload, so long
    /// strings arrived truncated.
    static func type(_ text: String) async {
        let src = source
        for character in text {
            var units = Array(String(character).utf16)

            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            else { continue }

            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down.post(tap: .cghidEventTap)
            try? await Task.sleep(for: keyHold)

            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up.post(tap: .cghidEventTap)
            try? await Task.sleep(for: keyGap)
        }
    }

    /// Named keys and shortcuts, e.g. `press("return")` or `press("c", ["command"])`.
    static func press(_ key: String, _ modifiers: [String] = []) async {
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
        if let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(for: keyHold)
        if let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
        // Shortcuts trigger real work — selecting, saving, navigating — so give the
        // app time to do it before anything else is posted.
        try? await Task.sleep(for: settle)
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

    static var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    static func move(to point: CGPoint) async {
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(40))
    }

    static func click(at point: CGPoint? = nil,
                      button: CGMouseButton = .left, count: Int = 1) async {
        let location = point ?? cursor
        if point != nil {
            // Move first and let hover handlers run: controls that only become
            // clickable on hover ignore a click that arrives with the cursor.
            await move(to: location)
        }

        let down: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp

        for click in 1...max(1, count) {
            for kind in [down, up] {
                guard let event = CGEvent(mouseEventSource: source, mouseType: kind,
                                          mouseCursorPosition: location, mouseButton: button)
                else { continue }
                // Click count is what turns two clicks into a double-click rather
                // than two unrelated ones.
                event.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                event.post(tap: .cghidEventTap)
                if kind == down { try? await Task.sleep(for: clickHold) }
            }
            if click < count { try? await Task.sleep(for: .milliseconds(70)) }
        }
        // Focus changes, menus open, pages navigate. Nothing else should be posted
        // until that has had a chance to happen.
        try? await Task.sleep(for: settle)
    }

    static func drag(from: CGPoint, to: CGPoint) async {
        await move(to: from)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                mouseCursorPosition: from, mouseButton: .left)?.post(tap: .cghidEventTap)
        try? await Task.sleep(for: clickHold)

        // Stepped rather than teleported: many drop targets only register a drag
        // once they have seen intermediate movement.
        let steps = 20
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: from.x + (to.x - from.x) * progress,
                                y: from.y + (to.y - from.y) * progress)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged,
                    mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(12))
        }

        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                mouseCursorPosition: to, mouseButton: .left)?.post(tap: .cghidEventTap)
        try? await Task.sleep(for: settle)
    }

    static func scroll(dx: Int = 0, dy: Int = 0) async {
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)?.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(120))
    }
}
