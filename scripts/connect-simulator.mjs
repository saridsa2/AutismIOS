import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
const device = process.argv[2] || '7089F03A-15FE-453E-8194-30AFCFCF0FCA';
const credentials = JSON.parse(fs.readFileSync('.build/caregiver-account.json', 'utf8'));
fs.chmodSync('.build/caregiver-account.json', 0o600);
const response = await fetch('https://srv1938927.hstgr.cloud/api/auth/sign-in', {
 method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(credentials), signal: AbortSignal.timeout(25000),
});
if (!response.ok) throw new Error(`Account sign-in failed (HTTP ${response.status}).`);
const session = await response.json();
// Each simulator gets its own refresh token, just as separate physical devices do.
const environment = { ...process.env, SIMCTL_CHILD_LITTLE_COMPANY_ACCOUNT_SESSION: JSON.stringify(session) };
spawnSync('xcrun', ['simctl', 'terminate', device, 'app.littlecompany.companion'], { stdio: 'ignore' });
const install = spawnSync('xcrun', ['simctl', 'install', device, '.build/derived/Build/Products/Debug-iphonesimulator/LittleCompany.app'], { stdio: 'inherit' });
if (install.status !== 0) process.exit(install.status || 1);
const result = spawnSync('xcrun', ['simctl', 'launch', device, 'app.littlecompany.companion'], { env: environment, stdio: 'inherit' });
process.exit(result.status || 0);
