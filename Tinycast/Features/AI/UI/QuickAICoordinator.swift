import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Quick AI's floating panel: summoning, the open policy, and handing a chat on to the window.
@MainActor
final class QuickAICoordinator {
    private let chats: AIChatSurfacesState
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    private lazy var panel: QuickChatPanelController = QuickChatPanelController(
        content: { [unowned self] in
            AnyView(
                QuickChatView(quickAI: self, onLayout: { [weak self] in self?.panel.apply($0) })
                    .environment(chatCoordinator)
                    // Find is the window's; the panel's never searches, but the transcript reads one.
                    .environment(ChatFindState()))
        },
        onKeyDown: { [weak self] in self?.handle($0) ?? false })

    init(
        chats: AIChatSurfacesState, settings: AppSettings,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.chats = chats
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    private var chat: AIChatState { chats.quickAI }
    private var chatCoordinator: AIChatCoordinator { core.aiChatCoordinator }

    /// The shortcut toggles: a second press closes a panel that has focus, and focuses one that does not.
    func show() {
        guard settings.aiEnabled else { return }
        if panel.isKey {
            close()
            return
        }
        // The open policy decides a chat only on the way in, never for a panel already up.
        if !panel.isVisible { applyOpenPolicy() }
        present()
    }

    /// ⇥ and the AI fallback: a fresh chat that carries the question, already asked.
    func ask(_ prompt: String) {
        guard settings.aiEnabled else { return }
        // No question is no reason to skip the open policy: this is a summon, not an ask.
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            show()
            return
        }
        chat.startNewChat()
        present()
        send(prompt)
    }

    func close() {
        panel.hide()
    }

    /// Off leaves nothing behind, so the panel never shows a feature that is gone.
    func leave() {
        panel.tearDown()
    }

    /// A file pasted at the launcher belongs in Quick AI, never in a search for its name.
    func attachPastedFileFromLauncher(files: [URL]) -> Bool {
        guard settings.aiEnabled, !files.isEmpty else { return false }
        show()
        return chatCoordinator.attachPastedFile(files: files, to: chat)
    }

    /// Over the palette, the app it covered is the one to go back to, not the palette itself.
    private func present() {
        let returnTo =
            paletteCoordinator.isVisible
            ? paletteCoordinator.targetApp : NSWorkspace.shared.frontmostApplication
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        let own = returnTo?.processIdentifier == NSRunningApplication.current.processIdentifier
        chatCoordinator.prepareForChat()
        panel.show(returningTo: own ? nil : returnTo)
    }

    /// The one place deciding whether summoning resumes.
    private func applyOpenPolicy() {
        // A reply still arriving was asked for; resetting would discard the answer.
        guard !chat.isStreaming else { return }
        let recent = core.chatHistory.conversations.first
        let hasTranscript = !chat.session.messages.isEmpty
        // Staged files are unsent work: neither branch may throw them away on a plain re-summon.
        let hasStaging = !chat.pendingAttachments.isEmpty
        // From history when nothing is resident, so the verdict still holds after a relaunch.
        let lastActiveAt = hasTranscript ? chat.session.updatedAt : recent?.updatedAt
        let decision = AIConversationOpenPolicy.decide(
            opensTo: core.aiSettings.opensTo, newAfter: core.aiSettings.newChatAfter,
            lastActiveAt: lastActiveAt, now: Date())
        switch decision {
        case .resume:
            guard !hasTranscript, !hasStaging, let recent else { return }
            // The window may have it open, in which case this summon starts fresh instead.
            chats.openInQuickAI(id: recent.id)
        case .startNew:
            // An empty chat is already new; resetting it would only drop what is staged in it.
            guard hasTranscript else { return }
            chat.startNewChat()
        }
    }

    @discardableResult
    func send(_ input: String) -> Bool {
        chatCoordinator.send(input, in: chat)
    }

    func startNewChat() {
        chat.startNewChat()
    }

    /// A chat the window holds opens there, since two writers would each save over the other.
    func openChat(id: UUID) {
        guard chats.openInQuickAI(id: id) else {
            close()
            chatCoordinator.openChat(id: id)
            chatCoordinator.showWindow()
            return
        }
    }

    func showAllChats() {
        close()
        chatCoordinator.showWindow()
    }

    /// The window takes the conversation over, half-typed line and all, and the panel closes.
    func continueInChat() {
        let draft = chat.draft
        chat.draft = ""
        close()
        chatCoordinator.continueInWindow(draft: draft)
    }

    /// The window's chords where they mean the same thing, and ⎋ / ⌘W to put the panel away.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if Int(event.keyCode) == kVK_Escape, modifiers.isEmpty {
            // An input method's marked text is Escape's to cancel first.
            if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() {
                return false
            }
            close()
            return true
        }
        guard !event.isARepeat else { return false }
        let key = (ASCIIKeyboardLayout.character(for: event) ?? event.charactersIgnoringModifiers)?
            .lowercased()
        switch (modifiers, key) {
        case ([.command], "w"):
            close()
        case ([.command], "n"):
            startNewChat()
        case ([.command], "j"):
            continueInChat()
        case ([.command], "r") where AIChatActionsMenu.canRegenerate(chat):
            chatCoordinator.regenerate(in: chat)
        case ([.command, .shift], "c") where chat.lastAssistantText != nil:
            chatCoordinator.copyLastResponse(in: chat)
        case ([.command], ".") where chat.isStreaming:
            chatCoordinator.stopResponse(in: chat)
        case ([.command, .option], ","):
            close()
            chatCoordinator.showSettings()
        case ([.command], "v"):
            return chatCoordinator.attachPastedFile(files: PasteboardFiles.urls(on: .general), to: chat)
        default:
            return false
        }
        return true
    }
}
