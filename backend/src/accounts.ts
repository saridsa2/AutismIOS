import { createClient, type Session, type SupabaseClient } from '@supabase/supabase-js';
import { profileSchema, type Profile } from './profile.js';
export class HTTPError extends Error {
 constructor(public statusCode: number, message: string, public code = 'REQUEST_FAILED') { super(message); }
}
export function supabase(token?: string, admin = false): SupabaseClient {
 const url = process.env.SUPABASE_URL;
 const key = admin ? process.env.SUPABASE_SERVICE_ROLE_KEY : process.env.SUPABASE_ANON_KEY;
 if (!url || !key) throw new HTTPError(503, 'Account service is temporarily unavailable.');
 return createClient(url, key, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  global: { ...(token ? { headers: { Authorization: `Bearer ${token}` } } : {}),
   fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(15000) }) },
 });
}
export async function authenticate(header?: string) {
 const token = header?.match(/^Bearer (\S+)$/)?.[1];
 if (!token) throw new HTTPError(401, 'Please sign in.', 'SIGN_IN_REQUIRED');
 const db = supabase(token);
 const { data, error } = await db.auth.getUser(token);
 if (error || !data.user) {
  if (error && (!error.status || error.status >= 500)) throw new HTTPError(503, 'Account service is temporarily unavailable.');
  throw new HTTPError(401, 'Please sign in again.', 'SIGN_IN_REQUIRED');
 }
 return { db, user: data.user, token };
}
export function sessionResponse(session: Session | null) {
 if (!session) throw new HTTPError(401, 'Please verify your email before signing in.');
 return { accessToken: session.access_token, refreshToken: session.refresh_token,
  expiresAt: session.expires_at!, user: { id: session.user.id, email: session.user.email || '' } };
}
export function checkDB(error: unknown) {
 if (error) throw new HTTPError(503, 'Could not save or load your account. Please try again.');
}
export async function accountProfile(db: SupabaseClient, userId: string): Promise<Profile> {
 const { data, error } = await db.from('care_profiles').select('child_name,today,context').eq('user_id', userId).maybeSingle();
 checkDB(error);
 return profileSchema.parse(data ? { childName: data.child_name, today: data.today, context: data.context } : {});
}
