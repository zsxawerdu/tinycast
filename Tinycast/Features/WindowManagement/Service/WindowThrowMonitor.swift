import AppKit

@MainActor
final class WindowThrowMonitor {
    private let settings: AppSettings
    private let mover: WindowMover
    private var gesture = WindowThrowGesture()
    private var target: WindowMover.ThrowTarget?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var validationTask: Task<Void, Never>?
    private var tokens: [NotificationToken] = []
    private var sessionActive = true
    var isPaused: () -> Bool = { false }

    init(settings: AppSettings, mover: WindowMover) {
        self.settings = settings
        self.mover = mover
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            tokens.append(NotificationToken(center.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.sessionActive = false
                    self?.cancel()
                }
            }, center: center))
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            tokens.append(NotificationToken(center.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.sessionActive = true
                    self?.cancel()
                }
            }, center: center))
        }
    }

    isolated deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        validationTask?.cancel()
    }

    func applySettings() {
        stop()
        guard settings.windowManagementEnabled, settings.windowThrowEnabled else { return }
        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.process(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.process(event)
        }
        validationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                validate()
            }
        }
    }

    private func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        validationTask?.cancel()
        validationTask = nil
        cancel()
    }

    private func cancel() {
        gesture.cancel()
        target = nil
    }

    private func validate() {
        guard settings.windowManagementEnabled, settings.windowThrowEnabled,
            sessionActive, !isPaused(), Permissions.isAccessibilityTrusted()
        else { cancel(); return }
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        if let target {
            if flags & settings.windowThrowChord.flags != settings.windowThrowChord.flags
                || !mover.isCurrent(target)
            { cancel() }
        } else if flags & settings.windowThrowChord.flags == 0 {
            _ = gesture.update(flags: flags, point: .zero, chord: settings.windowThrowChord)
        }
    }

    private func process(_ event: NSEvent) {
        guard settings.windowManagementEnabled, settings.windowThrowEnabled,
            sessionActive, !isPaused(), Permissions.isAccessibilityTrusted()
        else {
            cancel()
            return
        }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: -mouse.y)
        let interrupted = event.type != .flagsChanged && event.type != .mouseMoved
        let action = gesture.update(
            flags: UInt64(event.modifierFlags.rawValue), point: point,
            chord: settings.windowThrowChord, interrupted: interrupted)
        switch action {
        case .begin:
            target = mover.captureThrowTarget()
            if target == nil { cancel() }
        case .commit(let direction):
            if let target {
                mover.performThrow(
                    direction, target: target,
                    gap: CGFloat(settings.windowGap))
            }
            target = nil
        case .cancel: target = nil
        case nil: break
        }
    }
}
