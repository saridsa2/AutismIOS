# Hostinger deployment

Deployed host: `srv1938927.hstgr.cloud`. No SSH password or Gemini API key is stored in this project. See the deployment record below for the active configuration.

Use a Linux VPS with Docker Engine and Docker Compose. This deployment uses host networking for LiveKit and the worker; it is intended for Linux, not ordinary shared web hosting. Inspect existing services and port usage before starting Caddy or changing firewalls.

1. Point two DNS A records (for example `api.your-domain` and `voice.your-domain`) at the VPS public IP. Avoid an HTTP-only proxy for the LiveKit hostname.
2. Copy the project without `.build`, `node_modules`, or secrets to a dedicated deployment directory.
3. Copy `deploy/.env.example` to `deploy/.env`; configure the dedicated Supabase URL and keys, and generate strong LiveKit API key and secret values. Add the Gemini API key privately on the server. Set API_DOMAIN, LIVEKIT_DOMAIN, and LIVEKIT_PUBLIC_URL.
4. Copy `deploy/livekit.example.yaml` to `deploy/livekit.yaml`; set matching LiveKit key/secret and TURN domain. These YAML values are literal; Compose does not substitute them. Set restrictive file permissions on both secret files.
5. Ensure ports are available and permitted in both the Hostinger firewall and OS firewall:
   - TCP 80 and 443: Caddy HTTPS and certificate issuance.
   - TCP 7881: WebRTC TCP fallback.
   - UDP 50000–50100: WebRTC media.
   - UDP 3478: built-in TURN.
   - Keep TCP 7880, 3000 and agent health ports blocked from the public internet. API 3000 is published on loopback only. LiveKit 7880 is reached through Caddy.
   - Preserve the actual SSH port; do not replace existing firewall rules wholesale.
6. From `deploy`, run `docker compose -f compose.yml config --quiet`, then `docker compose -f compose.yml up -d --build`.
7. Check `docker compose -f compose.yml ps` and service logs. Confirm the worker registers under `little-company-agent`. Verify `https://API_DOMAIN/health`, then an authenticated `/session` request and actual agent join/audio from the iPad.

This initial config provides TURN/UDP and ICE/TCP. Networks allowing only TLS on 443 may need a dedicated TURN/TLS hostname, certificate, and listener arrangement; that path is not configured or tested here.

Caddy owns host ports 80/443 in this template. If the VPS already has a reverse proxy, integrate the two routes there instead of launching a conflicting listener. LiveKit runs without Redis for this single-node setup. The profile and Caddy certificate volumes persist across container restarts. Back up the companion-data volume before changing deployments.

Apple setup: enable MusicKit on the app identifier, sign with your developer team, authorize the subscription in the caregiver screen, and test playback on physical hardware. No developer key or Apple subscription token is shipped in the app.

Acceptance run: connection + microphone permission; spontaneous voice response; intentional quiet; pause/resume listening; ABBA/play/pause/next/repeat; speaking over music; network loss and recovery; agent restart; session beyond the model's initial duration; app relaunch; Guided Access. Keep the model's silence/turn-timing behavior under caregiver review.

Reference: https://docs.livekit.io/transport/self-hosting/ports-firewall/

## Deployment performed on 2026-09-28

- Root SSH on port 22 verified.
- Project installed in `/opt/little-company`; Compose project name `little-company`.
- API exposed through `https://srv1938927.hstgr.cloud/api`; host mapping `127.0.0.1:3300` avoids an existing service on 3000.
- LiveKit uses `wss://srv1938927.hstgr.cloud`, with signaling bound to loopback behind the existing Caddy container `caddy-caddy-1`.
- Existing Caddy configuration at `/opt/vokoo/caddy/Caddyfile` was backed up to `Caddyfile.before-madhav-20260928`, extended with the block in `deploy/Caddyfile.hostinger`, validated, and reloaded.
- The standalone Caddy service is disabled on this host through a profile; existing services retain their listeners.
- LiveKit server updated to v1.13.7 after the real connection test found that v1.9.12 rejected the SDK's `RoomAgentDispatch.restartPolicy` token field.
- Private credentials reside on the VPS in `/opt/little-company/deploy/.env` and `livekit.yaml` (0600). Gemini is configured and the TypeScript agent is running. Its health listener uses loopback port 3301 to avoid the existing service on 8081.
- Simulator connected with microphone permission granted; agent logs confirm incoming speech activity. `node scripts/check-voice.mjs` independently verified audible Gemini output over LiveKit using a diagnostic text prompt. Physical iPad speaker/microphone and MusicKit playback still need device testing.
- The original shared-token provisioning was replaced on 2026-09-29 by verified caregiver accounts. See [account integration](accounts.md). Private development sessions and credentials stay under ignored `.build`; production builds do not consume provisioning variables.
- Simulator builds must use `CODE_SIGNING_ALLOWED=YES` (ad-hoc signing, no developer team required). `ios/Simulator.entitlements` supplies the simulator Keychain identity through Xcode. Without it, Keychain returns -34018 and tokens disappear on ordinary relaunch. Do not manually apply iOS entitlements with `codesign`; Xcode embeds simulator entitlements during linking. Saved tokens remain in Keychain after provisioning.

## Voice quota handling (2026-09-29)

Gemini rejected live sessions with “You exceeded your current quota.” The provider did not identify the specific quota in its WebSocket close reason. Check the API project's quota and billing in Google AI Studio; a Freepik subscription is unrelated to Gemini API quota.

The agent now records quota/rate-limit failures in the shared data volume. `/session` returns authenticated HTTP 503 with code `GEMINI_QUOTA_EXCEEDED` for a five-minute cooldown instead of creating more rooms. The app stops automatic retries and shows “Voice unavailable”; caregiver settings show a service availability message. After quota recovers, use Connect / Reconnect. An operator can clear an active cooldown with `await pauseForQuota(Date.now() - 1000)` from the API container's `dist/availability.js` module. This only resets the local cooldown, not Google quota.

## Naming

The product is A Little Company. The Xcode project/scheme is `LittleCompany`, bundle ID `app.littlecompany.companion`, agent name `little-company-agent`, participant identity `caregiver-<account UUID>`, and room prefix `little-company-`. The VPS Compose project and active directory are `little-company` and `/opt/little-company`. The prior deployment directory and data volume are retained only as a rollback backup. Personal names in caregiver context are unchanged.

## Current account deployment

The separate Little Company Supabase instance and account migration are deployed. Apply the SQL migration before updating the app backend. API and agent require the new instance’s Supabase environment values. The API joins `little-company-supabase_default`; the agent uses the loopback gateway. SMTP and account flows are documented in [accounts.md](accounts.md).
