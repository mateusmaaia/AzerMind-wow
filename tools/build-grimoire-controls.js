'use strict';
// Exact pixel recipes: authored here, rendered/reviewed through PixelLab workbench.
const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib');
const manifest=require('./grimoire-manifest');
const root=path.resolve(__dirname,'..');
const C={ink:'#29190F',shadow:'#49301A',bronze:'#79502B',mid:'#A4773B',gold:'#C7A15B',light:'#E7CB88',paper:'#E8D8B7',red:'#60222A',redlight:'#85323B',purple:'#9760D1',violet:'#553076',cyan:'#63A8B4',stone:'#77716C'};
function canvas(w,h) {
  const pixels=new Array(w*h).fill(null);
  const dot=(x,y,c)=>{x=Math.round(x);y=Math.round(y);if(x>=0&&y>=0&&x<w&&y<h)pixels[y*w+x]=c;};
  const rect=(x,y,r,b,c)=>{for(let py=y;py<=b;py++)for(let px=x;px<=r;px++)dot(px,py,c);};
  const box=(x,y,r,b,c)=>{rect(x,y,r,y,c);rect(x,b,r,b,c);rect(x,y,x,b,c);rect(r,y,r,b,c);};
  const line=(x,y,r,b,c)=>{const n=Math.max(Math.abs(r-x),Math.abs(b-y));for(let i=0;i<=n;i++)dot(x+(r-x)*i/(n||1),y+(b-y)*i/(n||1),c);};
  const ellipse=(x,y,r,b,c)=>{const rx=(r-x)/2,ry=(b-y)/2;for(let py=y;py<=b;py++)for(let px=x;px<=r;px++)if(((px-(x+r)/2)/(rx||1))**2+((py-(y+b)/2)/(ry||1))**2<=1.04)dot(px,py,c);};
  const poly=(points,c)=>{for(let py=0;py<h;py++)for(let px=0;px<w;px++){let inside=false;for(let i=0,j=points.length-1;i<points.length;j=i++){const [xi,yi]=points[i],[xj,yj]=points[j];if((yi>py)!==(yj>py)&&px<(xj-xi)*(py-yi)/(yj-yi)+xi)inside=!inside;}if(inside)dot(px,py,c);}};
  return {w,h,pixels,dot,rect,box,line,ellipse,poly};
}
function asset(spec) {
  const p=canvas(spec.width,spec.height),{w,h,rect,box,line,ellipse,poly}=p;
  const id=spec.id;
  if(spec.mode==='nine-slice') {
    const button=id.startsWith('button-')||id==='conversation-selection';
    if(button) {rect(0,0,w-1,h-1,C.ink);rect(3,3,w-4,h-4,id==='button-secondary'?'#38251A':C.red);rect(5,5,w-6,11,id==='button-secondary'?'#49301F':C.redlight);}
    const heavy=id==='frame-window';
    for(const [inset,color] of [[0,C.ink],[1,C.shadow],[2,C.mid],[3,C.light],[4,C.bronze],[5,C.shadow]]) box(inset,inset,w-inset-1,h-inset-1,color);
    if(!button) {box(6,6,w-7,h-7,C.ink);box(7,7,w-8,h-8,C.bronze);}
    // Self-contained corner fittings, entirely inside the protected 16px insets.
    for(const [x,y] of [[0,0],[w-16,0],[0,h-16],[w-16,h-16]]) {
      if(heavy){rect(x+1,y+1,x+12,y+4,C.gold);rect(x+1,y+1,x+4,y+12,C.gold);line(x+2,y+2,x+11,y+2,C.light);}
      ellipse(x+7,y+7,x+10,y+10,C.shadow);p.dot(x+8,y+8,C.light);
    }
  } else if(id==='divider') {
    rect(0,62,127,62,C.shadow);rect(0,63,127,63,C.gold);poly([[58,63],[64,57],[70,63],[64,69]],C.gold);poly([[61,63],[64,60],[67,63],[64,66]],C.red);
  } else if(id==='scroll-track') {
    rect(11,0,20,31,C.ink);rect(12,0,12,31,C.bronze);rect(19,0,19,31,C.mid);
  } else if(id==='resize-grip') {
    for(const n of [10,17,24]) {line(30-n,30,30,30-n,C.gold);line(30-n,29,29,30-n,C.shadow);}
  } else if(id.startsWith('gem-')) {
    const color=id==='gem-connected'?'#477C50':id==='gem-disconnected'?'#A83337':id==='gem-connecting'?C.gold:C.purple;
    poly([[8,5],[23,5],[28,11],[28,22],[22,28],[9,28],[4,22],[4,11]],C.shadow);
    poly([[10,7],[21,7],[26,12],[26,21],[21,26],[10,26],[6,21],[6,12]],C.gold);
    poly([[11,9],[20,9],[24,13],[24,20],[20,24],[11,24],[8,20],[8,13]],color);
    line(11,10,18,10,C.paper);line(9,13,9,17,C.paper);
  } else {
    const kind=id.replace('icon-','');
    if(kind==='items') {ellipse(5,11,27,29,C.shadow);ellipse(7,12,25,27,C.bronze);rect(10,10,22,13,C.gold);rect(11,7,21,9,C.shadow);box(12,3,20,8,C.gold);rect(14,17,19,23,C.gold);rect(15,18,18,21,C.light);}
    else if(kind==='quests') {rect(8,5,24,27,C.shadow);rect(9,6,23,25,C.paper);ellipse(5,3,26,10,C.gold);rect(8,5,24,7,C.paper);ellipse(18,20,28,30,C.red);line(12,12,21,12,C.bronze);line(12,16,20,16,C.bronze);}
    else if(kind==='instances') {ellipse(4,2,28,28,C.shadow);ellipse(7,4,25,27,C.stone);ellipse(11,8,21,28,C.violet);ellipse(14,12,19,28,C.purple);rect(3,15,9,29,C.stone);rect(23,15,29,29,C.stone);rect(1,28,30,30,C.mid);line(5,15,8,15,C.paper);line(24,15,27,15,C.paper);}
    else if(kind==='character'||kind==='user') {ellipse(11,3,22,14,C.gold);poly([[9,16],[23,16],[29,29],[3,29]],C.bronze);poly([[11,16],[20,16],[22,27],[8,27]],C.gold);}
    else if(kind==='connect') {ellipse(3,13,29,19,C.cyan);poly([[16,2],[24,14],[17,29],[8,15]],C.violet);poly([[16,3],[16,24],[10,14]],C.purple);poly([[17,4],[22,14],[17,15]],'#D9B7F1');}
    else if(kind==='settings') {for(const [x,y] of [[13,2],[13,24],[2,13],[24,13],[5,5],[22,22],[5,22],[22,5]])rect(x,y,x+5,y+5,C.gold);ellipse(6,6,26,26,C.gold);ellipse(12,12,20,20,C.ink);}
    else if(kind==='plus') {rect(14,6,17,26,C.gold);rect(6,14,26,17,C.light);}
    else if(kind==='more') {for(const x of [5,14,23])ellipse(x,14,x+4,18,C.gold);}
    else if(kind==='delete') {rect(8,10,24,27,C.shadow);box(8,10,24,27,C.gold);rect(6,7,26,9,C.gold);rect(13,3,19,5,C.light);for(const x of [12,16,20])rect(x,13,x,24,C.gold);}
    else if(kind==='copy') {rect(6,4,21,23,C.paper);box(6,4,21,23,C.bronze);rect(12,10,27,29,C.paper);box(12,10,27,29,C.gold);}
    else if(kind==='send'||kind==='resend') {if(kind==='resend') {box(4,11,21,27,C.gold);rect(17,10,23,19,null);}poly([[9,4],[28,15],[9,24],[13,15]],C.gold);line(12,6,25,15,C.light);}
    else if(kind==='stop') {rect(7,7,25,25,C.red);box(7,7,25,25,C.gold);}
    else if(kind==='clear') {poly([[4,19],[16,5],[29,16],[17,29],[10,29]],C.red);poly([[4,19],[10,13],[23,24],[17,29],[10,29]],C.paper);line(7,30,29,30,C.gold);}
    else if(kind==='minimize') {rect(7,18,25,20,C.gold);line(7,18,25,18,C.light);}
    else if(kind==='reload') {for(let a=45;a<320;a+=3){const r=a*Math.PI/180;ellipse(Math.round(16+10*Math.cos(r))-1,Math.round(16+10*Math.sin(r))-1,Math.round(16+10*Math.cos(r))+1,Math.round(16+10*Math.sin(r))+1,C.gold);}poly([[19,2],[29,3],[28,12]],C.gold);}
    else if(kind.startsWith('chevron-')) {const up=kind.endsWith('up');for(let i=0;i<3;i++){line(7,up?21-i:11+i,16,up?12-i:20+i,C.gold);line(16,up?12-i:20+i,25,up?21-i:11+i,C.gold);}}
    else if(kind==='warning') {poly([[16,3],[30,29],[2,29]],C.gold);rect(15,11,17,21,C.ink);rect(15,24,17,26,C.ink);}
    else if(kind==='sources') {poly([[2,6],[14,9],[16,28],[2,25]],C.paper);poly([[17,9],[30,6],[30,25],[16,28]],C.paper);line(16,9,16,28,C.bronze);line(5,12,11,14,C.bronze);line(21,14,27,12,C.bronze);}
    else throw Error('Missing drawing '+id);
  }
  return p;
}
function recipe(p) {
  const colors=[...new Set(p.pixels.filter(Boolean))];
  const chars='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  if(colors.length>chars.length)throw Error('Palette too large');
  const legend=Object.fromEntries(colors.map((c,i)=>[chars[i],c]));
  const index=new Map(colors.map((c,i)=>[c,chars[i]]));
  const rows=Array.from({length:p.h},(_,y)=>p.pixels.slice(y*p.w,(y+1)*p.w).map(c=>c?index.get(c):'.').join(''));
  const draw=[];
  for(let x=0;x<p.w;x+=256) {
    const width=Math.min(256,p.w-x),band=Math.floor(16384/width);
    for(let y=0;y<p.h;y+=band)draw.push({op:'grid',at:[x,y],legend,rows:rows.slice(y,y+band).map(row=>row.slice(x,x+width))});
  }
  return {job:{canvas:[p.w,p.h],frame_count:1,views:[{id:'controls',offset:[0,0]}],source_bookends_exact:false,body_palette_exact:false},scene:{layers:[{id:'art',name:'Body - controls'}],views:{controls:{nodes:{art:{layer:'art',draw}}}}}};
}
function sheet(list,columns,cell) {
  const p=canvas(columns*cell,Math.ceil(list.length/columns)*cell);
  list.forEach((spec,i)=>{const a=asset(spec),ox=i%columns*cell+Math.floor((cell-a.w)/2),oy=Math.floor(i/columns)*cell+Math.floor((cell-a.h)/2);a.pixels.forEach((c,n)=>{if(c)p.dot(ox+n%a.w,oy+Math.floor(n/a.w),c);});});
  return p;
}
function rgba(p) {return Buffer.from(p.pixels.flatMap(c=>c?[...Buffer.from(c.slice(1),'hex'),255]:[0,0,0,0]));}
function crc(buf) {let c=0xffffffff;for(const b of buf){c^=b;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;}
function chunk(name,data) {const type=Buffer.from(name);const n=Buffer.alloc(4),sum=Buffer.alloc(4);n.writeUInt32BE(data.length);sum.writeUInt32BE(crc(Buffer.concat([type,data])));return Buffer.concat([n,type,data,sum]);}
function png(p) {const pixels=rgba(p),scan=[];for(let y=0;y<p.h;y++)scan.push(Buffer.from([0]),pixels.subarray(y*p.w*4,(y+1)*p.w*4));const header=Buffer.alloc(13);header.writeUInt32BE(p.w);header.writeUInt32BE(p.h,4);header[8]=8;header[9]=6;return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',header),chunk('IDAT',zlib.deflateSync(Buffer.concat(scan))),chunk('IEND',Buffer.alloc(0))]);}
function tga(p) {const header=Buffer.alloc(18);header[2]=2;header.writeUInt16LE(p.w,12);header.writeUInt16LE(p.h,14);header[16]=32;header[17]=40;const data=rgba(p);for(let i=0;i<data.length;i+=4){const r=data[i];data[i]=data[i+2];data[i+2]=r;}return Buffer.concat([header,data]);}
function batches() {
  const all=manifest.assets.filter(a=>a.phase===3&&a.authoring!=='imagegen');
  return [
    {id:'frames',list:all.filter(a=>a.mode==='nine-slice'&&a.id!=='scroll-thumb'),columns:4,cell:128},
    {id:'icons',list:all.filter(a=>a.id.startsWith('icon-')),columns:7,cell:32},
    {id:'navigation',list:all.filter(a=>['divider','scroll-track','scroll-thumb','resize-grip'].includes(a.id)),columns:4,cell:128},
    {id:'gems',list:all.filter(a=>a.id.startsWith('gem-')),columns:4,cell:32}
  ].filter(batch=>batch.list.length>0);
}
function build() {
  for(const spec of manifest.assets.filter(a=>a.phase===3&&a.authoring!=='imagegen')) {const p=asset(spec);for(const [file,buf] of [[spec.source,png(p)],[spec.runtime,tga(p)]]){fs.mkdirSync(path.dirname(path.join(root,file)),{recursive:true});fs.writeFileSync(path.join(root,file),buf);}}
  for(const batch of batches()){const p=sheet(batch.list,batch.columns,batch.cell);fs.mkdirSync(path.join(root,'art/grimoire/recipes'),{recursive:true});fs.writeFileSync(path.join(root,`art/grimoire/recipes/${batch.id}.json`),JSON.stringify(recipe(p)));fs.writeFileSync(path.join(root,`art/grimoire/previews/${batch.id}.png`),png(p));}
  console.log('Built procedural control assets. Illustrated textures are preserved; run import-grimoire-illustrated.py to rebuild them.');
}
module.exports={asset,recipe,sheet,batches,build};
if(require.main===module)build();
