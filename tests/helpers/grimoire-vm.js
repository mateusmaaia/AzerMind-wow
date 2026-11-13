'use strict';
const fs=require('node:fs'),path=require('node:path');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
module.exports=function boot(t) {
  const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);t.after(()=>lua.lua_close(L));
  function run(code,arg) {
    if(lauxlib.luaL_loadstring(L,to_luastring(code))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
    if(arg!==undefined)lua.lua_pushstring(L,to_luastring(arg));
    if(lua.lua_pcall(L,arg===undefined?0:1,0,0)!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
  }
  function value(expr) {
    run(`local v=(${expr}); TEST_RESULT=v==nil and "nil" or tostring(v)`);
    lua.lua_getglobal(L,to_luastring('TEST_RESULT'));const v=to_jsstring(lua.lua_tostring(L,-1));lua.lua_pop(L,1);return v;
  }
  run(fs.readFileSync(path.join(__dirname,'../wow_stub.lua'),'utf8'));
  run('UIParent:SetSize(1920,1080)');
  const folder=path.join(__dirname,'../../addon/AzerMind');
  for(const f of ['Codec.lua','Inbox.lua','Theme.lua','AzerMind.lua','TalentContext.lua','Links.lua','Settings.lua','Quests.lua','Catalog.lua','Auction.lua','Items.lua','InstancesData.lua','Instances.lua','GearQuestContext.lua','JournalContext.lua','GearIntelligence.lua'])run(fs.readFileSync(path.join(folder,f),'utf8'),'AzerMind');
  run('STUB.FireEvent("ADDON_LOADED","AzerMind"); STUB.FireEvent("PLAYER_LOGIN"); AzerMind.Toggle(true)');
  return {run,value,num:expr=>Number(value(expr))};
};
