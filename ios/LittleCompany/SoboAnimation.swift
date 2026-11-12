import SwiftUI
import RiveRuntime

/// One artboard and one state machine for the entire conversation.
/// Pose transitions belong to the Rive rig, never to SwiftUI opacity layers.
struct SoboAnimation: UIViewRepresentable {
    let speaking: Bool
    let motionEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RiveView {
        let view = context.coordinator.character.createRiveView()
        view.isUserInteractionEnabled = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: RiveView, context: Context) {
        context.coordinator.character.apply(speaking: speaking, motionEnabled: motionEnabled)
    }

    static func dismantleUIView(_ view: RiveView, coordinator: Coordinator) {
        coordinator.character.pause()
        coordinator.character.deregisterView()
    }

    final class Coordinator {
        let character = SoboStateMachine()
    }
}

final class SoboStateMachine: RiveViewModel {
    // Retain the exact instance bound to this artboard; do not recreate on speech changes.
    private(set) var binding: RiveDataBindingViewModel.Instance?
    private var motionEnabled = false
    private var speaking = false

    init() {
        super.init(fileName: "sobo", stateMachineName: "State Machine",
                   autoPlay: false, artboardName: "SOBO-Motion-V01", loadCdn: false)
        riveModel?.enableAutoBind { [weak self] instance in
            guard let self else { return }
            self.binding = instance
            self.updateState()
        }
    }

    func apply(speaking: Bool, motionEnabled: Bool) {
        self.speaking = speaking
        self.motionEnabled = motionEnabled
        updateState()
        if motionEnabled {
            if !isPlaying { play() }
        } else {
            // Freeze in place; stopping/resetting would snap back to a different pose.
            pause()
        }
    }

    private func updateState() {
        // Verified against the asset: 0 = Idle, 2 = Listen, 4 = Talk.
        // Keep the neutral Idle breathing motion between utterances.
        guard motionEnabled else { return }
        let next: Float = speaking ? 4 : 0
        if let state = binding?.numberProperty(fromPath: "numState"), state.value != next {
            state.value = next
        }
    }
}
