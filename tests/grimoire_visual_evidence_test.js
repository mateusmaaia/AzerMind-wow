'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const {fingerprint,template,validateReview}=require('../tools/visual-review');
function fixture(t){
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'azermind-review-'));t.after(()=>{assert.ok(dir.startsWith(os.tmpdir()+path.sep));fs.rmSync(dir,{recursive:true,force:true});});
 const addon=path.join(dir,'addon');fs.mkdirSync(addon);fs.writeFileSync(path.join(addon,'Theme.lua'),'initial build');
 const file=path.join(dir,'review.json'),review=template(addon);
 return {dir,addon,file,review,save(){fs.writeFileSync(file,JSON.stringify(review));}};
}
test('visual approval is never inferred from passing unit tests or missing evidence',t=>{
 const f=fixture(t);assert.throws(()=>validateReview(f.file,f.addon),/pending/);f.save();assert.throws(()=>validateReview(f.file,f.addon),/pending|rejected/);
 f.review.status='approved';f.save();assert.throws(()=>validateReview(f.file,f.addon),/reviewer/);
});
test('review binds to exact runtime build, real image bytes, required states and interaction checklist',t=>{
 const f=fixture(t);Object.assign(f.review,{status:'approved',reviewer:'Synthetic test fixture only',reviewedAt:new Date().toISOString(),clientVersion:'test fixture'});
 // Synthetic fixtures live only in a temporary test directory, never in review evidence.
 const program="import sys; from PIL import Image\nfor i in range(9): Image.new('RGB',(640,400),(20+i*20,80,120)).save(sys.argv[1]+'/'+str(i)+'.png')";
 const r=cp.spawnSync('python',['-c',program,f.dir],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);
 f.review.captures.forEach((c,i)=>{c.file=i+'.png';c.sha256=crypto.createHash('sha256').update(fs.readFileSync(path.join(f.dir,c.file))).digest('hex');});
 for(const key of Object.keys(f.review.interactions))f.review.interactions[key]=true;
 f.save();assert.equal(validateReview(f.file,f.addon).status,'approved');
 f.review.interactions.copy=false;f.save();assert.throws(()=>validateReview(f.file,f.addon),/copy/);f.review.interactions.copy=true;
 const first=f.review.captures[0];const saved={...first};Object.assign(first,{file:f.review.captures[1].file,sha256:f.review.captures[1].sha256});f.save();assert.throws(()=>validateReview(f.file,f.addon),/same screenshot/);Object.assign(first,saved);
 f.review.captures.pop();f.save();assert.throws(()=>validateReview(f.file,f.addon),/Missing/);
 fs.writeFileSync(path.join(f.addon,'Theme.lua'),'changed build');assert.throws(()=>validateReview(f.file,f.addon),/different build/);
});
test('live bridge inbox does not invalidate an otherwise identical UI build',t=>{
 const f=fixture(t),before=fingerprint(f.addon);fs.writeFileSync(path.join(f.addon,'Inbox.lua'),'live reply');assert.equal(fingerprint(f.addon),before);
});
