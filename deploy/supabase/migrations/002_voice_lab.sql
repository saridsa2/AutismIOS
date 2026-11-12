begin;
create table if not exists public.voice_lab_samples (
 user_id uuid not null references auth.users(id) on delete cascade,
 id uuid not null,
 profile_id uuid not null,
 label text not null check(length(label) between 1 and 80),
 kind text not null check(kind in ('enrollment','test')),
 model_id text not null,
 embedding jsonb not null check(jsonb_typeof(embedding) = 'array' and jsonb_array_length(embedding) = 256),
 object_path text not null,
 sha256 text not null,
 duration_ms double precision not null check(duration_ms between 3000 and 11000),
 inference_ms double precision not null check(inference_ms between 0 and 300000),
 recorded_at timestamptz not null,
 consent_version text not null,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null,
 primary key(user_id,id)
);
alter table public.voice_lab_samples enable row level security;
create policy voice_lab_owner_select on public.voice_lab_samples for select to authenticated using (auth.uid() = user_id);
create policy voice_lab_owner_insert on public.voice_lab_samples for insert to authenticated with check (auth.uid() = user_id and object_path = user_id::text || '/' || id::text || '.wav' and expires_at <= now() + interval '30 days 1 minute');
create policy voice_lab_owner_delete on public.voice_lab_samples for delete to authenticated using (auth.uid() = user_id);
grant select,insert,delete on public.voice_lab_samples to authenticated;
grant all on public.voice_lab_samples to service_role;
create index if not exists voice_lab_expiration on public.voice_lab_samples(expires_at);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('voice-lab','voice-lab',false,360000,array['audio/wav']) on conflict(id) do nothing;
create policy voice_lab_audio_select on storage.objects for select to authenticated using (bucket_id = 'voice-lab' and (storage.foldername(name))[1] = auth.uid()::text);
create policy voice_lab_audio_insert on storage.objects for insert to authenticated with check (bucket_id = 'voice-lab' and (storage.foldername(name))[1] = auth.uid()::text);
create policy voice_lab_audio_update on storage.objects for update to authenticated using (bucket_id = 'voice-lab' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = 'voice-lab' and (storage.foldername(name))[1] = auth.uid()::text);
create policy voice_lab_audio_delete on storage.objects for delete to authenticated using (bucket_id = 'voice-lab' and (storage.foldername(name))[1] = auth.uid()::text);
commit;
