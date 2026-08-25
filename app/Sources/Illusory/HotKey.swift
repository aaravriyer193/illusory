import AppKit
import Carbon.HIToolbox

/// A global hotkey that reports press *and* release, because Illusory's gesture is
/// hold-to-preview, release-to-commit. Carbon is used deliberately: it captures the
/// key system-wide without requiring Accessibility permission at launch.
final class HotKey {
    private static var registry: [UInt32: HotKey] = [:]
    private static var installed = false
    private static var nextID: UInt32 = 1

    private var ref: EventHotKeyRef?
    private let id: UInt32
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    init?(keyCode: UInt32, modifiers: UInt32) {
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x494C5553), id: id)  // 'ILUS'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        HotKey.registry[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.registry[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard let hk = HotKey.registry[hkID.id] else { return noErr }
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) {
                hk.onPress()
            } else {
                hk.onRelease()
            }
            return noErr
        }, 2, &spec, nil, nil)
    }
}
