import Foundation

/// Tab rings the launcher and the clipboard; typed text on the launcher is a question for Quick AI.
enum PaletteTabAction: Equatable {
    /// The typed text rides along, because both ends narrow their own list by the same query.
    case carryQuery(PaletteMode)
    /// The typed text is the question, so Quick AI opens on the answer rather than an empty composer.
    case ask

    static func resolve(
        mode: PaletteMode, hasQuery: Bool, aiEnabled: Bool, clipboardEnabled: Bool
    ) -> Self {
        switch mode {
        // A stop that is off leaves the ring, so Tab skips it rather than opening nothing.
        case .launcher:
            if aiEnabled, hasQuery { return .ask }
            return clipboardEnabled ? .carryQuery(.clipboard) : .carryQuery(.launcher)
        default: return .carryQuery(.launcher)
        }
    }
}
