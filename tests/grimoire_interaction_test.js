'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const boot=require('./helpers/grimoire-vm');
test('inventory attachments become inspectable cards while saved context and copy remain intact',t=>{
  const vm=boot(t);
  const original='--- Selected inventory items ---\nInventory snapshot: 2026-11-11 20:21. Only Equipped entries are worn.\nBank: |cffa335ee|Hitem:6265|h[Soul Shard]|h|r ×4 (bank snapshot: yesterday)\n--- End selected inventory items ---\n\nWhat is it for?';
  vm.run(`ORIGINAL=${JSON.stringify(original)}; AzerMindDB.chats[1].history={{role="user",text=ORIGINAL}}; AzerMind.Render(); B=AzerMindContent.children[1]`);
  assert.equal(vm.value('B.body:GetText()'),'What is it for?');
  assert.equal(vm.value('B.attachment:GetText()'),'Soul Shard ×4 · Bank');
  assert.equal(vm.value('B.attachment:IsShown()'),'true');
  assert.equal(vm.value('AzerMindDB.chats[1].history[1].text'),original);
  assert.match(vm.value('B.copyText'),/Inventory snapshot:/);
  vm.run('B.attachment.scripts.OnClick(B.attachment)');
  assert.match(vm.value('AzerMindCopyBox:GetText()'),/Soul Shard/);
  vm.run('AzerMindDB.chats[1].history={{role="assistant",text="Normal response"}}; AzerMind.Render()');
  assert.equal(vm.value('B.attachment:IsShown()'),'false');
});
test('incomplete snapshots and assistant-quoted markers are not silently hidden',t=>{
  const vm=boot(t);
  for(const role of ['user','assistant']) {
    const text='--- Selected inventory items ---\nBank: [Soul Shard] ×4';
    assert.equal(vm.value(`AzerMind.PresentMessage(${JSON.stringify(role)},${JSON.stringify(text)})`),text);
  }
});
test('skinned chat controls keep draft, conversation selection, menu and minimize/restore behavior',t=>{
  const vm=boot(t);
  vm.run(`
    AzerMindInput:SetText("My draft")
    FIRST=AzerMindDB.activeChat
    AzerMind.NewChat(); SECOND=AzerMindDB.activeChat
    FIRST_ROW=AzerMindConversationScroll:GetScrollChild().children[1]
    FIRST_ROW.scripts.OnClick(FIRST_ROW,"LeftButton")
  `);
  assert.equal(vm.value('AzerMindDB.activeChat'),vm.value('FIRST'));
  assert.equal(vm.value('FIRST_ROW.grimoireFrame.name'),'conversation-selection');
  vm.run('FIRST_ROW.menu.scripts.OnClick(FIRST_ROW.menu)');
  assert.equal(vm.value('AzerMindChatMenu:IsShown()'),'true');
  vm.run('FIRST_ROW.menu.scripts.OnClick(FIRST_ROW.menu)');
  assert.equal(vm.value('AzerMindChatMenu:IsShown()'),'false');
  vm.run('AzerMindInput:SetText("Keep draft"); AzerMind.Minimize(true)');
  assert.equal(vm.value('AzerMindMini:IsShown()'),'true');
  vm.run('AzerMind.Minimize(false)');
  assert.equal(vm.value('AzerMindInput:GetText()'),'Keep draft');
  assert.equal(vm.value('AzerMindFrame:IsShown()'),'true');
  assert.equal(vm.value('AzerMindInput:HasFocus()'),'true');
});
