'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {install}=require('../tools/install-grimoire');
const {verify}=require('../tools/verify-installed');
test('preview installation copies nested game textures and preserves live inbox and saved data',t=>{
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'azermind-grimoire-'));
  t.after(()=>fs.rmSync(temp,{recursive:true,force:true}));
  const addons=path.join(temp,'Interface','AddOns'), addon=path.join(addons,'AzerMind');
  fs.mkdirSync(addon,{recursive:true});
  fs.writeFileSync(path.join(addon,'Inbox.lua'),'live inbox');
  const saved=path.join(temp,'saved.lua'); fs.writeFileSync(saved,'saved data');
  const result=install(addons);
  assert.ok(result.checked>=18);
  assert.equal(fs.readFileSync(path.join(addon,'Inbox.lua'),'utf8'),'live inbox');
  assert.equal(fs.readFileSync(saved,'utf8'),'saved data');
  for(const file of ['leather','parchment','parchment-warm','emblem']) {
    const relative=path.join('Art','Grimoire',file+'.tga');
    assert.deepEqual(fs.readFileSync(path.join(addon,relative)),fs.readFileSync(path.join(__dirname,'../addon/AzerMind',relative)));
  }
  assert.deepEqual(verify(addons).differences.filter(d=>d.startsWith('AzerMind/')),[]);
  fs.writeFileSync(path.join(addon,'Art/Grimoire/leather.tga'),'outdated texture');
  assert.ok(verify(addons).differences.some(d=>d.includes('leather.tga: outdated')));
});

test('reinstallation snapshots the installed version and rollback preserves the live inbox',t=>{
 const {rollback}=require('../tools/install-grimoire');
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'azermind-recovery-'));t.after(()=>{assert.ok(dir.startsWith(os.tmpdir()+path.sep));fs.rmSync(dir,{recursive:true,force:true});});
 const addons=path.join(dir,'AddOns'),target=path.join(addons,'AzerMind'),backupRoot=path.join(dir,'backups');
 fs.mkdirSync(target,{recursive:true});fs.writeFileSync(path.join(target,'Theme.lua'),'previous working theme');fs.writeFileSync(path.join(target,'Inbox.lua'),'live inbox');
 const result=install(addons,{backupRoot});assert.ok(result.backup);assert.notEqual(fs.readFileSync(path.join(target,'Theme.lua'),'utf8'),'previous working theme');
 fs.writeFileSync(path.join(target,'Inbox.lua'),'new live reply');
 const recovery=rollback(addons,{backupRoot});assert.equal(recovery.restored,1);assert.equal(fs.readFileSync(path.join(target,'Theme.lua'),'utf8'),'previous working theme');
 assert.equal(fs.readFileSync(path.join(target,'Inbox.lua'),'utf8'),'new live reply');assert.equal(fs.existsSync(path.join(target,'Art/Grimoire/leather.tga')),false);
});
test('rollback rejects corrupt backups and traversal before writing installed files',t=>{
 const {rollback}=require('../tools/install-grimoire');
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'azermind-recovery-'));t.after(()=>{assert.ok(dir.startsWith(os.tmpdir()+path.sep));fs.rmSync(dir,{recursive:true,force:true});});
 const addons=path.join(dir,'AddOns'),target=path.join(addons,'AzerMind'),backupRoot=path.join(dir,'backups');
 fs.mkdirSync(target,{recursive:true});fs.writeFileSync(path.join(target,'Theme.lua'),'old');const result=install(addons,{backupRoot});
 fs.writeFileSync(path.join(result.backup,'files/Theme.lua'),'corrupted');const installed=fs.readFileSync(path.join(target,'Theme.lua'),'utf8');
 assert.throws(()=>rollback(addons,{backupRoot}),/Corrupt backup/);assert.equal(fs.readFileSync(path.join(target,'Theme.lua'),'utf8'),installed);
 assert.throws(()=>rollback(addons,{backupRoot,id:'..'}),/Unsafe/);
});
