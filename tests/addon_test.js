// Runs the real addon Lua (Codec.lua + AzerMind.lua) in a Lua VM with a stub
// WoW API (wow_stub.lua) and drives it through a session: login, hello, a sent
// message read back off the pixel strip, a reply delivered through a slot, the
// bridge's default folder and agent, a chat that picks another agent, a
// permission denial with Allow, and a restore.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const ADDON = path.join(__dirname, '..', 'addon', 'AzerMind');
const CELLS_PER_ROW = 200;

test('quest location dropdowns cascade in both tabs and preserve hidden selections',()=>{
  const vm=newVM(); login(vm);
  vm.run(`
    C_Map.GetAreaInfo=function(id) return ({[130]="Silverpine Forest",[85]="Tirisfal Glades"})[id] end
    AzerMindCatalog={manifest={version="fixture"},items={},npcs={},objects={},quests={
      [900001]={id=900001,name="First",zoneID=130,cityIDs={1497}},
      [900002]={id=900002,name="Second",zoneID=85,cityIDs={1497}},
      [900003]={id=900003,name="Third",zoneID=130,cityIDs={1637}}}}
    C_QuestLog={GetNumQuestLogEntries=function() return 3 end,GetInfo=function(i) return {questID=900000+i,title="Quest "..i} end}
    function FilterLocations()
      local p=AzerMindQuestPicker
      p.selected[900002]=true
      for _,b in ipairs(p.children) do if b.text and b.text:find("City:",1,true)==1 then b.scripts.OnClick(b); break end end
      for _,row in ipairs(AzerMindChoiceMenu.rows) do if row.option.key=="1497" then row.scripts.OnClick(row); break end end
      CITY_RESULT=#p.visible
      for _,b in ipairs(p.children) do if b.text and b.text:find("Zone:",1,true)==1 then b.scripts.OnClick(b); break end end
      ZONE_CHOICES=#AzerMindChoiceMenu.options
      for _,row in ipairs(AzerMindChoiceMenu.rows) do if row.option.key=="130" then row.scripts.OnClick(row); break end end
    end
    AzerMind.ShowQuestPicker(); FilterLocations()
  `);
  for(const tab of ['active','catalog']) {
    if(tab==='catalog') vm.run(`for _,b in ipairs(AzerMindQuestPicker.children) do if b.text=="Quest database" then b.scripts.OnClick(b); break end end; FilterLocations()`);
    assert.equal(vm.num('CITY_RESULT'),2,tab);
    assert.equal(vm.num('ZONE_CHOICES'),3,tab);
    assert.equal(vm.num('#AzerMindQuestPicker.visible'),1,tab);
    assert.equal(vm.num('AzerMindQuestPicker.visible[1].id'),900001,tab);
    assert.equal(vm.evaluate('AzerMindQuestPicker.selected[900002]'),'true',tab);
  }
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'),null);
});

test('catalog pickers reuse a bounded number of rows and do not send selections automatically',()=>{
  const vm=newVM(); login(vm);
  vm.run(`
    AzerMindCatalog={manifest={source="Fixture",version="1"},items={},quests={},npcs={},objects={}}
    for i=1,2000 do
      AzerMindCatalog.items[i]={id=i,name=string.format("Item %04d",i),classID=4,subclassID=1}
      AzerMindCatalog.quests[i]={id=i,name=string.format("Quest %04d",i),level=23}
    end
    AzerMind.ShowItemPicker()
    for _,child in ipairs(AzerMindItemPicker.children) do if child.text=="Item database" then child.scripts.OnClick() end end
  `);
  assert.equal(vm.num('#AzerMindItemPicker.visible'),2000);
  assert.ok(vm.num('#AzerMindItemPicker.rows')<=6);
  vm.run(`AzerMindItemPicker.rows[1].checked=true; AzerMindItemPicker.rows[1].scripts.OnClick(AzerMindItemPicker.rows[1]); AzerMindItemPicker.next.scripts.OnClick()`);
  assert.equal(vm.num('AzerMindItemPicker.rows[1].item.id'),26);
  assert.equal(vm.num('AzerMindItemPicker.page'),2);
  assert.equal(vm.evaluate('AzerMindItemPicker.selected["catalog:1"]'),'true','changing pages preserves the selection');
  vm.run(`AzerMindItemPicker.previous.scripts.OnClick()`);
  assert.equal(vm.num('AzerMindItemPicker.rows[1].item.id'),1);
  vm.run(`AzerMindItemPickerScroll:SetVerticalScroll(48*10); for _,fn in ipairs(AzerMindItemPickerScroll.hooks.OnVerticalScroll) do fn() end`);
  assert.equal(vm.num('AzerMindItemPicker.rows[1].item.id'),11);
  vm.run(`AzerMind.ShowQuestPicker(); for _,child in ipairs(AzerMindQuestPicker.children) do if child.text=="Quest database" then child.scripts.OnClick() end end`);
  assert.equal(vm.num('#AzerMindQuestPicker.visible'),2000);
  assert.ok(vm.num('#AzerMindQuestPicker.rows')<=7);
  vm.run('AzerMindQuestPicker.next.scripts.OnClick()');
  assert.equal(vm.num('AzerMindQuestPicker.rows[1].quest.id'),26);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'),null);
});

test('owned items group matching bag stacks but keep equipped and cached bank locations separate', () => {
  const vm = newVM();
  vm.run(`
    local link = "|cffffffff|Hitem:123:0:0:0|h[Test cloth]|h|r"
    GetRealmName = function() return "TestRealm" end
    UnitName = function() return "TestPlayer" end
    GetInventoryItemLink = function(_, slot) if slot == 1 then return link end end
    C_Item = {GetItemInfo=function() return "Test cloth", link, 1, 10, 5, "Armor", "Cloth", 20, "INVTYPE_HEAD", 134400, 0, 4, 1 end}
    C_Container = {
      GetContainerNumSlots=function(bag) return bag == 0 and 2 or 0 end,
      GetContainerItemLink=function() return link end,
      GetContainerItemInfo=function(_, slot) return {stackCount=slot+1} end
    }
    AzerMindItemsDB = {["TestRealm:TestPlayer"]={bank={{link=link,count=7}},updated="2026-11-10 20:00"}}
    ITEMS = AzerMind.OwnedItems()
  `);
  assert.equal(vm.num('#ITEMS'), 3);
  for (const [location, count] of [['Bags', 5], ['Equipped', 1], ['Bank', 7]]) {
    assert.equal(vm.num(`(function() for _, item in ipairs(ITEMS) do if item.location == "${location}" then return item.count end end end)()`), count);
  }
  assert.equal(vm.evaluate('ITEMS[1].subtype'), 'Cloth');
  assert.equal(vm.num('ITEMS[1].classID'), 4);
});

test('opening, expanding and creating chats focuses the composer and hiding releases it', () => {
  const vm = newVM();
  login(vm);
  vm.run('AzerMind.Toggle(false); AzerMindInput:SetText("draft"); AzerMind.Toggle(true)');
  assert.equal(vm.evaluate('AzerMindInput:HasFocus()'), 'true');
  assert.equal(vm.evaluate('AzerMindInput:GetText()'), 'draft');
  vm.run('AzerMind.Minimize(true)');
  assert.equal(vm.evaluate('AzerMindInput:HasFocus()'), 'false');
  vm.run('AzerMind.Minimize(false)');
  assert.equal(vm.evaluate('AzerMindInput:HasFocus()'), 'true');
  vm.run('AzerMindInput:ClearFocus(); AzerMind.NewChat()');
  assert.equal(vm.evaluate('AzerMindInput:HasFocus()'), 'true');
  assert.equal(vm.evaluate('AzerMindInput:GetText()'), '');
  vm.run('AzerMind.Toggle(false)');
  assert.equal(vm.evaluate('AzerMindInput:HasFocus()'), 'false');
});

function newVM() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = (code, arg) => {
    if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK) throw new Error('Lua load: ' + to_jsstring(lua.lua_tostring(L, -1)));
    let nargs = 0;
    if (arg !== undefined) { lua.lua_pushstring(L, to_luastring(arg)); nargs = 1; }
    if (lua.lua_pcall(L, nargs, 0, 0) !== lua.LUA_OK) throw new Error('Lua error: ' + to_jsstring(lua.lua_tostring(L, -1)));
  };
  // Evaluate an expression and bring it back as a string (or nil).
  const evaluate = (expr) => {
    run(`local v = (${expr}); if v == nil then RESULT = nil else RESULT = tostring(v) end`);
    lua.lua_getglobal(L, to_luastring('RESULT'));
    const isNil = lua.lua_isnil(L, -1);
    const s = isNil ? null : to_jsstring(lua.lua_tolstring(L, -1));
    lua.lua_pop(L, 1);
    return s;
  };
  const num = (expr) => Number(evaluate(expr));
  run(fs.readFileSync(path.join(__dirname, 'wow_stub.lua'), 'utf8'));
  for (const f of ['Codec.lua', 'Inbox.lua', 'Theme.lua', 'AzerMind.lua', 'Links.lua', 'Settings.lua', 'Quests.lua', 'Catalog.lua', 'Items.lua', 'InstancesData.lua', 'Instances.lua']) run(fs.readFileSync(path.join(ADDON, f), 'utf8'), 'AzerMind');
  return { run, evaluate, num };
}

// Read the strip the addon drew, exactly like capture.ps1: 3 bits per cell,
// [C7 1A] [id] [len] [payload] [fletcher]. Returns { id, text } or null.
function decodeStrip(vm) {
  if (vm.evaluate('AzerMindStrip and AzerMindStrip.shown') !== 'true') return null;
  vm.run(`
    local parts = {}
    for _, t in ipairs(AzerMindStrip.textures) do
      if t.shown and t.color then
        local c, r = math.floor(t.x / 4), math.floor(-t.y / 4)
        local v = (t.color[1] >= 0.5 and 4 or 0) + (t.color[2] >= 0.5 and 2 or 0) + (t.color[3] >= 0.5 and 1 or 0)
        parts[#parts + 1] = (r * ${CELLS_PER_ROW} + c) .. ":" .. v
      end
    end
    RESULT = table.concat(parts, ",")`);
  const cells = [];
  for (const p of vm.evaluate('RESULT').split(',')) { const [i, v] = p.split(':').map(Number); cells[i] = v; }
  const bytes = [];
  let acc = 0, nbits = 0;
  for (let i = 0; i < cells.length; i++) {
    acc = (acc << 3) | (cells[i] || 0); nbits += 3;
    while (nbits >= 8) { bytes.push((acc >> (nbits - 8)) & 0xff); nbits -= 8; acc &= (1 << nbits) - 1; }
  }
  assert.equal(bytes[0], 0xc7); assert.equal(bytes[1], 0x1a);
  const id = bytes[2] * 256 + bytes[3];
  const len = bytes[4] * 256 + bytes[5];
  let s1 = 0, s2 = 0;
  for (let k = 2; k < 6 + len; k++) { s1 = (s1 + bytes[k]) % 255; s2 = (s2 + s1) % 255; }
  assert.equal(bytes[6 + len], s1, 'fletcher s1'); assert.equal(bytes[7 + len], s2, 'fletcher s2');
  return { id, text: Buffer.from(bytes.slice(6, 6 + len)).toString('utf8') };
}

function stripRecords(vm) {
  const frame = decodeStrip(vm);
  if (!frame) return [];
  return frame.text.split('\x1E').map(r => {
    const p = r.split('\x1F');
    const withCtx = p[4].split(';').includes('c'); // a "c" flag means field 7 is the game context
    const rec = { session: p[0], chat: p[1], id: Number(p[2]), cwd: p[3], flags: p[4], name: p[5], text: p.slice(withCtx ? 7 : 6).join('\x1F') };
    if (withCtx) rec.ctx = p[6];
    return rec;
  });
}

// Make the next LoadAddOn deliver this slot data (a Lua table literal body).
function nextSlot(vm, luaBody) {
  vm.run(`STUB.onLoadAddOn = function(name) AzerMind_SlotData = ${luaBody} end`);
}

function login(vm) {
  vm.run('STUB.FireEvent("ADDON_LOADED", "AzerMind")');
  vm.run('STUB.FireEvent("PLAYER_LOGIN")');
}

// Let the bridge answer the login hello: its slot carries a fresh clock, which is
// what makes the addon consider itself connected (Send is gated on that).
function connect(vm, metadata = "") {
  vm.run('STUB.RunTimers()'); // C_Timer.After(3, SayHello)
  nextSlot(vm, `{ now = time(), cwd = "", ${metadata} replies = {} }`);
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()'); // hello poll 5 s later
  assert.equal(vm.evaluate('AzerMind.IsConnected()'), 'true', 'connected after the hello slot');
}

test('message bubbles hide technical tooltips and clean WoW markup without changing stored text', () => {
  const vm = newVM();
  const markup = '|cnIQ2:|Hitem:5313|h[Totemic Clan Ring]|h|r';
  assert.equal(vm.evaluate(`AzerMind.PlainText(${JSON.stringify(markup)})`), '[Totemic Clan Ring]');
  assert.equal(vm.evaluate('AzerMind.PlainText("Sell Price: |A:coin-silver:14:14:2:0|a 50")'), 'Sell Price:  50');
  assert.equal(vm.evaluate('AzerMind.MessageText("user", "[Ring]\\n\\n--- Linked from the game ---\\n+3 Intellect")'), '[Ring]');
  assert.equal(vm.evaluate('AzerMind.MessageText("assistant", "Answer\\n\\nTL;DR:\\nAnswer again")'), 'Answer');
  assert.equal(vm.evaluate('AzerMind.MessageText("assistant", "TL;DR:\\nOnly answer")'), 'TL;DR:\nOnly answer');
});

test('each message keeps a visible copy button tied to its own text after rerendering', () => {
  const vm = newVM();
  login(vm);
  vm.run(`
    local chat = AzerMindDB.chats[1]
    chat.history = {{role="user",text="My question",id=1},{role="assistant",text="AI answer",id=1},{role="system",text="Status"}}
    AzerMind.Toggle(true)
    BUBBLES = {}
    for _, b in ipairs(AzerMindContent.children) do if b.copy then table.insert(BUBBLES,b) end end
  `);
  for (const [i, text] of [[1, 'My question'], [2, 'AI answer'], [3, 'Status']]) {
    vm.run(`local b=BUBBLES[${i}]; b.scripts.OnUpdate(b); b.copy.scripts.OnClick(b.copy)`);
    assert.equal(vm.evaluate(`BUBBLES[${i}].copy:IsShown()`), 'true');
    assert.equal(vm.evaluate('AzerMindCopyBox:GetText()'), text);
  }
  vm.run(`AzerMindDB.chats[1].history={{role="assistant",text="Another answer"}}; AzerMind.Render(); BUBBLES[1].copy.scripts.OnClick(BUBBLES[1].copy)`);
  assert.equal(vm.evaluate('AzerMindCopyBox:GetText()'), 'Another answer');
});

test('resend belongs only to user messages and delete removes exactly one history entry', () => {
  const vm = newVM();
  login(vm);
  vm.run(`
    local chat=AzerMindDB.chats[1]
    chat.history={{role="user",text="First",id=1},{role="assistant",text="Reply",id=1},{role="user",text="Second",id=2}}
    AzerMind.Toggle(true)
    BUBBLES={}
    for _,b in ipairs(AzerMindContent.children) do if b.copy then table.insert(BUBBLES,b) end end
    AzerMind.Send=function(text) SENT=text end
  `);
  for (const [i, visible] of [[1, 'true'], [2, 'false'], [3, 'true']]) {
    vm.run(`BUBBLES[${i}].scripts.OnUpdate(BUBBLES[${i}])`);
    assert.equal(vm.evaluate(`BUBBLES[${i}].resend:IsShown()`), visible);
    assert.equal(vm.evaluate(`BUBBLES[${i}].delete:IsShown()`), 'true');
  }
  vm.run('BUBBLES[1].resend.scripts.OnClick()');
  assert.equal(vm.evaluate('SENT'), 'First');
  vm.run('BUBBLES[2].delete.scripts.OnClick()');
  assert.equal(vm.num('#AzerMindDB.chats[1].history'), 2);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[1].text'), 'First');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[2].text'), 'Second');
  vm.run('BUBBLES[2].resend.scripts.OnClick()');
  assert.equal(vm.evaluate('SENT'), 'Second');
  vm.run('BUBBLES[1].delete.scripts.OnClick()');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[1].text'), 'Second');
});

test('model controls remain available for every provider', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  vm.run('AzerMind.SetAgent("codex"); AzerMind.CodexPrompt()');
  assert.equal(vm.evaluate('AzerMindGeneralSettings.model.shown'), 'true');
  vm.run('AzerMind.SetAgent("claude")');
  vm.run('AzerMind.CodexPrompt()');
  assert.equal(vm.evaluate('AzerMindGeneralSettings.model.shown'), 'true');
  assert.equal(vm.evaluate('AzerMindGeneralSettings.reasoning.shown'), 'false');
  vm.run('AzerMind.SetAgent("codex"); AzerMindDB.chats[1].codexModel = "test-model"; AzerMindDB.chats[1].codexReasoning = "high"; AzerMind.Send("test settings")');
  const rec = stripRecords(vm).find(r => r.text === 'test settings');
  assert.ok(rec.flags.includes('model=test-model'));
  assert.ok(rec.flags.includes('reasoning=high'));
});

test('addon loads, builds its UI and creates a first chat', () => {
  const vm = newVM();
  login(vm);
  assert.equal(vm.num('#AzerMindDB.chats'), 1);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].name'), 'Chat 1');
  assert.equal(vm.evaluate('AzerMindFrame ~= nil'), 'true');
  assert.equal(vm.evaluate('AzerMindMini ~= nil'), 'true');
  assert.equal(vm.num('#STUB.tickers'), 2);
  assert.equal(vm.evaluate('SlashCmdList.AZERMIND ~= nil'), 'true');
  assert.deepEqual([1, 2, 3, 4, 5].map(i => vm.evaluate('SLASH_AZERMIND' + i)), ['/azermind', '/wow-ai', '/wow-claude', '/ai', '/ask'], 'the old command name and the short forms are aliases');
  assert.equal(vm.evaluate('SlashCmdList.AZERMINDASK'), null, '/ai is an alias of the one command, not a handler of its own');
});

test('quest attachments include selected links and objectives without sending', () => {
  const vm = newVM(); login(vm);
  vm.run('QUESTS = {{id=479,title="Ambermill Investigations",level=20,zone="Silverpine",complete=false,objectives={{text="Pendants: 3/8",finished=false}}},{id=496,title="Elixir of Suffering",zone="Hillsbrad",complete=true,objectives={}}}; ATTACH = AzerMind.QuestSelectionText(QUESTS, {[479]=true})');
  const text = vm.evaluate('ATTACH');
  assert.ok(text.includes('|Hquest:479:20|h[Ambermill Investigations]|h'));
  assert.ok(text.includes('Pendants: 3/8'));
  assert.ok(!text.includes('Elixir of Suffering'));
  vm.run('AzerMindInput:SetText("Plan a route"); AzerMind.AppendQuestDraft(ATTACH, AzerMindDB.activeChat)');
  assert.ok(vm.evaluate('AzerMindInput:GetText()').startsWith('Plan a route\n\n'));
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'), null);
});

test('equipment attachment preserves the question and replaces the previous snapshot', () => {
  const vm = newVM();
  login(vm);
  vm.run('GetInventoryItemLink = function(unit, slot) if slot == 1 then return "|Hitem:123|h[Test Helm]|h" end end; GetInventoryItemID = function() return nil end; GetInventoryItemTexture = function() return nil end');
  vm.run('AzerMindInput:SetText("What should I upgrade?"); AzerMind.AttachEquipment()');
  const text = vm.evaluate('AzerMindInput:GetText()');
  assert.ok(text.startsWith('What should I upgrade?'));
  assert.ok(text.includes('Head: |cffd3b66f|Hitem:123|h[Test Helm]|h|r'));
  assert.ok(text.includes('Ring 1: empty'));
  assert.ok(text.includes('Tabard: empty'));
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'), null);
  vm.run('AzerMind.AttachEquipment()');
  const refreshed = vm.evaluate('AzerMindInput:GetText()');
  assert.equal(refreshed.match(/--- Equipped items ---/g).length, 1);
  assert.ok(refreshed.startsWith('What should I upgrade?'));
});

test('explicit entity references become native links without guessing IDs', () => {
  const vm = newVM();
  assert.ok(vm.evaluate('AzerMind.RichMessage("assistant", "Use [[item:5313:Totemic Clan Ring]]")').includes('|Hitem:5313|h[Totemic Clan Ring]|h'));
  assert.ok(vm.evaluate('AzerMind.RichMessage("assistant", "[[quest:849:Revenge of Gann]]")').includes('|Hquest:849:-1|h'));
  assert.ok(vm.evaluate('AzerMind.RichMessage("assistant", "[[spell:172:Corruption]]")').includes('|Hspell:172|h'));
  assert.equal(vm.evaluate('AzerMind.CopyMessage("assistant", "Use [[item:5313:Totemic Clan Ring]]")'), 'Use [Totemic Clan Ring]');
  assert.equal(vm.evaluate('AzerMind.RichMessage("assistant", "Totemic Clan Ring")'), 'Totemic Clan Ring');
  assert.ok(!vm.evaluate('AzerMind.RichMessage("assistant", "[[item:0:Invalid]]")').includes('|H'));
  assert.ok(!vm.evaluate('AzerMind.RichMessage("assistant", "[[script:12:Unsafe]]")').includes('|H'));
  assert.ok(vm.evaluate('AzerMind.RichMessage("user", "[Ring]\\n\\n--- Linked from the game ---\\n[Ring] item 5313 (Uncommon)")').includes('|Hitem:5313|h[Ring]|h'));
});

test('common equipped items use full links while retaining instance modifiers', () => {
  const vm = newVM();
  const payload = 'item:279391:0:0:0:0:0:0:0:23:0:0';
  const normalized = vm.evaluate(`AzerMind.NormalizeItemLink("|cnIQ1:|H${payload}|h[Taurajo Headband]|h|r")`);
  assert.equal(normalized, `|cffd3b66f|H${payload}|h[Taurajo Headband]|h|r`);
  assert.equal(vm.evaluate('AzerMind.NormalizeItemLink("plain text")'), 'plain text');
});

test('Shift+Enter inserts a newline without sending and Stop emits a targeted cancellation', () => {
  const vm = newVM();
  login(vm); connect(vm);
  vm.run('IsShiftKeyDown = function() return true end; AzerMindInput.Insert = function(self, text) self.inserted = text end; AzerMindInput:GetScript("OnEnterPressed")(AzerMindInput)');
  assert.equal(vm.evaluate('AzerMindInput.inserted'), '\n');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'), null);
  vm.run('AzerMind.Send("cancel this")');
  const target = vm.num('AzerMindDB.chats[1].pendingId');
  vm.run('AzerMind.CancelPending()');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'), null);
  assert.ok(stripRecords(vm).some(r => r.flags === `cancel=${target}`));
});

test('hello goes out on the strip after login', () => {
  const vm = newVM();
  login(vm);
  vm.run('STUB.RunTimers()'); // C_Timer.After(3, SayHello)
  const recs = stripRecords(vm);
  assert.equal(recs.length, 1);
  assert.equal(recs[0].flags, 'h;c', 'a hello always carries the game context');
  assert.equal(recs[0].text, '');
  assert.equal(recs[0].session, vm.evaluate('AzerMindDB.session'));
});

test('outbound records replace field separators inside user text', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  vm.run('AzerMind.Send("wire" .. string.char(30, 31) .. "safe")');
  const rec = stripRecords(vm).find(r => r.text === 'wire  safe');
  assert.ok(rec, 'the record keeps the full message as one wire field');
});

test('long item messages survive the pixel transport intact', () => {
  for (const size of [4362, 6100]) {
    const vm = newVM();
    login(vm);
    connect(vm);
    vm.run(`AzerMind.Send(string.rep("x", ${size}))`);
    const P = require('../bridge/protocol');
    const assemble = P.createStripAssembler();
    let record;
    const total = Number(decodeStrip(vm).text.split('\x1F')[4]);
    for (let i = 0; i <= total; i++) {
      const frame = decodeStrip(vm);
      record = assemble(frame.text);
      if (record) break;
      vm.run('STUB.now = STUB.now + 0.75; STUB.tickers[2]()');
    }
    const rec = P.jobsFromStrip(1, record).find(r => r.text === 'x'.repeat(size));
    assert.ok(rec, `complete ${size}-byte message is transmitted`);
  }
});

test('large questions rotate transport fragments while preserving one pending question', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  vm.run('AzerMind.Send(string.rep("x", 14000))');
  const first = decodeStrip(vm);
  assert.ok(first.text.startsWith('F1\x1F'));
  const pieces = new Map();
  const total = Number(first.text.split('\x1F')[4]);
  for (let i = 0; i < total + 1; i++) {
    vm.run('STUB.now = STUB.now + 0.75; STUB.tickers[2]()');
    const frame = decodeStrip(vm);
    const fields = frame.text.split('\x1F');
    assert.ok(Buffer.byteLength(frame.text) <= 2392);
    assert.ok(vm.num('AzerMindStrip:GetHeight()') <= 128);
    pieces.set(Number(fields[3]), Buffer.from(fields[5], 'hex'));
  }
  assert.equal(pieces.size, total);
  const record = Buffer.concat(Array.from({length: total}, (_, i) => pieces.get(i + 1))).toString('utf8');
  assert.equal(record.split('\x1F').at(-1), 'x'.repeat(14000));
  assert.equal(vm.num('#AzerMindDB.chats[1].history'), 1);
  vm.run('AzerMind.Send("small")');
  const frame = decodeStrip(vm);
  assert.ok(vm.num('AzerMindStrip:GetHeight()') < 128);
  assert.equal(vm.num('AzerMindStrip:GetHeight()'), Math.ceil(Math.ceil((Buffer.byteLength(frame.text) + 8) * 8 / 3) / 200) * 4);
});

test('the game context describes the character and rides on the hello, then only when it changes or is turned off', () => {
  const vm = newVM();
  login(vm);
  vm.run('STUB.RunTimers()');
  const hello = stripRecords(vm)[0];
  assert.deepEqual(hello.ctx.split('\n'), [
    'Game: World of Warcraft: Forever (client 1.60.1.69913, interface 16001)',
    'Character: Testchar, level 23 Night Elf Hunter (Alliance)',
    'Location: Duskwood - Darkshire',
  ]);
  // The bridge answers the hello: the context is now known to be on its side.
  nextSlot(vm, '{ now = time(), cwd = "", replies = {} }');
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()');
  assert.equal(vm.evaluate('AzerMind.IsConnected()'), 'true');
  vm.run('AzerMind.Send("hello world")');
  let rec = stripRecords(vm).find(r => r.text === 'hello world');
  assert.equal(rec.flags, '', 'unchanged context is not repeated');
  assert.equal(rec.ctx, undefined);
  assert.equal(vm.evaluate('AzerMindDB.outbox.ctx'), null);
  // Moving to another zone changes it, so the next message (from another chat,
  // the first one is still waiting) carries the new version.
  vm.run('STUB.zone = "Elwynn Forest"; STUB.subzone = ""; STUB.posX = 0.1; AzerMind.NewChat("Second"); AzerMind.Send("where am I")');
  rec = stripRecords(vm).find(r => r.text === 'where am I');
  assert.equal(rec.flags, 'c');
  assert.ok(rec.ctx.includes('Location: Elwynn Forest'), rec.ctx);
  assert.ok(!rec.ctx.includes('Position:'), 'basic mode excludes precise coordinates');
  assert.equal(Buffer.from(vm.evaluate('AzerMindDB.outbox.ctx'), 'hex').toString('utf8'), rec.ctx, 'the reload path carries it too');
  // Turning it off sends an empty context at once (a hello), so the bridge drops what it had.
  vm.run('SlashCmdList.AZERMIND("context off")');
  assert.equal(vm.evaluate('AzerMindDB.settings.context'), 'false');
  const off = stripRecords(vm).filter(r => r.flags === 'h;c');
  assert.equal(off.length, 1);
  assert.equal(off[0].ctx, '');
  assert.ok(vm.evaluate('AzerMindDB.chats[2].history[#AzerMindDB.chats[2].history].text').includes('Game context is OFF'));
  // Back on: another hello, with the context again.
  vm.run('SlashCmdList.AZERMIND("context on")');
  const on = stripRecords(vm).filter(r => r.flags === 'h;c');
  assert.ok(on.some(r => r.ctx.includes('Character: Testchar')));
  assert.ok(vm.evaluate('AzerMindDB.chats[2].history[#AzerMindDB.chats[2].history].text').includes('Game context is ON'));
});

test('a shift-clicked link lands in the focused input and is sent as its name plus tooltip', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  const link = '|cff1eff00|Hitem:2140:0:0:0:0:0:0:0:60:0:0|h[Fine Longsword]|h|r';
  vm.run(`STUB.tooltips["item:2140:0:0:0:0:0:0:0:60:0:0"] = { "Fine Longsword", { "Main Hand", "Sword" }, { "17 - 33 Damage", "Speed 2.70" }, "Requires Level 14" }`);
  // Without focus the link is left alone (shift-click keeps its normal meaning).
  vm.run(`AzerMindInput:SetText("is this good for me? "); AzerMindInput:ClearFocus(); ChatFrameUtil.InsertLink("${link}")`);
  assert.equal(vm.evaluate('AzerMindInput:GetText()'), 'is this good for me? ');
  // The client's own path (bags, spellbook, quest log all end here): ChatFrameUtil.InsertLink.
  vm.run(`AzerMindInput:SetFocus(); ChatFrameUtil.InsertLink("${link}")`);
  assert.equal(vm.evaluate('AzerMindInput:GetText()'), 'is this good for me? ' + link);
  // The old global name is not hooked as well, so nothing is inserted twice.
  vm.run(`ChatEdit_InsertLink("${link}")`);
  assert.equal(vm.evaluate('AzerMindInput:GetText()'), 'is this good for me? ' + link + link, 'the alias reaches the one hook exactly once');
  vm.run(`AzerMindInput:SetText("is this good for me? ${link}")`);
  vm.run('AzerMind.SendFromInput()');
  const expected = [
    'is this good for me? [Fine Longsword]',
    '',
    '--- Linked from the game ---',
    '[Fine Longsword] item 2140 (Uncommon)',
    '  Fine Longsword',
    '  Main Hand  Sword',
    '  17 - 33 Damage  Speed 2.70',
    '  Requires Level 14',
  ].join('\n');
  const rec = stripRecords(vm).find(r => r.text.startsWith('is this good'));
  assert.equal(rec.text, expected);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].text'), expected, 'the transcript shows what was sent');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].name'), 'Is this good for me');
  // Bare links (no colour) and repeated links: one block each, tooltip or not.
  vm.run('RESULT = (AzerMind.ExpandLinks("x |Hspell:1978|h[Serpent Sting]|h y |Hspell:1978|h[Serpent Sting]|h"))');
  assert.equal(vm.evaluate('RESULT'), 'x [Serpent Sting] y [Serpent Sting]\n\n--- Linked from the game ---\n[Serpent Sting] spell 1978');
  vm.run('RESULT, COUNT = AzerMind.ExpandLinks("plain text | with a pipe")');
  assert.equal(vm.evaluate('RESULT'), 'plain text | with a pipe');
  assert.equal(vm.evaluate('COUNT'), '0');
});

test('deleted-chat receipt hides the strip even when sound acknowledgements fail', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  vm.run('AzerMind.NewChat("Delete me")');
  const gone = vm.evaluate('AzerMindDB.chats[2].id');
  vm.run(`AzerMind.DeleteChat("${gone}")`);
  const rec = stripRecords(vm).find(r => r.flags === 'd');
  const token = vm.evaluate('AzerMindDB.session');
  nextSlot(vm, `{ now = time(), replies = { { chat = "${gone}", id = ${rec.id}, status = "ack", session = "${token}" } } }`);
  vm.run('STUB.now = STUB.now + 4; STUB.Tick()');
  assert.equal(vm.evaluate(`AzerMindDB.forget["${gone}"]`), null);
  assert.ok(!stripRecords(vm).find(r => r.flags === 'd'));
});

test('deleting a chat tells the bridge to forget it, and a restore never brings it back', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  vm.run('AzerMind.NewChat("Second")');
  assert.equal(vm.num('#AzerMindDB.chats'), 2);
  const gone = vm.evaluate('AzerMindDB.chats[2].id');
  vm.run(`AzerMind.DeleteChat("${gone}")`);
  assert.equal(vm.num('#AzerMindDB.chats'), 1);
  // A forget record for that chat is on the strip and remembered until acked.
  const rec = stripRecords(vm).find(r => r.flags === 'd');
  assert.ok(rec, 'forget record on the strip');
  assert.equal(rec.chat, gone);
  assert.equal(rec.text, '');
  assert.equal(vm.evaluate(`AzerMindDB.forget["${gone}"] ~= nil`), 'true');
  // A restore that still lists the chat is ignored for it.
  const token = vm.evaluate('AzerMindDB.session');
  nextSlot(vm, `{ now = time(), cwd = "", replies = {}, restore = { token = "${token}", chats = { { id = "${gone}", name = "Second", cwd = "", messages = { { role = "user", text = "old", id = 1, t = 1 } } } } } }`);
  vm.run('AzerMind.Connect(); STUB.now = STUB.now + 6; STUB.Tick()');
  assert.equal(vm.num('#AzerMindDB.chats'), 1, 'deleted chat not restored');
  // The bridge acks the forget record: it leaves the strip and the memory.
  nextSlot(vm, `{now=time(),replies={{session="${token}",chat="${gone}",id=${rec.id},status="ack"}}}`);
  vm.run('STUB.now=STUB.now+5; STUB.Tick()');
  assert.equal(vm.evaluate(`AzerMindDB.forget["${gone}"]`), null, 'forgotten once acked');
  assert.ok(!stripRecords(vm).find(r => r.flags === 'd'), 'forget record left the strip');
});

test('until the bridge answers, Connect replaces Send and a message stays in the box', () => {
  const vm = newVM();
  login(vm);
  vm.run('AzerMind.Toggle(true)');
  assert.equal(vm.evaluate('AzerMind.IsConnected()'), 'false');
  const texts = () => vm.evaluate('table.concat(STUB.texts, "|")');
  assert.ok(texts().includes('Not connected - start the bridge, then click Connect'));
  // Sending while disconnected puts the text back in the box and starts a connect attempt.
  vm.run('AzerMindInput:SetText("fix the bug"); AzerMind.SendFromInput()');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'), null, 'nothing sent');
  assert.equal(vm.evaluate('AzerMindInput:GetText()'), 'fix the bug', 'message kept in the box');
  const hello = stripRecords(vm);
  assert.equal(hello.length, 1);
  assert.equal(hello[0].flags, 'h;c', 'a hello went out instead');
  assert.ok(texts().includes('Connecting...'));
  assert.ok(texts().includes('your message goes out as soon as it answers'));
  // No answer within CONNECT_WAIT: the attempt is reported as failed, Connect is back.
  vm.run('STUB.now = STUB.now + 20; STUB.Tick()');
  assert.equal(vm.evaluate('AzerMind.IsConnected()'), 'false');
  assert.ok(texts().includes('No answer from the bridge'));
  assert.equal(vm.evaluate('AzerMindInput:GetText()'), 'fix the bug', 'message still in the box after a failed attempt');
  // Click Connect again; this time the bridge answers the hello poll. Nothing was
  // queued by that click, so the message waits for the user.
  vm.run('AzerMind.Connect()');
  nextSlot(vm, '{ now = time(), cwd = "C:\\\\proj", replies = {} }');
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()');
  assert.equal(vm.evaluate('AzerMind.IsConnected()'), 'true');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'), null, 'a plain Connect sends nothing by itself');
  vm.run('AzerMind.SendFromInput()');
  assert.ok(vm.num('AzerMindDB.chats[1].pendingId') >= 1, 'the kept message goes out once connected');
  assert.ok(stripRecords(vm).find(r => r.text === 'fix the bug'));
});

test('a message sent while disconnected goes out by itself once the bridge answers', () => {
  const vm = newVM();
  login(vm);
  vm.run('AzerMind.Toggle(true)');
  vm.run('AzerMindInput:SetText("fix the bug"); AzerMind.SendFromInput()');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'), null, 'nothing sent yet');
  // The bridge answers the hello poll: the queued message follows without a second click.
  nextSlot(vm, '{ now = time(), cwd = "C:\\\\proj", replies = {} }');
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()');
  assert.equal(vm.evaluate('AzerMind.IsConnected()'), 'true');
  assert.ok(vm.num('AzerMindDB.chats[1].pendingId') >= 1, 'queued message went out on connect');
  assert.ok(stripRecords(vm).find(r => r.text === 'fix the bug'));
  assert.equal(vm.evaluate('AzerMindInput:GetText()'), '', 'box cleared after the auto-send');
  // Only once: a later reconnect sends nothing.
  vm.run('AzerMind.Connect()');
  nextSlot(vm, '{ now = time(), cwd = "C:\\\\proj", replies = {} }');
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()');
  assert.equal(stripRecords(vm).filter(r => r.text === 'fix the bug').length, 1);
});

test('without the sound channel, the light stays green between idle slot polls', () => {
  // The stub has no ctl/valid.wav, so the login self-test disables the sound
  // channel: the addon is in "slot checks only" mode, like a client whose
  // PlaySoundFile reports every file as playable.
  const vm = newVM();
  login(vm);
  connect(vm);
  assert.equal(vm.evaluate('AzerMind.BridgeState()'), 'ok');
  // 90 s of silence used to mean "stale"; with no beats to hear that is normal.
  vm.run('STUB.now = STUB.now + 200; STUB.Tick()');
  assert.equal(vm.evaluate('AzerMind.BridgeState()'), 'ok', 'still green after 200 s');
  assert.equal(vm.evaluate('AzerMind.IsConnected()'), 'true');
  // 10 minutes in, the idle poll spends a slot; the bridge's clock in it keeps the light green.
  vm.run('STUB.loadCount = 0; STUB.onLoadAddOn = function(name) STUB.loadCount = STUB.loadCount + 1; AzerMind_SlotData = { now = time(), cwd = "", replies = {} } end');
  vm.run('STUB.now = STUB.now + 410; STUB.Tick()');
  assert.equal(vm.num('STUB.loadCount'), 1, 'one idle poll');
  assert.equal(vm.evaluate('AzerMind.BridgeState()'), 'ok', 'green again after the idle poll');
  // A bridge that really is gone still shows: no slot answers, and the light drops.
  vm.run('STUB.onLoadAddOn = function(name) AzerMind_SlotData = nil end');
  vm.run('STUB.now = STUB.now + 800; STUB.Tick()');
  assert.equal(vm.evaluate('AzerMind.BridgeState()'), 'stale');
  vm.run('STUB.now = STUB.now + 700; STUB.Tick()');
  assert.equal(vm.evaluate('AzerMind.BridgeState()'), 'down');
});

test('the Folder... menu item (right-click a chat) opens a prompt that sets the chat folder like /azermind cd', () => {
  const vm = newVM();
  login(vm);
  vm.run('AzerMind.FolderPrompt()');
  assert.equal(vm.evaluate('STUB.popup.which'), 'AZERMIND_FOLDER');
  assert.equal(vm.evaluate('STUB.popup.data.cwd'), '');
  // Accept the dialog the way the game would: an edit box holding the new path.
  vm.run(`
    local dialog = { editBox = { GetText = function() return "  ..\\\\realms " end } }
    StaticPopupDialogs.AZERMIND_FOLDER.OnAccept(dialog, STUB.popup.data)`);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].cwd'), '..\\realms');
  assert.ok(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].text').includes('relative to'));
  vm.run('AzerMind.FolderPrompt()');
  assert.equal(vm.evaluate('STUB.popup.data.cwd'), '..\\realms', 'prompt is prefilled with the current folder');
  // A full path gets no "relative to" note; empty goes back to the default.
  vm.run('AzerMind.SetFolder("C:\\\\other")');
  assert.ok(!vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].text').includes('relative to'));
  vm.run('AzerMind.SetFolder("")');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].cwd'), '');
});

test('a sent message is encoded on the strip with the chat folder, then a slot reply finishes it', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  vm.run('SlashCmdList.AZERMIND("cd realms")');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].cwd'), 'realms');
  vm.run('AzerMind.Send("hello world")');
  const chatId = vm.evaluate('AzerMindDB.chats[1].id');
  const id = vm.num('AzerMindDB.chats[1].pendingId');
  assert.ok(id >= 1);
  const rec = stripRecords(vm).find(r => r.text === 'hello world');
  assert.ok(rec, 'message record on the strip');
  assert.equal(rec.chat, chatId);
  assert.equal(rec.id, id);
  assert.equal(rec.cwd, 'realms');
  assert.equal(rec.flags, '');
  // The chat took its title from the first message.
  assert.equal(vm.evaluate('AzerMindDB.chats[1].name'), 'Hello world');

  nextSlot(vm, `{ now = time(), cwd = "C:\\\\proj", replies = { { chat = "${chatId}", id = ${id}, status = "done", text = "hi back", cwd = "x", session = "s" } } }`);
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()'); // first scheduled poll is 5 s after sending
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'), null);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].role'), 'assistant');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].text'), 'hi back');
  assert.ok(vm.evaluate('table.concat(STUB.prints, "\\n")').includes('hi back'), 'reply echoed to the game chat');
  assert.equal(vm.evaluate('AzerMindStrip.shown'), 'false', 'strip cleared once nothing is pending');

  // The bridge's default folder arrived with the slot and is what "/azermind cd" reports.
  vm.run('SlashCmdList.AZERMIND("cd")');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].cwd'), '');
  assert.ok(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].text').includes('C:\\proj'));
});

test('a denied reply shows Allow, and Allow resends with the rules as flags', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  vm.run('AzerMind.Send("search for it")');
  const chatId = vm.evaluate('AzerMindDB.chats[1].id');
  const id = vm.num('AzerMindDB.chats[1].pendingId');
  nextSlot(vm, `{ now = time(), cwd = "", replies = { { chat = "${chatId}", id = ${id}, status = "done", text = "need permission", denied = { "WebSearch", "Bash(cargo:*)" } } } }`);
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].denied[2]'), 'Bash(cargo:*)');
  vm.run(`AzerMind.Allow("${chatId}", { "WebSearch", "Bash(cargo:*)" })`);
  const rec = stripRecords(vm).find(r => r.flags.includes('allow='));
  assert.ok(rec, 'allow record on the strip');
  assert.equal(rec.flags, 'allow=WebSearch,Bash(cargo:*)');
  assert.equal(rec.id, id + 1);
});

test('a chat can pick its agent: the strip says so, replies are labelled by their writer, unknown names are refused', () => {
  const vm = newVM();
  login(vm);
  // The hello slot carries the bridge's default agent and the ones it knows.
  vm.run('STUB.RunTimers()');
  const slot = replies => `{ now = time(), cwd = "", agent = "claude", agents = { "claude", "codex", "grok" }, replies = { ${replies || ''} } }`;
  nextSlot(vm, slot());
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()');
  assert.equal(vm.evaluate('AzerMind.IsConnected()'), 'true');
  const texts = () => vm.evaluate('table.concat(STUB.texts, "|")');
  assert.ok(texts().includes('agent: Claude (bridge default)'), 'the cwd line names the bridge default');
  // Without an agent of its own the chat sends no agent flag, and the reply is labelled Claude.
  vm.run('AzerMind.Send("hello")');
  const chatId = vm.evaluate('AzerMindDB.chats[1].id');
  let rec = stripRecords(vm).find(r => r.text === 'hello');
  assert.equal(rec.flags, '');
  assert.equal(vm.evaluate('AzerMindDB.outbox.agent'), null);
  const id = vm.num('AzerMindDB.chats[1].pendingId');
  nextSlot(vm, slot(`{ chat = "${chatId}", id = ${id}, status = "done", text = "hi", agent = "claude" }`));
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].role'), 'assistant');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].agent'), 'claude');
  assert.ok(vm.evaluate('table.concat(STUB.prints, "\\n")').includes('[Claude · '), 'the game chat echo names the agent');
  // Switch this chat to Codex: the next message carries agent=codex, on both transports.
  vm.run('SlashCmdList.AZERMIND("agent Codex")');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].agent'), 'codex');
  assert.ok(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].text').includes('agent set to Codex'));
  vm.run('AzerMind.Send("now with codex")');
  rec = stripRecords(vm).find(r => r.text === 'now with codex');
  assert.equal(rec.flags, 'agent=codex');
  assert.equal(vm.evaluate('AzerMindDB.outbox.agent'), 'codex');
  assert.ok(texts().includes('agent: Codex   mode: pixel'));
  const id2 = vm.num('AzerMindDB.chats[1].pendingId');
  nextSlot(vm, slot(`{ chat = "${chatId}", id = ${id2}, status = "done", text = "codex here", agent = "codex" }`));
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].agent'), 'codex');
  assert.ok(vm.evaluate('table.concat(STUB.prints, "\\n")').includes('[Codex · '));
  // Resend keeps the agent flag.
  vm.run('AzerMind.Send("again")');
  vm.run('AzerMind.Resend()');
  assert.equal(stripRecords(vm).find(r => r.text === 'again').flags, 'agent=codex');
  vm.run('SlashCmdList.AZERMIND("cancel")');
  // A name the bridge did not list is refused; "default" goes back to the bridge's.
  vm.run('SlashCmdList.AZERMIND("agent gemini")');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].agent'), 'codex');
  assert.ok(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].text').includes('Unknown agent "gemini"'));
  vm.run('SlashCmdList.AZERMIND("agent default")');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].agent'), '');
  assert.ok(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].text').includes('agent reset to the bridge\'s default: Claude'));
  // The Agent... menu item opens a prompt prefilled with the chat's agent.
  vm.run('AzerMind.SetAgent("grok"); AzerMind.AgentPrompt()');
  assert.equal(vm.evaluate('STUB.popup.which'), 'AZERMIND_AGENT');
  assert.equal(vm.evaluate('STUB.popup.data.agent'), 'grok');
  vm.run(`
    local dialog = { editBox = { GetText = function() return " codex " end } }
    StaticPopupDialogs.AZERMIND_AGENT.OnAccept(dialog, STUB.popup.data)`);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].agent'), 'codex');
  // A new chat inherits the agent, like the folder.
  vm.run('AzerMind.NewChat("Second")');
  assert.equal(vm.evaluate('AzerMindDB.chats[2].agent'), 'codex');
});

test('replies saved under the old "claude" role are read as assistant replies from Claude', () => {
  const vm = newVM();
  vm.run('AzerMindDB = { chats = { { id = "c1", name = "Old", cwd = "", history = { { role = "user", text = "q", id = 1, t = 1 }, { role = "claude", text = "a", id = 1, t = 2 } }, unread = 0, created = 1 } }, activeChat = "c1", settings = {} }');
  login(vm);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[2].role'), 'assistant');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[2].agent'), 'claude');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].agent'), '');
  // Before the bridge has said which agent it runs, the label falls back to "AI".
  vm.run('AzerMind.Toggle(true)');
  assert.ok(vm.evaluate('table.concat(STUB.texts, "|")').includes('|Claude|'), 'the old reply is labelled Claude');
});

test('free text that starts with a command word is sent as a message; exact commands still run', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  const sent = text => !!stripRecords(vm).find(r => r.text === text);
  const last = () => vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].text');
  // "delete the unused imports" is a message, not /azermind delete; "cancel" alone is the command.
  vm.run('SlashCmdList.AZERMIND("delete the unused imports")');
  assert.equal(vm.num('#AzerMindDB.chats'), 1, 'no chat deleted');
  assert.ok(sent('delete the unused imports'));
  vm.run('SlashCmdList.AZERMIND("cancel")');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'), null, 'cancel ran as a command');
  // "help me with this macro" is a message; "help" alone prints the help.
  vm.run('SlashCmdList.AZERMIND("help me with this macro")');
  assert.ok(sent('help me with this macro'));
  vm.run('SlashCmdList.AZERMIND("cancel")');
  vm.run('SlashCmdList.AZERMIND("help")');
  assert.ok(last().includes('/azermind cd'));
  // One-word arguments keep their command; more words make it a message.
  vm.run('SlashCmdList.AZERMIND("agent codex")');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].agent'), 'codex');
  vm.run('SlashCmdList.AZERMIND("agent smith says hi")');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].agent'), 'codex');
  assert.ok(sent('agent smith says hi'));
  vm.run('SlashCmdList.AZERMIND("cancel")');
  // Enumerated arguments: "context off" is the command, "context matters here" a message.
  vm.run('SlashCmdList.AZERMIND("context off")');
  assert.equal(vm.evaluate('AzerMindDB.settings.context'), 'false');
  vm.run('SlashCmdList.AZERMIND("context matters here")');
  assert.ok(sent('context matters here'));
  vm.run('SlashCmdList.AZERMIND("cancel")');
  // "reset the counter" and "clear the cache" are messages; the transcript survives.
  vm.run('SlashCmdList.AZERMIND("clear the cache")');
  assert.ok(sent('clear the cache'));
  assert.ok(vm.num('#AzerMindDB.chats[1].history') > 1, 'clear did not run');
  vm.run('SlashCmdList.AZERMIND("cancel")');
  vm.run('SlashCmdList.AZERMIND("reset the counter")');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].resetNext'), null);
  assert.ok(sent('reset the counter'));
  vm.run('SlashCmdList.AZERMIND("cancel")');
  // A chat can still be picked by number or name; "chat with me about it" is a message.
  vm.run('SlashCmdList.AZERMIND("new Realms")');
  vm.run('SlashCmdList.AZERMIND("chat 1")');
  assert.equal(vm.evaluate('AzerMindDB.activeChat'), vm.evaluate('AzerMindDB.chats[1].id'));
  vm.run('SlashCmdList.AZERMIND("chat realms")');
  assert.equal(vm.evaluate('AzerMindDB.activeChat'), vm.evaluate('AzerMindDB.chats[2].id'));
  vm.run('SlashCmdList.AZERMIND("chat with me about it")');
  assert.ok(sent('chat with me about it'));
  // /ai alone toggles the window.
  vm.run('AzerMind.Toggle(false); SlashCmdList.AZERMIND("")');
  assert.equal(vm.evaluate('AzerMindFrame.shown'), 'true');
});

test('/azermind reset marks the next message as a new session', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  vm.run('SlashCmdList.AZERMIND("reset")');
  vm.run('AzerMind.Send("start over")');
  const rec = stripRecords(vm).find(r => r.text === 'start over');
  assert.equal(rec.flags, 'n');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].resetNext'), null);
});

test('game chat echo: the summary by default, the first lines without one, the whole reply with "echo full"', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  assert.equal(vm.evaluate('AzerMindDB.settings.echo'), 'summary', 'summary echo is the default');
  const chatId = vm.evaluate('AzerMindDB.chats[1].id');
  const prints = () => vm.evaluate('table.concat(STUB.prints, "\\n")');
  const reply = (text, summary) => {
    vm.run('STUB.prints = {}');
    vm.run('AzerMind.Send("do it")');
    const id = vm.num('AzerMindDB.chats[1].pendingId');
    const sum = summary === undefined ? '' : `, summary = "${summary}"`;
    nextSlot(vm, `{ now = time(), cwd = "", replies = { { chat = "${chatId}", id = ${id}, status = "done", text = "${text}", agent = "claude"${sum} } } }`);
    vm.run('STUB.now = STUB.now + 6; STUB.Tick()');
    assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'), null);
  };

  // With a summary only the summary is printed; the window keeps the whole reply.
  reply('Long line one\\nLong line two\\nLong line three\\n\\nTL;DR: Renamed foo.\\nTests pass.', 'Renamed foo.\\nTests pass.');
  let out = prints();
  assert.ok(out.includes('[Claude · ') && out.includes('Renamed foo.') && out.includes('Tests pass.'), 'summary lines printed: ' + out);
  assert.ok(!out.includes('Long line one'), 'the body stays out of the game chat');
  assert.ok(out.includes('[open]'), 'the open link is there');
  assert.ok(vm.evaluate('AzerMindDB.chats[1].history[#AzerMindDB.chats[1].history].text').includes('Long line three'), 'the window has the full reply');

  // Without a summary: the first two lines, then a hint that there is more.
  reply('Line one\\nLine two\\nLine three\\nLine four');
  out = prints();
  assert.ok(out.includes('Line one') && out.includes('Line two'), 'first two lines: ' + out);
  assert.ok(!out.includes('Line three'), 'third line held back');
  assert.ok(out.includes('click [open]'), 'hint to open the window');

  // A short reply without a summary needs no hint.
  reply('Just this');
  out = prints();
  assert.ok(out.includes('Just this') && !out.includes('click [open] to read'), out);

  // "echo full" prints everything, as before.
  vm.run('SlashCmdList.AZERMIND("echo full")');
  assert.equal(vm.evaluate('AzerMindDB.settings.echo'), 'full');
  reply('Line one\\nLine two\\nLine three\\n\\nTL;DR: Short.', 'Short.');
  out = prints();
  assert.ok(out.includes('Line one') && out.includes('Line three') && out.includes('TL;DR: Short.'), out);
  vm.run('SlashCmdList.AZERMIND("echo summary")');
  assert.equal(vm.evaluate('AzerMindDB.settings.echo'), 'summary');
  vm.run('SlashCmdList.AZERMIND("echo bogus")');
  assert.equal(vm.evaluate('AzerMindDB.settings.echo'), 'summary', 'an unknown mode is ignored');

  // An install that still had the old default saved moves to summary once; a mode picked on purpose stays.
  const vm2 = newVM();
  vm2.run('AzerMindDB = { settings = { echo = "full" } }');
  login(vm2);
  assert.equal(vm2.evaluate('AzerMindDB.settings.echo'), 'summary');
  const vm3 = newVM();
  vm3.run('AzerMindDB = { settings = { echo = "short" } }');
  login(vm3);
  assert.equal(vm3.evaluate('AzerMindDB.settings.echo'), 'short');
  const vm4 = newVM();
  vm4.run('AzerMindDB = { settings = { echo = "full", echoV2 = true } }');
  login(vm4);
  assert.equal(vm4.evaluate('AzerMindDB.settings.echo'), 'full');
});

test('a restore bundle addressed to this session adds the missing chats once', () => {
  const vm = newVM();
  login(vm);
  connect(vm);
  vm.run('AzerMind.Send("hi")');
  const chatId = vm.evaluate('AzerMindDB.chats[1].id');
  const id = vm.num('AzerMindDB.chats[1].pendingId');
  const token = vm.evaluate('AzerMindDB.session');
  const bundle = `restore = { token = "${token}", chats = { { id = "old1", name = "Old work", cwd = "C:\\\\old", messages = { { role = "user", id = 1, t = 1, text = "q" }, { role = "claude", id = 1, t = 2, text = "a" } } } } }`;
  nextSlot(vm, `{ now = time(), cwd = "", replies = { { chat = "${chatId}", id = ${id}, status = "done", text = "ok" } }, ${bundle} }`);
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()');
  assert.equal(vm.num('#AzerMindDB.chats'), 2);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].id'), 'old1');
  assert.equal(vm.num('#AzerMindDB.chats[1].history'), 2);
  // An older bridge's transcript says "claude"; it is read as an assistant reply from Claude.
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[2].role'), 'assistant');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].history[2].agent'), 'claude');
  assert.equal(vm.evaluate('AzerMindDB.restored'), 'true');
  // A second bundle with the same token is ignored.
  vm.run('AzerMind.Send("again")');
  const id2 = vm.num('AzerMindDB.chats[2].pendingId');
  nextSlot(vm, `{ now = time(), cwd = "", replies = { { chat = "${chatId}", id = ${id2}, status = "done", text = "ok" } }, ${bundle.replace('old1', 'old2')} }`);
  vm.run('STUB.now = STUB.now + 6; STUB.Tick()');
  assert.equal(vm.num('#AzerMindDB.chats'), 2);
});

test('chat management commands: new, chat, rename, delete, clear, copy', () => {
  const vm = newVM();
  login(vm);
  vm.run('SlashCmdList.AZERMIND("new Realms")');
  assert.equal(vm.num('#AzerMindDB.chats'), 2);
  assert.equal(vm.evaluate('AzerMindDB.chats[2].name'), 'Realms');
  assert.equal(vm.evaluate('AzerMindDB.activeChat'), vm.evaluate('AzerMindDB.chats[2].id'));
  vm.run('SlashCmdList.AZERMIND("chat 1")');
  assert.equal(vm.evaluate('AzerMindDB.activeChat'), vm.evaluate('AzerMindDB.chats[1].id'));
  vm.run('SlashCmdList.AZERMIND("rename Stuff")');
  assert.equal(vm.evaluate('AzerMindDB.chats[1].name'), 'Stuff');
  vm.run('SlashCmdList.AZERMIND("help")');
  assert.ok(vm.evaluate('AzerMindDB.chats[1].history[1].text').includes('/azermind cd'));
  vm.run('SlashCmdList.AZERMIND("clear")');
  assert.equal(vm.num('#AzerMindDB.chats[1].history'), 0);
  vm.run('SlashCmdList.AZERMIND("delete")');
  assert.equal(vm.num('#AzerMindDB.chats'), 1);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].name'), 'Realms');
  // The copy box builds with a proper backdrop (the stub fails on SetBackdrop(nil)).
  vm.run('AzerMind.ShowCopy("some reply")');
  assert.equal(vm.evaluate('AzerMindCopy.shown'), 'true');
  assert.equal(vm.evaluate('AzerMindCopyBox.text'), 'some reply');
});

test('chat rows: right-click opens a menu that renames or sets the folder of that chat, the trash can asks before deleting', () => {
  const vm = newVM();
  login(vm);
  vm.run('SlashCmdList.AZERMIND("new Realms")');
  const first = vm.evaluate('AzerMindDB.chats[1].id');
  const second = vm.evaluate('AzerMindDB.chats[2].id');
  assert.equal(vm.evaluate('AzerMindDB.activeChat'), second);
  // The menu opens for the row's chat, not the active one, and toggles closed on a second open.
  vm.run(`AzerMind.ShowChatMenu("${first}", AzerMindFrame)`);
  assert.equal(vm.evaluate('AzerMindChatMenu.shown'), 'true');
  assert.equal(vm.evaluate('AzerMindChatMenu.chatId'), first);
  assert.equal(vm.evaluate('AzerMindChatMenu.title.text'), 'Chat 1');
  vm.run(`AzerMind.ShowChatMenu("${first}", AzerMindFrame)`);
  assert.equal(vm.evaluate('AzerMindChatMenu.shown'), 'false');
  // Rename and Folder prompts target the chat they were opened for.
  vm.run(`AzerMind.RenamePrompt("${first}")`);
  assert.equal(vm.evaluate('STUB.popup.which'), 'AZERMIND_RENAME');
  assert.equal(vm.evaluate('STUB.popup.data.id'), first);
  vm.run(`
    local dialog = { editBox = { GetText = function() return "Old stuff" end } }
    StaticPopupDialogs.AZERMIND_RENAME.OnAccept(dialog, STUB.popup.data)`);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].name'), 'Old stuff');
  assert.equal(vm.evaluate('AzerMindDB.chats[2].name'), 'Realms');
  vm.run(`AzerMind.FolderPrompt("${first}")`);
  assert.equal(vm.evaluate('STUB.popup.which'), 'AZERMIND_FOLDER');
  assert.equal(vm.evaluate('STUB.popup.data.id'), first);
  // The X asks first: nothing happens until OK, then only that chat goes and the active one stays.
  vm.run(`AzerMind.ConfirmDelete("${first}")`);
  assert.equal(vm.evaluate('STUB.popup.which'), 'AZERMIND_DELETE');
  assert.equal(vm.num('#AzerMindDB.chats'), 2);
  vm.run('StaticPopupDialogs.AZERMIND_DELETE.OnAccept({}, STUB.popup.data)');
  assert.equal(vm.num('#AzerMindDB.chats'), 1);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].id'), second);
  assert.equal(vm.evaluate('AzerMindDB.activeChat'), second);
  // Deleting the last chat clears it instead of removing it.
  vm.run(`AzerMind.ConfirmDelete("${second}")`);
  vm.run('StaticPopupDialogs.AZERMIND_DELETE.OnAccept({}, STUB.popup.data)');
  assert.equal(vm.num('#AzerMindDB.chats'), 1);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].name'), 'Chat 1');
});

test('minimize collapses to the mini bar and back; the mini bar X hides everything', () => {
  const vm = newVM();
  login(vm);
  vm.run('AzerMind.Toggle(true)');
  assert.equal(vm.evaluate('AzerMindFrame.shown'), 'true');
  vm.run('AzerMind.Minimize(true)');
  assert.equal(vm.evaluate('AzerMindFrame.shown'), 'false');
  assert.equal(vm.evaluate('AzerMindMini.shown'), 'true');
  assert.equal(vm.evaluate('AzerMindDB.settings.minimized'), 'true');
  vm.run('AzerMind.Minimize(false)');
  assert.equal(vm.evaluate('AzerMindFrame.shown'), 'true');
  assert.equal(vm.evaluate('AzerMindMini.shown'), 'false');
  vm.run('AzerMind.Toggle(false)');
  assert.equal(vm.evaluate('AzerMindFrame.shown'), 'false');
  assert.equal(vm.evaluate('AzerMindMini.shown'), 'false');
  assert.equal(vm.evaluate('AzerMindDB.settings.shown'), 'false');
});

test('reload mode writes the outbox for the bridge instead of drawing the strip', () => {
  const vm = newVM();
  login(vm);
  vm.run('SlashCmdList.AZERMIND("mode reload")');
  vm.run('SlashCmdList.AZERMIND("reset")');
  vm.run('AzerMind.Send("via reload", { "WebSearch", "Bash(git:*)" })');
  assert.equal(vm.evaluate('STUB.reloaded'), 'true');
  assert.equal(vm.evaluate('AzerMindDB.outbox.newSession'), 'true');
  assert.equal(vm.evaluate('AzerMindDB.outbox.text'), Buffer.from('via reload').toString('hex'));
  assert.equal(Buffer.from(vm.evaluate('AzerMindDB.outbox.allow'), 'hex').toString('utf8'), 'WebSearch\x1fBash(git:*)');
  assert.equal(decodeStrip(vm), null);
});


test('character context defaults to basic, full includes equipment and preview does not send', () => {
  const vm = newVM(); login(vm); connect(vm);
  assert.equal(vm.evaluate('AzerMindDB.settings.contextMode'), 'basic');
  const basic = vm.evaluate('AzerMind.GameContext()');
  assert.ok(!basic.includes('Money:'));
  vm.run('STUB.posX = 0.99');
  assert.equal(vm.evaluate('AzerMind.GameContext()'), basic);
  vm.run('AzerMind.SetContextMode("full")');
  const full = vm.evaluate('AzerMind.GameContext()');
  for (const field of ['Position:', 'Money:', 'Talents:', 'Professions:', 'Learned spells:', 'Quest log:', 'Equipped items', 'Individual talent ranks: not collected']) assert.ok(full.includes(field), field);
  assert.ok(Buffer.byteLength(full) <= 14000);
  const before = vm.num('AzerMindDB.lastSeq');
  vm.run('for _, child in ipairs(AzerMindFrame.children) do if child.text == "View context" then child.scripts.OnClick() end end');
  assert.equal(vm.num('AzerMindDB.lastSeq'), before);
  vm.run('AzerMind.SetContextMode("basic"); AzerMind.Send("hello basic")');
  const rec = stripRecords(vm).find(r => r.text === 'hello basic');
  assert.ok(rec.ctx && !rec.ctx.includes('Money:'));
});


test('completed quest context distinguishes delivered quests from the active quest log', () => {
  const vm = newVM(); login(vm);
  vm.run(`
    ACCOUNT_HISTORY_CALLS = 0
    C_QuestLog = {
      GetNumQuestLogEntries=function() return 2 end,
      GetInfo=function(i) return {questID=100+i,isHeader=false} end,
      IsComplete=function(id) return id==101 end,
      GetAllCompletedQuestIDs=function() return {99,44,2} end,
      IsQuestFlaggedCompletedOnAccount=function() ACCOUNT_HISTORY_CALLS=ACCOUNT_HISTORY_CALLS+1; return true end
    }
  `);
  const context = vm.evaluate('AzerMind.GameContext({quests=true})');
  assert.match(context, /^Quest log \(id, \* = ready to turn in\): 101\*,102\n/);
  assert.ok(context.includes('Completed quest IDs (delivered; 3/3 shown): 2,44,99'));
  assert.equal(vm.num('ACCOUNT_HISTORY_CALLS'), 0);
  assert.equal(vm.evaluate('(function() for _, field in ipairs(AzerMind.ContextCategories) do if field[1]=="quests" then return field[2] end end end)()'), 'Active and completed quest IDs');
});

test('completed quest context reports unavailable APIs and errors without claiming an empty history', () => {
  const vm = newVM(); login(vm);
  for (const api of ['nil', '{}', '{GetAllCompletedQuestIDs=function() error("not ready") end}', '{GetAllCompletedQuestIDs=function() return nil end}', '{GetAllCompletedQuestIDs=function() return "123" end}']) {
    vm.run(`C_QuestLog=${api}`);
    const context = vm.evaluate('AzerMind.GameContext({quests=true})');
    assert.ok(context.includes('Completed quest IDs (delivered; unavailable): client API unavailable or failed.'), api);
    assert.ok(!context.includes('0/0 shown'), api);
  }
});

test('completed quest context labels an empty API result as no reported IDs', () => {
  const vm = newVM(); login(vm);
  vm.run('C_QuestLog={GetAllCompletedQuestIDs=function() return {} end}');
  const context = vm.evaluate('AzerMind.GameContext({quests=true})');
  assert.ok(context.includes('Completed quest IDs (delivered; 0/0 shown): none reported by client; absence does not prove a quest is unfinished.'));
  assert.ok(!context.includes('unavailable):'));
});

test('completed quest context sorts and deduplicates positive integer IDs and rejects invalid entries', () => {
  const vm = newVM(); login(vm);
  vm.run(`C_QuestLog={GetAllCompletedQuestIDs=function() return {[1]=99,[3]=2,[4]=44.0,[5]=99,[6]=0,[7]=-1,[8]=1.5,[9]="77",[10]=math.huge,[11]=-math.huge,[12]=0/0,[13]=false,[14]={}} end}`);
  const context = vm.evaluate('AzerMind.GameContext({quests=true})');
  assert.ok(context.includes('Completed quest IDs (delivered; partial; 3/3 shown; invalid entries omitted): 2,44,99'));
});

test('completed quest context bounds large histories with explicit shown and total counts', () => {
  const vm = newVM(); login(vm);
  vm.run(`
    C_QuestLog={GetAllCompletedQuestIDs=function()
      local ids={}; for i=3000,1,-1 do ids[#ids+1]=100000+i end; return ids
    end}
  `);
  const context = vm.evaluate('AzerMind.GameContext({quests=true})');
  const history = context.split('\n').find(line => line.startsWith('Completed quest IDs'));
  assert.ok(history, 'completed history is present');
  assert.ok(Buffer.byteLength(history) <= 6000);
  const match = history.match(/^Completed quest IDs \(delivered; partial; (\d+)\/3000 shown; size limit\): ([\d,]+)$/);
  assert.ok(match, history);
  const shown = Number(match[1]);
  assert.ok(shown > 0 && shown < 3000);
  assert.deepEqual(match[2].split(',').map(Number), Array.from({length:shown}, (_, i) => 100001+i));
  assert.ok(Buffer.byteLength(context) <= 14000);
});

test('completed quest context keeps both quest sections ahead of verbose spells and skills', () => {
  const vm = newVM(); login(vm);
  vm.run(`
    C_QuestLog={GetNumQuestLogEntries=function() return 1 end,GetInfo=function() return {questID=101} end,
      IsComplete=function() return true end,GetAllCompletedQuestIDs=function() return {99} end}
    C_SkillInfo={GetNumSkillLines=function() return 1 end,
      GetSkillLineInfo=function() return {name=string.rep("Long skill name ",1100),rank=1,maxRank=300,skillID=43} end}
    GetNumSpellTabs=function() return 1 end
    GetSpellTabInfo=function() return "Mage",nil,0,100 end
    GetSpellBookItemInfo=function(i) return "SPELL",1000+i end
    GetSpellBookItemName=function(i) return "Long learned spell "..i,"Rank 1" end
  `);
  const context = vm.evaluate('AzerMind.GameContext("full")');
  assert.ok(context.includes('Quest log (id, * = ready to turn in): 101*'));
  assert.ok(context.includes('Completed quest IDs (delivered; 1/1 shown): 99'));
  assert.ok(context.includes('[Partial context: trailing sections omitted at size limit.]'));
  assert.ok(Buffer.byteLength(context) <= 14000);
  vm.run('C_SkillInfo=nil');
  const withSpells = vm.evaluate('AzerMind.GameContext("full")');
  assert.ok(withSpells.indexOf('Completed quest IDs') < withSpells.indexOf('Learned player spells'));
});

test('completed quest context respects disabled quest sharing and disabled character sharing', () => {
  const vm = newVM(); login(vm); connect(vm);
  vm.run('HISTORY_CALLS=0; C_QuestLog={GetAllCompletedQuestIDs=function() HISTORY_CALLS=HISTORY_CALLS+1; return {99} end}');
  const context = vm.evaluate('AzerMind.GameContext({game=true,quests=false})');
  assert.ok(!context.includes('Completed quest IDs') && !context.includes('Quest log'));
  assert.equal(vm.num('HISTORY_CALLS'), 0);
  vm.run('AzerMind.SaveContextSettings({quests=true}, false); AzerMind.Send("no quest sharing")');
  const rec = stripRecords(vm).find(r => r.text === 'no quest sharing');
  assert.ok(rec.ctx === '' || rec.ctx === undefined);
  assert.equal(vm.num('HISTORY_CALLS'), 0);
});

test('completed quest context refreshes newly delivered IDs on the next context', () => {
  const vm = newVM(); login(vm);
  vm.run('COMPLETED_IDS={99}; C_QuestLog={GetAllCompletedQuestIDs=function() return COMPLETED_IDS end}');
  assert.ok(vm.evaluate('AzerMind.GameContext({quests=true})').includes('Completed quest IDs (delivered; 1/1 shown): 99'));
  vm.run('COMPLETED_IDS[2]=101');
  assert.ok(vm.evaluate('AzerMind.GameContext({quests=true})').includes('Completed quest IDs (delivered; 2/2 shown): 99,101'));
});

test('full character context reaches bridge intact beside the question', () => {
  const vm = newVM(); login(vm); connect(vm);
  vm.run('C_QuestLog={GetAllCompletedQuestIDs=function() local ids={}; for i=1,500 do ids[i]=100000+i end; return ids end}');
  vm.run('AzerMind.SetContextMode("full"); AzerMind.Send("compare my character")');
  const expected = vm.evaluate('AzerMind.GameContext()');
  assert.ok(expected.includes('Completed quest IDs (delivered; 500/500 shown): 100001,'));
  assert.ok(Buffer.byteLength(expected) > 2000);
  const P = require('../bridge/protocol');
  const assemble = P.createStripAssembler();
  let record;
  const first = decodeStrip(vm);
  const count = first.text.startsWith('F1\x1F') ? Number(first.text.split('\x1F')[4]) : 1;
  for (let i=0; i<=count; i++) {
    record = assemble(decodeStrip(vm).text);
    if (record) break;
    vm.run('STUB.now = STUB.now + 0.75; STUB.tickers[2]()');
  }
  const job = P.jobsFromStrip(first.id, record).find(j => j.text === 'compare my character');
  assert.equal(job.ctx, expected);
});


test('custom sharing selects only requested fields and saves or cancels config changes', () => {
  const vm = newVM(); login(vm); connect(vm);
  vm.run('AzerMind.SaveContextSettings({game=true, progress=true}, true)');
  const ctx = vm.evaluate('AzerMind.GameContext()');
  assert.ok(ctx.includes('Game:') && ctx.includes('Money:'));
  for (const field of ['Character:', 'Location:', 'Position:', 'Professions:', 'Talents:', 'Equipped items', 'Learned spells', 'Quest log']) assert.ok(!ctx.includes(field), field);
  vm.run('AzerMind.ShowContextSettings(); AzerMindContextSettings.options.spells=true');
  assert.equal(vm.evaluate('AzerMindDB.settings.contextFields.spells'), 'false');
  const seq = vm.num('AzerMindDB.lastSeq');
  vm.run('for _, b in ipairs(AzerMindContextSettings.children) do if b.text=="Preview" then b.scripts.OnClick() end end');
  assert.equal(vm.num('AzerMindDB.lastSeq'), seq);
  assert.ok(vm.num('AzerMindCopy:GetFrameLevel()') > vm.num('AzerMindContextSettings:GetFrameLevel()'));
  vm.run('for _, b in ipairs(AzerMindContextSettings.children) do if b.text=="Cancel" then b.scripts.OnClick() end end');
  assert.equal(vm.evaluate('AzerMindDB.settings.contextFields.spells'), 'false');
  vm.run('AzerMind.ShowContextSettings(); AzerMindContextSettings.options.spells=true; for _, b in ipairs(AzerMindContextSettings.children) do if b.text=="Save" then b.scripts.OnClick() end end');
  assert.ok(vm.evaluate('AzerMind.GameContext()').includes('Learned spells:'));
  vm.run('AzerMind.SaveContextSettings({}, true)');
  assert.equal(vm.evaluate('AzerMind.GameContext()'), '');
  vm.run('AzerMind.SaveContextSettings({game=true}, false); AzerMind.Send("no automatic context")');
  const rec=stripRecords(vm).find(r=>r.text==='no automatic context');
  assert.ok(rec.ctx === '' || rec.ctx === undefined);
});


test('header latency reads game Home/World and tolerates missing API without sending', () => {
  const vm=newVM(); login(vm);
  const seq=vm.num('AzerMindDB.lastSeq');
  vm.run('GetNetStats=function() return 0, 0, 45, 67 end; AzerMind.UpdateLatency()');
  assert.equal(vm.evaluate('AzerMindLatency:GetText()'), 'Home 45 / World 67 ms');
  vm.run('GetNetStats=nil; AzerMind.UpdateLatency()');
  assert.equal(vm.evaluate('AzerMindLatency:GetText()'), 'Home -- / World -- ms');
  vm.run('GetNetStats=function() error("unavailable") end; AzerMind.UpdateLatency()');
  assert.equal(vm.evaluate('AzerMindLatency:GetText()'), 'Home -- / World -- ms');
  assert.equal(vm.num('AzerMindDB.lastSeq'), seq);
});


test('instances browse bounded pages, filter and attach native links without sending', () => {
 const vm=newVM(); login(vm); connect(vm);
 vm.run('AzerMind.ShowInstancePicker()');
 assert.ok(vm.num('#AzerMindInstancePicker.rows')<=7);
 assert.ok(vm.num('#AzerMindInstancePicker.visible')>=38);
 const before=vm.num('AzerMindDB.lastSeq');
 vm.run('AzerMindInstanceSearch:SetText("Wailing"); AzerMindInstancePicker.Refresh(); AzerMindInstancePicker.rows[1].scripts.OnClick(AzerMindInstancePicker.rows[1],"LeftButton"); for _,b in ipairs(AzerMindInstancePicker.children) do if b.text and b.text:find("^Add to message") then b.scripts.OnClick() end end');
 const draft=vm.evaluate('AzerMindInput:GetText()');
 assert.ok(draft.includes('|Hazermindinstance:')&&draft.includes('Wailing Caverns'));
 assert.equal(vm.num('AzerMindDB.lastSeq'),before);
 vm.run('EXPANDED=AzerMind.ExpandLinks(AzerMindInput:GetText())');
 const expanded=vm.evaluate('EXPANDED');
 assert.ok(expanded.includes('Boss: Lord Cobrahn'));
 assert.ok(expanded.includes("Cobrahn's Grasp"));
 assert.ok(vm.evaluate('AzerMind.RichMessage("user",EXPANDED)').includes('|Hazermindinstance:'));
 assert.equal(vm.num('#AzerMind.FilterInstances("", "Raid", "All", nil)'),3);
 assert.equal(vm.num('#AzerMind.FilterInstances("Wailing", "All", "All", 60)'),0);
 vm.run('local f=CreateFrame("Frame", "INSTANCE_LINK_TEST", UIParent); AzerMind.SetupLinks(f); local r=AzerMind.FilterInstances("Wailing","All","All")[1]; f.scripts.OnHyperlinkEnter(f,"azermindinstance:"..r.id); f.scripts.OnHyperlinkClick(f,"azermindinstance:"..r.id,"Wailing Caverns","LeftButton")');
 assert.equal(vm.evaluate('AzerMindInstanceDetails:IsShown()'),'true');
 assert.equal(vm.evaluate('AzerMindCopy ~= nil'), 'false');

});


test('quest locations resolve area IDs safely, use objectives and turn-ins, and reject missing coordinates', () => {
 const vm=newVM(); login(vm);
 vm.run(`
 C_Map.GetAreaInfo=function(id) if id==38 then return "Loch Modan" end end
 C_Map.GetMapChildrenInfo=function() return {{mapID=1432,name="Loch Modan"}} end
 AzerMindCatalog={manifest={layout=2},loaded={QuestDetails=true,World=true,ItemDetails=true},
 quests={[7]={id=7,name="Test quest",objectives={{{6}}},finishedBy={{197}}}},
 npcs={[6]={name="Kobold",spawns={[38]={{50,60},{51,61}}}},[197]={name="Marshal",spawns={[38]={{40,30}}}}},objects={},items={}}
 LOCATIONS,TITLE=AzerMind.QuestMapLocations(7,false)
 `);
 assert.equal(vm.num('#LOCATIONS'),2);
 assert.equal(vm.num('LOCATIONS[1][1]'),1432);
 assert.equal(vm.num('LOCATIONS[1][2]'),50);
 assert.equal(vm.evaluate('TITLE'),'Test quest');
 vm.run('LOCATIONS=AzerMind.QuestMapLocations(7,true)');
 assert.equal(vm.num('#LOCATIONS'),1);
 assert.equal(vm.num('LOCATIONS[1][2]'),40);
 vm.run('C_Map.GetMapChildrenInfo=function() return {{mapID=1432,name="Loch Modan"},{mapID=999,name="Loch Modan"}} end; LOCATIONS,REASON=AzerMind.QuestMapLocations(7,false)');
 assert.equal(vm.evaluate('LOCATIONS'),null);
 assert.ok(vm.evaluate('REASON').includes('No reliable'));
});


test('instance selection can be reviewed across filters and details never send a message', () => {
 const vm=newVM(); login(vm); connect(vm); vm.run('AzerMind.ShowInstancePicker()');
 const before=vm.num('AzerMindDB.lastSeq');
 vm.run('AzerMindInstancePicker.rows[1].check.scripts.OnClick(); AzerMindInstanceSearch:SetText("no such instance"); AzerMindInstancePicker.Refresh()');
 assert.equal(vm.num('#AzerMindInstancePicker.visible'),0);
 assert.equal(vm.evaluate('AzerMindInstancePicker.attach:GetText()'),'Add to message (1)');
 vm.run('AzerMindInstanceSearch:SetText(""); AzerMindInstancePicker.selectedOnly=true; AzerMindInstancePicker.Refresh()');
 assert.equal(vm.num('#AzerMindInstancePicker.visible'),1);
 vm.run('AzerMindInstancePicker.rows[1].details.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindInstanceDetails:IsShown()'),'true');
 assert.equal(vm.evaluate('AzerMindCopy ~= nil'),'false');
 assert.equal(vm.num('AzerMindDB.lastSeq'),before);
 vm.run('AzerMindInstancePicker.rows[1].check.scripts.OnClick()');
 assert.equal(vm.num('#AzerMindInstancePicker.visible'),0);
 assert.equal(vm.evaluate('AzerMindInstancePicker.attach:GetText()'),'Add to message (0)');
});


test('dungeon location dropdown uses the selected option key and can reset and combine type filters', () => {
 const vm=newVM(); login(vm); vm.run('AzerMind.ShowInstancePicker(); AzerMindInstancePicker.locationButton.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindInstancePicker.locationButton:GetText()'),'Location: All locations');
 vm.run('local row=AzerMindChoiceMenu.rows[2]; CHOSEN_LOCATION=row.option.key; row.scripts.OnClick(row)');
 const zone=vm.evaluate('CHOSEN_LOCATION');
 assert.equal(vm.evaluate('AzerMindInstancePicker.zone'),zone);
 assert.equal(vm.evaluate('AzerMindInstancePicker.locationButton:GetText()'),'Location: '+zone);
 assert.ok(vm.num('#AzerMindInstancePicker.visible')>0);
 assert.equal(vm.evaluate('(function() for _,r in ipairs(AzerMindInstancePicker.visible) do if r.location~=CHOSEN_LOCATION then return false end end return true end)()'),'true');
 vm.run('for _,b in ipairs(AzerMindInstancePicker.children) do if b.text=="Reset filters" then b.scripts.OnClick() end end');
 assert.equal(vm.evaluate('AzerMindInstancePicker.zone'),'All');
 assert.equal(vm.evaluate('AzerMindInstancePicker.locationButton:GetText()'),'Location: All locations');
 assert.equal(vm.num('#AzerMindInstancePicker.visible'),38);
 vm.run('for _,b in ipairs(AzerMindInstancePicker.children) do if b.text=="Raids" then b.scripts.OnClick() end end');
 assert.equal(vm.num('#AzerMindInstancePicker.visible'),3);
 vm.run('for _,b in ipairs(AzerMindInstancePicker.children) do if b.text=="Dungeons" then b.scripts.OnClick() end end');
 assert.equal(vm.num('#AzerMindInstancePicker.visible'),35);
});


test('quest coordinate chooser also accepts the dropdown option object', () => {
 const vm=newVM(); login(vm);
 vm.run(`
 AzerMind.QuestMapLocations=function() return {{1432,40,50,"First"},{1432,60,70,"Second"}},"Test quest" end
 AzerMindMap={MarkQuest=function(id,title,point) MARKED=point; return true end}
 AzerMind.MarkQuestOnMap(7,false)
 local row=AzerMindChoiceMenu.rows[2]; row.scripts.OnClick(row)
 `);
 assert.equal(vm.num('MARKED[2]'),60);
});


test('guide references validate atomically and travel independently of character sharing', () => {
  const vm = newVM(); login(vm); connect(vm);
  vm.run(`
    AzerMind.SaveContextSettings({}, false)
    GUIDE_OK = AzerMind.SaveGuideReferences("https://example.com/guide\\nhttps://example.com/second\\nhttps://example.com/guide")
  `);
  assert.equal(vm.evaluate('GUIDE_OK'), 'true');
  assert.equal(vm.num('#AzerMindDB.settings.guideReferences'), 2);
  vm.run('BAD_GUIDE = AzerMind.SaveGuideReferences("javascript:bad")');
  assert.equal(vm.evaluate('BAD_GUIDE'), 'false');
  assert.equal(vm.num('#AzerMindDB.settings.guideReferences'), 2);
  vm.run('AzerMind.ShowGuideSettings(); AzerMindGuideSettings:Hide(); AzerMind.Send("use my guides")');
  const rec = stripRecords(vm).find(r => r.text === 'use my guides');
  assert.ok(rec);
  assert.ok(rec.ctx.includes('https://example.com/second'));
  vm.run('AzerMind.SaveGuideReferences("")');
  assert.equal(vm.evaluate('AzerMind.GuideReferences()'), '');
});


test('guide editor takes keyboard focus, refocuses on blank-area clicks and preserves variant URLs', () => {
  const vm = newVM(); login(vm);
  const url = 'https://mobalytics.gg/wow-forever/classes/mage-leveling-guide?ws-ngf5-26=activeVariantId%2C7';
  vm.run(`
    AzerMind.CodexPrompt()
    for _,side in ipairs(AzerMindGeneralSettings.children) do
      for _,button in ipairs(side.children or {}) do
        if button.text=="Guide references" then button.scripts.OnClick(button) end
      end
    end
  `);
  assert.equal(vm.evaluate('AzerMindGuideSettings.input:HasFocus()'), 'true', 'opening the editor directs paste to the guide field');
  vm.run(`
    local input = AzerMindGuideSettings.input
    input.scripts.OnEscapePressed(input)
  `);
  assert.equal(vm.evaluate('AzerMindGuideSettings.input:HasFocus()'), 'false');
  vm.run(`
    local scroll = AzerMindGuideSettings.input:GetParent()
    if scroll.scripts.OnMouseDown then scroll.scripts.OnMouseDown(scroll, "LeftButton") end
  `);
  assert.equal(vm.evaluate('AzerMindGuideSettings.input:HasFocus()'), 'true', 'clicking the empty scroll surface restores keyboard focus');
  vm.run(`STUB.focus:Insert(${JSON.stringify(url)}); AzerMindGuideSettings.input.scripts.OnTextChanged()`);
  assert.equal(vm.evaluate('AzerMindGuideSettings.dirty'), 'true');
  assert.equal(vm.evaluate('AzerMind.GuideReferences()'), '', 'pasting does not save automatically');
  vm.run('AzerMindGuideSettings.input:ClearFocus(); AzerMind.ShowGuideSettings()');
  assert.equal(vm.evaluate('AzerMindGuideSettings.input:HasFocus()'), 'true', 'reopening an unsaved draft restores focus');
  assert.equal(vm.evaluate('AzerMindGuideSettings.input:GetText()'), url);
  vm.run('AzerMindGuideSettings.save.scripts.OnClick()');
  assert.equal(vm.evaluate('AzerMind.GuideReferences()'), url, 'Save keeps the selected build query exactly');
  vm.run('AzerMindGuideSettings:Hide()');
  assert.equal(vm.evaluate('AzerMindGuideSettings.input:HasFocus()'), 'false', 'closing releases the keyboard');
  vm.run('AzerMind.ShowGuideSettings()');
  assert.equal(vm.evaluate('AzerMindGuideSettings.input:HasFocus()'), 'true');
  assert.equal(vm.evaluate('AzerMindGuideSettings.input:GetText()'), url);
  assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'), null, 'editing guide settings does not send a chat');
});

test('provider choices stay isolated and survive outgoing transport', () => {
  const vm = newVM(); login(vm); connect(vm,'agentSettings={claude={model="sonnet",efforts={},models={{model="sonnet",efforts={"high"}}}}},');
  vm.run(`
    AzerMind.SaveAISettings(nil, "conversation", {agent="claude", model="sonnet", reasoning="high"})
    AzerMind.SetAgent("grok")
    ISOLATED = AzerMind.ChatAISettings(AzerMindDB.chats[1]).model == nil
    AzerMind.SetAgent("claude")
    AzerMind.Send("provider settings")
  `);
  assert.equal(vm.evaluate('ISOLATED'), 'true');
  const rec = stripRecords(vm).find(r => r.text === 'provider settings');
  assert.ok(rec.flags.includes('model=sonnet'));
  assert.ok(rec.flags.includes('reasoning=high'));
});


test('provider metadata drives model and reasoning settings in game', () => {
  const vm = newVM(); login(vm); connect(vm);
  vm.run('AzerMind.Send("load settings")');
  nextSlot(vm, '{now=time(), agentSettings={claude={model="sonnet",reasoning="",efforts={"low","high"},models={{model="sonnet",efforts={"high"}}}},grok={model="",reasoning="",efforts={},models={}}},replies={}}');
  vm.run('STUB.now = STUB.now + 6; STUB.Tick(); AzerMind.SetAgent("claude"); AzerMind.CodexPrompt()');
  assert.equal(vm.evaluate('AzerMindGeneralSettings.model.shown'), 'true');
  assert.equal(vm.evaluate('AzerMindGeneralSettings.reasoning.shown'), 'true');
  vm.run('AzerMind.SetAgent("grok"); AzerMind.CodexPrompt()');
  assert.equal(vm.evaluate('AzerMindGeneralSettings.model.shown'), 'true');
  assert.equal(vm.evaluate('AzerMindGeneralSettings.reasoning.shown'), 'false');
});

test('shared selectors choose explicit values, search bounded menus and preserve source selections', () => {
 const vm=newVM(); login(vm);
 vm.run(`
  AzerMind.OwnedItems=function() return {
   {key="bag:1",id=1,name="Cloth",link="Cloth",count=1,location="Bags",quality=1,level=1,kind="Armor",subtype="Cloth",slot="INVTYPE_HEAD"},
   {key="bag:2",id=2,name="Sword",link="Sword",count=1,location="Bags",quality=2,level=1,kind="Weapon",subtype="Sword",slot="INVTYPE_WEAPON"}}
  end
  AzerMind.CatalogItemList=function() return {} end
  AzerMind.ShowItemPicker()
  AzerMindItemPicker.selected["bag:1"]=true
  AzerMindItemPicker.raritySelector.scripts.OnClick()
 `);
 assert.equal(vm.num('AzerMindItemPicker.rarity'),-1,'opening a selector never cycles its value');
 vm.run('for _,row in ipairs(AzerMindChoiceMenu.rows) do if row.option.key==2 then row.scripts.OnClick(row); break end end');
 assert.equal(vm.num('AzerMindItemPicker.rarity'),2);
 assert.equal(vm.num('#AzerMindItemPicker.visible'),1);
 assert.equal(vm.evaluate('AzerMindItemPicker.selected["bag:1"]'),'true');
 assert.ok(vm.num('#AzerMindChoiceMenu.rows')<=9);
 vm.run('for _,b in ipairs(AzerMindItemPicker.children) do if b.text=="Item database" then b.scripts.OnClick() end end');
 assert.equal(vm.evaluate('next(AzerMindItemPicker.selected)'),null);
 vm.run('for _,b in ipairs(AzerMindItemPicker.children) do if b.text=="My items" then b.scripts.OnClick() end end');
 assert.equal(vm.evaluate('AzerMindItemPicker.selected["bag:1"]'),'true');
 vm.run('AzerMindItemPicker.selectedToggle.checked=true; AzerMindItemPicker.selectedToggle.scripts.OnClick(AzerMindItemPicker.selectedToggle)');
 assert.equal(vm.evaluate('AzerMindItemPicker.onlySelected'),'true');
});

test('quest bulk selection is additive and selected-only updates after unchecking', () => {
 const vm=newVM(); login(vm);
 vm.run(`
  AzerMind.ActiveQuests=function() return {{id=1,title="First",zone="Test",level=20},{id=2,title="Second",zone="Test",level=20}} end
  AzerMind.ShowQuestPicker()
  AzerMindQuestPicker.selected[99]=true
  for _,b in ipairs(AzerMindQuestPicker.children) do if b.text=="Select all results" then b.scripts.OnClick() end end
 `);
 assert.equal(vm.evaluate('AzerMindQuestPicker.selected[99]'),'true');
 assert.equal(vm.evaluate('AzerMindQuestPicker.selected[1]'),'true');
 vm.run(`local p=AzerMindQuestPicker; p.selectedToggle.checked=true; p.selectedToggle.scripts.OnClick(p.selectedToggle); p.rows[1].checked=false; p.rows[1].scripts.OnClick(p.rows[1])`);
 assert.equal(vm.num('#AzerMindQuestPicker.visible'),1);
 assert.equal(vm.num('AzerMindQuestPicker.rows[1].questId'),2);
});

test('message undo preserves the exact entry and conversation menus expose settings for every provider', () => {
 const vm=newVM(); login(vm);
 vm.run(`
  local chat=AzerMindDB.chats[1]; chat.history={{role="user",text="Question",id=9},{role="assistant",text="Answer",id=9}}
  DELETED=chat.history[2]; AzerMind.Toggle(true); AzerMind.DeleteMessage(chat.id,DELETED)
 `);
 assert.equal(vm.num('#AzerMindDB.chats[1].history'),1);
 assert.equal(vm.evaluate('AzerMind.UndoMessageDeletion()'),'true');
 assert.equal(vm.evaluate('AzerMindDB.chats[1].history[2]==DELETED'),'true');
 vm.run('AzerMindDB.chats[1].agent="claude"; AzerMind.ShowChatMenu(AzerMindDB.chats[1].id,AzerMindFrame)');
 assert.equal(vm.evaluate('(function() for _,b in ipairs(AzerMindChatMenu.children) do if b.label and b.label.text=="AI settings..." then return b:IsShown() end end end)()'),'true');
});

test('dropdown keyboard selection, empty results and local reset preserve selected entries', () => {
 const vm=newVM(); login(vm); vm.run('AzerMind.ShowQuestPicker(); AzerMindQuestPicker.statusSelector.scripts.OnClick()');
 vm.run('AzerMindChoiceMenu.search.scripts.OnArrowPressed(nil,"DOWN"); AzerMindChoiceMenu.search.scripts.OnEnterPressed()');
 assert.equal(vm.evaluate('AzerMindQuestPicker.status'),'Active');
 vm.run('AzerMindQuestPicker.statusSelector.scripts.OnClick(); AzerMindChoiceMenu.search:SetText("no such status"); AzerMindChoiceMenu.search.scripts.OnTextChanged()');
 assert.equal(vm.evaluate('AzerMindChoiceMenu.empty:IsShown()'),'true');
 vm.run('AzerMindQuestPicker.selected[123]=true; for _,b in ipairs(AzerMindQuestPicker.children) do if b.text=="Reset filters" then b.scripts.OnClick() end end');
 assert.equal(vm.evaluate('AzerMindQuestPicker.status'),'All');
 assert.equal(vm.evaluate('AzerMindQuestPicker.selected[123]'),'true');
});

test('guide validation reports its line and sharing off retains category choices', () => {
 const vm=newVM(); login(vm);
 vm.run('OK, MESSAGE=AzerMind.SaveGuideReferences("https://example.com/guide\\ninvalid")');
 assert.equal(vm.evaluate('OK'),'false');
 assert.ok(vm.evaluate('MESSAGE').includes('Line 2'));
 vm.run('AzerMind.ShowContextSettings(); BEFORE=AzerMindContextSettings.options.equipment; AzerMindContextSettings.enabledBox.checked=false; AzerMindContextSettings.enabledBox.scripts.OnClick(AzerMindContextSettings.enabledBox)');
 assert.equal(vm.evaluate('AzerMindContextSettings.enabled'),'false');
 assert.equal(vm.evaluate('AzerMindContextSettings.options.equipment==BEFORE'),'true');
});

test('rerendering preserves the reading position and unsaved guide settings require explicit discard', () => {
 const vm=newVM(); login(vm);
 vm.run(`
  AzerMind.Toggle(true); AzerMindScroll.GetVerticalScrollRange=function() return 1000 end; STUB.RunTimers()
  AzerMindScroll:SetVerticalScroll(200)
  table.insert(AzerMindDB.chats[1].history,{role="assistant",text="New reply"}); AzerMind.Render(); STUB.RunTimers()
 `);
 assert.equal(vm.num('AzerMindScroll:GetVerticalScroll()'),200);
 vm.run(`
  AzerMind.ShowGuideSettings(); local p=AzerMindGuideSettings
  p.input:SetText("https://example.com/unsaved"); p.input.scripts.OnTextChanged()
  p:Hide(); for _,hook in ipairs(p.hooks.OnHide) do hook(p) end
 `);
 assert.equal(vm.evaluate('AzerMindGuideSettings:IsShown()'),'true');
 assert.equal(vm.evaluate('STUB.popup.which'),'AZERMIND_DISCARD_UI_CHANGES');
 assert.equal(vm.evaluate('AzerMind.GuideReferences()'),'');
 vm.run('StaticPopupDialogs.AZERMIND_DISCARD_UI_CHANGES.OnAccept(nil,STUB.popup.data)');
 assert.equal(vm.evaluate('AzerMindGuideSettings:IsShown()'),'false');
});

test('AI model selector handles long catalogs and only offers the selected model reasoning', () => {
 const vm=newVM(); login(vm);
 const entries=Array.from({length:80},(_,i)=>`{model="model-${i+1}",name="Model ${i+1}",effortsKnown=true,efforts={${i===39?'"low","high"':''}}}`).join(',');
 connect(vm,`agent="claude",aiDefaults={agent="claude",model="model-1",reasoning=""},agentSettings={claude={model="model-1",efforts={},catalogSource="Fixture account catalog",models={${entries}}}},`);
 vm.run('AzerMind.CodexPrompt(); AzerMindGeneralSettings.inherit=false; AzerMindGeneralSettings.Refresh(); AzerMindGeneralSettings.model.scripts.OnClick()');
 assert.equal(vm.num('#AzerMindChoiceMenu.options'),82);
 assert.ok(vm.num('#AzerMindChoiceMenu.rows')<=9);
 assert.equal(vm.evaluate('AzerMindChoiceMenu.options[82].key'),'__custom');
 vm.run('AzerMindChoiceMenu.search:SetText("model-40"); AzerMindChoiceMenu.search.scripts.OnTextChanged(); local row=AzerMindChoiceMenu.rows[1]; row.scripts.OnClick(row)');
 assert.equal(vm.evaluate('AzerMindGeneralSettings.modelValue'),'model-40');
 assert.equal(vm.evaluate('AzerMindGeneralSettings.reasoning:IsShown()'),'true');
 vm.run('AzerMindGeneralSettings.reasoning.scripts.OnClick()');
 assert.equal(vm.num('#AzerMindChoiceMenu.options'),3);
 vm.run('local row=AzerMindChoiceMenu.rows[3]; row.scripts.OnClick(row); AzerMindGeneralSettings.save.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindDB.chats[1].aiSettings.claude.model'),'model-40');
 assert.equal(vm.evaluate('AzerMindDB.chats[1].aiSettings.claude.reasoning'),'high');
 vm.run('OK,ERROR=AzerMind.SaveAISettings(nil,"conversation",{agent="claude",model="model-1",reasoning="high"})');
 assert.equal(vm.evaluate('OK'),'false');
});

test('refreshing model choices is a control request and preserves unsaved settings on receipt', () => {
 const vm=newVM(); login(vm); connect(vm);
 vm.run('AzerMind.CodexPrompt(); AzerMindGeneralSettings.modelValue="unsaved-model"; AzerMindGeneralSettings.dirty=true; OK=AzerMind.RefreshModelChoices()');
 assert.equal(vm.evaluate('OK'),'true');
 assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'),null);
 const request=stripRecords(vm).find(r=>r.text==='{"action":"refresh-models"}');
 assert.ok(request.flags.includes('settings'));
 const token=vm.evaluate('AzerMindDB.session'),chat=vm.evaluate('AzerMindDB.activeChat');
 nextSlot(vm,`{now=time(),agentSettings={codex={model="",efforts={},models={{model="new-model",efforts={"low"}}}}},replies={{id=${request.id},chat="${chat}",session="${token}",status="models-refreshed",text="Model choices refreshed."}}}`);
 vm.run('STUB.now=STUB.now+6; STUB.Tick()');
 assert.equal(vm.evaluate('AzerMindGeneralSettings.modelValue'),'unsaved-model');
 assert.equal(vm.evaluate('AzerMindGeneralSettings.dirty'),'true');
 assert.equal(vm.evaluate('AzerMindGeneralSettings.message'),'Model choices refreshed.');
 assert.equal(vm.num('#(select(3,AzerMind.SettingsState(nil,"codex")))'),1);
});

test('clicking a selector twice closes it without changing its value or reopening on anchor mouse-down', () => {
 const vm=newVM(); login(vm); vm.run('AzerMind.ShowQuestPicker(); AzerMindQuestPicker.statusSelector.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindChoiceMenu:IsShown()'),'true');
 vm.run('MouseIsOver=function(frame) return frame==AzerMindQuestPicker.statusSelector end; AzerMindChoiceMenu.scripts.OnEvent(AzerMindChoiceMenu); AzerMindQuestPicker.statusSelector.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindChoiceMenu:IsShown()'),'false');
 assert.equal(vm.evaluate('AzerMindQuestPicker.status'),'All');
});

test('filter toggle survives global mouse-down when MouseIsOver is missing or unreliable',()=>{
 const vm=newVM(); login(vm); vm.run(`
  AzerMind.ShowQuestPicker(); OWNER=AzerMindQuestPicker.statusSelector
  OWNER.GetLeft=function() return 100 end; OWNER.GetRight=function() return 300 end
  OWNER.GetBottom=function() return 200 end; OWNER.GetTop=function() return 230 end
  OWNER.GetEffectiveScale=function() return 1.5 end
  GetCursorPosition=function() return 200,320 end
  MouseIsOver=nil
  OWNER.scripts.OnClick()
  AzerMindChoiceMenu.scripts.OnEvent(AzerMindChoiceMenu)
 `);
 assert.equal(vm.evaluate('AzerMindChoiceMenu:IsShown()'),'true');
 vm.run('OWNER.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindChoiceMenu:IsShown()'),'false');
 vm.run('MouseIsOver=function() return false end; OWNER.scripts.OnClick(); AzerMindChoiceMenu.scripts.OnEvent(AzerMindChoiceMenu); OWNER.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindChoiceMenu:IsShown()'),'false');
 vm.run('OWNER.scripts.OnClick(); GetCursorPosition=function() return 9999,9999 end; AzerMindChoiceMenu.scripts.OnEvent(AzerMindChoiceMenu)');
 assert.equal(vm.evaluate('AzerMindChoiceMenu:IsShown()'),'false','outside click still dismisses the menu');
});

test('instance details are an interactive bounded boss/loot browser rather than a copy dialog', () => {
 const vm=newVM(); login(vm); connect(vm);
 vm.run(`
  DETAIL_RECORD={id=99,name="Test dungeon",type="Dungeon",level="20-30",location="Test zone",bosses={},source="Fixture"}
  for i=1,15 do
   local boss={name="Boss "..i,npcID=i,loot={}}
   for j=1,17 do boss.loot[j]={id=i*100+j,name="Loot "..i.."/"..j} end
   table.insert(DETAIL_RECORD.bosses,boss)
  end
  AzerMind.ShowInstanceDetails(DETAIL_RECORD)
 `);
 assert.equal(vm.evaluate('AzerMindCopy ~= nil'),'false');
 assert.equal(vm.num('#AzerMindInstanceDetails.bossRows'),7);
 assert.equal(vm.num('#AzerMindInstanceDetails.lootRows'),5);
 vm.run('AzerMindInstanceDetails.bossRows[2].scripts.OnClick(AzerMindInstanceDetails.bossRows[2])');
 assert.equal(vm.evaluate('AzerMindInstanceDetails.bossTitle:GetText()'),'Boss 2');
 assert.equal(vm.num('AzerMindInstanceDetails.lootRows[1].item.id'),201);
 vm.run('AzerMindInstanceDetails.lootNext.scripts.OnClick()');
 assert.equal(vm.num('AzerMindInstanceDetails.lootRows[1].item.id'),206);
 vm.run('AzerMindInstanceDetails.search:SetText("Loot 2/17"); AzerMindInstanceDetails.search.scripts.OnTextChanged()');
 assert.equal(vm.num('#AzerMindInstanceDetails.visibleLoot'),1);
 assert.equal(vm.num('AzerMindInstanceDetails.lootRows[1].item.id'),217);
 vm.run('AzerMindInstanceDetails.bossNext.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindInstanceDetails.bossRows[1].boss.name'),'Boss 8');
 vm.run('AzerMind.ShowInstanceDetails({id=100,name="Empty",type="Raid",level="60",location="Unknown",bosses={},source="Fixture"})');
 assert.equal(vm.evaluate('AzerMindInstanceDetails.empty:IsShown()'),'true');
 assert.equal(vm.evaluate('AzerMindInstanceDetails.lootRows[1].item'),null,'reused rows cannot retain old loot actions');
});

test('instance loot opens exact item references, missing IDs are explained and copy is explicit', () => {
 const vm=newVM(); login(vm); connect(vm);
 const before=vm.num('AzerMindDB.lastSeq');
 vm.run(`
  SetItemRef=function(payload) OPENED_ITEM=payload end
  AzerMind.ShowInstanceDetails({id=99,name="Reference",type="Dungeon",level="20",location="Test",source="Fixture",bosses={{name="Boss",loot={{id=123,name="Known"},{name="Name only"}}}}})
  local row=AzerMindInstanceDetails.lootRows[1]; row.scripts.OnClick(row,"LeftButton")
 `);
 assert.equal(vm.evaluate('OPENED_ITEM'),'item:123');
 vm.run('local row=AzerMindInstanceDetails.lootRows[2]; row.scripts.OnClick(row,"LeftButton")');
 assert.equal(vm.evaluate('OPENED_ITEM'),'item:123');
 assert.ok(vm.evaluate('AzerMindInstanceDetails.feedback:GetText()').includes('No item reference'));
 assert.equal(vm.evaluate('AzerMindCopy ~= nil'),'false');
 vm.run('AzerMindInstanceDetails.copy.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindCopy:IsShown()'),'true');
 assert.ok(vm.evaluate('AzerMindCopyBox:GetText()').includes('Boss: Boss'));
 assert.equal(vm.num('AzerMindDB.lastSeq'),before,'browsing, inspecting and copying never send');
});

test('details close leaves the instance selection intact and adding uses the original conversation', () => {
 const vm=newVM(); login(vm); connect(vm);
 vm.run('AzerMind.ShowInstancePicker(); AzerMindInstancePicker.rows[1].check.scripts.OnClick(); AzerMindInstancePicker.rows[1].details.scripts.OnClick(); AzerMindInstanceDetails.back.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindInstancePicker:IsShown()'),'true');
 assert.equal(vm.evaluate('AzerMindInstanceDetails:IsShown()'),'false');
 assert.equal(vm.evaluate('AzerMindInstancePicker.attach:GetText()'),'Add to message (1)');
 vm.run('AzerMindInstancePicker.rows[1].details.scripts.OnClick(); AzerMind.NewChat(); AzerMindInstanceDetails.attach.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindInput:GetText()'),'');
 assert.ok(vm.evaluate('AzerMindInstanceDetails.feedback:GetText()').includes('Conversation changed'));
});

test('instance entrance actions only use explicitly recorded map coordinates', () => {
 const vm=newVM(); login(vm);
 vm.run(`
  WorldMapFrame=CreateFrame("Frame",nil,UIParent)
  WorldMapFrame.SetMapID=function(_,id) OPEN_MAP=id end
  C_Map.CanSetUserWaypointOnMap=function() return true end
  C_Map.SetUserWaypoint=function(point) WAYPOINT=point end
  UiMapPoint={CreateFromCoordinates=function(map,x,y) return {map=map,x=x,y=y} end}
  AzerMind.ShowInstanceDetails({id=99,name="Mapped",type="Dungeon",level="20",location="Test",bosses={},entrance={mapID=1432,x=0.25,y=0.5}})
  AzerMindInstanceDetails.map.scripts.OnClick()
 `);
 assert.equal(vm.num('OPEN_MAP'),1432);
 assert.equal(vm.num('WAYPOINT.x'),0.25);
 assert.equal(vm.num('WAYPOINT.y'),0.5);
 vm.run('AzerMind.ShowInstanceDetails({id=100,name="Unlocated",type="Dungeon",level="20",location="Test",bosses={}}); AzerMindInstanceDetails.map.scripts.OnClick()');
 assert.equal(vm.num('OPEN_MAP'),1432,'missing location cannot invent a different map or pin');
 assert.ok(vm.evaluate('AzerMindInstanceDetails.feedback:GetText()').includes('No entrance coordinates'));
});

test('database ownership, numeric required-level range, subtype and reset compose correctly',()=>{
 const vm=newVM(); login(vm);
 vm.run(`
 AzerMindCatalog={manifest={source="Fixture",version="1"},items={
 [1]={name="Cloth legs",requiredLevel=10,classID=4,subclassID=1},
 [2]={name="Leather legs",requiredLevel=20,classID=4,subclassID=2},
 [3]={name="Potion",requiredLevel=30,classID=0,subclassID=1}},quests={},npcs={},objects={}}
 AzerMind.OwnedItems=function() return {{key="owned:1",id=1,link="item:1",location="Bags",name="Cloth legs",kind="",subtype="",slot="",count=1}} end
 AzerMind.ShowItemPicker()
 function ItemClick(label) for _,b in ipairs(AzerMindItemPicker.children) do if b.text==label then b.scripts.OnClick(b); return end end; error("missing "..label) end
 ItemClick("Item database"); ItemClick("Bags")
 `);
 assert.equal(vm.num('#AzerMindItemPicker.visible'),1);
 assert.equal(vm.num('AzerMindItemPicker.visible[1].id'),1);
 vm.run(`ItemClick("All"); AzerMindItemMinLevel:SetText("15"); AzerMindItemMinLevel.scripts.OnTextChanged(AzerMindItemMinLevel); AzerMindItemMaxLevel:SetText("25"); AzerMindItemMaxLevel.scripts.OnTextChanged(AzerMindItemMaxLevel)`);
 assert.equal(vm.num('#AzerMindItemPicker.visible'),1);
 assert.equal(vm.num('AzerMindItemPicker.visible[1].id'),2);
 vm.run('ItemClick("Select page"); ItemClick("Reset filters")');
 assert.equal(vm.num('#AzerMindItemPicker.visible'),3);
 assert.equal(vm.evaluate('AzerMindItemPicker.selected["catalog:2"]'),'true');
 assert.equal(vm.evaluate('AzerMindItemPicker.minLevel'),null);
});

test('ready-to-turn-in and hypothetical class filters do not mix completed quests',()=>{
 const vm=newVM(); login(vm);
 vm.run(`
 C_QuestLog={GetNumQuestLogEntries=function() return 2 end,GetInfo=function(i) return {questID=i,title="Quest "..i,isComplete=i==1} end}
 AzerMind.ShowQuestPicker(); AzerMindQuestPicker.status="Ready to turn in"; AzerMindQuestPicker.Load()
 `);
 assert.equal(vm.num('#AzerMindQuestPicker.visible'),1);
 assert.equal(vm.num('AzerMindQuestPicker.visible[1].id'),1);
 vm.run('Q={record={requiredClasses=128,requiredRaces=8}}');
 assert.equal(vm.evaluate('AzerMind.CatalogQuestMatchesCharacter(Q,0,0)'),'true');
 assert.equal(vm.evaluate('AzerMind.CatalogQuestMatchesCharacter(Q,4,8)'),'true');
 assert.equal(vm.evaluate('AzerMind.CatalogQuestMatchesCharacter(Q,4,1)'),'false');
});

test('closing a settings child returns to its parent and reply sounds persist',()=>{
 const vm=newVM(); login(vm);
 vm.run(`
 AzerMind.CodexPrompt();
 for _,side in ipairs(AzerMindGeneralSettings.children) do for _,b in ipairs(side.children or {}) do if b.text=="Guide references" then b.scripts.OnClick(b) end end end
 `);
 assert.equal(vm.evaluate('AzerMindGeneralSettings:IsShown()'),'false');
 vm.run('AzerMindGuideSettings:Hide()');
 assert.equal(vm.evaluate('AzerMindGeneralSettings:IsShown()'),'true');
 vm.run('AzerMind.ReplySound(0); AzerMind.ShowNotificationSettings()');
 assert.equal(vm.num('AzerMind.ReplySound()'),0);
 vm.run('AzerMind.ReplySound(3175); AzerMind.ReplySound(999999)');
 assert.equal(vm.num('AzerMind.ReplySound()'),3175);
});

test('item source rows open NPC locations without sending a chat request',()=>{
 const vm=newVM(); login(vm);
 vm.run(`
 AzerMindCatalog={manifest={source="Fixture",version="1"},items={[7]={name="Test item",npcDrops={10,11}}},quests={},npcs={
 [10]={id=10,name="First NPC",spawns={[331]={{20,30},{40,50}}}},[11]={id=11,name="Second NPC",spawns={[85]={{12,34}}}}},objects={}}
 AzerMind.ShowSourceBrowser("item",7)
 `);
 assert.equal(vm.num('#AzerMindEntityBrowser.entries'),2);
 vm.run('AzerMindEntityBrowser.rows[1].scripts.OnClick(AzerMindEntityBrowser.rows[1]); AzerMindEntityBrowser.rows[1].map.scripts.OnClick()');
 assert.equal(vm.num('#AzerMindChoiceMenu.options'),2);
 assert.equal(vm.evaluate('AzerMindDB.chats[1].pendingId'),null);
});


test('configured chat hotkeys exist at login and focus input without opening settings first',()=>{
 const vm=newVM(); login(vm);
 vm.run('AzerMind.Toggle(false); AzerMindOpenChatKeyButton.scripts.OnClick()');
 assert.equal(vm.evaluate('AzerMindFrame:IsShown()'),'true');
 const before=vm.num('#AzerMindDB.chats');
 vm.run('AzerMindNewChatKeyButton.scripts.OnClick()');
 assert.equal(vm.num('#AzerMindDB.chats'),before+1);
});
