import XCTest
import RiveRuntime
@testable import LittleCompany

@MainActor
final class SoboAnimationTests: XCTestCase {
    func testSpeechTransitionsKeepOneArtboardAndStateMachine() throws {
        let character = SoboStateMachine()
        let view = character.createRiveView()
        defer { character.pause(); character.deregisterView() }
        let artboard = try XCTUnwrap(character.riveModel?.artboard)
        let machine = try XCTUnwrap(character.riveModel?.stateMachine)
        let state = try XCTUnwrap(character.binding?.numberProperty(fromPath: "numState"))
        character.apply(speaking: false, motionEnabled: true)
        XCTAssertEqual(state.value, 0)
        // The view initializes Idle before the test starts observing transitions.
        for _ in 0..<30 { view.advance(delta: 1.0 / 60.0) }
        for (speaking, expected) in [(true, Float(4)), (false, Float(0)), (true, Float(4)), (false, Float(0))] {
            character.apply(speaking: speaking, motionEnabled: true)
            var transitions: [String] = []
            for _ in 0..<30 {
                view.advance(delta: 1.0 / 60.0)
                transitions.append(contentsOf: machine.stateChanges())
            }
            XCTAssertTrue(transitions.contains(speaking ? "Talk" : "Idle"), "Expected \(speaking ? "Talk" : "Idle"), observed \(transitions)")
            XCTAssertEqual(state.value, expected)
            XCTAssertTrue(character.riveModel?.artboard === artboard)
            XCTAssertTrue(character.riveModel?.stateMachine === machine)
            XCTAssertNil(character.riveModel?.animation, "Speech must use the rig's state machine, not replace timeline players")
        }
        character.apply(speaking: false, motionEnabled: false)
        XCTAssertFalse(character.isPlaying)
        XCTAssertTrue(character.riveModel?.artboard === artboard)
        XCTAssertTrue(character.riveModel?.stateMachine === machine)
    }
}
