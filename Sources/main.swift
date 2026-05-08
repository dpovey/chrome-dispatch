import AppKit
import SwiftUI

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pickerWindow: NSWindow?
    private var mappingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    private static let chromeBundleID = "com.google.Chrome"
    private static let chromeFallbackPath = "/Applications/Google Chrome.app"

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
    }

    /// Re-launching via Spotlight or Finder while we're already running: open
    /// the management window instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMappingsWindow() }
        return true
    }

    /// Apps with LSUIElement = true still get this called when they're launched
    /// without a URL. Show the management window so the app feels responsive
    /// even when no link triggered it.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showMappingsWindow()
        return true
    }

    /// Finder uses this path (not GetURL) when opening a registered document
    /// type like an HTML file. Convert to absoluteString so the same dispatch
    /// flow handles file:// URLs.
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { handleURL(u.absoluteString) }
    }

    /// Stay alive after windows close so the next link click reuses this
    /// process instead of cold-launching a new one.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func handleGetURL(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else { return }
        handleURL(urlString)
    }

    private func handleURL(_ urlString: String) {
        let optionDown = NSEvent.modifierFlags.contains(.option)
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            // No host (file://, etc.) — nothing to map on, so honour Option as
            // a one-shot picker override but otherwise go straight to Default.
            if optionDown {
                showPicker(url: urlString, host: "", path: "")
            } else {
                launchChrome(profileDir: "Default", url: urlString)
            }
            return
        }
        let path = url.path
        if !optionDown, let profile = Mappings.load().lookup(host: host, path: path, profiles: ChromeProfiles.load()) {
            launchChrome(profileDir: profile, url: urlString)
            return
        }
        showPicker(url: urlString, host: host, path: path)
    }

    private func showPicker(url: String, host: String, path: String) {
        let profiles = ChromeProfiles.load()
        guard !profiles.isEmpty else {
            launchChrome(profileDir: "Default", url: url)
            return
        }
        pickerWindow?.close()
        NSApp.activate(ignoringOtherApps: true)
        let view = PickerView(url: url, host: host, path: path, profiles: profiles) { [weak self] selection in
            guard let self else { return }
            if let sel = selection {
                if sel.remember, !host.isEmpty {
                    var m = Mappings.load()
                    m.set(host: host,
                          pathPrefix: sel.pathPrefix,
                          profile: sel.profile.directory,
                          userName: sel.profile.userName)
                    m.save()
                }
                self.launchChrome(profileDir: sel.profile.directory, url: url)
            }
            self.pickerWindow?.close()
            self.pickerWindow = nil
        }
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "Open Link"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        pickerWindow = w
    }

    @objc private func showMappingsWindow() {
        if let existing = mappingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let profiles = ChromeProfiles.load()
        NSApp.activate(ignoringOtherApps: true)
        let view = MappingsView(profiles: profiles)
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "Chrome Dispatch"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 580, height: 480))
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        mappingsWindow = w
    }

    private static func chromeExecutable() -> URL? {
        if let bundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeBundleID) {
            let exec = bundle.appendingPathComponent("Contents/MacOS/Google Chrome")
            if FileManager.default.isExecutableFile(atPath: exec.path) { return exec }
        }
        let exec = URL(fileURLWithPath: chromeFallbackPath)
            .appendingPathComponent("Contents/MacOS/Google Chrome")
        return FileManager.default.isExecutableFile(atPath: exec.path) ? exec : nil
    }

    /// `Process` (not `NSWorkspace.openApplication`) is intentional: when Chrome
    /// is already running, NSWorkspace drops launch arguments, so the
    /// `--profile-directory` flag would be lost. Direct binary invocation
    /// hands off via Chrome's process-singleton mach port and respects the flag.
    private func launchChrome(profileDir: String, url: String) {
        guard let chromeBin = Self.chromeExecutable() else {
            NSLog("Chrome Dispatch: Google Chrome not found")
            return
        }
        let p = Process()
        p.executableURL = chromeBin
        p.arguments = ["--profile-directory=\(profileDir)", url]
        do {
            try p.run()
        } catch {
            NSLog("Chrome Dispatch: failed to launch Chrome: \(error)")
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let symbolNames = ["arrow.triangle.branch", "arrow.triangle.swap", "globe", "link"]
            var image: NSImage?
            for name in symbolNames {
                if let img = NSImage(systemSymbolName: name, accessibilityDescription: "Chrome Dispatch") {
                    image = img
                    break
                }
            }
            if let image {
                image.isTemplate = true
                button.image = image
            } else {
                // Last-resort visible label so the user can still find the menu.
                button.title = "CD"
            }
            button.toolTip = "Chrome Dispatch"
        }
        let menu = NSMenu()
        let manage = NSMenuItem(title: "Manage Mappings…",
                                action: #selector(showMappingsWindow),
                                keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Chrome Dispatch",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing == mappingsWindow { mappingsWindow = nil }
        if closing == pickerWindow { pickerWindow = nil }
    }
}
