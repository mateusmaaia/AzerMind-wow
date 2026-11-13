'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const boot=require('./helpers/grimoire-vm');
const geometry=fs.readFileSync(path.join(__dirname,'helpers/grimoire-geometry.lua'),'utf8');
test('reference 1-3: provider identity, decorated title and readable leather rows',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  AzerMindDB.chats[1].history={{role='assistant',agent='codex',text='Answer'},{role='assistant',agent='claude',text='Other answer'}}
  AzerMind.Render(); AI=AzerMindContent.children[1]; OTHER=AzerMindContent.children[2]
  for _,size in ipairs({{900,600},{1180,830},{1600,1000}}) do
   AzerMindFrame:SetSize(size[1],size[2])
   for _,fn in ipairs(AzerMindFrame.hooks.OnSizeChanged or {}) do fn(AzerMindFrame,size[1],size[2]) end
  end
  ROW=AzerMindConversationScroll:GetScrollChild().children[1]
 `);
 assert.equal(vm.value('AI.senderLabel'),'AzerMind - Codex');
 assert.match(vm.value('OTHER.senderLabel'),/^AzerMind - Claude/);
 vm.run(`
  local title
  for _,f in ipairs(STUB.frames) do if f.ornaments and #f.ornaments==4 then title=f end end
  assert(title,'missing title flourishes')
  assert(ROW.grimoireFrame.parts[5]:GetAlpha()==1,'missing row background')
  assert(ROW.label.textColor[1]>0.8,'conversation title not readable')
 `);
});

test('reference 4-8: continuous framed parchment, burgundy connect and full-height composer track',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  AzerMindDB.chats[1].history={{role='assistant',text='Answer'}};AzerMind.Render(); B=AzerMindContent.children[1]
  assert(AzerMindReadingPanel.grimoireFrame.name=='frame-input','missing outer reading border')
  assert(AzerMindScroll.grimoireMaterial.grimoireAsset=='parchment','missing continuous paper')
  assert(not B.grimoireFrame,'heavy per-message frame returned')
  assert(B.body.textColor[1]<0.3,'paper needs dark ink')
  for _,f in ipairs(STUB.frames) do if f.text=='Connect' and f.actionArt then CONNECT=f end end
  assert(CONNECT.grimoireFrame.name=='button-primary','connect is not burgundy')
  assert(CONNECT.actionArt:GetWidth()==32,'connect crystal is too small')
  local field=GR_Bounds(AzerMindInputScroll.parent);local bar=GR_Bounds(AzerMindInputScroll.ScrollBar)
  assert(bar.height==field.height-60,'composer track fails to span panel')
  assert(field.right-bar.right==12,'composer track crowds border')
 `);
});

test('reference 6: leather stitches survive resize without unbounded texture allocation',t=>{
 const vm=boot(t);
 vm.run(`
  local panel=AzerMindConversationScroll.parent
  assert(panel.grimoireStitches and #panel.grimoireStitches.parts>0,'missing leather seams')
  panel:SetSize(240,700)
  for _,fn in ipairs(panel.hooks.OnSizeChanged) do fn(panel,240,700) end
  COUNT=#panel.grimoireStitches.parts
  for i=1,10 do for _,fn in ipairs(panel.hooks.OnSizeChanged) do fn(panel,240,700) end end
  assert(#panel.grimoireStitches.parts==COUNT,'stitch textures accumulate')
 `);
});

test('reference 9: appearance navigation, live opacity, persistence, safe limits and reset',t=>{
 const vm=boot(t);
 vm.run(`
  AzerMind.CodexPrompt()
  for _,f in ipairs(STUB.frames) do if f.text=='Appearance' and f.scripts.OnClick then NAV=f end end
  assert(NAV,'missing appearance settings navigation');NAV.scripts.OnClick(NAV)
  assert(AzerMindAppearanceSettings:IsShown(),'appearance panel not reachable')
  AzerMindOpacitySlider:SetValue(65)
  assert(AzerMindDB.settings.opacity==0.65,'opacity not persisted')
  assert(AzerMindFrame:GetAlpha()==0.65 and AzerMindMini:GetAlpha()==0.65,'main or mini opacity unchanged')
  assert(AzerMindGeneralSettings:GetAlpha()==0.65 and AzerMindAppearanceSettings:GetAlpha()==0.65,'settings opacity unchanged')
  assert(AzerMindAppearanceSettings.ignoreParentAlpha,'nested opacity would multiply')
  AzerMind.ShowContextSettings()
  assert(AzerMindContextSettings:GetAlpha()==0.65,'new windows ignore saved opacity')
  AzerMind.SetOpacity(0);assert(AzerMind.GetOpacity()==0.35,'opacity can hide controls')
  AzerMind.SetOpacity(2);assert(AzerMind.GetOpacity()==1,'opacity upper limit broken')
  assert(not AzerMind.SetOpacity('invalid'),'invalid opacity accepted')
  AzerMind.SetOpacity(0.65);AzerMind.ShowAppearanceSettings()
  assert(AzerMindOpacitySlider:GetValue()==65,'reopening resets opacity')
  for _,f in ipairs(STUB.frames) do if f.text=='Reset to 100%' then f.scripts.OnClick(f) end end
  assert(AzerMind.GetOpacity()==1 and AzerMindFrame:GetAlpha()==1,'reset failed')
 `);
});
