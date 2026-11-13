'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('fengari');
const source = path.join(__dirname, '../addon/AzerMind/GearIntelligence.lua');

function fixture(extra = '') {
  const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
  const run = text => {
    if (lauxlib.luaL_dostring(L, to_luastring(text)) !== lua.LUA_OK)
      throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  };
  run(`
    calls=0
    AzerMind={ContextSettings=function() return {equipment=true},true end}
    destination={status="ok",name="Razorfen Downs",provenance="explicit"}
    hunts={status="ok",version="1.1.4",class="MAGE",spec="Frost",entries={
      {itemID=100,name="Ice staff",slot="MainHand",owned=false},
      {itemID=101,name="Owned robe",slot="Chest",owned=true},
      {itemID=102,name="Quest ring",slot="Finger",owned=false}}}
    loot={status="ok",source="ForeverDungeonJournal",version="2.0.2",entries={
      {itemID=100,name="Ice staff",kind="boss",sourceName="Amnennar"},
      {itemID=101,name="Owned robe",kind="trash",sourceName="Trash"},
      {itemID=102,name="Quest ring",kind="quest",sourceName="Test quest",questID=7,questCompleted=true}}}
    AzerMind.ResolveDungeonQuestion=function(text) query=text; return destination end
    AzerMind.ReadGearQuestHunts=function() calls=calls+1; return hunts end
    AzerMind.ReadDungeonLoot=function(name) lootQuery=name; return loot end
  `);
  if (fs.existsSync(source)) run(fs.readFileSync(source, 'utf8'));
  run(extra);
  return {
    run,
    get(expr) { run(`RESULT=${expr}`); lua.lua_getglobal(L,to_luastring('RESULT'));
      const value=lua.lua_isnil(L,-1)?null:to_jsstring(lua.lua_tolstring(L,-1)); lua.lua_pop(L,1); return value; }
  };
}

test('matches current hunts by item ID, omits owned gear and preserves source kinds',()=>{
  const vm=fixture(); const text=vm.get('AzerMind.GearQuestionContext("Vou RFD, tem itens do GearQuest?")');
  assert.match(text,/Ice staff.*item 100.*MainHand.*Boss: Amnennar/);
  assert.match(text,/Quest ring.*Quest reward: Test quest.*quest 7.*already turned in/);
  assert.doesNotMatch(text,/Owned robe/);
  assert.match(text,/GearQuest.*1\.1\.4/); assert.match(text,/ForeverDungeonJournal.*2\.0\.2/);
});
test('does not query or transmit hunts when character or equipment sharing is off',()=>{
  for(const settings of ['{},false','{equipment=false},true']) {
    const vm=fixture(`AzerMind.ContextSettings=function() return ${settings} end`);
    assert.equal(vm.get('AzerMind.GearQuestionContext("GearQuest RFD")'),'');
    assert.equal(vm.get('tostring(calls)'),'0');
  }
});
test('unrelated text inside an instance does not send a gear attachment',()=>{
  const vm=fixture('destination.provenance="current"');
  assert.equal(vm.get('AzerMind.GearQuestionContext("ola")'),'');
  assert.equal(vm.get('tostring(calls)'),'0');
});
test('ordinary item questions outside a dungeon do not demand a dungeon name',()=>{
  const vm=fixture('destination={status="unknown"}');
  assert.equal(vm.get('AzerMind.GearQuestionContext("Onde compro esse item?")'),'');
  assert.equal(vm.get('tostring(calls)'),'0');
});
test('missing or ambiguous destination asks for a name instead of guessing',()=>{
  for(const state of ['unknown','ambiguous']) {
    const vm=fixture(`destination={status="${state}"}`);
    assert.match(vm.get('AzerMind.GearQuestionContext("A dungeon que vou tem itens do GearQuest?")'),/Ask.*dungeon name/i);
    assert.equal(vm.get('tostring(calls)'),'0');
  }
});
test('unavailable and preview addons never become a no-upgrades answer',()=>{
  for(const state of ['unavailable','preview']) {
    const vm=fixture(`hunts={status="${state}",reason="test state"}`);
    const text=vm.get('AzerMind.GearQuestionContext("GearQuest RFD")');
    assert.match(text,/test state/); assert.match(text,/Cannot establish/);
    assert.doesNotMatch(text,/No matching/);
  }
});
test('partial snapshot misses are explicitly inconclusive',()=>{
  const vm=fixture('loot={status="partial",source="Bundled snapshot",entries={},partial=true}');
  const text=vm.get('AzerMind.GearQuestionContext("GearQuest RFD")');
  assert.match(text,/No matching.*available data/); assert.match(text,/incomplete|partial/i);
  assert.match(text,/not proof.*no upgrades/i);
});
test('missing item IDs and duplicate sources do not invent matches',()=>{
  const vm=fixture('loot.entries[4]=loot.entries[1]; loot.entries[5]={name="Missing",kind="boss",sourceName="Unknown"}; hunts.entries[4]={name="Missing",slot="Head"}');
  const text=vm.get('AzerMind.GearQuestionContext("GearQuest RFD")');
  assert.equal((text.match(/Boss: Amnennar/g)||[]).length,1); assert.doesNotMatch(text,/Missing/);
});
test('random suffix and unknown ownership cannot be claimed as guaranteed upgrades',()=>{
  const vm=fixture('hunts.entries[1].suffix=-19; hunts.entries[1].owned=nil');
  const text=vm.get('AzerMind.GearQuestionContext("GearQuest RFD")');
  assert.match(text,/suffix.*-19/i); assert.match(text,/ownership unknown/i);
  assert.match(text,/base item ID/); assert.match(text,/not guaranteed upgrades/i);
});
test('attachments stay within 3200 bytes with an explicit partial marker',()=>{
  const vm=fixture(`hunts.entries={}; loot.entries={}; for i=1,200 do
    hunts.entries[i]={itemID=i,name=string.rep("Ç",80),slot="MainHand",owned=false}
    loot.entries[i]={itemID=i,name="n",kind="boss",sourceName=string.rep("B",100)} end`);
  const text=vm.get('AzerMind.GearQuestionContext("GearQuest RFD")');
  assert.ok(Buffer.byteLength(text)<=3200); assert.match(text,/Partial matches/);
  assert.ok(!text.includes('\uFFFD'));
});
test('adapter errors do not block chat or expose raw stack traces',()=>{
  const vm=fixture('AzerMind.ReadDungeonLoot=function() error("C:/private/path/token") end');
  const text=vm.get('AzerMind.GearQuestionContext("GearQuest RFD")');
  assert.match(text,/unavailable/i); assert.doesNotMatch(text,/private|token/);
});
