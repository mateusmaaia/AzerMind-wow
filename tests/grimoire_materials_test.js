'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const cp=require('node:child_process');
const path=require('node:path');
const {assets}=require('../tools/grimoire-manifest');
const {art}=require('../tools/verify-grimoire');
const root=path.resolve(__dirname,'..');

test('all four material sources and production textures match their file contracts',()=>{
  for(const asset of assets.filter(a=>a.phase===2)) art(asset);
});

test('decoded materials have exact seams, no gradient drift, legible ink and lossless TGA pixels',()=>{
  const program=String.raw`
from pathlib import Path
from PIL import Image, ImageStat
root=Path.cwd()
def luminance(rgb):
    def linear(v):
        v=v/255
        return v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4
    return sum(w*linear(v) for w,v in zip([0.2126,0.7152,0.0722],rgb[:3]))
for name in ['emblem','leather','parchment','parchment-warm']:
    png=Image.open(root/'art/grimoire/sources'/f'{name}.png').convert('RGBA')
    tga=Image.open(root/'addon/AzerMind/Art/Grimoire'/f'{name}.tga').convert('RGBA')
    assert png.size==(256,256), (name,png.size)
    assert png.tobytes()==tga.tobytes(), name+' changed during TGA conversion'
    alpha=png.getchannel('A').getextrema()
    if name=='emblem':
        assert alpha==(0,255), 'emblem needs opaque artwork and actual transparency'
        assert png.getbbox(), 'empty emblem'
        continue
    assert alpha==(255,255), name+' has transparent holes'
    for y in range(256):
        assert png.getpixel((0,y))==png.getpixel((255,y)), name+' horizontal seam'
    for x in range(256):
        assert png.getpixel((x,0))==png.getpixel((x,255)), name+' vertical seam'
    means=[ImageStat.Stat(png.crop(box).convert('RGB')).mean for box in [(0,0,128,128),(128,0,256,128),(0,128,128,256),(128,128,256,256)]]
    for c in range(3):
        assert max(m[c] for m in means)-min(m[c] for m in means)<2, name+' has large lighting drift'
    assert 2<len(png.getcolors(256))<=7, name+' must have subtle nonempty texture'
    if name!='leather':
        ink=luminance((56,37,27))
        for _,rgba in png.getcolors(256):
            contrast=(luminance(rgba)+0.05)/(ink+0.05)
            assert contrast>=7, (name,'insufficient ink contrast',contrast)
print('Decoded pixels, seams, quadrant drift, alpha and ink contrast verified.')
`;
  const result=cp.spawnSync('python',['-c',program],{cwd:root,encoding:'utf8'});
  assert.equal(result.status,0,[result.error?.message,result.stdout,result.stderr].filter(Boolean).join('\n'));
});
