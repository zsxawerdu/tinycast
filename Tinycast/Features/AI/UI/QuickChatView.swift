import SwiftUI

/// Quick AI: a floating composer that grows into a chat once there is anything to show above it.
struct QuickChatView: View {
    @Environment(AIChatCoordinator.self) private var coordinator
    let quickAI: QuickAICoordinator
    let onLayout: (QuickChatPanelController.Layout) -> Void
    @State private var compactHeight: CGFloat = 0

    private var chat: AIChatState { coordinator.chats.quickAI }

    /// A route that cannot answer says so in the grown panel, where its Configure button has room.
    private var isExpanded: Bool {
        !chat.session.messages.isEmpty || chat.notice != nil
            || coordinator.availability(for: chat) != nil
    }

    var body: some View {
        let expanded = isExpanded
        VStack(spacing: 0) {
            if expanded { header }
            AIChatDetailView(
                host: .quickChat, showsTranscript: expanded,
                composerHeader: AnyView(
                    QuickChatSwitcher(chat: chat, coordinator: coordinator, quickAI: quickAI)))
        }
        .fixedSize(horizontal: false, vertical: !expanded)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if !expanded { compactHeight = height }
        }
        .onChange(of: QuickChatPanelController.Layout(expanded: expanded, compactHeight: compactHeight), initial: true) {
            onLayout($1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(Theme.Colors.quickChatSurface)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            HeaderButton(symbol: "xmark", help: "Close  ⎋", action: quickAI.close)
            Spacer(minLength: 0)
            Text("Quick AI")
                .font(.headline)
            Spacer(minLength: 0)
            HeaderButton(symbol: "square.and.pencil", help: "New Chat  ⌘N", action: quickAI.startNewChat)
            HeaderButton(
                symbol: "arrow.up.forward.app", help: "Continue in AI Chat  ⌘J",
                action: quickAI.continueInChat)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Theme.Size.quickChatHeader)
        .contentShape(Rectangle())
        // The panel has no title bar, and dragging the transcript selects text instead.
        .gesture(WindowDragGesture())
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The open chat by name, and the others a click away; the window's sidebar holds the full list.
private struct QuickChatSwitcher: View {
    let chat: AIChatState
    let coordinator: AIChatCoordinator
    let quickAI: QuickAICoordinator

    private static let recentCount = 8

    var body: some View {
        let current = chat.session.id
        let recent = coordinator.history.conversations.prefix(Self.recentCount)
        Menu {
            Button("New Chat", systemImage: "square.and.pencil", action: quickAI.startNewChat)
            if !recent.isEmpty {
                Section("Recent") {
                    ForEach(recent) { conversation in
                        Toggle(
                            conversation.displayTitle,
                            isOn: Binding(
                                get: { conversation.id == current },
                                set: { if $0 { quickAI.openChat(id: conversation.id) } }))
                    }
                }
            }
            Divider()
            Button("All Chats in AI Chat…", systemImage: "sidebar.left", action: quickAI.showAllChats)
        } label: {
            Label(
                chat.session.messages.isEmpty ? "New chat" : coordinator.title(of: chat),
                systemImage: "square.and.pencil")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.leading, Theme.Spacing.md)
    }
}
