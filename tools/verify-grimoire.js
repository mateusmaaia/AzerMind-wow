'use strict';
const fs=require('node:fs');
const path=require('node:path');
const cp=require('node:child_process');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const manifest=require('./grimoire-manifest');
const labels=['specification + baseline','materials','controls + icons','runtime integration','layout + interaction','visual review + installation'];
function exists(file) { assert.ok(fs.existsSync(path.join(root,file)),`Missing required evidence: ${file}`); }
function run(files) {
  for(const file of files) exists(file);
  const result=cp.spawnSync(process.execPath,['--test',...files],{cwd:root,encoding:'utf8'});
  if(result.status!==0) throw new Error(result.stdout+'\n'+result.stderr);
  console.log(`  Tests passed: ${files.join(', ')}`);
}
function art(asset) {
  exists(asset.source); exists(asset.runtime);
  const png=fs.readFileSync(path.join(root,asset.source));
  assert.equal(png.subarray(0,8).toString('hex'),'89504e470d0a1a0a',`${asset.id}: invalid PNG`);
  assert.equal(png.toString('ascii',12,16),'IHDR');
  assert.equal(png.readUInt32BE(16),asset.width,`${asset.id}: PNG width`);
  assert.equal(png.readUInt32BE(20),asset.height,`${asset.id}: PNG height`);
  const tga=fs.readFileSync(path.join(root,asset.runtime));
  assert.ok(tga.length>=18,`${asset.id}: TGA header missing`);
  assert.equal(tga[1],0,`${asset.id}: color-mapped TGA unsupported`);
  assert.equal(tga[2],2,`${asset.id}: expected uncompressed true-color TGA`);
  assert.equal(tga.readUInt16LE(12),asset.width,`${asset.id}: TGA width`);
  assert.equal(tga.readUInt16LE(14),asset.height,`${asset.id}: TGA height`);
  assert.equal(tga[16],32,`${asset.id}: expected RGBA TGA`);
  assert.equal(tga[17]&15,8,`${asset.id}: expected 8 alpha bits`);
  assert.ok(tga.length>=18+tga[0]+asset.width*asset.height*4,`${asset.id}: truncated pixel data`);
}
function verify(through) {
  assert.ok(Number.isInteger(through)&&through>=1&&through<=6,'Use --through 1..6');
  for(let step=1;step<=through;step++) {
    console.log(`Step ${step}: ${labels[step-1]}`);
    if(step===1) {
      exists('docs/GRIMOIRE-PLAN.md');
      const ids=new Set();
      for(const a of manifest.assets) {
        assert.ok(!ids.has(a.id),`Duplicate asset ${a.id}`); ids.add(a.id);
        assert.ok(a.width>0&&(a.width&(a.width-1))===0&&a.height>0&&(a.height&(a.height-1))===0,'Texture size must be power of two');
        assert.ok(['tile','fixed','nine-slice','horizontal','vertical'].includes(a.mode));
        if(a.mode==='nine-slice') {
          const slices=a.slices||manifest.slices;
          assert.ok(slices.left+slices.right<a.width,`${a.id}: no expandable center`);
          assert.ok(slices.top+slices.bottom<a.height,`${a.id}: no expandable center`);
        }
        for(const p of [a.source,a.runtime]) assert.ok(!path.isAbsolute(p)&&!p.split(/[\\/]/).includes('..'));
      }
      assert.ok(manifest.assets.length>30,'Incomplete inventory');
      run(['tests/addon_test.js']);
    }
    if(step===2||step===3) {
      const batch=manifest.assets.filter(a=>a.phase===step);
      batch.forEach(art);
      // Real image decoding, alpha, PNG/TGA pixel equivalence and tile seams.
      // Must be implemented with the materials; existence checks alone are insufficient.
      run([step===2?'tests/grimoire_materials_test.js':'tests/grimoire_assets_test.js']);
      console.log(`  ${batch.length} assets verified`);
    }
    if(step===4) run(['tests/grimoire_theme_test.js','tests/addon_test.js']);
    if(step===5) run(['tests/grimoire_layout_test.js','tests/grimoire_interaction_test.js','tests/grimoire_visual_contract_test.js']);
    if(step===6) { run(['tests/grimoire_visual_evidence_test.js','tests/grimoire_install_test.js']); const review=require('./visual-review'); review.validateReview(review.reviewFile()); }
    console.log(`PASS step ${step}`);
  }
}
if(require.main===module) {
  try {
    const args=process.argv.slice(2);
    assert.equal(args.length,2,'Use node tools/verify-grimoire.js --through 1..6');
    assert.equal(args[0],'--through','Use --through 1..6');
    verify(Number(args[1]));
  } catch(error) {console.error(`BLOCKED: ${error.message}`); process.exitCode=1;}
}
module.exports={verify,art};
