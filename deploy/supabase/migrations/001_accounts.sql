begin;
create table if not exists public.care_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 child_name text not null default '' check (length(child_name) <= 80),
 today text not null default '' check (length(today) <= 4000),
 context text not null default '' check (length(context) <= 12000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.devices (
 user_id uuid not null references auth.users(id) on delete cascade,
 installation_id uuid not null,
 platform text not null check (platform in ('iPhone','iPad','test')),
 last_seen_at timestamptz not null default now(),
 primary key(user_id, installation_id)
);
create table if not exists public.voice_sessions (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 installation_id uuid not null, room text not null unique,
 status text not null default 'requested' check(status in ('requested','active','ended','failed','quota_limited')),
 created_at timestamptz not null default now(), started_at timestamptz, ended_at timestamptz
);
create index if not exists voice_sessions_user_created on public.voice_sessions(user_id, created_at desc);
alter table public.care_profiles enable row level security;
alter table public.devices enable row level security;
alter table public.voice_sessions enable row level security;
revoke all on public.care_profiles, public.devices, public.voice_sessions from anon;
grant select, insert, update, delete on public.care_profiles, public.devices to authenticated;
grant select, insert on public.voice_sessions to authenticated;
grant all on public.care_profiles, public.devices, public.voice_sessions to service_role;
create policy own_profile on public.care_profiles to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_devices on public.devices to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_sessions_read on public.voice_sessions for select to authenticated using ((select auth.uid()) = user_id);
create policy own_sessions_create on public.voice_sessions for insert to authenticated with check ((select auth.uid()) = user_id and status = 'requested' and started_at is null and ended_at is null);
commit;
notify pgrst, 'reload schema';
