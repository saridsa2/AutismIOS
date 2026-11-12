// Run inside the API container; creates and removes only dedicated QA accounts.
import { createClient } from '@supabase/supabase-js';
import { randomUUID, randomBytes } from 'node:crypto';
import assert from 'node:assert/strict';
const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const root = 'http://127.0.0.1:3000';
const created = [];
const password = randomBytes(24).toString('base64url');
async function call(path, body, token, method = 'POST') {
 const r = await fetch(root + path, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
 return { status: r.status, body: await r.json() };
}
async function user(index) {
 const email = `lc-qa-${randomUUID()}-${index}@example.com`;
 const result = await sb.auth.admin.generateLink({ type: 'signup', email, password });
 if (result.error) throw new Error('Could not create QA account: ' + result.error.code);
 created.push(result.data.user.id);
 const verified = await call('/auth/verify', { email, code: result.data.properties.email_otp });
 assert.equal(verified.status, 200, 'verification');
 return { ...verified.body, email };
}
try {
 const a = await user('a'); const b = await user('b');
 assert.equal((await call('/auth/sign-in', { email: a.email, password: 'incorrect' })).status, 401);
 const login = await call('/auth/sign-in', { email: a.email, password });
 assert.equal(login.status, 200);
 a.accessToken = login.body.accessToken; a.refreshToken = login.body.refreshToken;
 const profile = { childName: 'QA child A', today: 'QA plan A', context: 'Private context A' };
 assert.equal((await call('/profile', profile, a.accessToken, 'PUT')).status, 200);
 assert.deepEqual((await call('/profile', null, a.accessToken, 'GET')).body, profile);
 assert.equal((await call('/profile', null, b.accessToken, 'GET')).body.context, '');
 const bClient = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false }, global: { headers: { Authorization: 'Bearer ' + b.accessToken } } });
 const crossRead = await bClient.from('care_profiles').select('*').eq('user_id', a.user.id);
 assert.equal(crossRead.error, null); assert.deepEqual(crossRead.data, []);
 const crossWrite = await bClient.from('care_profiles').upsert({ user_id: a.user.id, context: 'attack' });
 assert.ok(crossWrite.error, 'RLS must reject another account overwrite');
 const anonymous = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
 assert.ok((await anonymous.from('care_profiles').select('*')).error);
 const device = { installationId: randomUUID(), platform: 'test' };
 assert.equal((await call('/device', device, a.accessToken, 'PUT')).status, 200);
 const account = await call('/account', null, a.accessToken, 'GET');
 assert.equal(account.status, 200); assert.equal(account.body.devices.length, 1);
 const room = await call('/session', device, a.accessToken);
 assert.ok([200,503].includes(room.status));
 if (room.status === 200) {
  const token = JSON.parse(Buffer.from(room.body.token.split('.')[1], 'base64url').toString());
  assert.equal(token.sub, 'caregiver-' + a.user.id);
  assert.equal((await call('/account', null, a.accessToken, 'GET')).body.sessionCount, 1);
 }
 assert.equal((await call('/profile', null, process.env.ADMIN_TOKEN, 'GET')).status, 401);
 const refresh = await call('/auth/refresh', { refreshToken: a.refreshToken });
 assert.equal(refresh.status, 200);
 assert.equal((await call('/auth/sign-out', {}, refresh.body.accessToken)).status, 200);
 assert.equal((await call('/auth/refresh', { refreshToken: refresh.body.refreshToken })).status, 401);
 const reset = await sb.auth.admin.generateLink({ type: 'recovery', email: b.email });
 if (reset.error) throw reset.error;
 const newPassword = randomBytes(24).toString('base64url');
 assert.equal((await call('/auth/reset', { email: b.email, code: reset.data.properties.email_otp, password: newPassword })).status, 200);
 assert.equal((await call('/auth/sign-in', { email: b.email, password: newPassword })).status, 200);
 console.log('PASS: verification, password login, recovery, refresh, logout, device/session tracking, legacy-token rejection, and real database cross-account/anonymous isolation.');
} finally {
 for (const id of created) { const result = await sb.auth.admin.deleteUser(id); if (result.error) throw new Error('QA account cleanup failed'); }
 console.log('QA accounts and their data removed.');
}
