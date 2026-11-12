import fs from 'node:fs';
export const endpoint = 'https://srv1938927.hstgr.cloud/api';
export async function getAccountSession() {
 const path = '.build/account-session.json';
 let session = JSON.parse(fs.readFileSync(path, 'utf8'));
 fs.chmodSync(path, 0o600);
 if (session.expiresAt < Date.now() / 1000 + 60) {
  const result = await fetch(endpoint + '/auth/refresh', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refreshToken: session.refreshToken }), signal: AbortSignal.timeout(20000) });
  if (!result.ok) throw new Error('Sign in again before running account diagnostics.');
  session = await result.json(); fs.writeFileSync(path, JSON.stringify(session), { mode: 0o600 });
 }
 return session;
}
