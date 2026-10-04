import AppKit
import CoreGraphics
@preconcurrency import ApplicationServices
import VoiceOverlayCore

final class MacFocusPreserver: FocusPreserver {
    private var target: NSRunningApplication?

    func rememberTarget() {
        target = NSWorkspace.shared.frontmostApplication
        AppLog.write("remember target \(target?.localizedName ?? "none") (\(target?.bundleIdentifier ?? "-"))")
    }

    func restoreTarget() {
        guard let target else { return }
        target.activate()
        AppLog.write("restore target \(target.localizedName ?? "none")")
    }
}

enum AccessibilityPrompt {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings()
    }

    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for raw in urls {
            if let url = URL(string: raw) {
                NSWorkspace.shared.open(url)
                break
            }
        }
    }
}

struct MacCommandVPoster: CommandVPoster {
    func pasteCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9
        if let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }
    }
}

enum MacPasteboard {
    static func write(_ value: String?) {
        let board = NSPasteboard.general
        board.clearContents()
        if let value {
            board.setString(value, forType: .string)
        }
    }
}

struct MacTextPaster: TextPaster {
    func paste(_ text: String) async throws {
        MacPasteboard.write(text)
        AppLog.write("clipboard set (\(text.count) chars) ax=\(AccessibilityPrompt.isTrusted())")
        try await Task.sleep(nanoseconds: 150_000_000)
        if insertViaAccessibility(text) {
            AppLog.write("inserted via AX selected text")
            return
        }
        MacCommandVPoster().pasteCommandV()
        AppLog.write("posted ⌘V")
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    private func insertViaAccessibility(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let copyStatus = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard copyStatus == .success, let focused else {
            AppLog.write("no focused AX element (\(copyStatus.rawValue))")
            return false
        }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        AppLog.write("AXSelectedText set \(status.rawValue)")
        return status == .success
    }
}
