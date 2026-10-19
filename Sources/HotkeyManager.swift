import Cocoa
import Carbon

/// Global hotkeys via Carbon RegisterEventHotKey.
/// Works without Accessibility permission.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var installed = false

    private init() {}

    func installHandler() {
        guard !installed else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ -> OSStatus in
            var hotkeyID = EventHotKeyID()
            let err = GetEventParameter(eventRef,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hotkeyID)
            if err == noErr, let action = HotkeyManager.shared.handlers[hotkeyID.id] {
                DispatchQueue.main.async { action() }
            }
            return noErr
        }, 1, &spec, nil, nil)
        installed = true
    }

    /// modifiers: Carbon modifier mask (optionKey, shiftKey, controlKey, cmdKey)
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        installHandler()
        let hotkeyID = EventHotKeyID(signature: OSType(0x53534854) /* 'SSHT' */, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID,
                                       GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            handlers[id] = action
            NSLog("SwiftShot: hotkey id \(id) registered OK (keyCode \(keyCode), mods \(modifiers))")
        } else {
            NSLog("SwiftShot: RegisterEventHotKey failed for id \(id), status \(status)")
        }
    }
}
