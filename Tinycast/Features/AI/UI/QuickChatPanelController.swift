import AppKit
import SwiftUI

/// Non-activating like the palette, but a chat is worked beside other apps, so it floats until closed.
private final class QuickChatPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Theme.Size.quickChatPanel),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Where and how big Quick AI's panel is; what it shows and what its keys do stay with the caller.
@MainActor
final class QuickChatPanelController: NSObject, NSWindowDelegate {
    /// What the content asks of the frame: grown into a chat, or the composer's own height.
    struct Layout: Equatable {
        var expanded: Bool
        var compactHeight: CGFloat
    }

    /// Above the Dock and clear of the screen edge, where a chat box sits in most AI apps.
    private static let restingBottom: CGFloat = 0.12
    private static let screenMargin: CGFloat = 12
    private static let positionKey = "quickAI.bottomCenter"

    private let makeContent: () -> AnyView
    private let onKeyDown: (NSEvent) -> Bool
    private var panel: QuickChatPanel?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    /// The composer's resting point; the panel grows up from it, so the field never moves.
    private var bottomCenter: CGPoint?
    private var layout = Layout(expanded: false, compactHeight: 0)
    /// Set while the controller moves the panel itself, so only a drag re-anchors it.
    private var isPlacing = false

    init(content: @escaping () -> AnyView, onKeyDown: @escaping (NSEvent) -> Bool) {
        makeContent = content
        self.onKeyDown = onKeyDown
        if let position = UserDefaults.standard.array(forKey: Self.positionKey) as? [Double],
            position.count == 2, position.allSatisfy(\.isFinite)
        {
            bottomCenter = CGPoint(x: position[0], y: position[1])
        }
    }

    isolated deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var isKey: Bool { panel?.isKeyWindow ?? false }

    func show(returningTo app: NSRunningApplication?) {
        let panel = ensurePanel()
        if !panel.isVisible {
            previousApp = app
            if let anchor = bottomCenter, !NSScreen.screens.contains(where: { $0.frame.contains(anchor) }) {
                bottomCenter = nil
            }
            // Flush first-mount layout off-screen, so the composer reports its height before showing.
            panel.contentView?.layoutSubtreeIfNeeded()
            place(panel, animate: false)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        // Next turn: a text view added by the first layout has no window to take focus in yet.
        Task { @MainActor [weak self] in self?.focusComposer() }
    }

    /// Focus goes back only when the panel held it; a click elsewhere already chose where it went.
    func hide() {
        guard let panel, panel.isVisible else { return }
        let hadFocus = panel.isKeyWindow
        panel.orderOut(nil)
        if hadFocus { previousApp?.activate() }
        previousApp = nil
    }

    /// Off means fully off: the SwiftUI tree goes too, so nothing keeps observing the chat.
    func tearDown() {
        hide()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.close()
        panel = nil
    }

    func apply(_ next: Layout) {
        guard next != layout else { return }
        let grew = next.expanded != layout.expanded
        layout = next
        guard let panel, panel.isVisible else { return }
        place(panel, animate: grew)
    }

    private func ensurePanel() -> QuickChatPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: makeContent())
        // The controller owns the frame; the content only reports what it needs.
        hosting.sizingOptions = []
        let panel = QuickChatPanel(contentView: hosting)
        panel.delegate = self
        self.panel = panel
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel, panel.isKeyWindow else {
                return event
            }
            return self.onKeyDown(event) ? nil : event
        }
        return panel
    }

    private func place(_ panel: NSPanel, animate: Bool) {
        let mouse = NSEvent.mouseLocation
        guard
            let screen = bottomCenter.flatMap({ anchor in
                NSScreen.screens.first { $0.frame.contains(anchor) }
            }) ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        let margin = Self.screenMargin
        let size = Theme.Size.quickChatPanel
        let height =
            layout.expanded
            ? min(size.height, visible.height - margin * 2) : max(layout.compactHeight, 1)
        let anchor =
            bottomCenter
            ?? CGPoint(x: visible.midX, y: visible.minY + visible.height * Self.restingBottom)
        let x = min(max(anchor.x - size.width / 2, visible.minX + margin), visible.maxX - size.width - margin)
        let y = min(max(anchor.y, visible.minY + margin), visible.maxY - height - margin)
        isPlacing = true
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: height), display: true, animate: animate)
        isPlacing = false
    }

    private func focusComposer() {
        guard let panel, let content = panel.contentView,
            let field = Self.editableTextView(in: content)
        else { return }
        panel.makeFirstResponder(field)
    }

    /// The composer is the only text the panel lets you type in; the transcript's is read-only.
    private static func editableTextView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView, text.isEditable { return text }
        for subview in view.subviews {
            if let found = editableTextView(in: subview) { return found }
        }
        return nil
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !isPlacing, let frame = panel?.frame else { return }
        bottomCenter = CGPoint(x: frame.midX, y: frame.minY)
        UserDefaults.standard.set([Double(frame.midX), Double(frame.minY)], forKey: Self.positionKey)
    }
}
