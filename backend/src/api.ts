import 'dotenv/config';
import Fastify, { type FastifyError } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { z } from 'zod';
import { AccessToken, RoomConfiguration, RoomAgentDispatch } from 'livekit-server-sdk';
import { profileSchema } from './profile.js';
import { readProfile } from './store.js';
import { quotaPause } from './availability.js';
import { registerVoiceLab } from './voice-lab.js';
import { supabase, authenticate, sessionResponse, accountProfile, checkDB, HTTPError } from './accounts.js';
const email = z.string().trim().email().max(254);
const password = z.string().min(10).max(128);
const emailBody = z.object({ email });
const loginBody = z.object({ email, password: z.string().min(1).max(128) });
const verification = z.object({ email, code: z.string().regex(/^\d{6,10}$/) });
const deviceBody = z.object({ installationId: z.string().uuid(), platform: z.enum(['iPhone','iPad','test']) });
const authLimit = { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } };
function parse<T>(schema: z.ZodType<T>, body: unknown): T {
 const result = schema.safeParse(body);
 if (!result.success) throw new HTTPError(400, 'Check the fields and try again. Passwords need at least 10 characters.');
 return result.data;
}
export async function createApp() {
 for (const name of ['SUPABASE_URL','SUPABASE_ANON_KEY','LIVEKIT_API_KEY','LIVEKIT_API_SECRET','LIVEKIT_PUBLIC_URL']) {
  if (!process.env[name]) throw new Error(`Missing ${name}`);
 }
 // Caddy is the only public ingress. Trust only loopback and private Docker gateways.
 const app = Fastify({ trustProxy: ['127.0.0.1', '::1', '172.16.0.0/12'], logger: { redact: ['req.headers.authorization', 'req.body'] }, bodyLimit: 20000 });
 await app.register(rateLimit, { max: 60, timeWindow: '1 minute' });
 app.setErrorHandler<FastifyError>((error, request, reply) => {
  if (error instanceof HTTPError) return reply.code(error.statusCode).send({ code: error.code, error: error.message });
  if (error.statusCode && error.statusCode < 500) return reply.code(error.statusCode).send({ error: error.statusCode === 429 ? 'Too many attempts. Please wait a minute.' : 'Invalid request.' });
  request.log.error({ code: error.code || 'INTERNAL' }, 'Request failed');
  return reply.code(500).send({ error: 'Something went wrong. Please try again.' });
 });
 app.addHook('onSend', async (_req, reply) => { reply.header('Cache-Control', 'no-store'); });
 await registerVoiceLab(app);
 app.get('/mail/confirmation', async (_request, reply) => reply.type('text/html').send('<h2>Welcome to Little Company</h2><p>Enter this code in the app to verify your email:</p><p style="font-size:32px;letter-spacing:6px">{{ .Token }}</p><p>If you did not request this, you can ignore this email.</p>'));
 app.get('/mail/recovery', async (_request, reply) => reply.type('text/html').send('<h2>Reset your Little Company password</h2><p>Enter this code in the app:</p><p style="font-size:32px;letter-spacing:6px">{{ .Token }}</p><p>If you did not request this, you can ignore this email.</p>'));
 app.get('/health', async () => ({ status: 'ok' }));
 app.post('/auth/sign-in', authLimit, async request => {
  const { data, error } = await supabase().auth.signInWithPassword(parse(loginBody, request.body));
  if (error) throw new HTTPError(error.status && error.status >= 500 ? 503 : 401, 'Could not sign in. Check your email and password, and verify your email first.');
  return sessionResponse(data.session);
 });
 app.post('/auth/sign-up', authLimit, async request => {
  const fields = parse(z.object({ email, password }), request.body);
  const { error } = await supabase().auth.signUp(fields);
  if (error) throw new HTTPError(400, 'Could not send a verification code. Please try again shortly.');
  return { message: 'Check your email for a verification code. If you already have an account, sign in instead.' };
 });
 app.post('/auth/verify', authLimit, async request => {
  const fields = parse(verification, request.body);
  const { data, error } = await supabase().auth.verifyOtp({ email: fields.email, token: fields.code, type: 'signup' });
  if (error) throw new HTTPError(400, 'That code is invalid or expired. Request a new code.');
  return sessionResponse(data.session);
 });
 app.post('/auth/resend', authLimit, async request => {
  const fields = parse(emailBody, request.body);
  const { error } = await supabase().auth.resend({ type: 'signup', email: fields.email });
  if (error && error.status && error.status >= 500) throw new HTTPError(503, 'Email is temporarily unavailable.');
  return { message: 'If verification is needed, a new code will arrive shortly.' };
 });
 app.post('/auth/recover', authLimit, async request => {
  const fields = parse(emailBody, request.body);
  const { error } = await supabase().auth.resetPasswordForEmail(fields.email);
  if (error && error.status && error.status >= 500) throw new HTTPError(503, 'Email is temporarily unavailable.');
  return { message: 'If an account exists, a recovery code will arrive shortly.' };
 });
 app.post('/auth/reset', authLimit, async request => {
  const fields = parse(verification.extend({ password }), request.body);
  const client = supabase();
  const verified = await client.auth.verifyOtp({ email: fields.email, token: fields.code, type: 'recovery' });
  if (verified.error || !verified.data.session) throw new HTTPError(400, 'That recovery code is invalid or expired.');
  const changed = await client.auth.updateUser({ password: fields.password });
  if (changed.error) throw new HTTPError(400, 'Could not change your password. Request a new recovery code and try again.');
  return sessionResponse(verified.data.session);
 });
 app.post('/auth/refresh', authLimit, async request => {
  const fields = parse(z.object({ refreshToken: z.string().min(1).max(4000) }), request.body);
  const { data, error } = await supabase().auth.refreshSession({ refresh_token: fields.refreshToken });
  if (error) throw new HTTPError(error.status && error.status < 500 ? 401 : 503, 'Could not renew your sign-in. Please try again.', 'SESSION_REFRESH_FAILED');
  return sessionResponse(data.session);
 });
 app.post('/auth/sign-out', async request => {
  const { token } = await authenticate(request.headers.authorization);
  const response = await fetch(`${process.env.SUPABASE_URL}/auth/v1/logout?scope=local`, { method: 'POST', headers: { apikey: process.env.SUPABASE_ANON_KEY!, Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15000) });
  if (!response.ok && response.status !== 401) throw new HTTPError(503, 'Could not sign out on the server. Please try again.');
  return { signedOut: true };
 });
 app.get('/account', async request => {
  const { db, user } = await authenticate(request.headers.authorization);
  const devices = await db.from('devices').select('installation_id,platform,last_seen_at').eq('user_id', user.id).order('last_seen_at', { ascending: false });
  const sessions = await db.from('voice_sessions').select('id,status,created_at', { count: 'exact' }).eq('user_id', user.id).order('created_at', { ascending: false }).limit(5);
  checkDB(devices.error); checkDB(sessions.error);
  return { email: user.email, createdAt: user.created_at, devices: devices.data, sessionCount: sessions.count || 0 };
 });
 app.put('/device', async request => {
  const { db, user } = await authenticate(request.headers.authorization);
  const device = parse(deviceBody, request.body);
  checkDB((await db.from('devices').upsert({ user_id: user.id, installation_id: device.installationId, platform: device.platform, last_seen_at: new Date().toISOString() })).error);
  return { saved: true };
 });
 app.post('/session', async (request, reply) => {
  const { db, user } = await authenticate(request.headers.authorization);
  const device = parse(deviceBody, request.body);
  const unavailable = await quotaPause();
  if (unavailable) return reply.code(503).header('Retry-After', Math.ceil((unavailable.until - Date.now()) / 1000)).send({ code: unavailable.code, error: 'Voice is temporarily unavailable. Please try again later.' });
  const id = crypto.randomUUID();
  const room = `little-company-${id}`;
  checkDB((await db.from('voice_sessions').insert({ id, user_id: user.id, installation_id: device.installationId, room })).error);
  const token = new AccessToken(process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET, { identity: `caregiver-${user.id}`, ttl: '10m' });
  token.addGrant({ roomJoin: true, room, canPublish: true, canSubscribe: true, canPublishData: true });
  token.roomConfig = new RoomConfiguration({ agents: [new RoomAgentDispatch({ agentName: 'little-company-agent', metadata: JSON.stringify({ sessionId: id, userId: user.id }) })], emptyTimeout: 60, maxParticipants: 2 });
  return { url: process.env.LIVEKIT_PUBLIC_URL, token: await token.toJwt() };
 });
 app.get('/profile', async request => {
  const { db, user } = await authenticate(request.headers.authorization);
  if (user.email_confirmed_at && user.email?.toLowerCase() === process.env.LEGACY_PROFILE_OWNER_EMAIL?.toLowerCase()) {
   const existing = await db.from('care_profiles').select('user_id').eq('user_id', user.id).maybeSingle();
   checkDB(existing.error);
   if (!existing.data) {
    const legacy = await readProfile();
    checkDB((await db.from('care_profiles').upsert({ user_id: user.id, child_name: legacy.childName || 'Madhav', today: legacy.today, context: legacy.context }, { onConflict: 'user_id', ignoreDuplicates: true })).error);
   }
  }
  return accountProfile(db, user.id);
 });
 app.put('/profile', async request => {
  const { db, user } = await authenticate(request.headers.authorization);
  const p = parse(profileSchema, request.body);
  checkDB((await db.from('care_profiles').upsert({ user_id: user.id, child_name: p.childName, today: p.today, context: p.context, updated_at: new Date().toISOString() })).error);
  return { saved: true, applies: 'next session' };
 });
 return app;
}
if (process.argv[1]?.endsWith('/api.js')) {
 const app = await createApp();
 await app.listen({ host: process.env.API_BIND || '0.0.0.0', port: Number(process.env.PORT || 3000) });
}
