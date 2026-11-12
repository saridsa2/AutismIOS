import type { FastifyInstance } from 'fastify';
import { createHash } from 'node:crypto';
import { z } from 'zod';
import { authenticate, supabase, checkDB, HTTPError } from './accounts.js';
const uuid = z.string().uuid().transform(value => value.toLowerCase());
export const voiceSampleSchema = z.object({
 id: uuid, profileId: uuid, label: z.string().trim().min(1).max(80), kind: z.enum(['enrollment','test']),
 modelID: z.literal('community1-wespeaker-df2625ac-v1'), embedding: z.array(z.number().finite().min(-1).max(1)).length(256),
 wavBase64: z.string().min(100).max(500000).regex(/^[A-Za-z0-9+/]+={0,2}$/),
 durationMs: z.number().finite().min(3000).max(11000), inferenceMs: z.number().finite().min(0).max(300000),
 recordedAt: z.number().finite().positive(), consentVersion: z.literal('voice-lab-v1'), retentionDays: z.literal(30),
}).strict();
export function inspectWav(wav: Buffer): number {
 if (wav.length < 44 || wav.length > 360000 || wav.toString('ascii',0,4) !== 'RIFF' || wav.toString('ascii',8,12) !== 'WAVE') throw new HTTPError(400,'Expected a short WAV recording.');
 let offset = 12, validFormat = false, audioBytes = 0;
 while (offset + 8 <= wav.length) {
  const kind = wav.toString('ascii',offset,offset+4), size = wav.readUInt32LE(offset+4), start = offset+8;
  if (start+size > wav.length) throw new HTTPError(400,'Incomplete WAV recording.');
  if (kind === 'fmt ') {
   validFormat = size >= 16 && wav.readUInt16LE(start) === 1 && wav.readUInt16LE(start+2) === 1 && wav.readUInt32LE(start+4) === 16000 && wav.readUInt32LE(start+8) === 32000 && wav.readUInt16LE(start+12) === 2 && wav.readUInt16LE(start+14) === 16;
  }
  if (kind === 'data') audioBytes += size;
  offset = start+size+(size%2);
 }
 const duration = audioBytes/32;
 if (!validFormat || audioBytes%2 !== 0 || duration < 3000 || duration > 11000) throw new HTTPError(400,'Use 16 kHz mono PCM16 audio, between 3 and 11 seconds.');
 return duration;
}
export async function registerVoiceLab(app: FastifyInstance) {
 app.post('/voice-lab/samples',{bodyLimit:550000,config:{rateLimit:{max:12,timeWindow:'1 minute'}}},async request => {
  const {db,user} = await authenticate(request.headers.authorization);
  const parsed = voiceSampleSchema.safeParse(request.body);
  if (!parsed.success) throw new HTTPError(400,'Invalid voice sample metadata.');
  const sample = parsed.data, wav = Buffer.from(sample.wavBase64,'base64');
  const durationMs = inspectWav(wav);
  const norm = Math.sqrt(sample.embedding.reduce((sum,v) => sum+v*v,0));
  if (Math.abs(norm-1) > 0.03) throw new HTTPError(400,'Speaker embedding must be normalized.');
  const hash = createHash('sha256').update(wav).digest('hex');
  const existing = await db.from('voice_lab_samples').select('sha256,expires_at').eq('user_id',user.id).eq('id',sample.id).maybeSingle();
  checkDB(existing.error);
  if (existing.data) {
   if (existing.data.sha256 !== hash) throw new HTTPError(409,'Sample ID is already in use.');
   return {saved:true,id:sample.id,expiresAt:existing.data.expires_at};
  }
  const objectPath = `${user.id}/${sample.id}.wav`;
  const upload = await db.storage.from('voice-lab').upload(objectPath,wav,{contentType:'audio/wav',upsert:false});
  checkDB(upload.error);
  const expiresAt = new Date(Date.now()+30*86400000).toISOString();
  const inserted = await db.from('voice_lab_samples').insert({
   user_id:user.id,id:sample.id,profile_id:sample.profileId,label:sample.label,kind:sample.kind,model_id:sample.modelID,embedding:sample.embedding,
   object_path:objectPath,sha256:hash,duration_ms:durationMs,inference_ms:sample.inferenceMs,recorded_at:new Date(sample.recordedAt*1000).toISOString(),
   consent_version:sample.consentVersion,expires_at:expiresAt,
  });
  if (inserted.error) { await db.storage.from('voice-lab').remove([objectPath]); checkDB(inserted.error); }
  return {saved:true,id:sample.id,expiresAt};
 });
 app.delete<{Params:{id:string}}>('/voice-lab/samples/:id',async request => {
  const {db,user} = await authenticate(request.headers.authorization);
  const parsed = uuid.safeParse(request.params.id);
  if (!parsed.success) throw new HTTPError(400,'Invalid sample ID.');
  checkDB((await db.storage.from('voice-lab').remove([`${user.id}/${parsed.data}.wav`])).error);
  checkDB((await db.from('voice_lab_samples').delete().eq('user_id',user.id).eq('id',parsed.data)).error);
  return {deleted:true};
 });
 let pruning = false;
 const prune = async () => {
  if (pruning) return;
  pruning = true;
  try {
   const db = supabase(undefined,true);
   const expired = await db.from('voice_lab_samples').select('user_id,id,object_path').lt('expires_at',new Date().toISOString()).limit(100);
   checkDB(expired.error);
   for (const sample of expired.data ?? []) {
    checkDB((await db.storage.from('voice-lab').remove([sample.object_path])).error);
    checkDB((await db.from('voice_lab_samples').delete().eq('user_id',sample.user_id).eq('id',sample.id)).error);
   }
  } catch { app.log.error('Voice Lab retention cleanup failed; will retry'); }
  finally { pruning = false; }
 };
 const timer = setInterval(() => { void prune(); },3600000); timer.unref();
 app.addHook('onReady',async () => { void prune(); });
 app.addHook('onClose',async () => { clearInterval(timer); });
}
