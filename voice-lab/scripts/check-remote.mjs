import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';
const options={auth:{persistSession:false,autoRefreshToken:false}};
const admin=createClient(process.env.SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY,options);
const ids=[]; const sampleID=randomUUID(); let objectPath;
try {
 const accounts=[];
 for(let i=0;i<2;i++) {
  const email=`voice-lab-check-${randomUUID()}@littlecompany.invalid`,password=randomBytes(24).toString('base64url');
  const created=await admin.auth.admin.createUser({email,password,email_confirm:true});
  assert.ifError(created.error);ids.push(created.data.user.id);
  const client=createClient(process.env.SUPABASE_URL,process.env.SUPABASE_ANON_KEY,options);
  const auth=await client.auth.signInWithPassword({email,password});assert.ifError(auth.error);
  accounts.push({client,token:auth.data.session.access_token,id:created.data.user.id});
 }
 const wav=Buffer.alloc(320044);wav.write('RIFF');wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(1,22);wav.writeUInt32LE(16000,24);wav.writeUInt32LE(32000,28);wav.writeUInt16LE(2,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(320000,40);
 for(let i=0;i<160000;i++) wav.writeInt16LE(Math.round(3000*Math.sin(2*Math.PI*180*i/16000)),44+i*2);
 const body={id:sampleID,profileId:randomUUID(),label:'Synthetic test',kind:'test',modelID:'community1-wespeaker-df2625ac-v1',embedding:Array(256).fill(0.0625),wavBase64:wav.toString('base64'),durationMs:10000,inferenceMs:5,recordedAt:Date.now()/1000,consentVersion:'voice-lab-v1',retentionDays:30};
 const api=async(path,method,token,payload)=>fetch('http://127.0.0.1:3000'+path,{method,headers:{...(payload?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token}:{})},...(payload?{body:JSON.stringify(payload)}:{})});
 assert.equal((await api('/voice-lab/samples','POST',null,body)).status,401);
 const first=await api('/voice-lab/samples','POST',accounts[0].token,body);assert.equal(first.status,200,await first.text());
 assert.equal((await api('/voice-lab/samples','POST',accounts[0].token,body)).status,200);
 objectPath=`${accounts[0].id}/${sampleID}.wav`;
 const read=await accounts[0].client.storage.from('voice-lab').download(objectPath);assert.ifError(read.error);assert.equal(read.data.size,wav.length);
 const other=await accounts[1].client.storage.from('voice-lab').download(objectPath);assert.ok(other.error);
 const hidden=await accounts[1].client.from('voice_lab_samples').select('id').eq('id',sampleID);assert.ifError(hidden.error);assert.equal(hidden.data.length,0);
 assert.equal((await api('/voice-lab/samples/'+sampleID,'DELETE',accounts[1].token)).status,200);
 assert.ifError((await accounts[0].client.storage.from('voice-lab').download(objectPath)).error);
 assert.equal((await api('/voice-lab/samples/'+sampleID,'DELETE',accounts[0].token)).status,200);
 assert.ok((await accounts[0].client.storage.from('voice-lab').download(objectPath)).error);
 console.log('PASS: authenticated upload, retry idempotency, audio retrieval, cross-account isolation, owner-only deletion');
} finally {
 if(objectPath) await admin.storage.from('voice-lab').remove([objectPath]);
 for(const id of ids) { await admin.from('voice_lab_samples').delete().eq('user_id',id); await admin.auth.admin.deleteUser(id); }
 console.log('Temporary test accounts and synthetic audio removed');
}
