'use strict';
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
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
