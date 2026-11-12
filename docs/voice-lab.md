# Voice Lab prototype

Separate native Swift app: `app.littlecompany.voicelab`, version 0.1 (1). It does not replace or add recording to A Little Company. No Python is used. The independent XcodeGen project is `voice-lab/project.yml`.

## What it does

- Caregiver-triggered, 10-second, mono 16 kHz PCM16 recordings. No background recording. Leaving the foreground or an audio interruption cancels and removes an unfinished recording.
- Three accepted enrollment samples establish a profile. Additional samples refine its normalized mean embedding. A low similarity to the existing profile rejects a likely mixed-speaker enrollment sample.
- Local Core ML FBANK + WeSpeaker Community-1 inference produces 256-dimensional normalized embeddings. Fresh test recordings compare with enrolled centroids. Default cosine threshold 0.75, runner-up margin 0.08; below either criterion gives Unknown. The threshold is adjustable and UNCALIBRATED, not a probability or authentication mechanism.
- Energy, duration and clipping gates reject clearly unusable samples. This is an energy quality check, not a trained VAD, and cannot exclude all background noise or overlapping speakers. Accuracy for this family, child speech, Tamil/English, room noise and playback has not yet been measured.
- Capture and embedding-processing durations are stored with each sample locally and remotely. Upload round-trip duration is stored locally. These are not Gemini end-of-turn/first-audio latency metrics.
- Recordings and profile metadata use iOS complete file protection; the library is excluded from backups. Credentials use a separate Keychain service. Local samples persist until deleted.
- Sign in with an existing Little Company account. Explicitly enable sample upload, then tap Upload pending samples. Failed uploads retain the local files and can be retried with the same idempotency ID.
- Remote WAV files are in the private `voice-lab` bucket. Metadata/fingerprints are in `voice_lab_samples`, with owner RLS. The API authenticates every operation, validates audio format and bounds, and accepts only the pinned model identifier.
- Remote samples expire after 30 days; a cleanup runs at API startup and hourly, up to 100 expired samples per run. Account deletion does not currently provide an app UI; deletion of an individual uploaded sample removes its remote file and row before local removal. Local recordings are not automatically expired.

## Model provenance

Publisher: https://huggingface.co/FluidInference/speaker-diarization-coreml

Pinned revision: `df2625ac79a7ac6b65ad868fee6d80f320da4232`.

Only the explicitly licensed Community-1 `FBank.mlmodelc` and `Embedding.mlmodelc` artifacts are bundled (approximately 15 MB). No legacy WeSpeaker artifacts are used. Models are modified Core ML conversions licensed CC BY 4.0; attribution includes pyannote, WeSpeaker, BUT Speech@FIT and Fluid Inference. LICENSE, NOTICE, provenance and a download SHA-256 manifest are bundled in Models. The prototype's adapter is native Swift/Core ML with no FluidAudio runtime dependency.

Re-download: `node voice-lab/scripts/download-models.mjs`.

## Build and verification

```sh
xcodegen generate --spec voice-lab/project.yml
xcodebuild -project voice-lab/VoiceLab.xcodeproj -scheme VoiceLab -destination 'platform=iOS Simulator,id=7089F03A-15FE-453E-8194-30AFCFCF0FCA' -derivedDataPath .build/voice-lab test
```

Swift tests cover invalid vectors, silence/clipping rejection, ambiguity/unknown handling, and actual bundled-model inference on a synthetic signal. Synthetic inference is an execution test, not speaker-accuracy validation.

`backend/src/voice-lab.test.ts` checks WAV format, truncation, duration and metadata constraints. `voice-lab/scripts/check-remote.mjs`, run inside the API container, creates and removes two temporary accounts and a synthetic WAV to test authenticated upload, idempotency, cross-account RLS and storage isolation, and owner deletion. Never use real family recordings as integration fixtures.

Migration: `deploy/supabase/migrations/002_voice_lab.sql`. Routes: authenticated POST `/api/voice-lab/samples` and DELETE `/api/voice-lab/samples/:id`. Deployed only to the Little Company API and its separate Supabase instance; existing voice agent and other VPS applications are unchanged.

## Next validation

Record three natural samples each for two consenting speakers. Test new phrases from both, plus an unenrolled speaker. Compare quiet-room and ordinary-room results; measure false accepts and false rejects before selecting a threshold. Do not use this prototype as a login or an authorization factor. Matching has not yet been connected to Gemini personalization. Full conversation latency tracing, VAD tuning and automatic speaker-context routing are separate work.

## Verification on 2026-09-30

- Four Swift tests passed, including actual Core ML inference; nine backend tests passed.
- Live VPS integration test passed authenticated upload, idempotency, private retrieval, cross-account isolation, and deletion. Temporary accounts and synthetic test data were removed afterward.
- Final simulator and generic-device builds succeeded for both apps. Voice Lab is installed and launched in the iPad simulator; A Little Company build 4 is installed alongside it.
- Physical iPad installation is pending reconnection. The generic Voice Lab development profile does not yet include Udaya's iPad UDID; build again with that connected device as destination and `-allowProvisioningDeviceRegistration`. Do not treat the current generic-device app as ready to install on that iPad.
