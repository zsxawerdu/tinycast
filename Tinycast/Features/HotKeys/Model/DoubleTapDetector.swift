import Foundation

/// Recognizes a double-tapped lone modifier. See docs/features/hotkeys.md#double-tap-modifiers.
struct DoubleTapDetector {
    /// Longest a press may last and still be a tap; matches `HyperKeyTap.quickPressWindow`.
    static let maxHold: TimeInterval = 0.25
    /// Longest gap between the first tap's release and the second tap's press.
    static let maxGap: TimeInterval = 0.30

    /// A completed double-tap; the side is nil when the two taps came from different sides.
    struct Tap: Equatable, Sendable {
        let modifier: DoubleTapModifier
        let side: ModifierSide?
    }

    enum Input: Sendable {
        /// Which of the four eligible modifiers are now held, and whether `fn` is down too.
        case modifiers(
            Set<DoubleTapModifier>, sides: ModifierSides = .either, hasOtherModifiers: Bool)
        /// A key press or mouse click, which turns the press in flight into a chord.
        case otherInput
    }

    private var held: Set<DoubleTapModifier> = []
    private var press: (tap: Tap, startedAt: TimeInterval)?
    private var pendingTap: (tap: Tap, releasedAt: TimeInterval)?

    /// The double-tap that completed, fired on the second release, never the press.
    mutating func handle(_ input: Input, at now: TimeInterval) -> Tap? {
        switch input {
        case .otherInput:
            invalidate()
            return nil
        case .modifiers(let modifiers, let sides, let hasOtherModifiers):
            return handle(modifiers, sides: sides, hasOtherModifiers: hasOtherModifiers, at: now)
        }
    }

    mutating func reset() {
        held = []
        invalidate()
    }

    private mutating func handle(
        _ modifiers: Set<DoubleTapModifier>, sides: ModifierSides, hasOtherModifiers: Bool,
        at now: TimeInterval
    ) -> Tap? {
        let previous = held
        held = modifiers

        guard !hasOtherModifiers else {
            invalidate()
            return nil
        }
        if modifiers.isEmpty { return completeTap(at: now) }

        // A tap begins only from nothing held, so an unwinding chord isn't a fresh press.
        guard previous.isEmpty, modifiers.count == 1, let modifier = modifiers.first else {
            invalidate()
            return nil
        }
        press = (Tap(modifier: modifier, side: sides.side(of: modifier)), now)
        return nil
    }

    private mutating func completeTap(at now: TimeInterval) -> Tap? {
        guard let press, now - press.startedAt <= Self.maxHold else {
            invalidate()
            return nil
        }
        self.press = nil

        guard let pending = pendingTap, pending.tap.modifier == press.tap.modifier,
            press.startedAt - pending.releasedAt <= Self.maxGap
        else {
            pendingTap = (press.tap, now)
            return nil
        }
        pendingTap = nil
        return pending.tap.side == press.tap.side
            ? press.tap : Tap(modifier: press.tap.modifier, side: nil)
    }

    private mutating func invalidate() {
        press = nil
        pendingTap = nil
    }
}
