import AppKit
import SwiftUI

/// micinput lives in the background with no Dock icon or menu bar item.
/// Opening the app shows the settings window; closing it leaves the rules running.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = Store()
    private let hud = HUD()
    private var window: NSWindow?

    static func main() {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        store.onOverride = { [hud] in hud.show($0) }
        store.start()
        if !launchedInBackground { showWindow() }
    }

    /// Opening the app again while it runs in the background brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        // The login item may have been changed in System Settings meanwhile.
        store.objectWillChange.send()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Hand focus back to the previous app, then leave the Dock.
        NSApp.hide(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    /// True when macOS started the app as a login item: stay silent, show no window.
    private var launchedInBackground: Bool {
        if CommandLine.arguments.contains("--background") { return true }
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    private func showWindow() {
        if window == nil {
            store.refresh()
            let content = NSHostingController(rootView: SettingsView(store: store))
            content.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: content)
            window.title = "micinput"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        // A Dock icon and menu bar only while the window is open.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closeWindow() {
        window?.performClose(nil)
    }

    private func makeMenu() -> NSMenu {
        let app = NSMenu()
        app.addItem(withTitle: "About micinput",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide micinput", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        // ⌘Q closes the window like any app, but the rules keep running; ⌥⌘Q really ends the process.
        app.addItem(withTitle: "Quit micinput", action: #selector(closeWindow), keyEquivalent: "q").target = self
        app.addItem(withTitle: "Quit Completely", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            .keyEquivalentModifierMask = [.command, .option]

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let main = NSMenu()
        main.addItem(withTitle: "micinput", action: nil, keyEquivalent: "").submenu = app
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window
        return main
    }
}
