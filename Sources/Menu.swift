import AppKit

// The menu bar: the app, editing (so copy, paste and the rest work in the
// site), and the window.
enum Menu {
    static func main() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(NSMenu(title: "Reevun"), [
            item("About Reevun", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide Reevun", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Reevun", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        menu.addItem(submenu(NSMenu(title: "Edit"), [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        let window = NSMenu(title: "Window")
        menu.addItem(submenu(window, [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        NSApp.windowsMenu = window
        return menu
    }

    private static func submenu(_ menu: NSMenu, _ items: [NSMenuItem]) -> NSMenuItem {
        items.forEach(menu.addItem)
        let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
