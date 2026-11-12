import { endpoint, getAccountSession } from './account-session.mjs';
import { randomUUID } from 'node:crypto';
import { Room, RoomEvent, AudioStream, dispose } from '../backend/node_modules/@livekit/rtc-node/dist/index.js';

const account = await getAccountSession();
const room = new Room();
let reader;
let deadline;
try {
  const response = await fetch(endpoint + '/session', {
    method: 'POST', headers: { Authorization: `Bearer ${account.accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ installationId: randomUUID(), platform: 'test' }),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error('Session request failed');
  const { url, token } = await response.json();
  const receivedAudio = new Promise((resolve, reject) => {
    deadline = setTimeout(() => reject(new Error('Audio timeout')), 45000);
    room.on(RoomEvent.TrackSubscribed, async track => {
      try {
        reader = new AudioStream(track, 24000, 1).getReader();
        await room.localParticipant.sendText('Hello! Please say hello back.', { topic: 'lk.chat' });
        let audibleFrames = 0;
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          if (value.data.some(sample => Math.abs(sample) > 300)) audibleFrames++;
          if (audibleFrames >= 10) { resolve(); break; }
        }
      } catch (error) { reject(error); }
    });
  });
  await room.connect(url, token);
  await receivedAudio;
  console.log('PASS: Gemini generated audible PCM audio through the self-hosted LiveKit agent.');
} catch {
  console.error('Voice return-path check failed; inspect the agent logs.');
  process.exitCode = 1;
} finally {
  clearTimeout(deadline);
  await reader?.cancel();
  await room.disconnect();
  await dispose();
}
