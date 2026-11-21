import Carbon
import Foundation

final class HotKeyManager {
    var onHotKeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // FourCharCode 'DRPS' = 0x44525053
    private let signature: OSType = 0x44525053
    private let hotKeyIdentifier: UInt32 = 1

    func registerDefaultHotKey() {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event = event, let userData = userData else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleCarbonEvent(event)
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else {
            return
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: hotKeyIdentifier)
        let modifiers = UInt32(optionKey | shiftKey)
        let keyCode = UInt32(kVK_ANSI_D)

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    deinit {
        unregister()
    }

    private func handleCarbonEvent(_ event: EventRef) -> OSStatus {
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
        guard err == noErr,
              hotKeyID.signature == signature,
              hotKeyID.id == hotKeyIdentifier else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async { [weak self] in
            self?.onHotKeyPressed?()
        }
        return noErr
    }
}
