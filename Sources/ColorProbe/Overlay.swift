import AppKit

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayController {
    private let window: OverlayWindow
    private let view: OverlayView
    private let image: CGImage
    var onFinish: ((URL?) -> Void)?

    init(screen: NSScreen, image: CGImage) {
        self.image = image
        let frame = screen.frame
        window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(frame, display: false)
        window.level = .screenSaver
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let local = CGRect(origin: .zero, size: frame.size)
        let container = NSView(frame: local)
        container.wantsLayer = true
        container.layer?.contents = image
        container.layer?.contentsGravity = .resize
        container.layer?.magnificationFilter = .nearest

        view = OverlayView(frame: local, pixels: PixelBuffer(image: image))
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        window.contentView = container

        view.onSave = { [weak self] in self?.save() }
        view.onCancel = { [weak self] in self?.finish(nil) }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSCursor.crosshair.set()
    }

    private func save() {
        guard let data = view.renderPNG(base: image) else {
            alert(L.renderFailed)
            return
        }
        let folder = Settings.saveFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let url = folder.appendingPathComponent("ColorProbe \(f.string(from: Date())).png")
            try data.write(to: url)
            finish(url)
        } catch {
            alert(L.saveFailed(folder.path, error.localizedDescription))
        }
    }

    private func alert(_ text: String) {
        window.level = .normal
        let a = NSAlert()
        a.messageText = "ColorProbe"
        a.informativeText = text
        a.runModal()
        window.level = .screenSaver
    }

    private func finish(_ url: URL?) {
        window.orderOut(nil)
        window.close()
        NSCursor.arrow.set()
        onFinish?(url)
    }
}
