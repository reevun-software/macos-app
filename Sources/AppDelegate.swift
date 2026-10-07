import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: SiteWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.mainMenu = Menu.main()
        window = SiteWindow()
        window?.show()
    }

    // Closing the window keeps the app (as Mac apps do); the Dock icon
    // brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { window?.show() }
        return true
    }
}
