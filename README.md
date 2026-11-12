# A Little Company

Native SwiftUI voice companion for iPhone and iPad, with a TypeScript LiveKit agent using Gemini Live, a TypeScript API, and an independent Supabase instance on Hostinger. No Python.

## App

Open `ios/LittleCompany.xcodeproj`, select the LittleCompany scheme, and run on iPhone or iPad. Generate the project with `xcodegen generate --spec ios/project.yml` after adding files.

In **Grown-ups**, create an account with email/password, enter the emailed verification code, and add the child's name and family context. Returning caregivers sign in once. Password recovery also uses a code entered in the app. The app connects only to our fixed HTTPS backend; there are no URL, device-token, admin-token, or provider-key fields.

Account sessions are stored in Keychain, refreshed automatically, and survive relaunch. Each device has its own refresh session. On physical devices, opening caregiver settings after sign-in requires device passcode or biometrics; the simulator skips this gate for development. Family context belongs to the authenticated account and is shared between its devices. Comfort preferences remain local to each device.

The child-facing screen stays voice-only. Family context is loaded for each new agent session. MusicKit plays requested music on-device. Enable MusicKit on your Apple App ID and test Apple Music permissions, subscription playback, and microphone/music coexistence on real hardware. Enable Guided Access for kiosk use.

## Backend

Node.js 22:

```sh
cd backend
npm ci
npm run build
npm test
```

Use `deploy/.env.example` for server configuration. The API uses Supabase Auth to verify requests, then queries with the user's JWT so database row-level security applies. The voice worker receives account/session IDs through server-controlled LiveKit dispatch, validates the session/room relationship, and reads that family's profile with server-only credentials. No family context is embedded in the LiveKit token.

Routes:

- `/auth/sign-up`, `/auth/verify`, `/auth/resend`: registration and verification.
- `/auth/sign-in`, `/auth/refresh`, `/auth/sign-out`: account sessions.
- `/auth/recover`, `/auth/reset`: password recovery.
- `GET /account`, `PUT /device`: account and device tracking.
- `GET/PUT /profile`: account-owned family context.
- `POST /session`: authenticated room token and agent dispatch.
- `GET /health`: API liveness, not Gemini readiness.

Supabase stores family profiles, device last-seen timestamps, and voice session requests/status/start/end timestamps. Audio and transcripts are not stored by this app. Requested sessions that never reach the worker remain `requested`; counts do not imply successful conversations or billing usage. Separate new conversations do not have persistent transcript memory.

## Deployment and verification

See [deployment](docs/deployment.md), [Supabase setup](deploy/supabase/README.md), and [account integration](docs/accounts.md).

Backend tests cover authentication failure, cross-account request scoping, token claims, quota cooldown, upstream failures, and owner-only legacy migration. `scripts/check-accounts.mjs` additionally verifies real Supabase Auth and RLS, using temporary QA users and deleting their rows afterward. It must run inside the API container with server environment, never in the app.

Simulator builds require `CODE_SIGNING_ALLOWED=YES` and `ios/Simulator.entitlements`. `scripts/connect-simulator.mjs` uses private local caregiver credentials in `.build` to provision a normal, distinct account session for each debug simulator. No credentials are bundled in the app. Voice diagnostics use the separately saved `.build/account-session.json`.

Gemini availability still depends on the Google API project's quota. Quota failures suspend automatic reconnection and show “Voice unavailable.”
