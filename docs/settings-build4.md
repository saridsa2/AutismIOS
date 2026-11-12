# Settings build 4

Caregiver settings now use a NavigationStack destination instead of a modal sheet. The connection switch and Pause/Resume listening are in Conversation. Switching off disconnects and cancels retry intent; the switch is disabled during an in-flight connection. Existing companion/Rive playback is unchanged.

The Kiosk section provides Open Settings and the Accessibility → Guided Access path. The current public `AccessibilitySettings.Feature` enum does not expose Guided Access; the app does not use private App-Prefs URLs. The supported link opens this app's Settings page, from which the caregiver navigates back to Accessibility. Guided Access still starts via the device's top/Home button shortcut.

A Little Company version 1.0 (4) is separate from Voice Lab 0.1 (1). No voice recording, biometric model or sample-upload UI is added to the companion build.
