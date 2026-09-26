import Carbon.HIToolbox

/// C entry point: decode the `EventRef` to a plain value before crossing into actor code.
private func hotKeyCarbonEventHandler(
    _: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let error = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard error == noErr else { return error }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated { center.handle(hotKeyID) }
}

/// The Carbon layer only; which shortcuts exist is `HotKeyManager`'s business.
@MainActor
final class HotKeyCenter {
    private struct Entry {
        let shortcut: KeyShortcut
        let onKeyDown: () -> Void
    }

    /// Carbon cannot see sides, so sided twins of one chord share a single registration.
    private struct Registration {
        let carbonID: UInt32
        var ref: EventHotKeyRef?
    }

    /// Live bindings by stable id, the one registration per chord, and the callback's lookup.
    private var entries: [String: Entry] = [:]
    private var registrations: [KeyShortcut: Registration] = [:]
    private var carbonIDToChord: [UInt32: KeyShortcut] = [:]
    private var nextCarbonID: UInt32 = 0
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x5459_4354  // FourCC "TYCT"

    /// Whether a press is routed by which side's modifier is down. See docs/features/hotkeys.md.
    var distinguishesSides = false
    /// The sides held right now; a hot-key event carries no flags of its own.
    var pressedSides: () -> ModifierSides = {
        ModifierSides(rawEventFlags: CGEventSource.flagsState(.combinedSessionState).rawValue)
    }

    /// While true every hotkey is soft-unregistered, so a recorder can capture combos.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            for chord in registrations.keys {
                if isPaused { deactivate(chord) } else { activate(chord) }
            }
        }
    }

    /// Registers `shortcut` under `id`, dropping any previous one so no combo leaks.
    func register(id: String, shortcut: KeyShortcut, onKeyDown: @escaping () -> Void) {
        unregister(id: id)
        entries[id] = Entry(shortcut: shortcut, onKeyDown: onKeyDown)
        let chord = shortcut.sideBlind
        if registrations[chord] == nil {
            nextCarbonID += 1
            registrations[chord] = Registration(carbonID: nextCarbonID, ref: nil)
            carbonIDToChord[nextCarbonID] = chord
        }
        if !isPaused { activate(chord) }
    }

    func unregister(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        let chord = entry.shortcut.sideBlind
        guard !entries.values.contains(where: { $0.shortcut.sideBlind == chord }) else { return }
        deactivate(chord)
        if let registration = registrations.removeValue(forKey: chord) {
            carbonIDToChord.removeValue(forKey: registration.carbonID)
        }
    }

    private func activate(_ chord: KeyShortcut) {
        guard var registration = registrations[chord], registration.ref == nil else { return }
        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let error = RegisterEventHotKey(
            UInt32(chord.carbonKeyCode),
            UInt32(chord.carbonModifiers),
            EventHotKeyID(signature: signature, id: registration.carbonID),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        // Another app may own the combo; the binding stays visible but doesn't fire.
        guard error == noErr, let ref else {
            let ids = entries.filter { $0.value.shortcut.sideBlind == chord }.keys.sorted()
            NSLog(
                "Tinycast: could not register hotkey for %@ (OSStatus %d)",
                ids.joined(separator: ", "), error)
            return
        }
        registration.ref = ref
        registrations[chord] = registration
    }

    private func deactivate(_ chord: KeyShortcut) {
        guard var registration = registrations[chord], let ref = registration.ref else { return }
        UnregisterEventHotKey(ref)
        registration.ref = nil
        registrations[chord] = registration
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil, let dispatcher = GetEventDispatcherTarget() else { return }
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]
        InstallEventHandler(
            dispatcher,
            hotKeyCarbonEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    fileprivate func handle(_ hotKeyID: EventHotKeyID) -> OSStatus {
        guard hotKeyID.signature == signature, let chord = carbonIDToChord[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }
        let candidates = entries.filter { $0.value.shortcut.sideBlind == chord }
        let winner = ModifierSides.winner(
            among: candidates.mapValues(\.shortcut.sides), pressed: pressedSides(),
            distinguishing: distinguishesSides)
        guard let winner, let entry = entries[winner] else { return OSStatus(eventNotHandledErr) }
        entry.onKeyDown()
        return noErr
    }
}
