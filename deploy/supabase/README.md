# Little Company Supabase

An independent self-hosted Supabase project on `srv1938927.hstgr.cloud`.
Uses official `supabase/supabase` tag `self-hosted/v0.8.1`.
This is separate from the existing `/opt/supabase` deployment.

- Checkout and Compose directory: `/opt/little-company-supabase/docker`
- Compose project: `little-company-supabase`
- Containers: `lc-supabase-*` (Realtime: `realtime-dev.lc-supabase-realtime`)
- Gateway and authenticated Studio: server loopback `127.0.0.1:8002`
- Postgres pooler: loopback `5434` (session), `6545` (transaction)
- Secrets: server `.env`, mode `0600`; generated separately from the existing project.
- Database and file storage: the new checkout's `docker/volumes` directories.
- Encryption and function-cache named volumes: scoped by Compose project.

## Administration

```sh
ssh -L 8002:127.0.0.1:8002 root@srv1938927.hstgr.cloud
```

Then open `http://localhost:8002`. Dashboard username is `littlecompany`.
The generated dashboard password is in the server `.env` (`DASHBOARD_PASSWORD`).
Do not copy the environment file into the app or source control.

Run `docker compose ps` or `docker compose up -d` from the new Compose directory.
Do not run reset scripts against a live project.

Public sign-up is enabled with required email verification; Hostinger SMTP and in-app verification/recovery codes are configured.
No existing accounts or application data are copied into this database.
The backend integration uses the new gateway over a private Docker network;
mobile apps should only contact the Little Company backend.
The backend has `SUPABASE_URL` and `SUPABASE_ANON_KEY` configured. Auth settings
returned HTTP 200 from inside the API container on 2026-09-29. All 11 new
services reported healthy; the existing Supabase stack was left running.
The app account integration is deployed. See `docs/accounts.md` for authentication, RLS, SMTP, and migration details.

## Reproducible initial setup

Clone the pinned official repository, sparse-checkout `docker`, then run
`node prepare.mjs` in that directory. It generates unique secrets and rewrites
container names and host ports. It refuses to overwrite an existing `.env`.
Start with `docker compose up -d`.

Before production account use, configure tested database/storage backups and
SMTP for verification and password recovery. Back up `.env` securely as well:
it contains encryption keys needed with the data.

Official architecture reference:
https://supabase.com/docs/guides/self-hosting
Standard self-hosted Studio manages one project. Multiple independently
deployed stacks can run on a host; multi-project control planes are separate.
