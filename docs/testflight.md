# TestFlight

- App: A Little Company
- Bundle ID: `app.littlecompany.companion`
- Apple Developer team: `2NPACMVW3K` (Satya Suman Saridae)
- App Store Connect app ID: `6817328489`
- Version: 1.0, current build 3
- Internal group: Internal Testing (manual build distribution)

Build 1 uploaded on 2026-09-29 but Apple subsequently rejected processing with ITMS-90683: LiveKit references camera APIs, requiring NSCameraUsageDescription even though the app never enables camera capture. Build 2 adds an accurate voice-only camera declaration.

Apple confirmed build 2 completed processing on 2026-09-29. Its export questionnaire declares standard encryption beyond Apple's OS (WebRTC) and no distribution in France for this owner-only internal beta. Revisit the distribution declaration before expanding testing to France; do not claim the app contains no encryption.

Build 1.0 (2) is assigned to Internal Testing with the account owner as its sole tester. What to Test notes are saved, including the unresolved voice behavior. No external group or public testing link has been created.

Upload reported missing vendor dSYMs for LiveKitWebRTC and RustLiveKitUniFFI; these warnings did not block the upload, but limit symbolication of crashes inside those frameworks.

## Build 3 (2026-09-30)

Uploaded successfully. Adds full-screen Sobo with a single Rive artboard/state machine for Talk and Idle, removes image crossfades and filler text, and uses the agent speech-state attribute. The user verified the final animation locally; native state-transition regression tests passed. Apple processing completed. The unchanged export-compliance declaration was saved, and build 1.0 (3) was assigned to Internal Testing (1 tester), with What to Test notes saved. App Store Connect build ID: `8df2608a-4448-4c45-a320-a45e129bb0b1`.

Archive: `.build/LittleCompany-build3.xcarchive`. Upload log: `.build/testflight-build3-upload.log`. What to Test notes: `.build/testflight-build3-notes.txt`. The same two vendor dSYM warnings remain nonblocking.

## External beta (2026-09-30)

Created the private external group Family Testing (`2ac13f62-5551-4f94-91e4-47aa7035983a`) and added the single tester requested by the owner. Build 1.0 (3) is assigned and submitted to Apple; verified status: Waiting for Review. Automatically notify testers is enabled. No public invitation link was created.

The owner supplied review contact details. A separate empty reviewer account was created and its password login verified, without sharing the owner's app account or family profile. Credentials were entered in Apple's review form and retained only in a root-readable file on the VPS (`/root/little-company-apple-review.json`), not in this repository.

## Build and upload

```sh
xcodegen generate --spec ios/project.yml
xcodebuild -project ios/LittleCompany.xcodeproj -scheme LittleCompany \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath .build/release -clonedSourcePackagesDirPath .build/packages \
  -archivePath .build/LittleCompany.xcarchive -allowProvisioningUpdates archive
PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/xcodebuild -exportArchive \
  -archivePath .build/LittleCompany.xcarchive -exportPath .build/testflight \
  -exportOptionsPlist ios/ExportOptions.plist -allowProvisioningUpdates
```

Use the system PATH for export: Apple's packaging invokes `/usr/bin/rsync`, which fails when its child process resolves Homebrew rsync with incompatible extended-attribute options.

## First beta checks

Sign in with a caregiver account. Verify microphone permission, connection, a spoken reply, interruption, long quiet pauses, and Disconnect. Check both iPhone and iPad layouts. Apple Music requires permission and an eligible subscription.

The backend audio return path passed after the Gemini key update. Simulator media connections were still unreliable, and repeated speech was reported; neither issue is claimed fixed by this release. Test quiet-room behavior and speaker feedback on a physical device with adult supervision.

The release contains the server URL only. Provider credentials and Supabase service keys remain on the VPS. Debug simulator account injection is excluded from the Release build.
