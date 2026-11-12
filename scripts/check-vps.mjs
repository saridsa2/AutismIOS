import { endpoint, getAccountSession } from './account-session.mjs';
import { randomUUID } from 'node:crypto';
import { Room, dispose } from '../backend/node_modules/@livekit/rtc-node/dist/index.js';
const account = await getAccountSession();
const health = await fetch(endpoint + '/health', { signal: AbortSignal.timeout(15000) });
if (!health.ok) throw new Error(`API health HTTP ${health.status}`);
const response = await fetch(endpoint + '/session', { method: 'POST', headers: { Authorization: `Bearer ${account.accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ installationId: randomUUID(), platform: 'test' }), signal: AbortSignal.timeout(15000) });
if (!response.ok) throw new Error(`Session HTTP ${response.status}`);
const { url, token } = await response.json();
const room = new Room();
const timeout = setTimeout(() => { console.error('LiveKit connection timed out'); process.exit(1); }, 25000);
try {
 await room.connect(url, token);
 console.log('HTTPS API, authenticated session, and LiveKit room connection passed.');
} catch {
 console.error('LiveKit room connection failed. Inspect the server compatibility and network configuration.');
 process.exitCode = 1;
} finally { clearTimeout(timeout); await room.disconnect(); await dispose(); }
