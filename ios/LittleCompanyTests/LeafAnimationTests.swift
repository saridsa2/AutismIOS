import XCTest
import Lottie
@testable import LittleCompany

@MainActor
final class LeafAnimationTests: XCTestCase {
    func testSpeakingPlaysAndMotionOffStopsPlayback() async throws {
        let animation = try XCTUnwrap(LottieAnimation.named("leaf-speaking", bundle: Bundle(for: Companion.self)))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        let view = LottieAnimationView(animation: animation)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        controller.view.addSubview(view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { view.stop(); window.isHidden = true; previous?.makeKeyAndVisible() }
        LeafAnimation.apply(speaking: true, motionEnabled: true, to: view)
        XCTAssertTrue(view.isAnimationPlaying)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(view.realtimeAnimationProgress, 0)
        LeafAnimation.apply(speaking: true, motionEnabled: false, to: view)
        XCTAssertFalse(view.isAnimationPlaying)
        XCTAssertEqual(view.currentProgress, 0, accuracy: 0.001)
    }

    func testVectorAssetAndMotionAreBounded() throws {
        let animation = try XCTUnwrap(LottieAnimation.named("leaf-speaking", bundle: Bundle(for: Companion.self)))
        XCTAssertEqual(animation.framerate, 30)
        XCTAssertEqual(animation.duration, 4, accuracy: 0.01)
        let url = try XCTUnwrap(Bundle(for: Companion.self).url(forResource: "leaf-speaking", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let layers = try XCTUnwrap(json["layers"] as? [[String: Any]])
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0]["ty"] as? Int, 4, "Must remain vector artwork")
        let transform = try XCTUnwrap(layers[0]["ks"] as? [String: Any])
        let rotation = try XCTUnwrap(transform["r"] as? [String: Any])
        let frames = try XCTUnwrap(rotation["k"] as? [[String: Any]])
        for frame in frames {
            let angle = try XCTUnwrap((frame["s"] as? [Double])?.first)
            XCTAssertLessThanOrEqual(abs(angle), 2)
        }
    }

    func testListeningAndDisabledMotionResetToStillFrame() throws {
        let animation = try XCTUnwrap(LottieAnimation.named("leaf-speaking", bundle: Bundle(for: Companion.self)))
        let view = LottieAnimationView(animation: animation)
        for (speaking, enabled) in [(false, true), (true, false), (false, false)] {
            view.currentProgress = 0.25
            LeafAnimation.apply(speaking: speaking, motionEnabled: enabled, to: view)
            XCTAssertFalse(view.isAnimationPlaying)
            XCTAssertEqual(view.currentProgress, 0, accuracy: 0.001)
        }
    }
}
