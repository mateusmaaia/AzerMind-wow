'use strict';
const cp=require('node:child_process'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const files=['addon_test','grimoire_assets_test','grimoire_theme_test','grimoire_layout_test','grimoire_refinement_test','grimoire_reference_test','grimoire_finish_test','grimoire_interaction_test','grimoire_visual_contract_test','grimoire_visual_evidence_test','grimoire_install_test'].map(name=>'tests/'+name+'.js');
function check(){
 for(const args of [['tools/audit-ui-simulation.js','--summary'],['--test',...files]]){
  const r=cp.spawnSync(process.execPath,args,{cwd:root,stdio:'inherit'});
  if(r.error)throw r.error;
  if(r.status!==0)throw Error('UI code checks failed; installation/release stopped.');
 }
}
if(require.main===module){try{check();}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={files,check};
