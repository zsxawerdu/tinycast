import CoreGraphics
import Foundation

struct WindowThrowGesture: Sendable {
    enum Direction: CaseIterable, Sendable {
        case left, right, up, down

        var command: WindowCommand.ID {
            switch self {
            case .left: .leftHalf
            case .right: .rightHalf
            case .up: .maximize
            case .down: .center
            }
        }
    }

    enum Chord: String, CaseIterable, Identifiable, Sendable {
        case controlOption, controlShift, controlCommand, optionShift, optionCommand, shiftCommand
        var id: String { rawValue }
        var title: String {
            switch self {
            case .controlOption: "⌃ ⌥"
            case .controlShift: "⌃ ⇧"
            case .controlCommand: "⌃ ⌘"
            case .optionShift: "⌥ ⇧"
            case .optionCommand: "⌥ ⌘"
            case .shiftCommand: "⇧ ⌘"
            }
        }
        var flags: UInt64 {
            switch self {
            case .controlOption: (1 << 18) | (1 << 19)
            case .controlShift: (1 << 18) | (1 << 17)
            case .controlCommand: (1 << 18) | (1 << 20)
            case .optionShift: (1 << 19) | (1 << 17)
            case .optionCommand: (1 << 19) | (1 << 20)
            case .shiftCommand: (1 << 17) | (1 << 20)
            }
        }
    }

    enum Action { case begin, commit(Direction), cancel }
    private var origin: CGPoint?
    private var direction: Direction?
    private var awaitingRelease = true
    private static let modifierMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 23)

    mutating func cancel() {
        origin = nil
        direction = nil
        awaitingRelease = true
    }

    mutating func update(flags: UInt64, point: CGPoint, chord: Chord, interrupted: Bool = false) -> Action? {
        if interrupted {
            cancel()
            return .cancel
        }
        let held = flags & Self.modifierMask
        if awaitingRelease {
            if held & chord.flags == 0 { awaitingRelease = false }
            return nil
        }
        if let origin {
            if held & ~chord.flags != 0 {
                cancel()
                return .cancel
            }
            if held != chord.flags {
                let selected = direction
                cancel()
                if held & chord.flags == 0 { awaitingRelease = false }
                return selected.map(Action.commit) ?? .cancel
            }
            let x = point.x - origin.x
            let y = point.y - origin.y
            guard hypot(x, y) >= 40 else {
                direction = nil
                return nil
            }
            let horizontal = abs(x) >= abs(y)
            if let direction {
                let wasHorizontal = direction == .left || direction == .right
                if wasHorizontal != horizontal, abs(abs(x) - abs(y)) < 12 { return nil }
            }
            direction = horizontal ? (x < 0 ? .left : .right) : (y < 0 ? .up : .down)
            return nil
        }
        guard held == chord.flags else { return nil }
        origin = point
        return .begin
    }
}
