import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectWav,voiceSampleSchema} from './voice-lab.js';
function wav(seconds=10) {
 const data = Buffer.alloc(44+seconds*32000);
 data.write('RIFF');data.writeUInt32LE(data.length-8,4);data.write('WAVEfmt ',8);data.writeUInt32LE(16,16);data.writeUInt16LE(1,20);data.writeUInt16LE(1,22);data.writeUInt32LE(16000,24);data.writeUInt32LE(32000,28);data.writeUInt16LE(2,32);data.writeUInt16LE(16,34);data.write('data',36);data.writeUInt32LE(seconds*32000,40);return data;
}
test('accepts PCM16 mono, measures actual audio duration',()=>assert.equal(inspectWav(wav()),10000));
test('rejects malformed, truncated and wrong-rate audio',()=> {
 assert.throws(()=>inspectWav(Buffer.alloc(100)));
 assert.throws(()=>inspectWav(wav().subarray(0,100)));
 const bad=wav();bad.writeUInt32LE(48000,24);assert.throws(()=>inspectWav(bad));
 assert.throws(()=>inspectWav(wav(1)));
});
test('rejects arbitrary retention, nonfinite embeddings and absent consent',()=> {
 const sample = {id:crypto.randomUUID(),profileId:crypto.randomUUID(),label:'Test',kind:'enrollment',modelID:'community1-wespeaker-df2625ac-v1',embedding:Array(256).fill(0.0625),wavBase64:wav().toString('base64'),durationMs:10000,inferenceMs:50,recordedAt:Date.now()/1000,consentVersion:'voice-lab-v1',retentionDays:30};
 assert.equal(voiceSampleSchema.safeParse(sample).success,true);
 assert.equal(voiceSampleSchema.safeParse({...sample,retentionDays:365}).success,false);
 assert.equal(voiceSampleSchema.safeParse({...sample,consentVersion:undefined}).success,false);
 assert.equal(voiceSampleSchema.safeParse({...sample,embedding:[NaN,...sample.embedding.slice(1)]}).success,false);
});
