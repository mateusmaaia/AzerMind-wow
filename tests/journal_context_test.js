'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

function journal(setup = '') {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  function run(code) {
    const status = lauxlib.luaL_dostring(L, to_luastring(code));
    if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L, -1)));
  }
  function value(expression) {
    run('RESULT = tostring(' + expression + ')');
    lua.lua_getglobal(L, to_luastring('RESULT'));
    const result = to_jsstring(lua.lua_tostring(L, -1));
    lua.lua_pop(L, 1);
    return result;
  }

  run('AzerMind = {}');
  const source = path.join(__dirname, '../addon/AzerMind/JournalContext.lua');
  assert.ok(fs.existsSync(source), 'JournalContext.lua implements the journal adapter');
  run(fs.readFileSync(source, 'utf8'));
  run(setup);
  return { run, value };
}

const catalog = `
  AzerMindInstanceData = {
    { id = 10, name = "The Deadmines" },
    { id = 20, name = "Wailing Caverns" },
  }
  AzerMind.InstanceByID = function(id)
    for _, record in ipairs(AzerMindInstanceData) do
      if record.id == tonumber(id) then return record end
    end
  end
  ForeverDungeonJournal_NS = {
    DB = {
      ["The Deadmines"] = {},
      ["Wailing Caverns"] = {},
      ["Dire Maul: West"] = {},
      ["Dire Maul: East"] = {},
    },
    DUNGEON_SEARCH_ALIASES = {
      ["The Deadmines"] = { "vc", "dm" },
      ["Wailing Caverns"] = { "wc" },
      ["Dire Maul: West"] = { "dm west" },
      ["Dire Maul: East"] = { "dm east" },
    },
    GetSelectedDungeon = function() error("journal browsing is not a destination") end,
  }
`;

test('dungeon links resolve AzerMind IDs and exact names or whole aliases resolve text', () => {
  const v = journal(catalog);
  for (const [input, name] of [
    ['Upgrades in Deadmines?', 'The Deadmines'],
    ['Drops in WC?', 'Wailing Caverns'],
    ['Drops in DM West?', 'Dire Maul: West'],
    ['Drops in Dire Maul - East?', 'Dire Maul: East'],
    ['|cff8fc9df|Hazermindinstance:20|h[Some display name]|h|r', 'Wailing Caverns'],
  ]) {
    v.run(`R = AzerMind.ResolveDungeonQuestion(${JSON.stringify(input)})`);
    assert.equal(v.value('R.status'), 'ok');
    assert.equal(v.value('R.name'), name);
    assert.equal(v.value('R.provenance'), 'explicit');
  }
  for (const input of ['Does worldmodel show upgrades?', '|Hitem:123|h[Wailing Caverns Token]|h']) {
    assert.equal(v.value(`AzerMind.ResolveDungeonQuestion(${JSON.stringify(input)}).status`), 'unknown');
  }
});

test('independent names and colliding aliases are ambiguous', () => {
  const v = journal(catalog);
  v.run('R = AzerMind.ResolveDungeonQuestion("VC or Wailing Caverns?")');
  assert.equal(v.value('R.status'), 'ambiguous');
  assert.equal(v.value('#R.candidates'), '2');
  v.run('table.insert(ForeverDungeonJournal_NS.DUNGEON_SEARCH_ALIASES["Dire Maul: West"], "dm")');
  assert.equal(v.value('AzerMind.ResolveDungeonQuestion("DM?").status'), 'ambiguous');
});

test('current instance is accepted only inside a party or raid instance', () => {
  const v = journal(catalog + `
    ForeverDungeonJournal_NS.CurrentDungeon = function() return "The Deadmines" end
    GetInstanceInfo = function() return "Wailing Caverns", "party" end
    IsInInstance = function() return false, "none" end
  `);
  assert.equal(v.value('AzerMind.ResolveDungeonQuestion("What drops here?").status'), 'unknown');
  v.run('IsInInstance = function() return true, "pvp" end');
  assert.equal(v.value('AzerMind.ResolveDungeonQuestion("What drops here?").status'), 'unknown');
  v.run('IsInInstance = function() return true, "party" end; R = AzerMind.ResolveDungeonQuestion("What drops here?")');
  assert.equal(v.value('R.name'), 'The Deadmines');
  assert.equal(v.value('R.provenance'), 'current');
  v.run('ForeverDungeonJournal_NS.CurrentDungeon = function() error("unsupported") end; R = AzerMind.ResolveDungeonQuestion("What drops here?")');
  assert.equal(v.value('R.name'), 'Wailing Caverns');
  assert.equal(v.value('AzerMind.ResolveDungeonQuestion("|Hazermindinstance:999|h[Old dungeon]|h").status'), 'unknown');
});

test('loaded journal returns direct drops, shared drops, trash and actual quest rewards', () => {
  const v = journal(catalog + `
    C_AddOns = { GetAddOnMetadata = function(addon, key)
      if addon == "ForeverDungeonJournal" and key == "Version" then return "2.0.2" end
    end }
    C_QuestLog = { IsQuestFlaggedCompleted = function(id) return id == 201 end }
    ForeverDungeonJournal_NS.DB["The Deadmines"] = {
      bosses = {
        { name = "Boss", npcID = 101, loot = {{11, "Sword"}} },
        { name = "Trash", trash = true, loot = {{13, "Leather"}} },
        { name = "Recipes", recipeTab = true, loot = {{14, "Pattern"}} },
      },
      quests = {
        { id = 201, name = "A Quest", faction = "Alliance", rewardItems = {{15, "Reward"}},
          additionalRewardItems = {{16, "Other Reward"}}, requiredItem = {17, "Required"},
          startItem = {18, "Starts quest"}, noteItem = {19, "Note"}, noteRewardItems = {{20, "Note-only"}} },
      },
    }
    ForeverDungeonJournal_NS.GetBossSharedLoot = function(_, boss)
      if boss.name == "Boss" then return {{12, "Shield"}, {11, "Sword"}} end
    end
    R = AzerMind.ReadDungeonLoot("Deadmines")
    E = {}
    for _, entry in ipairs(R.entries) do E[entry.itemID] = entry end
  `);
  assert.equal(v.value('R.status'), 'ok');
  assert.equal(v.value('R.source'), 'ForeverDungeonJournal');
  assert.equal(v.value('R.version'), '2.0.2');
  assert.equal(v.value('#R.entries'), '5');
  assert.equal(v.value('E[11].kind .. ":" .. E[11].sourceName .. ":" .. E[11].npcID'), 'boss:Boss:101');
  assert.equal(v.value('E[12].shared'), 'true');
  assert.equal(v.value('E[13].kind'), 'trash');
  assert.equal(v.value('E[15].kind .. ":" .. E[15].questID .. ":" .. E[15].questFaction'), 'quest:201:Alliance');
  assert.equal(v.value('E[16].questCompleted'), 'true');
  for (const id of [14, 17, 18, 19, 20]) assert.equal(v.value(`E[${id}]`), 'nil');
  assert.equal(v.value('#ForeverDungeonJournal_NS.DB["The Deadmines"].bosses[1].loot'), '1');
});

test('missing IDs and failing shared-loot API preserve known live drops as partial evidence', () => {
  const v = journal(catalog + `
    ForeverDungeonJournal_NS.GetBossSharedLoot = function() error("unsupported") end
    ForeverDungeonJournal_NS.DB["The Deadmines"].bosses = {
      { name = "Boss", loot = {{0, "Unresolved"}, {-5, "Invalid"}, {22, "Confirmed"}} }
    }
    R = AzerMind.ReadDungeonLoot("The Deadmines")
  `);
  assert.equal(v.value('R.status'), 'partial');
  assert.equal(v.value('R.partial'), 'true');
  assert.equal(v.value('#R.entries'), '1');
  assert.equal(v.value('R.entries[1].itemID'), '22');
});

test('bundled fallback identifies listed items as partial and missing data as unavailable', () => {
  const v = journal(`
    AzerMindInstanceData = {
      { name = "The Deadmines", bosses = {{name = "Boss", loot = {{id=11,name="Sword"},{name="Unknown"}}}} }
    }
    R = AzerMind.ReadDungeonLoot("The Deadmines")
  `);
  assert.equal(v.value('R.status'), 'partial');
  assert.equal(v.value('R.source'), 'AzerMind bundled dungeon snapshot');
  assert.equal(v.value('#R.entries'), '1');
  assert.equal(v.value('R.entries[1].kind'), 'listed');
  assert.equal(v.value('AzerMind.ReadDungeonLoot("Unlisted").status'), 'unavailable');
  v.run('AzerMindInstanceData = nil');
  assert.equal(v.value('AzerMind.ResolveDungeonQuestion("Upgrades in The Deadmines?").status'), 'unavailable');
});

test('City of Dalaran resolves from the journal aliases Dalaran and Dala', () => {
  const v = journal(catalog + `
    ForeverDungeonJournal_NS.DB["City of Dalaran"] = {}
    ForeverDungeonJournal_NS.DUNGEON_SEARCH_ALIASES["City of Dalaran"] = { "dala", "dal", "dalaran" }
  `);
  for (const input of ['I am heading to Dalaran now', 'Any upgrades in Dala?']) {
    v.run(`R = AzerMind.ResolveDungeonQuestion(${JSON.stringify(input)})`);
    assert.equal(v.value('R.status'), 'ok');
    assert.equal(v.value('R.name'), 'City of Dalaran');
    assert.equal(v.value('R.provenance'), 'explicit');
  }
});

test('oversized loot and source lists stop at their inspection limits and return partial results', () => {
  const v = journal(catalog + `
    local dungeon = ForeverDungeonJournal_NS.DB["The Deadmines"]
    local function failPastEnd()
      return { __index = function() error("read beyond the inspection limit") end }
    end
    local loot = {}
    for i = 1, 1200 do loot[i] = {i, "Item"} end
    setmetatable(loot, failPastEnd())
    dungeon.bosses = {{name = "Boss", loot = loot}}
    dungeon.quests = setmetatable({}, failPastEnd())
    R = AzerMind.ReadDungeonLoot("The Deadmines")
    local bosses, quests = {}, {}
    for i = 1, 128 do
      bosses[i] = {name = "Trash", trash = true, loot = {{i, "Drop"}}}
      quests[i] = {name = "Quest", rewardItems = {{i + 1000, "Reward"}}}
    end
    dungeon.bosses = setmetatable(bosses, failPastEnd())
    dungeon.quests = setmetatable(quests, failPastEnd())
    S = AzerMind.ReadDungeonLoot("The Deadmines")
  `);
  assert.equal(v.value('R.status'), 'partial');
  assert.equal(v.value('R.partial'), 'true');
  assert.equal(v.value('#R.entries'), '1200');
  assert.match(v.value('R.reason'), /limit/i);
  assert.equal(v.value('S.status'), 'partial');
  assert.equal(v.value('#S.entries'), '256');
  assert.match(v.value('S.reason'), /limit/i);
});
