import 'dotenv/config';
import { defineAgent, cli, ServerOptions, voice, llm } from '@livekit/agents';
import { realtime } from '@livekit/agents-plugin-google';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { instructions } from './profile.js';
import { supabase, accountProfile, checkDB } from './accounts.js';
import { isQuotaError, pauseForQuota } from './availability.js';
export default defineAgent({
 entry: async ctx => {
  const job = z.object({ sessionId: z.string().uuid(), userId: z.string().uuid() }).parse(JSON.parse(ctx.job.metadata));
  const db = supabase(undefined, true);
  const record = await db.from('voice_sessions').select('room,status').eq('id', job.sessionId).eq('user_id', job.userId).single();
  checkDB(record.error);
  if (!record.data || record.data.room !== ctx.job.room?.name || record.data.status !== 'requested') throw new Error('Invalid voice session dispatch');
  const profile = await accountProfile(db, job.userId);
  const updateSession = async (status: string, extra = {}) => {
   checkDB((await db.from('voice_sessions').update({ status, ...extra }).eq('id', job.sessionId).eq('user_id', job.userId)).error);
  };
  let finalStatus = 'ended';
  ctx.addShutdownCallback(async () => { await updateSession(finalStatus, { ended_at: new Date().toISOString() }); });
  await ctx.connect();
  const participant = await ctx.waitForParticipant('caregiver-' + job.userId);
  const model = process.env.GEMINI_MODEL || 'gemini-2.5-flash-native-audio-preview-12-2025';
  const session = new voice.AgentSession({
   llm: new realtime.RealtimeModel({
    model, voice: process.env.GEMINI_VOICE || 'Kore',
    ...(model.includes('2.5') ? { proactivity: true } : {}),
    realtimeInputConfig: { automaticActivityDetection: { silenceDurationMs: 1800, prefixPaddingMs: 300 } },
    contextWindowCompression: { slidingWindow: {} },
   }),
  });
  session.on(voice.AgentSessionEventTypes.Error, event => {
   const message = 'error' in event.error ? event.error.error.message : '';
   finalStatus = isQuotaError(message) ? 'quota_limited' : 'failed';
   void updateSession(finalStatus).catch(() => console.error('Could not update session status'));
   if (isQuotaError(message)) {
    void pauseForQuota().catch(error => console.error('Could not persist voice availability', error.code));
   }
  });
  const agent = new voice.Agent({
   instructions: instructions(profile),
   tools: {
    music: llm.tool({
     description: 'Control Apple Music on the device only when the child asks. Return actual device result.',
     parameters: z.object({ action: z.enum(['play','pause','resume','next','repeat']), query: z.string().max(150).optional() }),
     execute: async args => {
      try {
       const result = await ctx.room.localParticipant!.performRpc({ destinationIdentity: participant.identity, method: 'music', payload: JSON.stringify(args), responseTimeout: 15 });
       return JSON.parse(result);
      } catch { return { ok: false, message: 'The iPad could not complete the music request. Do not claim playback succeeded.' }; }
     },
    }),
   },
  });
  try {
   await session.start({ room: ctx.room, agent });
   if (finalStatus === 'ended') await updateSession('active', { started_at: new Date().toISOString() });
  } catch (error) { finalStatus = 'failed'; throw error; }
  ctx.addShutdownCallback(async () => { await session.close(); });
 },
});
cli.runApp(new ServerOptions({ agent: fileURLToPath(import.meta.url), agentName: 'little-company-agent', numIdleProcesses: 1, host: '127.0.0.1', port: Number(process.env.AGENT_HEALTH_PORT || 3301) }));
