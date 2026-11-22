import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey that fires even when another app is in front.
/// Carbon keeps this to a handful of lines; the modern replacement (CGEventTap) needs
/// accessibility permission, which would be a far bigger ask than this feature deserves.
final class GlobalHotKey {
    fileprivate static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false
    private static var eventHandler: EventHandlerRef?

    private let hotKeyRef: EventHotKeyRef
    private let id: UInt32

    /// Returns nil when macOS refuses the combination (usually because another app owns it).
    init?(keyCode: UInt32, carbonModifiers: UInt32, handler: @escaping () -> Void) {
        GlobalHotKey.installDispatcherIfNeeded()
        let id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B4B4755), id: id) // 'KKGU'
        let status = RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        self.hotKeyRef = ref
        self.id = id
        GlobalHotKey.handlers[id] = handler
    }

    deinit {
        UnregisterEventHotKey(hotKeyRef)
        GlobalHotKey.handlers[id] = nil
    }

    private static func installDispatcherIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyDispatcher, 1, &spec, nil, &eventHandler)
    }

    /// Carbon modifier masks (`controlKey`, `optionKey`, `cmdKey`, `shiftKey`) live in
    /// MacTypes; they are not the same numbers as NSEvent.ModifierFlags.
    static let option = UInt32(optionKey)
    static let command = UInt32(cmdKey)
    static let spaceKey = UInt32(kVK_Space)
    static let graveKey = UInt32(kVK_ANSI_Grave)
}

/// Top-level so it can be handed to Carbon as a plain C function pointer.
private func hotKeyDispatcher(_ caller: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr, let handler = GlobalHotKey.handlers[hotKeyID.id] else {
        return OSStatus(eventNotHandledErr)
    }
    handler()
    return noErr
}
