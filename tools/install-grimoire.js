'use strict';
// Snapshot before updating; never touch live Inbox.lua or SavedVariables.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),defaultBackups=path.join(root,'backups/grimoire');
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function files(dir,relative='') {
 if(!fs.existsSync(dir))return [];
 return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>{
  if(e.isSymbolicLink())throw Error('Refusing symlink: '+e.name);
  const name=relative?relative+'/'+e.name:e.name;
  return e.isDirectory()?files(path.join(dir,e.name),name):(name==='Inbox.lua'?[]:[name]);
 });
}
function inside(dir,name){
 if(typeof name!=='string'||/[:\0]/.test(name)||path.isAbsolute(name)||name.split(/[\\/]/).some(p=>p==='..'||p===''))throw Error('Unsafe backup path');
 const file=path.resolve(dir,name);if(!file.startsWith(path.resolve(dir)+path.sep))throw Error('Unsafe backup path');
 let current=path.resolve(dir);if(fs.existsSync(current)&&fs.lstatSync(current).isSymbolicLink())throw Error('Refusing symlink target');
 for(const part of name.split(/[\\/]/)){current=path.join(current,part);if(fs.existsSync(current)&&fs.lstatSync(current).isSymbolicLink())throw Error('Refusing symlink target');}
 return file;
}
function copy(from,to){fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(from,to);if(hash(from)!==hash(to))throw Error('Copy mismatch: '+to);}
function install(addons,options={}) {
 if(!addons||!path.isAbsolute(addons))throw Error('An absolute Interface/AddOns directory is required.');
 const source=path.join(root,'addon/AzerMind'),target=path.join(addons,'AzerMind');
 const old=files(target),incoming=files(source),backupRoot=options.backupRoot||defaultBackups;
 let backup=null;
 if(old.length){
  const id=new Date().toISOString().replace(/[:.]/g,'-')+'-'+crypto.randomBytes(4).toString('hex');
  backup=path.join(backupRoot,id);fs.mkdirSync(backup,{recursive:true});
  const manifest={schema:1,createdAt:new Date().toISOString(),target,files:[],created:[]};
  for(const name of old){copy(inside(target,name),inside(path.join(backup,'files'),name));manifest.files.push({name,sha256:hash(inside(target,name))});}
  for(const name of incoming)if(!fs.existsSync(inside(target,name)))manifest.created.push({name,sha256:hash(inside(source,name))});
  fs.writeFileSync(path.join(backup,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 }
 try{for(const name of incoming)copy(inside(source,name),inside(target,name));}
 catch(e){throw Error(e.message+(backup?'\nPrevious version saved at '+backup:''));}
 return {target,checked:incoming.length,backup};
}
function rollback(addons,options={}) {
 if(!addons||!path.isAbsolute(addons))throw Error('An absolute Interface/AddOns directory is required.');
 const backupRoot=options.backupRoot||defaultBackups;
 const id=options.id||fs.readdirSync(backupRoot).filter(n=>fs.existsSync(path.join(backupRoot,n,'manifest.json'))).sort().at(-1);
 if(!id||id!==path.basename(id))throw Error('No valid backup selected');
 const backup=inside(backupRoot,id),manifest=JSON.parse(fs.readFileSync(path.join(backup,'manifest.json'),'utf8'));
 const target=path.join(addons,'AzerMind');if(manifest.schema!==1||path.resolve(manifest.target)!==path.resolve(target))throw Error('Backup target differs from this installation');
 // Validate the entire recovery set before changing anything.
 for(const item of manifest.files){if(item.name==='Inbox.lua')throw Error('Live inbox is never restored');const from=inside(path.join(backup,'files'),item.name);inside(target,item.name);if(hash(from)!==item.sha256)throw Error('Corrupt backup: '+item.name);}
 for(const item of manifest.created){const file=inside(target,item.name);if(item.name==='Inbox.lua')throw Error('Live inbox is never removed');if(fs.existsSync(file)&&hash(file)!==item.sha256)throw Error('New file changed since install: '+item.name);}
 for(const item of manifest.files)copy(inside(path.join(backup,'files'),item.name),inside(target,item.name));
 for(const item of manifest.created){const file=inside(target,item.name);if(fs.existsSync(file))fs.unlinkSync(file);}
 return {target,restored:manifest.files.length,backup};
}
module.exports={install,rollback};
if(require.main===module){try{
 const args=process.argv.slice(2),recover=args[0]==='--rollback';
 const addons=recover?JSON.parse(fs.readFileSync(path.join(root,'bridge/config.json'),'utf8')).addonDir:(args[0]||JSON.parse(fs.readFileSync(path.join(root,'bridge/config.json'),'utf8')).addonDir);
 const result=recover?rollback(addons,{id:args[1]}):install(addons);
 console.log(recover?`Restored ${result.restored} files in ${result.target}`:`Installed and verified ${result.checked} files in ${result.target}\nPrevious version: ${result.backup||'first installation'}\nVisual review remains separate from code checks.`);
}catch(e){console.error('Installation/recovery failed: '+e.message);process.exitCode=1;}}
