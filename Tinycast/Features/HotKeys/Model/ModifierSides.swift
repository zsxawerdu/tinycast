import Foundation

/// Device-level modifier bits from IOLLEvent.h, which say which side's key is down.
enum DeviceModifierFlag {
    static let leftControl: UInt64 = 0x0000_0001
    static let leftShift: UInt64 = 0x0000_0002
    static let rightShift: UInt64 = 0x0000_0004
    static let leftCommand: UInt64 = 0x0000_0008
    static let rightCommand: UInt64 = 0x0000_0010
    static let leftOption: UInt64 = 0x0000_0020
    static let rightOption: UInt64 = 0x0000_0040
    static let rightControl: UInt64 = 0x0000_2000
}

enum ModifierSide: String, Codable, Sendable {
    case left
    case right

    /// A sided keycap reads "L⌘" or "R⌘"; a letter, because an arrow already means an arrow key.
    func marking(_ glyph: String) -> String {
        switch self {
        case .left: "L" + glyph
        case .right: "R" + glyph
        }
    }
}

/// Which side's ⌃, ⌥ or ⌘ a shortcut asks for, where nil means either; ⇧ is never sided.
struct ModifierSides: Hashable, Codable, Sendable {
    var control: ModifierSide?
    var option: ModifierSide?
    var command: ModifierSide?

    static let either = ModifierSides()

    init(control: ModifierSide? = nil, option: ModifierSide? = nil, command: ModifierSide? = nil) {
        self.control = control
        self.option = option
        self.command = command
    }

    /// A lone modifier's side, the shape a double-tap routes through `winner` with.
    init(_ modifier: DoubleTapModifier, side: ModifierSide?) {
        switch modifier {
        case .control: control = side
        case .option: option = side
        case .command: command = side
        case .shift: break
        }
    }

    /// Reads the sides off an event's raw flags; both sides of one modifier held reads as either.
    init(rawEventFlags flags: UInt64) {
        typealias Flag = DeviceModifierFlag
        control = Self.side(in: flags, left: Flag.leftControl, right: Flag.rightControl)
        option = Self.side(in: flags, left: Flag.leftOption, right: Flag.rightOption)
        command = Self.side(in: flags, left: Flag.leftCommand, right: Flag.rightCommand)
    }

    /// ⇧ always answers nil: it is never sided.
    func side(of modifier: DoubleTapModifier) -> ModifierSide? {
        switch modifier {
        case .control: control
        case .option: option
        case .command: command
        case .shift: nil
        }
    }

    /// Whether a press with `pressed` sides meets every side this one asks for.
    func isSatisfied(by pressed: ModifierSides) -> Bool {
        (control == nil || control == pressed.control)
            && (option == nil || option == pressed.option)
            && (command == nil || command == pressed.command)
    }

    /// Which of several bindings on one chord a press fires. See docs/features/hotkeys.md.
    static func winner(
        among candidates: [String: ModifierSides], pressed: ModifierSides, distinguishing: Bool
    ) -> String? {
        let eligible = distinguishing ? candidates.filter { $0.value.isSatisfied(by: pressed) } : candidates
        return eligible.min { lhs, rhs in
            let (left, right) = (lhs.value.sidedCount, rhs.value.sidedCount)
            if left != right { return distinguishing ? left > right : left < right }
            return lhs.key < rhs.key
        }?.key
    }

    private var sidedCount: Int { [control, option, command].compactMap(\.self).count }

    private static func side(in flags: UInt64, left: UInt64, right: UInt64) -> ModifierSide? {
        switch (flags & left != 0, flags & right != 0) {
        case (true, false): .left
        case (false, true): .right
        default: nil
        }
    }
}
