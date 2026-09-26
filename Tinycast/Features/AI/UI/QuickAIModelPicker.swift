import AppKit
import SwiftUI

struct QuickAIModelPicker: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresented = false
    let chat: AIChatState
    let coordinator: AIChatCoordinator

    var body: some View {
        let efforts = coordinator.reasoningEfforts(for: chat)
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: metrics.spacing.xs) {
                Text(modelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !efforts.isEmpty {
                    Text(coordinator.selectedReasoningTitle(for: chat))
                        .fixedSize()
                }
                SymbolImage(name: "chevron.down", size: metrics.size.menuIcon / 2)
            }
            .font(metrics.typography.bar)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, metrics.spacing.md)
            .frame(
                width: metrics.scaled(Theme.Size.quickChatModelPickerWidth),
                height: metrics.size.barButtonHeight)
            .background(Theme.Colors.controlSurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model and reasoning effort")
        .accessibilityValue("\(modelTitle), \(coordinator.selectedReasoningTitle(for: chat))")
        .background {
            QuickAIModelPanel(
                isPresented: $isPresented, chat: chat, coordinator: coordinator,
                metrics: metrics, colorScheme: colorScheme)
        }
    }

    private var modelTitle: String {
        coordinator.modelTitle(of: coordinator.model(for: chat), among: coordinator.modelOptions)
    }
}

private struct QuickAIModelCard: View {
    @Environment(\.metrics) private var metrics
    let chat: AIChatState
    let coordinator: AIChatCoordinator

    private var efforts: [ChatGPTSubscription.Effort] { coordinator.reasoningEfforts(for: chat) }
    private var selected: AIModelSelection? { coordinator.model(for: chat) }
    private var selectedIndex: Int? { efforts.firstIndex { $0.id == selected?.effort } }
    private var modelTitle: String {
        coordinator.modelTitle(of: selected, among: coordinator.modelOptions)
    }

    var body: some View {
        VStack(spacing: metrics.spacing.xl) {
            HStack(alignment: .top, spacing: metrics.spacing.md) {
                SymbolImage(name: "bolt", size: metrics.size.menuIcon)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: metrics.size.menuIcon, height: metrics.size.barButtonHeight)
                    .accessibilityHidden(true)
                modelMenu
                    .frame(maxWidth: .infinity)
                Button {
                    if let option = coordinator.modelOptions.first(where: { selected.map($0.matches) ?? false }) {
                        coordinator.selectModel(option, in: chat)
                    }
                } label: {
                    SymbolImage(name: "arrow.counterclockwise", size: metrics.size.menuIcon)
                        .frame(width: metrics.size.menuIcon, height: metrics.size.barButtonHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textSecondary)
                .disabled(efforts.isEmpty)
                .accessibilityLabel("Reset reasoning effort to model default")
            }
            if efforts.count > 1 {
                effortSlider
            } else if let effort = efforts.first {
                Text(effort.title)
                    .font(metrics.typography.bar)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(metrics.spacing.xl)
        .frame(width: metrics.size.menuWidth)
        .background {
            RoundedRectangle(cornerRadius: metrics.radius.menuPanel, style: .continuous)
                .fill(Theme.Colors.panelScrim)
                .glassEffect(.regular, in: RoundedRectangle(
                    cornerRadius: metrics.radius.menuPanel, style: .continuous))
        }
    }

    private var modelMenu: some View {
        modelLabel
            .frame(maxWidth: .infinity)
            .padding(.vertical, metrics.spacing.xs)
            .overlay {
                QuickAIModelMenuButton(chat: chat, coordinator: coordinator)
            }
    }

    private var modelLabel: some View {
            VStack(spacing: metrics.spacing.xxs) {
                HStack(spacing: metrics.spacing.sm) {
                    Text(efforts.isEmpty ? "Select model" : coordinator.selectedReasoningTitle(for: chat))
                        .foregroundStyle(Theme.Colors.primaryAction)
                    SymbolImage(name: "chevron.right", size: metrics.size.menuIcon / 2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .font(metrics.typography.rowTitle)
                Text(modelTitle)
                    .font(metrics.typography.bar)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
    }

    private var effortSlider: some View {
        GeometryReader { geometry in
            let diameter = metrics.size.barButtonHeight
            let travel = max(geometry.size.width - diameter, 1)
            let position = CGFloat(selectedIndex ?? 0) / CGFloat(efforts.count - 1) * travel
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.controlSurface)
                if selectedIndex != nil {
                    Capsule().fill(Theme.Colors.primaryAction)
                        .frame(width: position + diameter / 2)
                }
                ForEach(efforts.indices, id: \.self) { index in
                    Circle().fill(Theme.Colors.textTertiary)
                        .frame(width: metrics.spacing.xs, height: metrics.spacing.xs)
                        .offset(x: diameter / 2 - metrics.spacing.xs / 2
                            + CGFloat(index) / CGFloat(efforts.count - 1) * travel)
                }
                Circle().fill(Theme.Colors.textPrimary)
                    .frame(width: diameter, height: diameter)
                    .offset(x: position)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let fraction = min(max((value.location.x - diameter / 2) / travel, 0), 1)
                let index = Int((fraction * CGFloat(efforts.count - 1)).rounded())
                coordinator.selectReasoningEffort(efforts[index], in: chat)
            })
        }
        .frame(height: metrics.size.barButtonHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reasoning effort")
        .accessibilityValue(coordinator.selectedReasoningTitle(for: chat))
        .accessibilityAdjustableAction { direction in
            let index = selectedIndex ?? 0
            switch direction {
            case .increment: select(index + 1)
            case .decrement: select(index - 1)
            @unknown default: break
            }
        }
    }

    private func select(_ index: Int) {
        guard efforts.indices.contains(index) else { return }
        coordinator.selectReasoningEffort(efforts[index], in: chat)
    }
}

private struct QuickAIModelPanel: NSViewRepresentable {
    @Binding var isPresented: Bool
    let chat: AIChatState
    let coordinator: AIChatCoordinator
    let metrics: InterfaceMetrics
    let colorScheme: ColorScheme

    func makeCoordinator() -> Controller { Controller() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.dismiss = { isPresented = false }
        context.coordinator.step = { delta in
            let efforts = coordinator.reasoningEfforts(for: chat)
            let index = efforts.firstIndex { $0.id == coordinator.model(for: chat)?.effort } ?? 0
            let next = min(max(index + delta, 0), efforts.count - 1)
            if efforts.indices.contains(next) {
                coordinator.selectReasoningEffort(efforts[next], in: chat)
            }
        }
        if isPresented {
            let content = QuickAIModelCard(chat: chat, coordinator: coordinator)
                .environment(\.metrics, metrics)
                .environment(\.colorScheme, colorScheme)
            context.coordinator.show(AnyView(content), above: view, gap: metrics.spacing.md)
        } else {
            context.coordinator.hide()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Controller) { coordinator.hide() }

    @MainActor
    final class Controller {
        var dismiss: (() -> Void)?
        var step: ((Int) -> Void)?
        private var panel: NSPanel?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var resignObserver: NotificationToken?

        func show(_ content: AnyView, above anchor: NSView, gap: CGFloat) {
            guard let host = anchor.window else { return }
            let panel: NSPanel
            if let existing = self.panel {
                panel = existing
                (panel.contentView as? NSHostingView<AnyView>)?.rootView = content
            } else {
                panel = NSPanel(
                    contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.contentView = NSHostingView(rootView: content)
                self.panel = panel
                host.addChildWindow(panel, ordered: .above)
                installMonitors(host: host)
            }
            guard let contentView = panel.contentView else { return }
            let size = contentView.fittingSize
            let button = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let screen = host.screen?.visibleFrame ?? host.frame
            let x = min(max(button.midX - size.width / 2, screen.minX), screen.maxX - size.width)
            let y = min(max(button.maxY + gap, screen.minY), screen.maxY - size.height)
            panel.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: size), display: true)
            panel.orderFront(nil)
        }

        func hide() {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil
            globalMonitor = nil
            resignObserver = nil
            if let panel {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
            panel = nil
        }

        private func close() {
            hide()
            dismiss?()
        }

        private func installMonitors(host: NSWindow) {
            localMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .keyDown]
            ) { [weak self] event in
                guard let self, let panel else { return event }
                if event.type == .keyDown {
                    if event.keyCode == 53 {
                        close()
                        return nil
                    }
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                        if event.keyCode == 123 || event.keyCode == 124 {
                            step?(event.keyCode == 123 ? -1 : 1)
                            return nil
                        }
                    }
                    close()
                } else if event.window !== panel {
                    close()
                }
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] _ in self?.close()
            }
            let center = NotificationCenter.default
            resignObserver = NotificationToken(center.addObserver(
                forName: NSWindow.didResignKeyNotification, object: host, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.close() }
            }, center: center)
        }
    }
}

private struct QuickAIModelMenuButton: NSViewRepresentable {
    let chat: AIChatState
    let coordinator: AIChatCoordinator

    func makeNSView(context: Context) -> Button {
        let button = Button()
        button.isTransparent = true
        button.isBordered = false
        button.title = "Choose model"
        button.setAccessibilityLabel("Choose model")
        button.target = button
        button.action = #selector(Button.showMenu)
        return button
    }

    func updateNSView(_ button: Button, context: Context) {
        button.chat = chat
        button.coordinator = coordinator
    }

    final class Button: NSButton {
        var chat: AIChatState?
        weak var coordinator: AIChatCoordinator?

        @objc func showMenu() {
            guard let chat, let coordinator else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            if coordinator.isModelCatalogLoading {
                let loading = NSMenuItem(title: "Loading models…", action: nil, keyEquivalent: "")
                loading.isEnabled = false
                menu.addItem(loading)
            }
            for group in coordinator.modelGroups {
                if !menu.items.isEmpty { menu.addItem(.separator()) }
                menu.addItem(.sectionHeader(title: group.title))
                for option in group.options {
                    let item = NSMenuItem(title: option.title, action: #selector(selectModel(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = option
                    item.state = coordinator.model(for: chat).map(option.matches) == true ? .on : .off
                    switch option.menuIcon {
                    case .asset(let name): item.image = NSImage(named: name)
                    case .symbol(let name): item.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
                    default: break
                    }
                    menu.addItem(item)
                }
            }
            if coordinator.modelGroups.isEmpty, !coordinator.isModelCatalogLoading {
                let item = NSMenuItem(title: "Configure AI…", action: #selector(configure), keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: bounds.maxX, y: bounds.maxY), in: self)
        }

        @objc private func selectModel(_ item: NSMenuItem) {
            guard let chat, let option = item.representedObject as? AIModelOption else { return }
            coordinator?.selectModel(option, in: chat)
        }

        @objc private func configure() { coordinator?.showSettings() }
    }
}
