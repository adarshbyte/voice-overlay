import AppKit
import VoiceOverlayCore

@MainActor
final class OverlayWindowController: NSObject {
    private let panel: NSPanel
    private let orb: OrbView
    private let controller: OverlayController
    private var dragOffset: NSPoint?
    private var dragMoved = false

    init(controller: OverlayController) {
        self.controller = controller
        let size = NSSize(width: 72, height: 72)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = OverlayWindowController.savedOrigin(defaultFrame: screen, size: size)
        panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        orb = OrbView(frame: NSRect(origin: .zero, size: size))
        super.init()

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.title = "Voice Overlay"
        panel.contentView = orb
        orb.toolTip = "Right ⌥ auto · Right ⌘ English. F5/F6 toggle. ⌃⌥H hides."

        orb.onMouseDown = { [weak self] pointInScreen in
            self?.beginDrag(at: pointInScreen)
        }
        orb.onMouseDragged = { [weak self] pointInScreen in
            self?.drag(to: pointInScreen)
        }
        orb.onMouseUp = { [weak self] in
            self?.endDragOrClick()
        }
        orb.onRightMouseUp = { [weak self] in
            self?.showMenu()
        }

        controller.onPhaseChange = { [weak self] phase in
            AppLog.write("phase \(phase.statusText)")
            self?.orb.phase = phase
            self?.orb.englishMode = controller.talkLanguage == .english
            self?.orb.toolTip = phase.statusText
            if phase == .pasting {
                self?.showCopiedToast(controller.lastTranscript)
            }
        }
        orb.phase = controller.phase
        orb.toolTip = controller.phase.statusText
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        clampToVisibleScreen()
        panel.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: "overlayVisible")
    }

    func hide() {
        panel.orderOut(nil)
        UserDefaults.standard.set(false, forKey: "overlayVisible")
    }

    func toggleVisible() {
        if isVisible { hide() } else { show() }
    }

    private var toastPanel: NSPanel?

    func showCopiedToast(_ text: String) {
        NSSound(named: "Pop")?.play()
        toastPanel?.orderOut(nil)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let size = NSSize(width: min(520, max(280, screen.width * 0.4)), height: 56)
        let rect = NSRect(
            x: screen.midX - size.width / 2,
            y: screen.maxY - 88,
            width: size.width,
            height: size.height
        )
        let toast = NSPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        toast.level = .statusBar
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.hasShadow = true
        toast.ignoresMouseEvents = true
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.94).cgColor
        host.layer?.cornerRadius = 16
        let label = NSTextField(labelWithString: "Copied  ⌘V   \(text)")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 16, y: 16, width: size.width - 32, height: 24)
        host.addSubview(label)
        toast.contentView = host
        toast.orderFrontRegardless()
        toastPanel = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self, weak toast] in
            toast?.orderOut(nil)
            if self?.toastPanel === toast {
                self?.toastPanel = nil
            }
        }
    }

    private func beginDrag(at point: NSPoint) {
        dragOffset = NSPoint(x: point.x - panel.frame.origin.x, y: point.y - panel.frame.origin.y)
        dragMoved = false
    }

    private func drag(to point: NSPoint) {
        guard let dragOffset else { return }
        let next = NSPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
        if hypot(next.x - panel.frame.origin.x, next.y - panel.frame.origin.y) > 4 {
            dragMoved = true
        }
        panel.setFrameOrigin(next)
    }

    private func endDragOrClick() {
        if dragMoved {
            UserDefaults.standard.set(panel.frame.origin.x, forKey: "overlayX")
            UserDefaults.standard.set(panel.frame.origin.y, forKey: "overlayY")
        } else {
            controller.toggle()
        }
        dragOffset = nil
        dragMoved = false
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: controller.phase == .recording ? "Stop Recording" : "Start Recording", action: #selector(toggleFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Hide Overlay", action: #selector(hideFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Cancel", action: #selector(cancelFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Enable Auto-Paste…", action: #selector(openAccessibility), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Voice Overlay", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items {
            item.target = self
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 36, y: 0), in: orb)
    }

    @objc private func toggleFromMenu() {
        controller.toggle()
    }

    @objc private func hideFromMenu() {
        hide()
    }

    @objc private func cancelFromMenu() {
        controller.cancel()
    }

    @objc private func openAccessibility() {
        AccessibilityPrompt.prompt()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func clampToVisibleScreen() {
        let size = panel.frame.size
        let origin = panel.frame.origin
        let frame = NSRect(origin: origin, size: size)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            return
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.minY + 28))
    }

    private static func savedOrigin(defaultFrame screen: NSRect, size: NSSize) -> NSPoint {
        let fallback = NSPoint(x: screen.midX - size.width / 2, y: screen.minY + 28)
        guard UserDefaults.standard.object(forKey: "overlayX") != nil else { return fallback }
        let origin = NSPoint(
            x: UserDefaults.standard.double(forKey: "overlayX"),
            y: UserDefaults.standard.double(forKey: "overlayY")
        )
        let frame = NSRect(origin: origin, size: size)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            return origin
        }
        return fallback
    }
}

@MainActor
final class OrbView: NSView {
    var onMouseDown: ((NSPoint) -> Void)?
    var onMouseDragged: ((NSPoint) -> Void)?
    var onMouseUp: (() -> Void)?
    var onRightMouseUp: (() -> Void)?

    var phase: OverlayPhase = .idle {
        didSet { needsDisplay = true }
    }
    var englishMode = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }

    override func rightMouseUp(with event: NSEvent) {
        onRightMouseUp?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 4, dy: 4)
        let path = NSBezierPath(ovalIn: bounds)
        fillColor.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()

        drawGlyph(in: bounds)
        drawCaption(in: bounds)
    }

    private var fillColor: NSColor {
        switch phase {
        case .idle:
            return NSColor(calibratedWhite: 0.08, alpha: 0.92)
        case .recording:
            return NSColor(calibratedRed: 0.86, green: 0.18, blue: 0.22, alpha: 0.95)
        case .transcribing, .pasting:
            return NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.92, alpha: 0.95)
        case .failed:
            return NSColor(calibratedRed: 0.75, green: 0.45, blue: 0.10, alpha: 0.95)
        }
    }

    private func drawGlyph(in bounds: NSRect) {
        let symbolName: String
        switch phase {
        case .idle: symbolName = "mic.fill"
        case .recording: symbolName = "waveform"
        case .transcribing, .pasting: symbolName = "ellipsis"
        case .failed: symbolName = "exclamationmark"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: phase.statusText)?
            .withSymbolConfiguration(config) else { return }
        image.isTemplate = true
        let size = NSSize(width: 24, height: 24)
        let rect = NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2 + 6,
            width: size.width,
            height: size.height
        )
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: rect)
    }

    private func drawCaption(in bounds: NSRect) {
        let text: String
        switch phase {
        case .idle: text = "Talk"
        case .recording: text = englishMode ? "EN" : "Stop"
        case .transcribing: text = "…"
        case .pasting: text = "Paste"
        case .failed: text = "Err"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let sized = text.size(withAttributes: attrs)
        let point = NSPoint(x: bounds.midX - sized.width / 2, y: bounds.minY + 8)
        text.draw(at: point, withAttributes: attrs)
    }
}
