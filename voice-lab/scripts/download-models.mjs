import { mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
const revision = 'df2625ac79a7ac6b65ad868fee6d80f320da4232';
const base = `https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/${revision}/`;
const root = fileURLToPath(new URL('../VoiceLab/Models/', import.meta.url));
const files = ['FBank','Embedding'].flatMap(name => ['analytics/coremldata.bin','coremldata.bin','metadata.json','model.mil','weights/weight.bin'].map(file => `${name}.mlmodelc/${file}`));
files.push('LICENSE','NOTICE.md','PROVENANCE.md','provenance.json');
const manifest = { repository:'FluidInference/speaker-diarization-coreml', revision, files:[] };
for (const file of files) {
 const response = await fetch(base + file);
 if (!response.ok) throw new Error(`Download ${file}: ${response.status}`);
 const bytes = Buffer.from(await response.arrayBuffer());
 const path = root + file;
 await mkdir(path.slice(0,path.lastIndexOf('/')), {recursive:true});
 await writeFile(path,bytes);
 manifest.files.push({file,sha256:createHash('sha256').update(bytes).digest('hex'),bytes:bytes.length});
 console.log(`${file}: ${bytes.length} bytes`);
}
await writeFile(root+'manifest.json',JSON.stringify(manifest,null,2));
