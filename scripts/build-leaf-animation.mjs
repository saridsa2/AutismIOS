import fs from 'node:fs';
import {execFileSync} from 'node:child_process';

const svg = fs.readFileSync('assets/brand/leaf.svg','utf8');
const path = svg.match(/<path d="([^"]+)"/)[1];
const tokens = path.match(/[A-Za-z]|[-+]?(?:\d*\.)?\d+/g);
const vertices = [], incoming = [], outgoing = [];
let x=0,y=0,index=0,command;
const point = (px,py) => [px/10,1024-py/10];
const add = p => { vertices.push(p); incoming.push([0,0]); outgoing.push([0,0]); };
while(index<tokens.length) {
  if(/[A-Za-z]/.test(tokens[index])) command=tokens[index++];
  if(command==='z'||command==='Z') break;
  if(command==='M'||command==='m'||command==='l'||command==='L') {
    const a=Number(tokens[index++]),b=Number(tokens[index++]);
    x=command===command.toLowerCase()?x+a:a;
    y=command===command.toLowerCase()?y+b:b;
    add(point(x,y));
    if(command==='M') command='L';
    if(command==='m') command='l';
  } else if(command==='c') {
    const a=tokens.slice(index,index+6).map(Number);index+=6;
    const c1=point(x+a[0],y+a[1]),c2=point(x+a[2],y+a[3]);
    x+=a[4];y+=a[5]; const end=point(x,y), prev=vertices.at(-1);
    outgoing[outgoing.length-1]=[c1[0]-prev[0],c1[1]-prev[1]];
    add(end);incoming[incoming.length-1]=[c2[0]-end[0],c2[1]-end[1]];
  } else throw new Error(`Unsupported SVG command ${command}`);
}
const fixed=k=>({a:0,k});
const rotation=[0,2,0,-2,0].map((value,i)=>({t:i*30,s:[value],...(i<4?{e:[[2,0,-2,0][i]],o:{x:[0.42],y:[0]},i:{x:[0.58],y:[1]}}:{})}));
const animation={v:'5.12.2',fr:30,ip:0,op:120,w:1024,h:1024,nm:'A Little Company — gentle speaking leaf',ddd:0,assets:[],layers:[{
  ddd:0,ind:1,ty:4,nm:'Freepik leaf silhouette',sr:1,ip:0,op:120,st:0,bm:0,
  ks:{o:fixed(100),r:{a:1,k:rotation},p:fixed([512,650,0]),a:fixed([512,650,0]),s:fixed([100,100,100])},
  shapes:[{ty:'sh',nm:'Editable leaf path',ks:fixed({i:incoming,o:outgoing,v:vertices,c:true})},
    {ty:'fl',nm:'Sage',c:fixed([108/255,147/255,127/255,1]),o:fixed(100),r:1,bm:0}]
}]};
const resources='ios/LittleCompany/Resources';
const catalog='ios/LittleCompany/Assets.xcassets';
fs.mkdirSync(resources,{recursive:true});
fs.mkdirSync(`${catalog}/AppIcon.appiconset`,{recursive:true});
fs.mkdirSync(`${catalog}/Leaf.imageset`,{recursive:true});
fs.writeFileSync(`${resources}/leaf-speaking.json`,JSON.stringify(animation));
fs.writeFileSync('assets/brand/leaf-speaking.json',JSON.stringify(animation,null,2));
fs.writeFileSync(`${catalog}/Contents.json`,JSON.stringify({info:{author:'xcode',version:1}}));
fs.writeFileSync(`${catalog}/Leaf.imageset/Contents.json`,JSON.stringify({images:[{filename:'leaf.pdf',idiom:'universal'}],info:{author:'xcode',version:1},properties:{'preserves-vector-representation':true}}));
execFileSync('rsvg-convert',['-f','pdf','-o',`${catalog}/Leaf.imageset/leaf.pdf`,'assets/brand/leaf.svg']);
const icon=svg.replace(/<g /,'<rect width="1024" height="1024" fill="#E8F0EB"/><g ');
fs.writeFileSync('assets/brand/leaf-icon.svg',icon);
execFileSync('rsvg-convert',['-o',`${catalog}/AppIcon.appiconset/AppIcon.png`,'assets/brand/leaf-icon.svg']);
fs.writeFileSync(`${catalog}/AppIcon.appiconset/Contents.json`,JSON.stringify({images:[{filename:'AppIcon.png',idiom:'universal',platform:'ios',size:'1024x1024'}],info:{author:'xcode',version:1}}));
console.log(`Built vector PDF, app icon, and Lottie JSON with ${vertices.length} path vertices.`);
