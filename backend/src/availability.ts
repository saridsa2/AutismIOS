import { mkdir, readFile, writeFile, rename } from 'node:fs/promises';
import { join } from 'node:path';
const dir = process.env.DATA_DIR || './data';
export function isQuotaError(message: string) {
 return /quota|resource.exhausted|rate.limit|too many requests/i.test(message);
}
export async function pauseForQuota(until = Date.now() + 5 * 60 * 1000) {
 await mkdir(dir, { recursive: true, mode: 0o700 });
 const temp = join(dir, `availability-${crypto.randomUUID()}.tmp`);
 await writeFile(temp, JSON.stringify({ code: 'GEMINI_QUOTA_EXCEEDED', until }), { mode: 0o600 });
 await rename(temp, join(dir, 'availability.json'));
}
export async function quotaPause() {
 try {
  const state = JSON.parse(await readFile(join(dir, 'availability.json'), 'utf8'));
  return state.code === 'GEMINI_QUOTA_EXCEEDED' && state.until > Date.now() ? state : null;
 } catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null; throw error; }
}
