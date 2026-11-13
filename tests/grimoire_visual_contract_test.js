'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const boot=require('./helpers/grimoire-vm');
function setup(t){const vm=boot(t);for(const file of ['grimoire-geometry.lua','visual-contract.lua'])vm.run(fs.readFileSync(path.join(__dirname,'helpers',file),'utf8'));return vm;}
test('visual contract detects hidden parents, inherited alpha, missing anchors and clipped actions',t=>{
 const vm=setup(t);
 vm.run(`AzerMindDB.chats[1].history={{role='user',text='Question'}};AzerMind.Render();B=AzerMindContent.children[1];GR_AssertMessageAction(B.copy)`);
 for(const [breakIt,restore] of [
  ['B:Hide()','B:Show()'],['B:SetAlpha(0)','B:SetAlpha(1)'],
  ['B:SetScale(0.8)','B:SetScale(1)'],
  ['B.copy.actionIcon:SetVertexColor(1,1,1,0)','B.copy.actionIcon:SetVertexColor(1,1,1,1)'],
  ['B.copy.actionIcon:ClearAllPoints()',`B.copy.actionIcon:SetPoint('CENTER',B.copy,'CENTER',0,0)`],
  ["B.copy.actionIcon:SetDrawLayer('BACKGROUND',0)","B.copy.actionIcon:SetDrawLayer('OVERLAY',7)"],
  ['AzerMindScroll:SetVerticalScroll(10000)','AzerMindScroll:SetVerticalScroll(0)']
 ]){vm.run(breakIt);assert.throws(()=>vm.run('GR_AssertMessageAction(B.copy)'));vm.run(restore);vm.run('GR_AssertMessageAction(B.copy)');}
});
test('strict UI mode rejects unsupported calls and supports the actual glyph renderer',t=>{
 const vm=setup(t);vm.run('STUB.strictUI=true');
 assert.throws(()=>vm.run('AzerMindFrame:GetImaginaryRenderingBounds()'),/Unmodeled WoW API/);
 assert.throws(()=>vm.run('AzerMindFrame:SetImaginaryRenderingProperty(true)'),/Unmodeled WoW API/);
 vm.run(`local g=AzerMindTheme.InkGlyph(AzerMindFrame,'copy');assert(g:IsVisible());assert(g.kind=='Texture' and g.texture:find('icon-copy.tga',1,true))`);
 assert.equal(vm.num('STUB.unsupportedCalls.SetImaginaryRenderingProperty'),1);
});
for(const [width,height] of [[900,600],[1180,830],[1600,1000]])test(`message actions remain visibly anchored in ${width}x${height} with opacity and resize`,t=>{
 const vm=setup(t);vm.run(`
  AzerMindFrame:SetSize(${width},${height})
  for _,fn in ipairs(AzerMindFrame.hooks.OnSizeChanged or {}) do fn(AzerMindFrame,${width},${height}) end
  AzerMindDB.chats[1].history={{role='user',text='Question'},{role='assistant',text='Answer'}};AzerMind.Render()
  for _,opacity in ipairs({1,0.35}) do
   AzerMind.SetOpacity(opacity)
   for _,b in ipairs(AzerMindContent.children) do if b:IsShown() and b.copy then
    GR_AssertMessageAction(b.copy);GR_AssertMessageAction(b.delete)
    if b.canResend then GR_AssertMessageAction(b.resend) end
   end end
  end
 `);
});

for(const state of ['disconnected','connected','responding'])test(`header and message actions stay visible while ${state}`,t=>{
 const vm=setup(t);vm.run(`
  AzerMind.IsConnected=function() return ${state==='disconnected'?'false':'true'} end
  local chat=AzerMindDB.chats[1];chat.history={{role='user',text='Question'},{role='assistant',text='Answer'}}
  chat.pendingId=${state==='responding'?'123':'nil'}
  AzerMind.Render()
  for _,f in ipairs(STUB.frames) do
   if f.text=='Config' then
    GR_AssertVisible(f);GR_AssertVisible(f.icon.art,f)
    assert(f.icon.art.texture:find('icon-settings.tga',1,true),'missing generated gear')
   end
  end
  local first=AzerMindContent.children[1];GR_AssertMessageAction(first.copy);GR_AssertMessageAction(first.delete)
  GR_AssertMessageAction(first.resend)
 `);
});
