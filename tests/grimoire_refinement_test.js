'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const boot=require('./helpers/grimoire-vm');
const geometry=fs.readFileSync(path.join(__dirname,'helpers/grimoire-geometry.lua'),'utf8');
test('refinement 1: header safe area, aligned controls and latency on its own row',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  for _,f in ipairs(STUB.frames) do if f.text=='Config' then CONFIG=f end end
  local mini=CONFIG.points.RIGHT.relative
  local outer=GR_Bounds(AzerMindFrame); local c=GR_Bounds(CONFIG); local m=GR_Bounds(mini)
  assert(outer.top-c.top>=28 and outer.right-m.right>=32,'header safe margin')
  assert(c.top==m.top and c.bottom==m.bottom and m.left-c.right==12,'header alignment')
  GetNetStats=function() return 0,0,41,133 end; AzerMind.UpdateLatency()
  local anchor=AzerMindLatency.points.LEFT
  assert(anchor.relative==AzerMindLatencyIcon and anchor.relativePoint=='RIGHT','latency needs its mini icon')
  assert(AzerMindLatencyIcon.points.TOPLEFT.y==-70,'latency needs a separate row below bridge status')
 `);
 assert.equal(vm.value('AzerMindLatency:GetText()'),'133 ms');
 vm.run('GetNetStats=nil; AzerMind.UpdateLatency()');assert.equal(vm.value('AzerMindLatency:GetText()'),'-- ms');
});

test('refinement 2: composer actions respect safe margins and keep their state behavior',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  for _,f in ipairs(STUB.frames) do if f.text=='Clear draft' then CLEAR=f elseif f.text=='Send' then SEND=f end end
  for _,size in ipairs({{900,600},{1180,830},{1600,1000}}) do
   AzerMindFrame:SetSize(size[1],size[2])
   for _,fn in ipairs(AzerMindFrame.hooks.OnSizeChanged or {}) do fn(AzerMindFrame,size[1],size[2]) end
   local outer=GR_Bounds(AzerMindFrame); local field=GR_Bounds(AzerMindInputScroll.parent)
   local send=GR_Bounds(SEND);local clear=GR_Bounds(CLEAR)
   assert(outer.right-send.right==32 and clear.bottom-outer.bottom==30,'composer safe margins')
   assert(send.left-field.right==12 and send.left==clear.left and send.right==clear.right,'composer alignment')
   assert(send.top==field.top and send.bottom-clear.top==8,'composer vertical rhythm')
  end
  AzerMindInput:SetText('draft');CLEAR.scripts.OnClick(CLEAR)
  assert(AzerMindInput:GetText()=='','clear draft behavior lost')
 `);
 assert.equal(vm.value('SEND.grimoireFrame.name'),'button-secondary');
});

test('refinement 3: message actions use distinct artwork, safe hit areas and close assistant gaps',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  AzerMindDB.chats[1].history={{role='user',text='Question'},{role='assistant',text='Answer'}}
  AzerMind.Render(); USER=AzerMindContent.children[1]; AI=AzerMindContent.children[2]
  for _,b in ipairs({USER,AI}) do
   local outer=GR_Bounds(b);local action=GR_Bounds(b.delete)
   assert(outer.right-action.right==14 and outer.top-action.top==10,'action margin')
   assert(b.copy:GetWidth()==32,'action hit area too small')
   assert(b.copy.points.RIGHT.relative==b.delete,'copy and delete columns drift')
  end
  USER.resend:Disable(); assert(USER.resend.actionIcon.alpha==0.35,'missing disabled feedback')
  USER.resend:Enable(); assert(USER.resend.actionIcon.alpha==1,'missing enabled feedback')
 `);
 for(const kind of ['copy','resend','delete']) assert.equal(vm.value(`USER.${kind}.actionIcon.glyphKind`),kind);
});

test('refinement 4: navigation prioritizes titles, keeps deletion accessible and uses bronze thumbs',t=>{
 const vm=boot(t);
 vm.run(`
  AzerMind.NewChat(); AzerMind.Render()
  ROW=AzerMindConversationScroll:GetScrollChild().children[1]
  assert(not ROW.del:IsShown(),'permanent trash crowds conversation title')
  ROW.menu.scripts.OnClick(ROW.menu)
  FOUND=false
  for _,f in ipairs(STUB.frames) do if f.label and f.label:GetText()=='Delete conversation...' then FOUND=true end end
  assert(FOUND,'conversation deletion disappeared from menu')
  for _,scroll in ipairs({AzerMindScroll,AzerMindInputScroll,AzerMindConversationScroll}) do
   assert(scroll.ScrollBar:GetThumbTexture():GetAlpha()==1,'thumb invisible')
   assert(scroll.ScrollBar.grimoireThumb.grimoireFrame.name=='button-secondary','thumb lacks bronze skin')
  end
 `);
 assert.ok(vm.num('ROW.label.textColor[1]')>0.8);
 assert.equal(vm.num('ROW.grimoireFrame.parts[5].alpha'),1);
});

test('refinement 5: sources remain inspectable and long sender labels reserve action space',t=>{
 const vm=boot(t);
 vm.run(`
  TEXT='Answer\\n\\nSources:\\nhttps://example.com/reference'
  RENDERED,SOURCES=AzerMind.RichMessage('assistant',TEXT)
  assert(RENDERED:find('Sources (1)',1,true),'missing source count')
  assert(RENDERED:find('|Hazermindsources:1|h',1,true),'sources lost their interaction')
  assert(AzerMind.CopyMessage('assistant',TEXT):find('https://example.com/reference',1,true),'copy dropped sources')
  AzerMindDB.chats[1].history={{role='assistant',text=TEXT}}
  AzerMind.Render(); B=AzerMindContent.children[1]
  assert(B.who:GetWidth()<=B:GetWidth()-240,'sender can overlap action cluster')
  assert(B.body:GetWidth()<=B:GetWidth()-28,'body lost its inner margins')
 `);
});

test('refinement 6: measured multiline drafts grow within bounds and release space when cleared',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  FIELD=AzerMindInputScroll.parent
  FIELD.draftMeasure.GetStringHeight=function() return 220 end
  AzerMindInput:SetText('A multiline draft')
  for _,fn in ipairs(AzerMindInput.hooks.OnTextChanged) do fn(AzerMindInput) end
  assert(FIELD:GetHeight()==180,'long draft does not grow or exceeds cap')
  local chat=GR_Bounds(AzerMindScroll);local field=GR_Bounds(FIELD)
  assert(chat.bottom>=field.top+42,'growing draft overlaps transcript')
  FIELD.draftMeasure.GetStringHeight=function() return 16 end
  AzerMindInput:SetText('')
  for _,fn in ipairs(AzerMindInput.hooks.OnTextChanged) do fn(AzerMindInput) end
  assert(FIELD:GetHeight()==112,'clearing draft does not restore history space')
 `);
});

test('toolbar icons and captions share a centerline and retain padding at every window size',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  for _,size in ipairs({{900,600},{1180,830},{1600,1000}}) do
   AzerMindFrame:SetSize(size[1],size[2])
   for _,fn in ipairs(AzerMindFrame.hooks.OnSizeChanged or {}) do fn(AzerMindFrame,size[1],size[2]) end
   local count=0
   for _,button in ipairs(STUB.frames) do
    if button.text=='Items' or button.text=='Quests' or button.text=='Dungeons & Raids' or (button.text and button.text:find('Context:',1,true)==1) then
     count=count+1
     local b=GR_Bounds(button); local icon=GR_Bounds(button.icon)
     assert(icon.width==24 and icon.height==24,'inconsistent icon canvas')
     assert(icon.bottom+icon.height/2==b.bottom+b.height/2,'icon not vertically centered')
     assert(icon.left-b.left==10,'inconsistent icon inset')
     assert(button.caption.points.LEFT.y==0,'caption baseline drift')
     assert(button.caption.points.LEFT.x==40,'inconsistent icon/text spacing')
     assert(button.caption:GetWidth()==button:GetWidth()-50,'caption lacks right padding')
    end
   end
   assert(count==4,'missing toolbar control')
  end
 `);
});

test('reference composition keeps continuous paper, dark sidebar and compact message rhythm',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  AzerMindDB.chats[1].history={{role='user',text='Question'},{role='assistant',text='Answer'}}
  AzerMind.Render()
  local user=AzerMindContent.children[1]; local ai=AzerMindContent.children[2]
  assert(AzerMindScroll.grimoireMaterial.grimoireAsset=='parchment','continuous paper backdrop missing')
  for _,b in ipairs({user,ai}) do
   assert(not b.grimoireFrame,'ornamental message frame returned')
   assert(b.bg.color[4]<0.1 and b.body.textColor[1]<0.3,'paper has unreadable text or an opaque inner box')
   assert(b.separator:GetHeight()==1,'message divider too heavy')
  end
  assert(-ai.points.TOPLEFT.y-user:GetHeight()==4,'excess message gap returned')
  local row=AzerMindConversationScroll:GetScrollChild().children[1]
  assert(row.grimoireMaterial.grimoireAsset=='leather','white conversation background returned')
  assert(row.grimoireFrame.parts[5]:GetAlpha()==1 and row.grimoireFrame.name~='button-paper','dark conversation background missing')
  assert(#row.menu.dots==3 and row.menu.dots[1]:GetWidth()==3,'conversation menu is not legible')
  local b=GR_Bounds(row);local bar=GR_Bounds(AzerMindConversationScroll.ScrollBar)
  assert(bar.left-b.right>=12,'conversation row crowds scrollbar')
  local outer=GR_Bounds(AzerMindFrame);local logo
  for _,texture in ipairs(AzerMindFrame.textures) do
   if texture.texture and texture.texture:find('emblem.tga',1,true) then logo=texture end
  end
  assert(logo,'missing logo')
  local l=GR_Bounds(logo)
  assert(l.left-outer.left>=32 and outer.top-l.top>=28,'logo crowds outer ornament')
 `);
});

test('minimum-width toolbar stays on one line while input and message actions retain behavior',t=>{
 const vm=boot(t);vm.run(geometry);
 vm.run(`
  for _,size in ipairs({{900,600},{1180,830},{1600,1000}}) do
   AzerMindFrame:SetSize(size[1],size[2])
   for _,fn in ipairs(AzerMindFrame.hooks.OnSizeChanged or {}) do fn(AzerMindFrame,size[1],size[2]) end
   local baseline
   for _,button in ipairs(STUB.frames) do
    if button.text=='Items' or button.text=='Quests' or button.text=='Dungeons & Raids' or (button.text and button.text:find('Context:',1,true)==1) then
     local bounds=GR_Bounds(button)
     baseline=baseline or bounds.bottom
     assert(bounds.bottom==baseline,'toolbar split into unbalanced rows')
    end
   end
  end
 `);
});
