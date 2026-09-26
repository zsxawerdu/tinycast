import CoreGraphics
import Foundation

@main
struct WindowThrowTests {
    static func main() {
        var gesture = WindowThrowGesture()
        let chord = WindowThrowGesture.Chord.controlOption
        func step(_ flags: UInt64, _ x: CGFloat = 0, _ y: CGFloat = 0, interrupted: Bool = false)
            -> WindowThrowGesture.Action?
        {
            gesture.update(flags: flags, point: CGPoint(x: x, y: y), chord: chord, interrupted: interrupted)
        }
        _ = step(0)
        guard case .begin = step(chord.flags) else { fatalError("begin") }
        _ = step(chord.flags, 80)
        guard case .commit(.right) = step(1 << 18, 80) else { fatalError("release commits") }
        assert(step(chord.flags) == nil)
        _ = step(0)
        _ = step(chord.flags)
        _ = step(chord.flags, 80)
        _ = step(chord.flags, 10)
        guard case .cancel = step(0) else { fatalError("dead zone cancels") }
        _ = step(chord.flags)
        _ = step(chord.flags, 0, -80)
        guard case .commit(.up) = step(0) else { fatalError("AX up") }
        _ = step(chord.flags)
        _ = step(chord.flags, -80)
        _ = step(chord.flags, -80, interrupted: true)
        assert(step(0) == nil)
        _ = step(chord.flags)
        _ = step(chord.flags, -80)
        guard case .cancel = step(chord.flags | (1 << 20)) else { fatalError("extra modifier") }
        _ = step(0)
        _ = step(chord.flags)
        _ = step(chord.flags, 70, 60)
        _ = step(chord.flags, 60, 70)
        guard case .commit(.right) = step(0) else { fatalError("hysteresis") }
        assert(WindowThrowGesture.Direction.left.command == .leftHalf)
        assert(WindowThrowGesture.Direction.right.command == .rightHalf)
        assert(WindowThrowGesture.Direction.up.command == .maximize)
        assert(WindowThrowGesture.Direction.down.command == .center)
        assert(Set(WindowThrowGesture.Chord.allCases.map(\.flags)).count == 6)
        assert(WindowThrowGesture.Chord.allCases.allSatisfy { $0.flags.nonzeroBitCount == 2 })
        print("PASS: Window throw gesture and directional commands")
    }
}
