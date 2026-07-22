import Foundation
import Carbon.HIToolbox

/// Registers system-wide hotkeys via the Carbon RegisterEventHotKey API.
/// Unlike NSEvent global monitors this requires no Accessibility permission.
final class HotkeyManager {
    typealias Handler = () -> Void

    private var handlers: [UInt32: Handler] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    private static let signature: OSType = 0x4C534E50 // "LSNP"

    init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) -> Bool {
        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("LightSnap: failed to register hotkey (status %d)", status)
            return false
        }
        handlers[id] = handler
        hotKeyRefs.append(ref)
        return true
    }

    deinit {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
