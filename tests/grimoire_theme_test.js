'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const boot=require('./helpers/grimoire-vm');
test('actual main-window controls use bronze skins, burgundy selection, avatars and generated icons',t=>{
  const vm=boot(t);
  vm.run(`
    local chat=AzerMindDB.chats[1]
    chat.history={{role="user",text="Question"},{role="assistant",text="Answer"}}
    AzerMind.Render()
    ROW=AzerMindConversationScroll:GetScrollChild().children[1]
    USER=AzerMindContent.children[1]; AI=AzerMindContent.children[2]
    for _,b in ipairs(STUB.frames) do if b.text=="Items" then ITEMS=b end end
  `);
  assert.equal(vm.value('AzerMindFrame.grimoireFrame.name'),'frame-window');
  assert.equal(vm.value('ROW.grimoireFrame.name'),'conversation-selection');
  assert.equal(vm.num('ROW.selected.color[1]'),0.29);
  assert.equal(vm.num('ROW.selected.color[2]'),0.07);
  assert.equal(vm.value('ITEMS.grimoireFrame.name'),'button-secondary');
  assert.equal(vm.value('ITEMS.normalTexture'),'');
  assert.equal(vm.value('ITEMS.template'),'nil');
  assert.match(vm.value('ITEMS.icon.art.texture'),/icon-items\.tga$/);
  assert.match(vm.value('USER.avatar.texture'),/icon-user\.tga$/);
  assert.match(vm.value('AI.avatar.texture'),/emblem\.tga$/);
  assert.equal(vm.value('AI.grimoireFrame'),'nil');
  assert.equal(vm.num('AI.separator.height'),1);
  assert.ok(vm.num('AI.height')>=72);
  vm.run('AzerMind.NewChat(); AzerMind.Render()');
  assert.equal(vm.value('ROW.grimoireFrame.name'),'button-secondary');
  assert.ok(vm.num('ROW.label.textColor[1]')>0.8);
});
test('button hover, pressed, disabled and selected artwork preserves the click action',t=>{
  const vm=boot(t);
  vm.run(`
    CLICKS=0
    BUTTON=AzerMindTheme.Button(AzerMindFrame,"Test",100,30,function() CLICKS=CLICKS+1 end)
    function HOOK(event) for _,fn in ipairs(BUTTON.hooks[event] or {}) do fn(BUTTON) end end
    HOOK("OnEnter")
  `);
  assert.equal(vm.value('BUTTON.grimoireState'),'hover');
  vm.run('HOOK("OnMouseDown")');assert.equal(vm.value('BUTTON.grimoireState'),'pressed');
  assert.equal(vm.num('BUTTON.grimoireFrame.parts[1].vertexColor[1]'),0.72);
  vm.run('HOOK("OnMouseUp"); BUTTON.scripts.OnClick()');assert.equal(vm.num('CLICKS'),1);
  vm.run('BUTTON:Disable()');assert.equal(vm.value('BUTTON.grimoireState'),'disabled');
  assert.equal(vm.num('BUTTON.grimoireFrame.parts[1].vertexColor[1]'),0.52);
  vm.run('BUTTON:Enable(); HOOK("OnLeave"); AzerMindTheme.Selected(BUTTON,true)');
  assert.equal(vm.value('BUTTON.grimoireState'),'normal');
  assert.equal(vm.value('BUTTON.grimoireFrame.name'),'button-primary');
});
test('three actual scrollbars retain slider behavior and receive generated navigation art',t=>{
  const vm=boot(t);
  for(const name of ['AzerMindConversationScroll','AzerMindScroll','AzerMindInputScroll']) {
    assert.equal(vm.value(`${name}.ScrollBar.grimoireSkinned`),'true');
    assert.equal(vm.value(`${name}.ScrollBar.grimoireThumb.grimoireFrame.name`),'button-secondary');
    assert.match(vm.value(`${name}.ScrollBar.ScrollUpButton.normalTexture`),/icon-chevron-up\.tga$/);
    assert.match(vm.value(`${name}.ScrollBar.ScrollDownButton.normalTexture`),/icon-chevron-down\.tga$/);
    vm.run(`${name}:SetVerticalScroll(64)`);
    assert.equal(vm.num(`${name}:GetVerticalScroll()`),64);
  }
});
test('composer focus highlights its existing border without allocating new textures',t=>{
  const vm=boot(t);
  vm.run('FIELD=AzerMindInputScroll.parent; REGIONS=#FIELD.textures; for _,fn in ipairs(AzerMindInput.hooks.OnEditFocusGained) do fn(AzerMindInput) end');
  assert.equal(vm.value('FIELD.grimoireFocused'),'true');
  assert.equal(vm.num('FIELD.grimoireFrame.parts[1].vertexColor[1]'),1);
  vm.run('for _,fn in ipairs(AzerMindInput.hooks.OnEditFocusLost) do fn(AzerMindInput) end');
  assert.equal(vm.value('FIELD.grimoireFocused'),'false');
  assert.equal(vm.num('FIELD.grimoireFrame.parts[1].vertexColor[1]'),0.95);
  assert.equal(vm.num('#FIELD.textures'),vm.num('REGIONS'));
});
test('illustrated skins use per-axis slices and larger live typography',t=>{
  const vm=boot(t);
  vm.run('AzerMindDB.chats[1].history={{role="assistant",text="Readable answer"}}; AzerMind.Render(); B=AzerMindContent.children[1]');
  assert.equal(vm.num('AzerMindFrame.grimoireFrame.native'),1024);
  assert.equal(vm.value('B.grimoireFrame'),'nil');
  assert.ok(vm.num('B.bg.color[4]')<0.1);
  assert.equal(vm.num('B.body.font.size'),16);
  assert.match(vm.value('B.body.font.file'),/FRIZQT__/);
  assert.equal(vm.num('B.who.font.size'),20);
  assert.equal(vm.num('AzerMindInput.font.size'),16);
  vm.run(`NEW=AzerMindConversationScroll.parent.children[1]; for _,f in ipairs(STUB.frames) do if f.text=="+ New chat" then NEW=f end end`);
  assert.equal(vm.value('NEW.grimoireFrame.name'),'button-paper');
});
test('composer placeholder follows draft content while its keyboard hint remains visible',t=>{
  const vm=boot(t);
  vm.run('FIELD=AzerMindInputScroll.parent; AzerMindInput:SetText("draft"); for _,fn in ipairs(AzerMindInput.hooks.OnTextChanged) do fn(AzerMindInput) end');
  assert.equal(vm.value('FIELD.placeholder:IsShown()'),'false');
  assert.equal(vm.value('FIELD.hint:IsShown()'),'true');
  vm.run('AzerMindInput:SetText(""); for _,fn in ipairs(AzerMindInput.hooks.OnTextChanged) do fn(AzerMindInput) end');
  assert.equal(vm.value('FIELD.placeholder:IsShown()'),'true');
});
test('composer action artwork follows connect, send and stop states',t=>{
  const vm=boot(t);
  vm.run(`for _,f in ipairs(STUB.frames) do if f.text=="Connect" and f.actionArt then CONNECT=f elseif f.text=="Send" and f.actionArt then SEND=f end end`);
  assert.match(vm.value('CONNECT.actionArt.texture'),/icon-connect\.tga$/);
  assert.match(vm.value('SEND.actionArt.texture'),/icon-send\.tga$/);
  vm.run('AzerMind.IsConnected=function() return true end; AzerMindDB.chats[1].pendingId=123; AzerMind.UpdateConnect()');
  assert.equal(vm.value('SEND:GetText()'),'Stop');
  assert.match(vm.value('SEND.actionArt.texture'),/icon-stop\.tga$/);
  assert.equal(vm.value('CONNECT:IsShown()'),'false');
  vm.run('AzerMindDB.chats[1].pendingId=nil; AzerMind.UpdateConnect()');
  assert.match(vm.value('SEND.actionArt.texture'),/icon-send\.tga$/);
});
test('runtime texture references resolve to generated production art',t=>{
  const vm=boot(t);
  vm.run(`local refs={}; for _,f in ipairs(STUB.frames) do for _,region in ipairs(f.textures or {}) do if type(region.texture)=="string" and region.texture:find("Art\\\\Grimoire",1,true) then refs[#refs+1]=region.texture end end end; REFERENCES=table.concat(refs,"\\n")`);
  const refs=vm.value('REFERENCES').split('\n');assert.ok(refs.length>30);
  for(const ref of refs) assert.ok(fs.existsSync(path.join(__dirname,'../addon/AzerMind/Art/Grimoire',ref.split('\\').at(-1))),ref);
});
