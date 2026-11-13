'use strict';
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const boot = require('./helpers/grimoire-vm');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('fengari');
test('optional AHledger prices handle missing data, failures, snapshots and copper', () => {
  const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
  function run(s) {
    if (lauxlib.luaL_loadstring(L, to_luastring(s)) !== lua.LUA_OK || lua.lua_pcall(L,0,0,0) !== lua.LUA_OK)
      throw Error(to_jsstring(lua.lua_tostring(L,-1)));
  }
  run('AzerMind={}; date=function() return "2026-11-12 01:00" end');
  run(fs.readFileSync(path.join(__dirname,'../addon/AzerMind/Auction.lua'),'utf8'));
  run(`
    assert(AzerMind.AuctionItemDetails(2589)==nil)
    AHledgerAPI={GetPrice=function() error('unavailable') end}
    assert(AzerMind.AuctionItemDetails(2589)==nil)
    AHledgerAPI.GetPrice=function() return {} end
    assert(AzerMind.AuctionItemDetails(2589)==nil)
    AHledgerAPI.GetPrice=function(id)
      assert(id==2589)
      return {median=12345,minBuyout=0,quantity=20,market='forever.pvp.horde.us',updated=1794440000,snapshot=true}
    end
    local text=AzerMind.AuctionItemDetails(2589)
    assert(text:find('1g 23s 45c',1,true))
    assert(text:find('minimum 0g 0s 0c',1,true))
    assert(text:find('bundled snapshot; not live',1,true))
    assert(text:find('forever.pvp.horde.us',1,true))
    assert(text:find('Prices from AHledger (ahledger.com)',1,true))
    AHledgerAPI.GetPrice=function() return {median=-1,minBuyout=math.huge} end
    assert(AzerMind.AuctionItemDetails(2589)==nil)
  `);
  lua.lua_close(L);
});

test('compact auction summary keeps prices, provenance and snapshot status without verbose market data', t => {
  const vm = boot(t);
  vm.run(`
    date=function() return "2026-11-13 10:30" end
    AHledgerAPI={GetPrice=function() return {
      minBuyout=12000,median=13500,quantity=200,market="forever.pvp.horde.us",updated=1794440000,snapshot=true
    } end}
  `);
  const compact = vm.value('AzerMind.AuctionItemDetails(2589, true)');
  assert.match(compact, /Auction \/ unit: Min 1g 20s · Median 1g 35s/);
  assert.match(compact, /Bundled snapshot · 2026-11-13 10:30/);
  assert.match(compact, /Prices from AHledger \(ahledger.com\)/);
  assert.doesNotMatch(compact, /Listed quantity|Market:|0c|not a sale guarantee/);
  assert.equal(compact.split('\n').length, 4);
  const full = vm.value('AzerMind.AuctionItemDetails(2589)');
  assert.match(full, /Market: forever.pvp.horde.us/);
  assert.match(full, /Listed quantity: 200/);
  assert.match(full, /bundled snapshot; not live/);
  vm.run('AHledgerAPI.GetPrice=function() return {minBuyout=0,updated=0} end');
  assert.match(vm.value('AzerMind.AuctionItemDetails(2589, true)'), /Min 0c\nLast scan · unknown/);
  vm.run('AHledgerAPI.GetPrice=function() return {median=25} end');
  assert.match(vm.value('AzerMind.AuctionItemDetails(2589, true)'), /unit: Median 25c/);
  vm.run('AHledgerAPI.GetPrice=function() error("offline") end');
  assert.equal(vm.value('AzerMind.AuctionItemDetails(2589, true)'), 'nil');
});

test('actual item tooltip expands and collapses on Shift while AI attachments retain details', t => {
  const vm = boot(t);
  vm.run(`
    SHIFT=false; IsShiftKeyDown=function() return SHIFT end
    AHledgerAPI={GetPrice=function() return {minBuyout=12000,median=13500,quantity=200,market="test-market"} end}
    AzerMind.OwnedItems=function() return {{key="bags:1",id=2589,link="item:2589",location="Bags",name="Linen Cloth",kind="",subtype="",slot="",count=1}} end
    TOOLTIP_LINES={}
    GameTooltip.ClearLines=function() TOOLTIP_LINES={} end
    GameTooltip.AddLine=function(_,text) TOOLTIP_LINES[#TOOLTIP_LINES+1]=text end
    AzerMind.ShowItemPicker()
    ROW=AzerMindItemPicker.rows[1]
    ROW.scripts.OnEnter(ROW)
  `);
  assert.match(vm.value('table.concat(TOOLTIP_LINES,"\\n")'), /Hold Shift for details/);
  assert.doesNotMatch(vm.value('table.concat(TOOLTIP_LINES,"\\n")'), /Market:/);
  vm.run('SHIFT=true; ROW.scripts.OnUpdate(ROW)');
  assert.match(vm.value('table.concat(TOOLTIP_LINES,"\\n")'), /Market: test-market/);
  vm.run('SHIFT=false; ROW.scripts.OnUpdate(ROW)');
  assert.doesNotMatch(vm.value('table.concat(TOOLTIP_LINES,"\\n")'), /Market:/);
  vm.run('ROW.scripts.OnLeave(ROW)');
  assert.equal(vm.value('ROW.scripts.OnUpdate'), 'nil');
  assert.equal(vm.value('GameTooltip:IsShown()'), 'false');
  // Manual item attachments use the full default formatter, independent of Shift.
  vm.run(`
    ATTACHED=nil
    AzerMind.AppendQuestDraft=function(text) ATTACHED=text; return true end
    AzerMindItemPicker.selected["bags:1"]=true
    AzerMindItemPicker.insert.scripts.OnClick(AzerMindItemPicker.insert)
  `);
  assert.match(vm.value('ATTACHED'), /Market: test-market/);
});

test('credits are reachable from Settings, copyable and return without losing unsaved edits', t => {
  const vm = boot(t);
  vm.run(`
    AzerMind.CodexPrompt()
    for _,side in ipairs(AzerMindGeneralSettings.children) do
      for _,button in ipairs(side.children or {}) do
        if button.text=="About & credits" then CREDITS_BUTTON=button end
      end
    end
    AzerMindGeneralSettings.dirty=true
    CREDITS_BUTTON.scripts.OnClick(CREDITS_BUTTON)
  `);
  assert.equal(vm.value('AzerMindCreditsSettings'), 'nil');
  assert.equal(vm.value('AzerMindGeneralSettings.dirty'), 'true');
  vm.run('AzerMindGeneralSettings.dirty=false; CREDITS_BUTTON.scripts.OnClick(CREDITS_BUTTON)');
  assert.equal(vm.value('AzerMindCreditsSettings:IsShown()'), 'true');
  assert.equal(vm.value('AzerMindGeneralSettings:IsShown()'), 'false');
  const credits = vm.value('AzerMindCreditsSettings.creditText');
  for (const name of ['chelinho139', 'AHledger', 'GearQuest', 'ForeverDungeonJournal', 'Questie', '0xInuarashi', 'Gethe', 'Blizzard']) assert.ok(credits.includes(name), name);
  vm.run(`
    for _,button in ipairs(AzerMindCreditsSettings.children) do
      if button.text=="Copy credits" then button.scripts.OnClick(button) end
    end
  `);
  assert.equal(vm.value('AzerMindCopyBox:GetText()'), credits);
  vm.run('AzerMindCopy:Hide(); AzerMindCreditsSettings:Hide()');
  assert.equal(vm.value('AzerMindGeneralSettings:IsShown()'), 'true');
});
