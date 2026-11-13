'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),cp=require('node:child_process'),path=require('node:path');
const manifest=require('../tools/grimoire-manifest');
const {art}=require('../tools/verify-grimoire');
test('all 58 control assets exist with production dimensions, format and protected slices',()=>{
  const controls=manifest.assets.filter(a=>a.phase===3);
  assert.equal(controls.length,58);
  for(const a of controls){art(a);if(a.mode==='nine-slice'){const s=a.slices||manifest.slices;assert.ok(a.width>s.left+s.right);assert.ok(a.height>s.top+s.bottom);}}
});
test('decoded control pixels survive export, icons are nonempty and frame centers are transparent',()=>{
  const program=String.raw`
import json,sys
from PIL import Image
for a in json.loads(sys.argv[1]):
    png=Image.open(a['source']).convert('RGBA')
    tga=Image.open(a['runtime']).convert('RGBA')
    assert png.tobytes()==tga.tobytes(), a['id']+' export mismatch'
    assert png.getbbox(), a['id']+' is empty'
    if a['id'].startswith('icon-') or a['id'].startswith('gem-'):
        assert png.getchannel('A').getextrema()==(0,255), a['id']+' transparency'
        assert png.getbbox()[0]>0 and png.getbbox()[1]>0, a['id']+' lacks padding'
    if a['id'].startswith('frame-') and a['mode']=='nine-slice':
        s=a.get('slices',{'left':16,'right':16,'top':16,'bottom':16})
        assert png.crop((s['left'],s['top'],a['width']-s['right'],a['height']-s['bottom'])).getchannel('A').getextrema()==(0,0), a['id']+' covers reading area'
    if a.get('derivedFrom'):
        if a['mode']=='horizontal':
            assert png.crop((0,0,1,256)).tobytes()==png.crop((255,0,256,256)).tobytes(), a['id']+' stitch seam'
        else:
            assert png.crop((0,0,256,1)).tobytes()==png.crop((0,255,256,256)).tobytes(), a['id']+' stitch seam'
`;
  const r=cp.spawnSync('python',['-c',program,JSON.stringify(manifest.assets.filter(a=>a.phase===3))],{cwd:path.resolve(__dirname,'..'),encoding:'utf8'});
  assert.equal(r.status,0,[r.error?.message,r.stdout,r.stderr].filter(Boolean).join('\n'));
});
