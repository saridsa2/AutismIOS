import { mkdir, readFile, writeFile, rename } from 'node:fs/promises';
import { join } from 'node:path';
import { profileSchema, type Profile } from './profile.js';
const dir = process.env.DATA_DIR || './data';
export async function readProfile(): Promise<Profile> {
 try { return profileSchema.parse(JSON.parse(await readFile(join(dir, 'profile.json'), 'utf8'))); }
 catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return profileSchema.parse({}); throw error; }
}
export async function saveProfile(p: Profile) {
 await mkdir(dir, { recursive: true, mode: 0o700 });
 const temp = join(dir, `profile-${crypto.randomUUID()}.tmp`);
 await writeFile(temp, JSON.stringify(p), { mode: 0o600 });
 await rename(temp, join(dir, 'profile.json'));
}
