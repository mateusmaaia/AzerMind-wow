'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const sizes=[[900,600],[1180,830],[1600,1000]],states=['disconnected','connected','responding'];
const interactions=['copy','resend','delete-and-undo','config','scroll-all-three','resize','minimize-restore','opacity','send-stop','overlap-other-addon'];
function fingerprint(addon=path.join(root,'addon/AzerMind')) {
 const hash=crypto.createHash('sha256');
 function walk(dir,relative='') {
  for(const e of fs.readdirSync(dir,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name))) {
   const name=relative?relative+'/'+e.name:e.name;if(name==='Inbox.lua')continue;
   if(e.isSymbolicLink())throw Error('Symlink in addon: '+name);
   if(e.isDirectory())walk(path.join(dir,e.name),name);
   else {hash.update(name+'\0');hash.update(fs.readFileSync(path.join(dir,e.name)));hash.update('\0');}
  }
 }
 walk(addon);return hash.digest('hex');
}
function template(addon) {
 return {schema:1,status:'pending',fingerprint:fingerprint(addon),source:'wow-client',reviewer:'',reviewedAt:'',clientVersion:'',
  limitations:'Screenshots and checklist require a human review in the WoW client; code tests cannot approve appearance.',
  captures:sizes.flatMap(([width,height])=>states.map(state=>({width,height,state,file:'',sha256:''}))),
  interactions:Object.fromEntries(interactions.map(k=>[k,false]))};
}
function reviewFile(addon){return path.join(root,'art/grimoire/reviews',fingerprint(addon),'review.json');}
function validateReview(file,addon) {
 assert.ok(fs.existsSync(file),'Visual review pending: capture and review this build in WoW. Run npm run grimoire:review:prepare.');
 const review=JSON.parse(fs.readFileSync(file,'utf8'));
 assert.equal(review.schema,1,'Unknown review format');
 assert.equal(review.fingerprint,fingerprint(addon),'Visual review belongs to a different build');
 assert.equal(review.source,'wow-client','Browser/mock previews do not count as in-game review');
 if(review.status!=='approved')throw Error('Visual review is '+review.status+'; client captures and human review are required.');
 assert.ok(typeof review.reviewer==='string'&&review.reviewer.trim(),'Missing human reviewer');
 assert.ok(typeof review.reviewedAt==='string'&&Number.isFinite(Date.parse(review.reviewedAt)),'Missing review date');
 assert.ok(typeof review.clientVersion==='string'&&review.clientVersion.trim(),'Missing client version');
 const hashes=new Set(),images=[];
 for(const [width,height] of sizes)for(const state of states){
  const matches=(review.captures||[]).filter(c=>c.width===width&&c.height===height&&c.state===state);
  assert.equal(matches.length,1,`Missing or duplicate screenshot: ${width}x${height} ${state}`);
  const capture=matches[0];assert.ok(capture.file,`Missing screenshot: ${width}x${height} ${state}`);
  const image=fs.readFileSync(path.resolve(path.dirname(file),capture.file));
  assert.ok(image.length>=33&&image.subarray(0,8).toString('hex')==='89504e470d0a1a0a','Expected a PNG client capture');
  assert.ok(image.readUInt32BE(16)>=640&&image.readUInt32BE(20)>=400,'Client capture is too small for review');
  const hash=crypto.createHash('sha256').update(image).digest('hex');assert.equal(hash,capture.sha256,'Screenshot changed after review');
  assert.ok(!hashes.has(hash),'The same screenshot cannot cover different sizes or states');hashes.add(hash);images.push(path.resolve(path.dirname(file),capture.file));
 }
 const decoded=require('node:child_process').spawnSync('python',['-c','import sys,json; from PIL import Image; [(Image.open(p).verify()) for p in json.loads(sys.argv[1])]',JSON.stringify(images)],{encoding:'utf8'});
 assert.equal(decoded.status,0,'Invalid PNG capture: '+(decoded.error?.message||decoded.stderr||''));
 for(const key of interactions)assert.equal(review.interactions?.[key],true,`Manual interaction not checked: ${key}`);
 return review;
}
if(require.main===module){try{
 const [command,...args]=process.argv.slice(2);
 const target=(command==='--attach'?args[3]:args[0])?path.resolve(command==='--attach'?args[3]:args[0]):reviewFile();
 if(command==='--prepare'){
  assert.ok(!fs.existsSync(target),'Review already exists; preserve its evidence and edit that file.');
  fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,JSON.stringify(template(),null,2)+'\n');
  console.log('Visual review PENDING. No screenshots or approval were fabricated.\n'+target);
 }else if(command==='--attach'){
  const [dimensions,state,screenshot]=args;assert.ok(screenshot,'Use --attach WIDTHxHEIGHT STATE screenshot.png');
  const review=JSON.parse(fs.readFileSync(target,'utf8'));assert.equal(review.fingerprint,fingerprint(),'Review belongs to another build');
  const capture=review.captures.find(c=>`${c.width}x${c.height}`===dimensions&&c.state===state);assert.ok(capture,'Unknown capture size/state');
  const file=dimensions+'-'+state+'.png',image=fs.readFileSync(path.resolve(screenshot));
  assert.equal(image.subarray(0,8).toString('hex'),'89504e470d0a1a0a','Expected PNG screenshot');
  fs.writeFileSync(path.join(path.dirname(target),file),image);
  Object.assign(capture,{file,sha256:crypto.createHash('sha256').update(image).digest('hex')});
  Object.assign(review,{status:'pending',reviewer:'',reviewedAt:''});
  fs.writeFileSync(target,JSON.stringify(review,null,2)+'\n');console.log('Capture attached. Human review remains pending.');
 }else if(command==='--verify'){validateReview(target);console.log('Human visual review matches the current addon build.');}
 else throw Error('Use --prepare [review.json] or --verify [review.json]');
}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={fingerprint,template,validateReview,reviewFile};
