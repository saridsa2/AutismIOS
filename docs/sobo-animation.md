# Sobo companion animation

- Asset: `ios/LittleCompany/Resources/sobo.riv`, supplied by the user.
- Creator: Patgrivet.
- Source: https://rive.app/marketplace/28761-54484-sobo/
- License listed by the creator: Creative Commons Attribution 4.0, https://creativecommons.org/licenses/by/4.0/.
- Attribution is visible in the caregiver Artwork section.
- The original file is unchanged. Little Company uses one `SOBO-Motion-V01` artboard and its `State Machine`. Its bound `numState` property selects Idle (0) or Talk (4), with transitions handled inside the rig. This version includes mouth movement in Talk. There are no overlapping Rive views, opacity fades, delayed view swaps, or timeline resets when speech ends. The rig maintains its own ambient layers; the app does not fire its bump trigger.
- Rive 6.27.0 is pinned. The asset loads locally with CDN asset loading disabled.
- Motion pauses in place when the app is inactive or either app/system Reduce Motion is enabled. The existing animation preference remains supported. Paused and disconnected conversation states select Idle rather than Talk.
- Speech detection uses LiveKit AgentSession's `lk.agent.state` attribute when present, falling back to `isSpeaking` when absent. This avoids depending solely on audio-level notifications.

Validation: the supplied file loaded in the official Rive web runtime; the artboard and animation names were enumerated and Talk was visually previewed. Simulator builds passed. The user confirmed motion works after disabling the saved Reduce Motion preference. Physical-device validation is pending. Released to the existing internal TestFlight group as 1.0 (3) on 2026-09-30.

The character canvas occupies the available screen with controls overlaid at the bottom. Greetings, taglines and other filler text were removed. `SoboAnimationTests` drives the actual rig through repeated speech transitions and verifies that the same artboard and state-machine instances are retained.
