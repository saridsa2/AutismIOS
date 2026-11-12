# Universal app and speaking animation

The app targets iPhone and iPad. Compact windows stack the greeting and leaf; wide landscape windows place them side by side. Accessibility text sizes use a scrollable single column. Safe-area insets protect the bottom controls and iPhone sensor housing.

Native iOS 26 Liquid Glass is applied to the caregiver button. The voice content remains on a quiet solid surface. Earlier systems and Reduce Transparency use the bordered control fallback. The app follows light/dark appearance, Dynamic Type, and system Reduce Motion.

The artwork was generated in the user's Freepik/Magnific Chrome session: https://www.magnific.com/app/creation/UPWgg39wny . The account's Essential tier still gated SVG export, so the downloaded PNG was color-separated and traced locally with ImageMagick and Potrace. Source: `assets/brand/leaf-source.png`; editable vectors: `leaf.svg`, `leaf-icon.svg`; animation: `leaf-speaking.json`. No creature artwork is used in the app.

`scripts/build-leaf-animation.mjs` converts the traced Bezier path into a native Lottie vector layer, produces the PDF asset and icon, and copies the animation to the iOS bundle. The four-second animation rotates at most two degrees about the stem. It plays only when a LiveKit agent is speaking and the app is active. Listening, paused, disconnected, motion-disabled, and Reduce Motion states display frame zero. This follows speaking activity, not individual phonemes or audio amplitude.

Caregivers can turn off “Animate leaf while speaking.” Suitability depends on the child's individual preferences; the visual design is not a clinical intervention.

References:
- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://github.com/airbnb/lottie-ios

Verification: simulator checks cover the iPhone 17 Pro portrait/landscape layouts, iPad Pro landscape, dark appearance, and largest accessibility text size. XCTest checks that the JSON is vector-based with bounded movement, actual Lottie playback advances, and disabling motion or listening restores a still frame. Physical device testing remains outstanding.
