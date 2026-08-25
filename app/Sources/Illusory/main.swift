import AppKit

// Agent app: no dock icon, no window on launch. Illusory only ever appears
// beside the notch and, for the length of one gesture, over the screen.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
