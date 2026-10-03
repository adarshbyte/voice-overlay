import AppKit
@preconcurrency import ApplicationServices
import Carbon
import VoiceOverlayCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayWindowController?
    private var statusItem: NSStatusItem?
    private var controller: OverlayController?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var rightOptionDown = false
    private var rightCommandDown = false
    private var pushToTalkLanguage: TalkLanguage?
    private var optionHoldTask: Task<Void, Never>?
    private var commandHoldTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard let binary = NemoSpeechLocator.find() else {
            presentMissingNemotron()
            return
        }

        let recorder = AVRecorder()
        let transcriber = NemoSpeechTranscriber(executable: binary)
        let focus = MacFocusPreserver()
        let controller = OverlayController(
            recorder: recorder,
            transcriber: transcriber,
            paster: MacTextPaster(),
            prep: WavSilencePrep(),
            focus: focus
        )
        self.controller = controller
        AppLog.write("started nemo-speech at \(binary)")

        let overlay = OverlayWindowController(controller: controller)
        self.overlay = overlay
        overlay.show()

        installStatusItem()
        installHotKeys()
        installPushToTalk()
        AppLog.write("accessibility \(AccessibilityPrompt.isTrusted() ? "ON" : "OFF (will still try paste)")")
        Task { try? await MicrophoneAuth.ensureAllowed() }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Voice Overlay")
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Right ⌥ auto · Right ⌘ English. F5/F6 toggle."
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func statusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Voice Overlay", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: "Start / Stop Recording", action: #selector(toggleRecord), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(withTitle: "Right ⌥ auto · Right ⌘ English", action: nil, keyEquivalent: "")
        let vis = NSMenuItem(title: "Show / Hide Overlay", action: #selector(toggleOverlay), keyEquivalent: "h")
        vis.keyEquivalentModifierMask = [.control, .option]
        vis.target = self
        menu.addItem(vis)
        let ax = NSMenuItem(title: "Enable Auto-Paste…", action: #selector(openAccessibility), keyEquivalent: "")
        ax.target = self
        menu.addItem(ax)
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func installHotKeys() {
        let mods = UInt32(controlKey | optionKey)
        HotKeyCenter.shared.register(
            id: HotKeyCenter.recordID,
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: mods
        ) { [weak self] in
            self?.toggleRecord()
        }
        HotKeyCenter.shared.register(
            id: HotKeyCenter.overlayID,
            keyCode: UInt32(kVK_ANSI_H),
            modifiers: mods
        ) { [weak self] in
            self?.toggleOverlay()
        }
        HotKeyCenter.shared.register(
            id: 4,
            keyCode: UInt32(kVK_F5),
            modifiers: 0
        ) { [weak self] in
            self?.toggleRecord()
        }
        HotKeyCenter.shared.register(
            id: 5,
            keyCode: UInt32(kVK_F6),
            modifiers: 0
        ) { [weak self] in
            self?.toggleEnglishRecord()
        }
        AppLog.write("hotkeys Right-⌥ auto, Right-⌘ English, F5/F6 toggle, ⌃⌥H overlay")
    }

    private func installPushToTalk() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let code = event.keyCode
            let flags = event.modifierFlags
            DispatchQueue.main.async {
                self?.handleFlagsChanged(keyCode: code, flags: flags)
            }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(keyCode: event.keyCode, flags: event.modifierFlags)
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            DispatchQueue.main.async {
                self?.cancelPendingCommandHold()
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.cancelPendingCommandHold()
            return event
        }
        AppLog.write("push-to-talk Right Option auto, Right Command English")
    }

    private func cancelPendingCommandHold() {
        guard rightCommandDown, pushToTalkLanguage == nil else { return }
        commandHoldTask?.cancel()
        commandHoldTask = nil
        rightCommandDown = false
    }

    private func handleFlagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        switch keyCode {
        case 61: // kVK_RightOption
            let down = flags.contains(.option) && flags.intersection([.command, .shift, .control]).isEmpty
            handleHold(
                isDown: down,
                language: .auto,
                downFlag: &rightOptionDown,
                holdTask: &optionHoldTask
            )
        case 54: // kVK_RightCommand
            let down = flags.contains(.command) && flags.intersection([.control, .shift, .option]).isEmpty
            handleHold(
                isDown: down,
                language: .english,
                downFlag: &rightCommandDown,
                holdTask: &commandHoldTask
            )
        default:
            break
        }
    }

    private func handleHold(
        isDown: Bool,
        language: TalkLanguage,
        downFlag: inout Bool,
        holdTask: inout Task<Void, Never>?
    ) {
        if isDown {
            downFlag = true
            holdTask?.cancel()
            holdTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 140_000_000)
                guard let self, !Task.isCancelled else { return }
                let stillDown = language == .english ? self.rightCommandDown : self.rightOptionDown
                guard stillDown else { return }
                self.beginPushToTalk(language: language)
            }
        } else {
            downFlag = false
            holdTask?.cancel()
            holdTask = nil
            endPushToTalk(language: language)
        }
    }

    private func beginPushToTalk(language: TalkLanguage) {
        guard let controller else { return }
        switch controller.phase {
        case .idle, .failed:
            pushToTalkLanguage = language
            AppLog.write(language == .english ? "PTT English start" : "PTT start")
            overlay?.show()
            controller.startRecording(language: language)
        default:
            break
        }
    }

    private func endPushToTalk(language: TalkLanguage) {
        guard pushToTalkLanguage == language else { return }
        pushToTalkLanguage = nil
        AppLog.write(language == .english ? "PTT English stop" : "PTT stop")
        guard controller?.phase == .recording else { return }
        Task { await controller?.stopAndTranscribe() }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent, let button = statusItem?.button else {
            toggleRecord()
            return
        }
        if event.type == .rightMouseUp {
            statusMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        } else {
            toggleRecord()
        }
    }

    @objc private func toggleRecord() {
        AppLog.write("hotkey record")
        overlay?.show()
        controller?.toggle()
    }

    @objc private func toggleEnglishRecord() {
        AppLog.write("hotkey english record")
        overlay?.show()
        guard let controller else { return }
        switch controller.phase {
        case .idle, .failed:
            controller.startRecording(language: .english)
        case .recording:
            Task { await controller.stopAndTranscribe() }
        case .transcribing, .pasting:
            break
        }
    }

    @objc private func toggleOverlay() {
        AppLog.write("hotkey overlay")
        overlay?.toggleVisible()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibility() {
        AccessibilityPrompt.prompt()
    }

    private func presentMissingNemotron() {
        let alert = NSAlert()
        alert.messageText = "Nemotron is not installed"
        alert.informativeText = """
        Voice Overlay transcribes with NVIDIA Nemotron Speech via the local `nemo-speech` CLI.

        Install it, then relaunch:

        curl -fsSL https://github.com/NVIDIA/NeMo-Speech.cpp/raw/main/scripts/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
        nemo-speech pull nemotron-3.5
        """
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
