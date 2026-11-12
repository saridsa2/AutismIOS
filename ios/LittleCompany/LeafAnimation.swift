import SwiftUI
import Lottie

struct LeafAnimation: UIViewRepresentable {
    let speaking: Bool
    let motionEnabled: Bool

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: "leaf-speaking")
        view.contentMode = .scaleAspectFit
        view.loopMode = .loop
        view.backgroundBehavior = .pauseAndRestore
        view.isAccessibilityElement = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: LottieAnimationView, context: Context) {
        Self.apply(speaking: speaking, motionEnabled: motionEnabled, to: view)
    }

    static func apply(speaking: Bool, motionEnabled: Bool, to view: LottieAnimationView) {
        if speaking && motionEnabled {
            if !view.isAnimationPlaying { view.play() }
        } else {
            view.stop()
            view.currentProgress = 0
        }
    }

    static func dismantleUIView(_ view: LottieAnimationView, coordinator: ()) {
        view.stop()
    }
}
