'use strict';
// Report limits instead of silently presenting a permissive mock as the client.
const boot=require('../tests/helpers/grimoire-vm');
const cleanups=[];
try{
 const vm=boot({after(fn){cleanups.push(fn);}});
 vm.run(`
  AzerMindDB.chats[1].history={{role='user',text='Question'},{role='assistant',text='Answer'}};AzerMind.Render()
  AUDIT={};for key,count in pairs(STUB.unsupportedCalls) do AUDIT[#AUDIT+1]=key..': '..count end;table.sort(AUDIT)
 `);
 if(process.argv.includes('--summary')) console.log('Simulator: '+vm.num('#AUDIT')+' unmodeled APIs recorded; npm run grimoire:audit lists limitations.');
 else console.log('UNMODELED API CALLS (recorded, not proof of correct rendering):\n'+vm.value('table.concat(AUDIT,"\\n")'));
 console.log('Fonts, texture occlusion, animation and scaled rendering still require review in WoW.');
}finally{for(const close of cleanups.reverse())close();}
