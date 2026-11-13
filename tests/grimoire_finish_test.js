'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const boot=require('./helpers/grimoire-vm');
const fs=require('node:fs'),path=require('node:path');
const geometry=fs.readFileSync(path.join(__dirname,'helpers/grimoire-geometry.lua'),'utf8');
test('finish 1: bronze scroll channel and readable thumb preserve native sliders',t=>{
 const vm=boot(t);
 vm.run(`
  for _,s in ipairs({AzerMindScroll,AzerMindInputScroll,AzerMindConversationScroll}) do
   local bar=s.ScrollBar
   assert(bar.grimoireTrough.grimoireFrame.name=='button-secondary','missing bronze channel')
   assert(bar:GetThumbTexture():GetHeight()==32,'thumb too small')
   assert(bar.ScrollUpButton.grimoireFrame.name=='button-secondary','arrow lacks button enclosure')
   s:SetVerticalScroll(50);assert(s:GetVerticalScroll()==50,'native scroll behavior lost')
  end
 `);
});

test('finish 2-5: textured actions, layered paper bevel and sender hierarchy retain message behavior',t=>{
 const vm=boot(t);
 vm.run(`
  AzerMindDB.chats[1].history={{role='user',text='Question'},{role='assistant',agent='codex',text='Answer'}};AzerMind.Render()
  U=AzerMindContent.children[1];A=AzerMindContent.children[2]
  assert(U.copy.actionIcon.glyphKind=='copy' and U.delete.actionIcon.glyphKind=='delete','illustrated item icons returned')
  assert(U.copy.actionIcon.texture:find('icon-copy.tga',1,true),'copy texture missing')
  assert(#AzerMindReadingPanel.paperBevel==12,'paper bevel missing')
  assert(#A.innerOutline==4 and not A.grimoireFrame,'message outline too heavy or missing')
  assert(A.avatar:GetWidth()==32,'avatar too small')
  assert(A.who:GetText()=='AzerMind' and A.provider:GetText()=='- Codex','sender hierarchy missing')
  assert(A.who.font.size>A.provider.font.size,'provider competes with brand')
  U.resend:Disable();assert(U.resend.actionIcon:GetAlpha()==0.35,'disabled feedback lost')
  U.copy.scripts.OnClick(U.copy);assert(AzerMindCopyBox:GetText():find('Question',1,true),'copy behavior lost')
 `);
});

test('finish 6-11: readable rows, optical icons, crystal, composer padding and recessed stitches',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  local row=AzerMindConversationScroll:GetScrollChild().children[1]
  assert(row.label.font.size==14 and row.menu:GetWidth()==20,'conversation titles still crowded')
  for _,f in ipairs(STUB.frames) do
   if f.text=='Items' then assert(f.icon.opticalSize==26,'bag optical size not adjusted') end
   if f.text=='Connect' and f.actionArt then
    assert(f.connectCrystal:GetHeight()==36 and f.actionArt:GetAlpha()==0,'connect still displays a star')
    local button=GR_Bounds(f);local gem=GR_Bounds(f.connectCrystal)
    assert(gem.left>=button.left+8 and gem.right<=button.right-8,'crystal escapes button')
    assert(f.caption.points.LEFT.x==gem.right-button.left+8,'crystal label spacing inconsistent')
   end
  end
  local field=AzerMindInputScroll.parent
  assert(#field.paperBevel==12,'composer lacks paper bevel')
  assert(field.hint.font.size==13 and field.hint.points.BOTTOMLEFT.y==16,'hint still cramped')
  local seam=AzerMindConversationScroll.parent.grimoireStitches
  assert(#seam.channels==8 and #seam.parts>0,'stitches float without a recessed channel')
  assert(AzerMindLatencyIcon.points.TOPLEFT.y==-70,'header status grid not compacted')
 `);
});

test('message action textures explicitly anchor to visible buttons above the paper',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  AzerMindDB.chats[1].history={{role='user',text='Question'},{role='assistant',text='Answer'}}
  AzerMind.Render()
  for _,bubble in ipairs({AzerMindContent.children[1],AzerMindContent.children[2]}) do
   for _,button in ipairs({bubble.copy,bubble.resend,bubble.delete}) do
    local glyph=button.actionIcon
    assert(glyph.points.CENTER.relative==button,'glyph anchor depends on client defaults')
    assert(glyph:IsShown(),'glyph explicitly hidden')
    assert(glyph.kind=='Texture' and glyph.drawLayer=='OVERLAY' and glyph.drawSublevel==7,'message action must draw directly above button')
    local b=GR_Bounds(button);local g=GR_Bounds(glyph)
    assert(g.left+g.width/2==b.left+b.width/2 and g.bottom+g.height/2==b.bottom+b.height/2,'glyph is not centered in its button')
   end
  end
  assert(AzerMindContent.children[1].copy:IsShown() and AzerMindContent.children[1].resend:IsShown() and AzerMindContent.children[1].delete:IsShown(),'user message actions hidden')
  assert(AzerMindContent.children[2].copy:IsShown() and AzerMindContent.children[2].delete:IsShown(),'assistant actions hidden')
 `);
});

test('message headers keep resend-copy-delete columns, time below name and provider close to text',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  AzerMindDB.chats[1].history={{role='user',text='Question',t=1},{role='assistant',agent='codex',text='Answer',t=2}};AzerMind.Render()
  local user=AzerMindContent.children[1];local ai=AzerMindContent.children[2]
  assert(GR_Bounds(user.resend).right<GR_Bounds(user.copy).left,'resend must come first')
  assert(GR_Bounds(user.copy).right<GR_Bounds(user.delete).left,'delete must come last')
  assert(GR_Bounds(user.copy).left==GR_Bounds(ai.copy).left,'copy columns differ')
  assert(GR_Bounds(user.delete).left==GR_Bounds(ai.delete).left,'delete columns differ')
  for _,b in ipairs({user,ai}) do
   assert(b.when.points.TOPLEFT.relative==b.who and b.when.points.TOPLEFT.relativePoint=='BOTTOMLEFT','time not below sender')
   assert(b.body.points.TOPLEFT.y==-54,'body overlaps timestamp row')
   assert(b.who:GetWidth()==math.min(math.max(40,b:GetWidth()-190),b.who:GetStringWidth()),'sender still reserves fixed empty space')
  end
  assert(ai.provider.points.LEFT.relative==ai.who and ai.provider.points.LEFT.x==6,'provider separated from sender')
 `);
});

test('history scrollbar has its own inner gutter and no jump-to-latest overlay',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  for _,size in ipairs({{900,600},{1180,830},{1600,1000}}) do
   AzerMindFrame:SetSize(size[1],size[2])
   for _,fn in ipairs(AzerMindFrame.hooks.OnSizeChanged or {}) do fn(AzerMindFrame,size[1],size[2]) end
   local paper=GR_Bounds(AzerMindReadingPanel);local bar=AzerMindScroll.ScrollBar
   for _,part in ipairs({bar,bar.ScrollUpButton,bar.ScrollDownButton}) do
    local b=GR_Bounds(part)
    assert(paper.right-b.right>=12,'scrollbar overlaps paper bevel')
    assert(paper.top-b.top>=8 and b.bottom-paper.bottom>=8,'scroll arrows overlap corners')
   end
  end
  for _,f in ipairs(STUB.frames) do assert(f.text~='Jump to latest','jump-to-latest overlay still exists') end
  local range=200;AzerMindScroll.GetVerticalScrollRange=function() return range end
  AzerMind.Render();STUB.RunTimers()
  AzerMindScroll:SetVerticalScroll(0);AzerMind.Render();STUB.RunTimers()
  assert(AzerMindScroll:GetVerticalScroll()==0,'reading old messages forces a jump')
  AzerMindScroll:SetVerticalScroll(200);AzerMind.Render();range=300;STUB.RunTimers()
  assert(AzerMindScroll:GetVerticalScroll()==300,'bottom-follow behavior was lost')
 `);
});

test('native window policy groups rendering, raises only on interaction and leaves foreign addons alone',t=>{
 const vm=boot(t);
 vm.run(`
  FOREIGN=CreateFrame('Frame','ForeignQuestWindow',UIParent)
  FOREIGN:SetFrameStrata('DIALOG');FOREIGN:SetFrameLevel(80)
  assert(AzerMindFrame:GetFrameStrata()=='MEDIUM' and AzerMindMini:GetFrameStrata()=='MEDIUM','normal chat competes with dialogs')
  assert(AzerMindFrame.toplevel and AzerMindFrame.flattensRenderLayers,'chat is not a native render group')
  assert(AzerMindMini.toplevel and AzerMindMini.flattensRenderLayers,'mini bar is not a native render group')
  local count=AzerMindFrame.raiseCount or 0
  AzerMind.Render();AzerMind.Render()
  assert((AzerMindFrame.raiseCount or 0)==count,'background rendering steals front position')
  for _,fn in ipairs(AzerMindFrame.hooks.OnMouseDown or {}) do fn(AzerMindFrame) end
  assert(AzerMindFrame.raiseCount==count+1,'click does not raise the window')
  AzerMind.ShowAppearanceSettings()
  assert(AzerMindAppearanceSettings.toplevel and AzerMindAppearanceSettings.flattensRenderLayers,'dialog not grouped')
  assert(AzerMindAppearanceSettings:GetFrameStrata()=='FULLSCREEN_DIALOG','modal dialog lost its intended layer')
  assert(FOREIGN:GetFrameStrata()=='DIALOG' and FOREIGN:GetFrameLevel()==80,'foreign addon was modified')
 `);
});
