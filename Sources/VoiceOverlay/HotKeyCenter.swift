import Carbon
import Foundation

private let carbonHotKeyHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard err == noErr else { return err }
    HotKeyCenter.dispatch(hotKeyID.id)
    return noErr
}

final class HotKeyCenter: @unchecked Sendable {
    static let shared = HotKeyCenter()
    static let recordID: UInt32 = 1
    static let overlayID: UInt32 = 2

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var installed = false
    private var refs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    static func dispatch(_ id: UInt32) {
        DispatchQueue.main.async {
            HotKeyCenter.shared.invoke(id)
        }
    }

    @MainActor
    private func invoke(_ id: UInt32) {
        AppLog.write("hotkey fired id=\(id)")
        handlers[id]?()
    }

    @MainActor
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) {
        installIfNeeded()
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x564F564C), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hkID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            refs.append(ref)
            AppLog.write("hotkey id=\(id) registered key=\(keyCode) mods=\(modifiers)")
        } else {
            AppLog.write("hotkey id=\(id) failed status=\(status)")
        }
    }

    @MainActor
    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            carbonHotKeyHandler,
            1,
            &spec,
            nil,
            &handlerRef
        )
        AppLog.write("hotkey handler install status=\(status)")
    }
}
