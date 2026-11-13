-- A minimal stand-in for the WoW addon environment, enough to load and drive
-- AzerMind.lua outside the game (see addon_test.js). Frames are plain tables:
-- capitalized names that aren't listed below resolve to a no-op method, so any
-- SetFoo/EnableBar call is accepted; lowercase names are ordinary fields.
--
-- STUB collects what the addon did: frames, texts, timers, tickers, prints.

STUB = {
	frames = {}, texts = {}, timers = {}, tickers = {}, prints = {}, bindings = {},
	now = 1000, epoch = 1700000000, sounds = {}, loaded = {}, reloaded = false,
	tooltips = {}, zone = "Duskwood", subzone = "Darkshire", level = 23, money = 12345,
}

local function noop() end
STUB.unsupportedCalls={}
STUB.strictUI=false
unpack = unpack or table.unpack -- WoW exposes the Lua 5.1 global; Fengari uses 5.3.

local Methods = {}
local FrameMT = {
	__index = function(t, k)
		if type(k) == "string" and k:match("^%u") then
			if Methods[k] then return Methods[k] end
            return function(...)
                STUB.unsupportedCalls[k]=(STUB.unsupportedCalls[k] or 0)+1
                if STUB.strictUI then error("Unmodeled WoW API: "..k) end
            end
		end
	end,
}

local function NewObject(kind, name, parent)
	local o = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, hooks = {}, events = {}, shown = true, textures = {}, children = {} }, FrameMT)
	if name then _G[name] = o end
	if parent and type(parent) == "table" and parent.children then table.insert(parent.children, o) end
	return o
end

function Methods.SetScript(self, name, fn) self.scripts[name] = fn end
function Methods.GetScript(self, name) return self.scripts[name] end
function Methods.HookScript(self, name, fn) self.hooks[name] = self.hooks[name] or {}; table.insert(self.hooks[name], fn) end
function Methods.RegisterEvent(self, ev) self.events[ev] = true end
function Methods.UnregisterEvent(self, ev) self.events[ev] = nil end
function Methods.Show(self) self.shown = true end
function Methods.Hide(self)
	local was = self.shown
	self.shown = false
	if was then
        if self.scripts.OnHide then self.scripts.OnHide(self) end
        for _,hook in ipairs(self.hooks.OnHide or {}) do hook(self) end
    end
end
function Methods.SetShown(self, v) if v then self:Show() else self:Hide() end end
function Methods.IsShown(self) return self.shown end
function Methods.IsVisible(self)
 local node=self
 while node do if node.shown==false then return false end;node=node.parent end
 return true
end
function Methods.SetText(self, t) self.text = t; if self.fontString then self.fontString.text=t end; table.insert(STUB.texts, tostring(t)) end
function Methods.GetText(self) return self.text or "" end
function Methods.SetChecked(self,value) self.checked=value and true or false end
function Methods.GetChecked(self) return self.checked or false end
function Methods.GetName(self) return self.name end
function Methods.GetParent(self) return self.parent end
function Methods.GetWidth(self) return self.width or 400 end
function Methods.GetHeight(self) return self.height or 300 end
function Methods.SetScale(self, value) self.scale = value end
function Methods.GetScale(self) return self.scale or 1 end
function Methods.GetFrameLevel(self) return self.frameLevel or 1 end
function Methods.SetFrameLevel(self, value) self.frameLevel = value end
function Methods.SetSize(self, w, h) self.width, self.height = w, h end
function Methods.SetWidth(self, w) self.width = w end
function Methods.SetHeight(self, h) self.height = h end
function Methods.GetSize(self) return self:GetWidth(), self:GetHeight() end
function Methods.SetScrollChild(self, child) self.scrollChild=child end
function Methods.GetScrollChild(self) return self.scrollChild end
function Methods.SetResizeBounds(self, minW, minH, maxW, maxH) self.resizeBounds={minW,minH,maxW,maxH} end
function Methods.GetStringHeight(self) return 14 end
function Methods.GetStringWidth(self) return 100 end
function Methods.SetFontString(self, region) self.fontString=region end
function Methods.GetFontString(self) return self.fontString or self end
function Methods.GetPoint(self) return "CENTER", nil, "CENTER", 0, 0 end
function Methods.SetPoint(self, point, rel, relPoint, x, y)
	if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, self.parent, point end
	if not rel then rel=self.parent end
	if type(relPoint)=="number" then x,y,relPoint=relPoint,x,point end
	self.points=self.points or {}
	self.points[point]={relative=rel,relativePoint=relPoint or point,x=x or 0,y=y or 0}
	self.x, self.y = x or 0, y or 0
end
function Methods.ClearAllPoints(self) self.points={} end
function Methods.SetAllPoints(self, relative)
	self:ClearAllPoints(); self:SetPoint("TOPLEFT",relative or self.parent,"TOPLEFT"); self:SetPoint("BOTTOMRIGHT",relative or self.parent,"BOTTOMRIGHT")
end
function Methods.GetVerticalScrollRange(self) return 0 end
function Methods.GetVerticalScroll(self) return self.verticalScroll or 0 end
function Methods.SetVerticalScroll(self,value) self.verticalScroll=value end
function Methods.CreateTexture(self, name, layer, template, sublevel)
	local t = NewObject("Texture", name, self)
	t.drawLayer,t.drawSublevel=layer,sublevel or 0
	table.insert(self.textures, t)
	return t
end
function Methods.CreateFontString(self, name) return NewObject("FontString", name, self) end
function Methods.CreateAnimationGroup(self) return NewObject("AnimationGroup", nil, self) end
function Methods.CreateAnimation(self) return NewObject("Animation", nil, self) end
function Methods.IsPlaying(self) return self.playing or false end
function Methods.Play(self) self.playing = true end
function Methods.Stop(self) self.playing = false end
function Methods.SetColorTexture(self, r, g, b, a) self.color = { r, g, b, a } end
function Methods.SetTexture(self, path) self.texture = path; return true end
function Methods.GetTexture(self) return self.texture end
function Methods.SetTexCoord(self, ...) self.texCoords = {...} end
function Methods.SetHorizTile(self, value) self.horizTile = value end
function Methods.SetVertTile(self, value) self.vertTile = value end
function Methods.SetAlpha(self, value) self.alpha=value end
function Methods.GetAlpha(self) return self.alpha or 1 end
function Methods.SetVertexColor(self, ...) self.vertexColor = {...} end
function Methods.SetTextColor(self, ...) self.textColor = {...} end
function Methods.SetShadowColor(self, ...) self.shadowColor = {...} end
function Methods.SetFont(self, file, size, flags) self.font={file=file,size=size,flags=flags} end
function Methods.GetRegions(self) return unpack(self.textures) end
function Methods.IsEnabled(self) return self.enabled ~= false end
function Methods.SetEnabled(self, enabled)
	local was=self:IsEnabled(); self.enabled=not not enabled
	if was~=self.enabled then
		local event=self.enabled and "OnEnable" or "OnDisable"
		if self.scripts[event] then self.scripts[event](self) end
		for _,hook in ipairs(self.hooks[event] or {}) do hook(self) end
	end
end
function Methods.Enable(self) self:SetEnabled(true) end
function Methods.Disable(self) self:SetEnabled(false) end
function Methods.SetNormalTexture(self, texture) self.normalTexture=texture end
function Methods.SetPushedTexture(self, texture) self.pushedTexture=texture end
function Methods.SetDisabledTexture(self, texture) self.disabledTexture=texture end
function Methods.SetHighlightTexture(self, texture) self.highlightTexture=texture end
function Methods.GetThumbTexture(self) return self.thumbTexture end
function Methods.SetBackdrop(self, t)
	-- The real client would silently draw nothing; make it a test failure instead.
	assert(type(t) == "table", "SetBackdrop called with " .. tostring(t) .. " on " .. tostring(self.name or self.kind))
	self.backdrop = t
end
function Methods.SetFocus(self) STUB.focus = self end
function Methods.ClearFocus(self) if STUB.focus == self then STUB.focus = nil end end
function Methods.HasFocus(self) return STUB.focus == self end
function Methods.Insert(self, t) self.text = (self.text or "") .. tostring(t) end
function Methods.GetEditBox(self) return self.editBox end
-- Tooltip scanning: SetHyperlink fills <name>TextLeft<i> / TextRight<i> from
-- STUB.tooltips[link], a list of strings or { left, right } pairs.
function Methods.ClearLines(self) self.lines = {} end
function Methods.NumLines(self) return #(self.lines or {}) end
function Methods.SetHyperlink(self, link)
	self.lines = STUB.tooltips[link] or {}
	for i, l in ipairs(self.lines) do
		local left, right = l, nil
		if type(l) == "table" then left, right = l[1], l[2] end
		local L = NewObject("FontString", self.name .. "TextLeft" .. i, self)
		L.text = left
		local R = NewObject("FontString", self.name .. "TextRight" .. i, self)
		R.text = right
		R.shown = right ~= nil
	end
end

function CreateFrame(kind, name, parent, template)
	local f = NewObject(kind, name, parent)
	f.template = template
	if template=="UIPanelScrollFrameTemplate" then
		f.ScrollBar=NewObject("Slider",name and name.."ScrollBar",f)
		f.ScrollBar.thumbTexture=f.ScrollBar:CreateTexture(nil,"ARTWORK")
		f.ScrollBar.ScrollUpButton=NewObject("Button",nil,f.ScrollBar)
		f.ScrollBar.ScrollDownButton=NewObject("Button",nil,f.ScrollBar)
	end
	table.insert(STUB.frames, f)
	return f
end

-- Fire an event on every frame that registered for it.
function STUB.FireEvent(ev, ...)
	for _, f in ipairs(STUB.frames) do
		if f.events[ev] and f.scripts.OnEvent then f.scripts.OnEvent(f, ev, ...) end
	end
end

-- Run every C_Timer.After callback that is due, then every ticker once.
function STUB.RunTimers()
	local due = STUB.timers
	STUB.timers = {}
	for _, t in ipairs(due) do t.fn() end
end
function STUB.Tick()
	for _, fn in ipairs(STUB.tickers) do fn() end
end

UIParent = CreateFrame("Frame", "UIParent")
GameTooltip = CreateFrame("Frame", "GameTooltip")
UIErrorsFrame = CreateFrame("Frame", "UIErrorsFrame")
ChatFontNormal = {}
OKAY, CANCEL = "Okay", "Cancel"
NUM_CHAT_WINDOWS = 1
StaticPopupDialogs = {}
function StaticPopup_Show(which, a, b, data) STUB.popup = { which = which, data = data } end
SlashCmdList = {}
UISpecialFrames = {}
tinsert = table.insert
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc(a, b, c)
	if type(a) == "table" then
		local orig = a[b]
		a[b] = function(...) local r = orig(...); c(...); return r end
	else
		local orig = _G[a]
		_G[a] = function(...) local r = orig(...); b(...); return r end
	end
end
function InCombatLockdown() return false end
function ReloadUI() STUB.reloaded = true end
function GetTime() return STUB.now end
function time() return STUB.epoch + math.floor(STUB.now) end
function date(fmt, t) return "12:00" end
C_Timer = {
	After = function(delay, fn) table.insert(STUB.timers, { delay = delay, fn = fn }) end,
	NewTicker = function(delay, fn) table.insert(STUB.tickers, fn); return { Cancel = noop } end,
}
C_AddOns = {
	IsAddOnLoaded = function(name) return STUB.loaded[name] or false end,
	LoadAddOn = function(name)
		STUB.loaded[name] = true
		if STUB.onLoadAddOn then STUB.onLoadAddOn(name) end
		return true
	end,
}
C_Texture = { GetAtlasExists = function() return true end }
function PlaySound() end
function PlaySoundFile(path) if STUB.sounds[path] then return true, 1 end return false end
function StopSound() end
function GetPhysicalScreenSize() return 1920, 1080 end
function SetBinding(key, cmd) STUB.bindings[key] = cmd end
function SaveBindings() end
function GetCurrentBindingSet() return 1 end
function SetItemRef() end
-- Nothing of Blizzard's is ever active here, so the link goes nowhere unless the
-- addon takes it. The Forever client's UI code calls ChatFrameUtil.InsertLink;
-- ChatEdit_InsertLink is the older global name.
ChatFrameUtil = { InsertLink = function(text) return false end }
function ChatEdit_InsertLink(text) return ChatFrameUtil.InsertLink(text) end

-- The character, for the game context (AzerMind.GameContext).
function GetBuildInfo() return "1.60.1", "69913", "Sep 1 2026", 16001 end
function UnitName(unit) if unit == "player" then return "Testchar" end end
function GetRealmName() return "Test Realm" end
function UnitLevel(unit) return STUB.level end
function UnitRace(unit) return "Night Elf", "NightElf" end
function UnitClass(unit) return "Hunter", "HUNTER" end
function UnitFactionGroup(unit) return "Alliance", "Alliance" end
function GetGuildInfo(unit) return "Test Guild", "Member", 1 end
function GetZoneText() return STUB.zone end
function GetSubZoneText() return STUB.subzone end
function GetMoney() return STUB.money end
C_Map = {
	GetBestMapForUnit = function(unit) return 1431 end,
	GetPlayerMapPosition = function(mapId, unit) return { x = STUB.posX or 0.452, y = STUB.posY or 0.678 } end,
	GetMapInfo = function(mapId) return { name = "Duskwood", mapID = mapId } end,
}
function UnitXP(unit) return 1234 end
function UnitXPMax(unit) return 5000 end
function GetNumTalentTabs() return 3 end
function GetTalentTabInfo(i)
	local tabs = { { "Beast Mastery", 10 }, { "Marksmanship", 5 }, { "Survival", 0 } }
	return tabs[i][1], "Interface\\Icons\\x", tabs[i][2]
end
TRADE_SKILLS, SECONDARY_SKILLS = "Professions", "Secondary Skills"
local SKILLS = {
	{ "Class Skills", true }, { "Bows", false, 46, 115 },
	{ "Professions", true }, { "Skinning", false, 75, 75 },
	{ "Secondary Skills", true }, { "First Aid", false, 40, 75 },
	{ "Weapon Skills", true }, { "Swords", false, 10, 115 },
}
function GetNumSkillLines() return #SKILLS end
function GetSkillLineInfo(i)
	local s = SKILLS[i]
	return s[1], s[2] or nil, false, s[3], 0, 0, s[4]
end
ITEM_QUALITY2_DESC = "Uncommon"
C_Item = {
	GetItemInfo = function(link)
		if tostring(link):find("^item:2140") then return "Fine Longsword", link, 2, 19, 14, "Weapon", "One-Handed Swords" end
	end,
}
function print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	table.insert(STUB.prints, table.concat(parts, " "))
end

function Methods.SetMinMaxValues(self,minimum,maximum) self.minimum,self.maximum=minimum,maximum end
function Methods.SetValue(self,value)
 self.value=math.max(self.minimum or value,math.min(self.maximum or value,value))
 if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,self.value) end
end
function Methods.GetValue(self) return self.value end
function Methods.SetIgnoreParentAlpha(self,value) self.ignoreParentAlpha=value end

-- Visual semantics that must never be substituted with permissive no-ops.
function Methods.GetEffectiveAlpha(self)
 local alpha,node=1,self
 while node do
  alpha=alpha*(node.alpha or 1)
  if node.ignoreParentAlpha then break end
  node=node.parent
 end
 return alpha
end
function Methods.SetDrawLayer(self,layer,sublevel) self.drawLayer,self.drawSublevel=layer,sublevel or 0 end
function Methods.SetClipsChildren(self,value) self.clipsChildren=value end
function Methods.SetRotation(self,value) self.rotation=value end
function Methods.EnableMouse(self,value) self.mouseEnabled=value end
function Methods.SetScale(self,value) self.scale=value end
function Methods.GetScale(self) return self.scale or 1 end
function Methods.SetFrameStrata(self,value) self.strata=value end
function Methods.GetFrameStrata(self) return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
function Methods.SetJustifyH(self,value) self.justifyH=value end
function Methods.SetJustifyV(self,value) self.justifyV=value end

-- Record native window policy; this mock does not rasterize overlapping addons.
function Methods.SetToplevel(self,value) self.toplevel=value end
function Methods.SetFlattensRenderLayers(self,value) self.flattensRenderLayers=value end
function Methods.Raise(self) self.raiseCount=(self.raiseCount or 0)+1 end
