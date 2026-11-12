import { test, after, mock } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const dir = await mkdtemp(join(tmpdir(), 'little-company-test-'));
Object.assign(process.env, { DATA_DIR: dir, SUPABASE_URL: 'https://accounts.example.com', SUPABASE_ANON_KEY: 'test-anon', LIVEKIT_API_KEY: 'test-key', LIVEKIT_API_SECRET: 'test-secret-that-is-at-least-32-chars', LIVEKIT_PUBLIC_URL: 'wss://voice.example.com' });
const alice = '4cd366a4-79aa-45b0-b2e4-1337cd61435f';
const bob = '72e621f5-1c4b-46a7-baa7-e7b63e8dc369';
const profiles = new Map<string, unknown>();
const inserted: any[] = [];
let unavailable = false;
mock.method(globalThis, 'fetch', async (input: string | URL | Request, init?: RequestInit) => {
 const url = new URL(String(input));
 assert.equal(url.origin, 'https://accounts.example.com');
 const token = new Headers(init?.headers).get('authorization');
 const id = token === 'Bearer token-a' ? alice : token === 'Bearer token-b' ? bob : undefined;
 const response = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });
 if (url.pathname === '/auth/v1/user') {
  if (unavailable) return response({ message: 'unavailable' }, 503);
  return id ? response({ id, email: id + '@example.com', email_confirmed_at: '2026-09-29T00:00:00Z' }) : response({ message: 'invalid', code: 'bad_jwt' }, 401);
 }
 assert.ok(id, 'data request must have verified user token');
 if (url.pathname === '/rest/v1/care_profiles') {
  if (init?.method === 'POST') {
   const body = JSON.parse(init.body as string); assert.equal(body.user_id, id);
   profiles.set(id, body); return new Response(null, { status: 201 });
  }
  assert.equal(url.searchParams.get('user_id'), 'eq.' + id);
  return response(profiles.has(id) ? [profiles.get(id)] : []);
 }
 if (url.pathname === '/rest/v1/voice_sessions') {
  const body = JSON.parse(init?.body as string); assert.equal(body.user_id, id); inserted.push(body);
  return new Response(null, { status: 201 });
 }
 throw new Error('Unexpected upstream path ' + url.pathname);
});
const { createApp } = await import('./api.js');
const { pauseForQuota, isQuotaError } = await import('./availability.js');
const app = await createApp();
after(async () => { await app.close(); mock.restoreAll(); await rm(dir, { recursive: true }); });
const headers = { authorization: 'Bearer token-a' };
const device = { installationId: '42b5c2b5-9e7c-41ec-8ea4-8a6e6b13a2a7', platform: 'test' };
test('missing, invalid, and prototype shared tokens cannot access accounts or rooms', async () => {
 for (const token of ['', 'forged', 'test-device-secret', 'test-admin-secret']) {
  for (const url of ['/session', '/profile', '/account']) {
   const result = await app.inject({ method: url === '/session' ? 'POST' : 'GET', url, headers: token ? { authorization: 'Bearer ' + token } : {} });
   assert.equal(result.statusCode, 401);
  }
 }
});
test('profiles bind to verified owner, ignore spoofed user_id, and have no family defaults', async () => {
 const blank = await app.inject({ method: 'GET', url: '/profile', headers });
 assert.deepEqual(blank.json(), { childName: '', today: '', context: '' });
 const saved = await app.inject({ method: 'PUT', url: '/profile', headers, payload: { user_id: bob, childName: 'A', today: 'Park', context: 'Likes music' } });
 assert.equal(saved.statusCode, 200);
 assert.equal((await app.inject({ method: 'GET', url: '/profile', headers })).json().today, 'Park');
 assert.equal((await app.inject({ method: 'GET', url: '/profile', headers: { authorization: 'Bearer token-b' } })).json().today, '');
 assert.equal((await app.inject({ method: 'PUT', url: '/profile', headers, payload: { context: 'x'.repeat(12001) } })).statusCode, 400);
});
test('voice token is account scoped, dispatches only IDs, and records the requesting account', async () => {
 const result = await app.inject({ method: 'POST', url: '/session', headers, payload: { ...device, userId: bob } });
 assert.equal(result.statusCode, 200);
 const payload = JSON.parse(Buffer.from(result.json().token.split('.')[1], 'base64url').toString());
 assert.equal(payload.sub, 'caregiver-' + alice);
 assert.equal(payload.video.roomJoin, true);
 assert.equal(payload.roomConfig.maxParticipants, 2);
 assert.ok(payload.exp - payload.nbf <= 600);
 const dispatch = JSON.parse(payload.roomConfig.agents[0].metadata);
 assert.equal(dispatch.userId, alice);
 assert.equal(inserted.at(-1).id, dispatch.sessionId);
 assert.equal(payload.video.room, inserted.at(-1).room);
 assert.equal(JSON.stringify(payload).includes('Likes music'), false);
});
test('quota cooldown prevents minting or recording another session', async () => {
 assert.equal(isQuotaError('You exceeded your current quota'), true);
 await pauseForQuota();
 const count = inserted.length;
 const result = await app.inject({ method: 'POST', url: '/session', headers, payload: device });
 assert.equal(result.statusCode, 503); assert.equal(result.json().code, 'GEMINI_QUOTA_EXCEEDED');
 assert.equal(inserted.length, count);
 await pauseForQuota(Date.now() - 1000);
});
test('Auth outages fail closed without telling the app its credentials are invalid', async () => {
 unavailable = true;
 const result = await app.inject({ method: 'GET', url: '/profile', headers });
 unavailable = false;
 assert.equal(result.statusCode, 503);
});

test('legacy context migrates only to its explicitly configured verified owner and preserves later edits', async () => {
 const { saveProfile } = await import('./store.js');
 await saveProfile({ childName: 'Original child', today: 'Original plan', context: 'Original private family context' });
 process.env.LEGACY_PROFILE_OWNER_EMAIL = alice + '@example.com';
 profiles.delete(alice);
 assert.equal((await app.inject({ method: 'GET', url: '/profile', headers: { authorization: 'Bearer token-b' } })).json().context, '');
 assert.equal((await app.inject({ method: 'GET', url: '/profile', headers })).json().context, 'Original private family context');
 await app.inject({ method: 'PUT', url: '/profile', headers, payload: { context: 'Updated' } });
 assert.equal((await app.inject({ method: 'GET', url: '/profile', headers })).json().context, 'Updated');
 delete process.env.LEGACY_PROFILE_OWNER_EMAIL;
});
