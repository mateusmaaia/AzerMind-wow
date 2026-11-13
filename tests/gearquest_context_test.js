// Exercise the adapter with the methods exposed by the installed GearQuest addon.
'use strict';
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const adapter = path.join(__dirname, '../addon/AzerMind/GearQuestContext.lua');
const gearQuest = `
  class, spec, owned = "MAGE", "frost", {}
  rows = { Chest = {{itemId=1, name="Robe"}}, MainHand = {{itemId=2}}, SecondaryHand = {{itemId=3}} }
  GearQuest = { VERSION="1.1.4", Data={}, Log={} }
  function GearQuest:GetEffectiveClass() return class end
  function GearQuest:GetEffectiveSpec() return spec end
  function GearQuest:IsPreviewEnabled() return preview end
  function GearQuest:WithContextSnapshot(read, ...)
    local result = read(...)
    snapshotRead = true
    return result
  end
  function GearQuest.Data:IsClassExpanded(playerClass) return playerClass == class and not pending end
  function GearQuest.Data:GetSlotsForClass(playerClass)
    assert(playerClass == class)
    return { "Chest", "MainHand", "SecondaryHand" }
  end
  function GearQuest.Data:GetItemDisplayName(itemId) return "Item " .. itemId end
  function GearQuest.Data:PlayerOwnsEntryItem(entry)
    entry.enriched = true
    return owned[entry.itemId] == (entry.suffix or true)
  end
  function GearQuest.Data:EntryMatchesPlayer(entry) return entry.eligible ~= false end
  function GearQuest.Data:UsesTwoHandOnlyWeapons() return class == "HUNTER" end
  function GearQuest.Log:EnsureActiveListCaches() ensured = true end
  function GearQuest.Log:GetActiveSlotListEntries(slot)
    assert(slot == "Chest" and ensured)
    return rows[slot]
  end
  function GearQuest.Log:FilteredWeaponEntries() assert(ensured); return rows.MainHand end
  function GearQuest.Log:HeldOffHandEntries() assert(ensured); return rows.SecondaryHand end
`;

function check(code) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  try {
    function run(source) {
      const status = lauxlib.luaL_dostring(L, to_luastring(source));
      if (status !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
    }
    run('AzerMind = {}');
    if (fs.existsSync(adapter)) run(fs.readFileSync(adapter, 'utf8'));
    run(gearQuest + '\n' + code);
  } finally {
    lua.lua_close(L);
  }
}

test('distinguishes missing GearQuest, unexpanded class data and simulation', () => {
  check(`
    local gq = GearQuest
    GearQuest = nil
    assert(AzerMind.ReadGearQuestHunts().status == "unavailable")
    GearQuest, pending = gq, true
    assert(AzerMind.ReadGearQuestHunts().status == "unavailable")
    pending, preview = false, true
    local result = AzerMind.ReadGearQuestHunts()
    assert(result.status == "preview" and #result.entries == 0 and not ensured)
  `);
});

test('reads active hunts with current class/spec and GearQuest weapon routing', () => {
  check(`
    local result = AzerMind.ReadGearQuestHunts()
    assert(snapshotRead and result.version == "1.1.4")
    assert(result.status == "ok" and result.class == "MAGE" and result.spec == "frost")
    assert(#result.entries == 3 and result.entries[1].itemID == 1)
    assert(result.entries[2].slot == "MainHand" and result.entries[3].slot == "SecondaryHand")
    class, spec = "HUNTER", "survival"
    result = AzerMind.ReadGearQuestHunts()
    assert(result.class == "HUNTER" and result.spec == "survival" and #result.entries == 2)
    class, spec, rows.MainHand = "ROGUE", nil, {{itemId=5, slot="SecondaryHand"}}
    result = AzerMind.ReadGearQuestHunts()
    assert(result.status == "ok" and result.spec == nil)
    assert(result.entries[2].slot == "SecondaryHand")
  `);
});

test('rechecks ownership with the suffix and leaves the GearQuest entry intact', () => {
  check(`
    rows.Chest = {{itemId=1, suffix="of the Eagle", sourceType="quest_reward", questId=41}}
    owned[1] = "of the Whale"
    local entry = AzerMind.ReadGearQuestHunts().entries[1]
    assert(entry.owned == false and entry.suffix == "of the Eagle")
    assert(entry.name == "Item 1" and entry.sourceType == "quest_reward" and entry.questID == 41)
    owned[1] = "of the Eagle"
    local newEntry = AzerMind.ReadGearQuestHunts().entries[1]
    assert(newEntry.owned == true and entry.owned == false)
    assert(rows.Chest[1].enriched == nil)
  `);
});

test('discards stale ineligible rows and reports missing IDs or broken slot reads as partial', () => {
  check(`
    rows.Chest = {{itemId=9, eligible=false}, {name="No ID"}, {itemId=11}}
    GearQuest.Log.FilteredWeaponEntries = function() error("unexpected API failure") end
    GearQuest.Log.HeldOffHandEntries = function() return false end
    local result = AzerMind.ReadGearQuestHunts()
    assert(result.status == "partial" and result.partial and result.reason)
    assert(#result.entries == 1 and result.entries[1].itemID == 11)
  `);
});

test('surfaces ownership failures while retaining usable hunt metadata', () => {
  check(`
    function GearQuest.Data:PlayerOwnsEntryItem() error("inventory unavailable") end
    local result = AzerMind.ReadGearQuestHunts()
    assert(result.status == "partial" and #result.entries == 3)
    assert(result.entries[1].owned == nil)
  `);
});

test('bounds the data read from the installed addon', () => {
  check(`
    rows.Chest = {}
    for i = 1, 250 do rows.Chest[i] = { itemId = i } end
    local result = AzerMind.ReadGearQuestHunts()
    assert(result.status == "partial" and result.total > #result.entries)
    assert(#result.entries == 200)
  `);
});

test('retains suffix requirements enriched by the ownership check without changing GearQuest rows', () => {
  check(`
    rows.Chest={{itemId=1}}
    function GearQuest.Data:PlayerOwnsEntryItem(entry) entry.suffix="of Frozen Wrath"; return false end
    local result=AzerMind.ReadGearQuestHunts()
    assert(result.entries[1].suffix=="of Frozen Wrath")
    assert(rows.Chest[1].suffix==nil)
  `);
});
