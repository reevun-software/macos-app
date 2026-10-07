import AppKit

// Reevun for macOS: reevun.app in a window of its own, with the app's own
// screens - title strip, loading and offline screens - from
// reevun-software/app-core, the same in every Reevun app.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
