import Foundation

/// What an action is bound to. See docs/features/hotkeys.md.
enum HotKeyBinding: Hashable, Sendable, Codable {
    case combo(KeyShortcut)
    case doubleTap(DoubleTapModifier, side: ModifierSide? = nil)
    case globe
    case doubleGlobe

    /// One string per keycap, so every display site renders all bindings through one path.
    @MainActor var keycaps: [String] {
        switch self {
        case .combo(let shortcut): shortcut.keycaps
        case .doubleTap(let modifier, let side):
            modifier.keycaps.map { cap in
                KeyShortcut.distinguishesSides() ? side?.marking(cap) ?? cap : cap
            }
        case .globe: ["🌐︎"]
        case .doubleGlobe: ["🌐︎", "🌐︎"]
        }
    }

    var shortcut: KeyShortcut? {
        if case .combo(let shortcut) = self { return shortcut }
        return nil
    }

    var usesModifierTapMonitor: Bool {
        switch self {
        case .combo: false
        case .doubleTap, .globe, .doubleGlobe: true
        }
    }

    var sideBlind: HotKeyBinding {
        switch self {
        case .combo(let shortcut): .combo(shortcut.sideBlind)
        case .doubleTap(let modifier, _): .doubleTap(modifier)
        case .globe, .doubleGlobe: self
        }
    }

    var doubleTapModifier: DoubleTapModifier? {
        if case .doubleTap(let modifier, _) = self { return modifier }
        return nil
    }
}
