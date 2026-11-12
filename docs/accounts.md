# Account integration — 2026-09-29

The mobile app uses `https://srv1938927.hstgr.cloud/api` exclusively. Supabase stays behind the API on its private network. Its API/Studio gateway is loopback port 8002; the existing Supabase project is untouched.

## Data and access

Migration: `deploy/supabase/migrations/001_accounts.sql`.

- `auth.users`: caregiver identity, verified email, encrypted password hash.
- `care_profiles`: one family profile per caregiver account (name, current plans, context).
- `devices`: app-generated installation UUID, platform, last seen.
- `voice_sessions`: requested room, owner, installation, lifecycle state and timestamps.

All public tables have RLS. Anonymous access is revoked. Clients cannot read or mutate another account's rows. Service-role keys are used only by server processes and never returned to iOS. API responses disable caching and logs redact authorization/body values.

The API validates Supabase users through `getUser(jwt)`. Account endpoints are rate-limited. Short-lived LiveKit room tokens carry only dispatch IDs, not private profile content. The worker validates account/session/room before loading context.

The original shared tokens no longer authorize any app endpoint. Existing family context is imported only when the verified email matches `LEGACY_PROFILE_OWNER_EMAIL` and that user has no profile row. A saved profile is never overwritten by this migration. The original source is archived in the private companion-data volume, not copied to new accounts.

## Email

The dedicated Supabase Auth instance reuses the existing Hostinger SMTP configuration, with sender `hello@sarvathra.ai` and display name **Little Company**. Credentials were copied directly between server environment files, not into the repository.

Sign-up and recovery templates are served internally by the API at `/mail/confirmation` and `/mail/recovery`. Supabase renders `{{ .Token }}` and sends the email. Codes expire in 10 minutes. Public sign-up is enabled, email confirmation required, minimum password length 10. Phone/anonymous signup remains disabled.

Set the following environment in the new Supabase Auth Compose service:

```yaml
GOTRUE_MAILER_TEMPLATES_CONFIRMATION: http://little-company-api-1:3000/mail/confirmation
GOTRUE_MAILER_TEMPLATES_RECOVERY: http://little-company-api-1:3000/mail/recovery
GOTRUE_PASSWORD_MIN_LENGTH: 10
GOTRUE_MAILER_OTP_EXP: 600
```

Its `.env` must have `DISABLE_SIGNUP=false`, `ENABLE_EMAIL_AUTOCONFIRM=false`, and working SMTP values. Keep the dashboard and database ports on loopback.

## Operations

API container uses `SUPABASE_URL=http://lc-supabase-envoy:8000` on the private Supabase network. Agent uses host networking and overrides it to `http://127.0.0.1:8002`. Both get the new instance's keys from the private app environment file.

To run real account checks, copy `scripts/check-accounts.mjs` into `/app/check-accounts.mjs` in the API container and execute `node /app/check-accounts.mjs`. It creates QA-only users, tests verification/login/recovery/refresh/logout, tries cross-account reads and writes directly against PostgREST, verifies device/session tracking, and removes those users in a finally block. No emails are sent by this check; tokens are generated administratively for QA only.

The VPS Linux native LiveKit binding is an explicit pinned optional dependency. Docker builds import `@livekit/rtc-node` to fail immediately if the platform binary is absent, rather than deploying a restarting worker. Update its version alongside the parent FFI binding.

No recordings or transcripts are written. Database/storage backups and recovery drills still need separate operational setup before a wider rollout.

## Verification performed

- Six local API tests passed, including verified-owner migration.
- Live Supabase smoke test passed verification, password login/recovery, refresh,
  sign-out, device/session tracking, anonymous denial and cross-account RLS.
- User received and supplied an emailed verification code; the first caregiver
  account was verified and its original family context imported.
- iPhone and iPad builds installed with separate account sessions. Normal relaunch
  retained sign-in. iPhone sign-in/account forms and both child layouts inspected.
- Backend image passed its Linux native-runtime import and worker registration.
- Voice diagnostic reached the account-scoped agent but did not return audible
  output: Gemini again reported quota exceeded. This is not an account failure.
