import AppKit
import Carbon

@MainActor
final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let actionID: UInt32
    private var registeredShortcut: Shortcut?
    var onFire: (() -> Void)?

    init(id: UInt32) {
        actionID = id
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
                guard identifier.signature == 0x53415452, identifier.id == manager.actionID else { return OSStatus(eventNotHandledErr) }
                manager.onFire?()
                return noErr
            }
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: Shortcut) throws {
        if let old = registeredShortcut, old.keyCode == shortcut.keyCode, old.modifiers == shortcut.modifiers { return }
        var replacement: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x53415452, id: actionID)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                         GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else { throw HotKeyError.conflict }
        unregister()
        hotKey = replacement
        registeredShortcut = shortcut
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registeredShortcut = nil
    }
}

enum HotKeyError: Error, LocalizedError {
    case conflict
    var errorDescription: String? { "快捷键注册失败，可能已被其他应用占用，请在设置中更换。" }
}
