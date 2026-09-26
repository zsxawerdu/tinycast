import Foundation

/// The launcher and clipboard stay reachable one way, and a typed question goes to Quick AI.
@main
@MainActor
struct PaletteTabTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ actual: PaletteTabAction, _ expected: PaletteTabAction, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func resolve(
        _ mode: PaletteMode, query: Bool = false, ai: Bool = true, clipboard: Bool = true
    ) -> PaletteTabAction {
        PaletteTabAction.resolve(
            mode: mode, hasQuery: query, aiEnabled: ai, clipboardEnabled: clipboard)
    }

    static func main() {
        expect(
            resolve(.launcher, query: true), .ask,
            "the launcher hands the typed text to Quick AI as the question")
        expect(
            resolve(.launcher), .carryQuery(.clipboard),
            "with nothing typed there is no question, so Tab rings on to the clipboard")
        expect(
            resolve(.clipboard, query: true), .carryQuery(.launcher),
            "the clipboard closes the ring, and one search narrows both lists")

        // Off, Quick AI has no command and no hotkey; the ring must not strand a reader there.
        expect(
            resolve(.launcher, query: true, ai: false), .carryQuery(.clipboard),
            "turned off, a typed query rings on to the clipboard instead of asking")
        expect(
            resolve(.clipboard, ai: false), .carryQuery(.launcher),
            "turned off, the clipboard still returns to the launcher")

        // A sub-screen is reached by a command or a hotkey, so Tab leaves rather than ringing on.
        for mode in [PaletteMode.emoji, .fileSearch, .calculatorHistory, .quicklinks, .snippets] {
            expect(
                resolve(mode, query: true), .carryQuery(.launcher),
                "\(mode.rawValue) is a sub-screen, so Tab exits to the launcher")
        }
        expect(
            resolve(.extensionCommand), .carryQuery(.launcher),
            "an extension command exits to the launcher rather than joining the ring")

        // Both stops off, so Tab has nowhere to ring on to and must leave the launcher standing.
        expect(
            resolve(.launcher, ai: false, clipboard: false), .carryQuery(.launcher),
            "with the clipboard off too, the launcher rings back onto itself")
        expect(
            resolve(.launcher, clipboard: false), .carryQuery(.launcher),
            "with the clipboard off and nothing typed, the launcher rings back onto itself")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
