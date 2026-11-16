import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var overlay: OverlayController?
    private var lastSaved: URL?
    private let folderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var lastItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eyedropper.halffull", accessibilityDescription: "ColorProbe")
        buildMenu()

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | shiftKey)) { [weak self] in
            self?.startCapture(delay: 0)
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        func item(_ title: String, _ action: Selector?, _ key: String = "") -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = self
            return i
        }
        let capture = item(L.menuCapture, #selector(captureFromMenu), "c")
        capture.keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(capture)
        menu.addItem(.separator())
        folderItem.isEnabled = false
        menu.addItem(folderItem)
        menu.addItem(item(L.menuChooseFolder, #selector(chooseFolder)))
        menu.addItem(item(L.menuOpenFolder, #selector(openFolder)))
        let last = item(L.menuRevealLast, #selector(revealLast))
        lastItem = last
        menu.addItem(last)
        menu.addItem(.separator())

        let langMenu = NSMenu()
        for lang in AppLanguage.allCases {
            let title: String
            switch lang {
            case .system: title = L.langSystem
            case .ru: title = "Русский"
            case .en: title = "English"
            }
            let li = item(title, #selector(selectLanguage(_:)))
            li.representedObject = lang.rawValue
            li.state = AppLanguage.selected == lang ? .on : .off
            langMenu.addItem(li)
        }
        let langItem = NSMenuItem(title: L.menuLanguage, action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L.menuQuit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let lang = AppLanguage(rawValue: raw) else { return }
        AppLanguage.selected = lang
        buildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        folderItem.title = L.menuFolder((Settings.saveFolder.path as NSString).abbreviatingWithTildeInPath)
        lastItem?.isEnabled = lastSaved != nil
    }

    @objc private func captureFromMenu() { startCapture(delay: 0.25) }

    private func startCapture(delay: TimeInterval) {
        guard overlay == nil else { return }
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            showPermissionAlert()
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            do {
                let image = try await ScreenCapture.capture(screen: screen)
                let controller = OverlayController(screen: screen, image: image)
                controller.onFinish = { [weak self] url in
                    self?.overlay = nil
                    if let url {
                        self?.lastSaved = url
                        NSSound(named: "Glass")?.play()
                    }
                }
                overlay = controller
                controller.show()
            } catch {
                let a = NSAlert()
                a.messageText = L.captureFailed
                a.informativeText = error.localizedDescription
                NSApp.activate(ignoringOtherApps: true)
                a.runModal()
            }
        }
    }

    private func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = L.permissionTitle
        a.informativeText = L.permissionText
        a.addButton(withTitle: L.openSettings)
        a.addButton(withTitle: L.later)
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func chooseFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = Settings.saveFolder
        panel.prompt = L.panelPrompt
        panel.message = L.panelMessage
        if panel.runModal() == .OK, let url = panel.url {
            Settings.saveFolder = url
        }
    }

    @objc private func openFolder() {
        let folder = Settings.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func revealLast() {
        if let url = lastSaved { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
