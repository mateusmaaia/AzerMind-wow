-- AzerMind: talk to local coding agents (Claude Code, Codex, Grok) from inside WoW,
-- without reloading.
--
-- The WoW sandbox has no network and no file reads at runtime. Two doors remain open:
--
--   OUT ("pixel" mode): pending messages are drawn as a strip of colored squares in
--        the top-left corner of the screen until the bridge acknowledges them.
--        bridge.js screen-captures that corner and decodes it. Nothing touches the game.
--   IN:  load-on-demand addons read their files from disk at the moment they load.
--        The bridge writes the latest replies for every chat into a pool of pre-made
--        slot addons (AzerMind_S001..S200); we load a fresh slot from a timer.
--        Each slot is single-use per session; a /reload frees them all.
--   Fallback ("reload" mode): SavedVariables + Inbox.lua, a ReloadUI() per step.
--
-- Chats: each chat is its own agent session (like a separate terminal) with its own
-- folder, agent, history and pending message. The bridge runs them in parallel.
-- Everything here is plain addon API. No automation, no memory reading.

local ADDON_NAME = ...
local AzerMind = {}
_G.AzerMind = AzerMind
local Codec = AzerMind_Codec

local DEFAULT_CWD = "" -- empty = the bridge's configured defaultCwd
local MAX_HISTORY = 200
local MAX_CHATS = 16

local SLOT_COUNT = 200
local SLOT_PREFIX = "AzerMind_S"
local ACT_MAX = 60 -- heartbeat files per message (act/NNN/01..60.wav)
local PRESENCE_MAX = 2000 -- presence/0001..2000.wav, one flipped by the bridge every 30 s
local STRIP_TRIES = 3 -- re-show an unacknowledged message this many times before falling back
local CELL, CELLS_PER_ROW, MAX_ROWS = 4, 200, 32
-- Keep the decoder geometry stable; smaller frames use more transport fragments.
local STRIP_PAYLOAD = math.floor(CELLS_PER_ROW * MAX_ROWS * Codec.BITS / 8) - 8
local FRAGMENT_BYTES = 1100
local STRIP_SECONDS = 120 -- max per message; it leaves the strip as soon as the bridge acknowledges
local POLL_SCHEDULE = { 5, 10, 16, 24, 34, 46, 60, 80, 100, 130, 160, 200, 240, 300 }
local POLL_TAIL = 60
local TICK_SECONDS = 2
local CONNECT_WAIT = 15 -- seconds the Connect button waits for the bridge before giving up
local HELLO_POLL_SCHEDULE = { 5, 10, CONNECT_WAIT }
local IDLE_POLL_SECONDS = 600 -- without the sound channel, spend one slot this often while idle to check the bridge
local RS, US = "\30", "\31" -- record / unit separators in the strip payload

local db
local ui = {}
-- Transport state for this UI session. outbound[id] = { chat, cwd, flags, text, sentAt, acked }
local run = { outbound = {} }

-- Shared window backdrop. Declared up here because ShowCopy (rendering section)
-- uses it too: a later `local` would be invisible there and resolve to a nil global.
local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- The assistant bubble is labelled with the agent that wrote it (see AgentName).
local ROLE_STYLE = AzerMindTheme and AzerMindTheme.roles or {
	user      = { label = "You",    color = { 0.49, 0.78, 1.00 }, bg = { 0.25, 0.45, 0.75, 0.16 } },
	assistant = { label = "AI",     color = { 1.00, 0.82, 0.25 }, bg = { 0.85, 0.70, 0.30, 0.10 } },
	system    = { label = "System", color = { 0.62, 0.62, 0.62 }, bg = { 0.50, 0.50, 0.50, 0.10 } },
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function ToHex(s)
	return (s:gsub(".", function(c)
		return string.format("%02x", c:byte())
	end))
end

-- Record fields use control characters as separators, so keep them out of the wire format.
local function Wire(s)
	local value = tostring(s or "")
	return (value:gsub("[\30\31]", " "))
end

-- Strip WoW markup without losing item names or tooltip attributes.
function AzerMind.PlainText(s)
	local text = tostring(s or "")
	text = text:gsub("|H[^|]+|h(.-)|h", "%1")
	text = text:gsub("|cn[%w_]+:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	return text
end

-- Keep attachments in storage and on the wire, out of the message bubble.
function AzerMind.MessageText(role, text)
	text = AzerMind.PlainText(text)
	if role == "user" then
		local start = text:find("\n\n--- Linked from the game ---", 1, true)
		if start then text = text:sub(1, start - 1) end
	elseif role == "assistant" then
		local start = text:find("\n%s*TL;DR:%s*\n")
		if start and text:sub(1, start - 1):find("%S") then text = text:sub(1, start - 1) end
	end
	return text
end

-- EditBoxes do not render UI escape sequences, so just make pipes harmless.
local function Display(s)
	s = AzerMind.PlainText(s)
	return (tostring(s or ""):gsub("|", "¦"))
end

local function Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function FmtDur(sec)
	sec = math.floor(sec or 0)
	if sec < 60 then return sec .. "s" end
	if sec < 3600 then return math.floor(sec / 60) .. "m" .. string.format("%02d", sec % 60) .. "s" end
	return math.floor(sec / 3600) .. "h" .. string.format("%02d", math.floor(sec / 60) % 60) .. "m"
end

-- Last path component of a folder, for labels.
local function FolderName(cwd)
	local name = tostring(cwd or ""):gsub("[\\/]+$", ""):match("([^\\/]+)$")
	return name or ""
end

-- The folder a chat works in: its own, or the bridge's default (the folder the
-- bridge was started from), which the bridge reports in every slot file.
local function ChatFolder(c)
	if c and c.cwd ~= "" then return c.cwd end
	return run.bridgeCwd or ""
end

-- Agents are named by id as the bridge knows them ("claude", "codex", "grok");
-- the bridge lists the ones it has, and its default, in every slot file. A chat
-- with no agent of its own runs on the bridge's default.
local AGENT_NAMES = { claude = "Claude", codex = "Codex", grok = "Grok", agy = "Antigravity", hermes = "Hermes" }

local function AgentName(id)
	id = tostring(id or "")
	if id == "" then return "AI" end
	return AGENT_NAMES[id] or (id:sub(1, 1):upper() .. id:sub(2))
end

local function ChatAgent(c)
	if c and c.agent and c.agent ~= "" then return c.agent end
	return run.bridgeAgent or ""
end

local function ChatAgentName(c)
	return AgentName(ChatAgent(c))
end

-- The name to show on a reply: the agent the bridge says wrote it, else the chat's.
local function ReplyAgentName(c, agent)
	if agent and agent ~= "" then return AgentName(agent) end
	return ChatAgentName(c)
end

local function Contains(list, v)
	for _, x in ipairs(list or {}) do
		if x == v then return true end
	end
	return false
end

-- First few words of a message, as a chat title.
local function AutoTitle(text)
	local words = {}
	for w in tostring(text or ""):gmatch("%S+") do
		w = w:gsub("^[%p]+", ""):gsub("[%p]+$", "")
		if w ~= "" then
			table.insert(words, w)
			if #words >= 5 then break end
		end
	end
	local title = table.concat(words, " ")
	if #title > 24 then title = title:sub(1, 24):gsub("%s+%S*$", "") end
	if title == "" then return nil end
	return title:sub(1, 1):upper() .. title:sub(2)
end

local function NewId()
	return string.format("%x%04x", time() % 0xFFFFFF, math.random(0, 0xFFFF))
end

local function FindChat(id)
	for i, c in ipairs(db.chats) do
		if c.id == id then return c, i end
	end
end

local function ActiveChat()
	return FindChat(db.activeChat)
end

local function AddChat(name, cwd)
	if #db.chats >= MAX_CHATS then return nil end
	local current = ActiveChat()
	local c = {
		id = NewId(),
		name = name or ("Chat " .. (#db.chats + 1)),
		cwd = cwd or (current and current.cwd) or DEFAULT_CWD,
		agent = (current and current.agent) or "",
		history = {},
		unread = 0,
		created = time(),
	}
	table.insert(db.chats, c)
	return c
end

local function AnyPending()
	for _, c in ipairs(db.chats) do
		if c.pendingId then return true end
	end
	return false
end

local function InitDB()
	AzerMindDB = AzerMindDB or {}
	db = AzerMindDB
	db.settings = db.settings or {}
	local s = db.settings
	local opacity=tonumber(s.opacity)
	s.opacity=(opacity and opacity==opacity) and math.max(0.35,math.min(1,opacity)) or 1
	if AzerMindTheme then AzerMindTheme.ApplyOpacity(s.opacity) end
	if s.autoRefresh == nil then s.autoRefresh = true end
	if s.signal == nil then s.signal = true end
	if s.contextMode ~= "full" and s.contextMode ~= "custom" then s.contextMode = "basic" end
	if s.context == nil then s.context = true end -- tell the agent about the character, zone, etc.
	-- How much of each reply to print in the game chat. "summary" (the agent's
	-- closing TL;DR lines) replaced "full" as the default; an install that still
	-- has the old default saved moves over once, any other choice is kept.
	if not s.echoV2 then
		s.echoV2 = true
		if s.echo == "full" then s.echo = "summary" end
	end
	s.echo = s.echo or "summary"
	s.mode = s.mode or "pixel"
	s.interval = s.interval or 20
	s.cwd = s.cwd or DEFAULT_CWD
	s.width = s.width or 780
	s.height = s.height or 500
	db.lastSeq = db.lastSeq or 0
	-- Chats deleted in game that the bridge hasn't confirmed forgetting yet.
	db.forget = db.forget or {}
	-- Identifies this counter's lifetime. If the saved data is ever reset, a new
	-- session lets the bridge tell "message #1 again" from "message #1, already done".
	if not db.session then
		db.session = string.format("%x%04x%04x", time() % 0xFFFFFF, math.random(0, 0xFFFF), math.random(0, 0xFFFF))
	end
	if not db.chats then
		-- Migrate the single-chat layout into the first chat.
		db.chats = {}
		local c = {
			id = NewId(),
			name = "Chat 1",
			cwd = s.cwd,
			history = db.history or {},
			pendingId = db.pendingId,
			unread = db.unread or 0,
			draft = db.draft,
			created = time(),
		}
		table.insert(db.chats, c)
		db.activeChat = c.id
		db.history, db.pendingId, db.unread, db.draft = nil, nil, nil, nil
	end
	if #db.chats == 0 then AddChat() end
	if not FindChat(db.activeChat) then db.activeChat = db.chats[1].id end
	-- Chats from before agents had names: replies were stored with role "claude".
	for _, c in ipairs(db.chats) do
		c.agent = c.agent or ""
		for _, m in ipairs(c.history or {}) do
			if m.role == "claude" then m.role, m.agent = "assistant", m.agent or "claude" end
		end
	end
end

local function AddHistory(chat, role, text, id, denied, agent, macros)
	table.insert(chat.history, { role = role, text = text, id = id, t = time(), denied = denied, agent = agent, macros = macros })
	while #chat.history > MAX_HISTORY do
		table.remove(chat.history, 1)
	end
end

local function SlotName(i)
	return string.format("%s%03d", SLOT_PREFIX, i)
end

local function SlotNumber(id)
	return ((id - 1) % SLOT_COUNT) + 1
end

---------------------------------------------------------------------------
-- Reload plumbing (fallback path)
---------------------------------------------------------------------------

local function SafeReload()
	if InCombatLockdown() then
		AzerMind.reloadAfterCombat = true
		if ui.status then
			ui.status:SetText("In combat - will reload as soon as it ends")
		end
		return
	end
	ReloadUI()
end

-- ReloadUI() only works from a hardware event (a keypress or click), never from
-- a timer. So the automatic reload piggybacks on the player's own next keypress
-- once the interval has elapsed. The key still reaches the game normally.
local keyCatcher = CreateFrame("Frame", "AzerMindKeyCatcher", UIParent)
keyCatcher:Hide()
keyCatcher:EnableKeyboard(true)
keyCatcher:SetScript("OnKeyDown", function(self, key)
	if db and AnyPending() and db.settings.autoRefresh
		and GetTime() >= (AzerMind.nextAutoRefresh or 0)
		and not InCombatLockdown() then
		self:Hide()
		ReloadUI()
	end
end)

-- Arm the keypress reload. In pixel mode this is only used once the slot pool
-- is exhausted (a reload frees every slot) or the slots are not installed.
function AzerMind.ArmAutoRefresh()
	keyCatcher:Hide()
	if not AnyPending() or not db.settings.autoRefresh then return end
	if db.settings.mode == "pixel" and not (run.slotsExhausted or run.slotsMissing or run.pixelFailed) then return end
	-- Propagation can't be changed in combat. Never show the catcher without it,
	-- or it would eat every keypress. PLAYER_REGEN_ENABLED re-arms after combat.
	if not keyCatcher.propagates then
		if InCombatLockdown() or not keyCatcher.SetPropagateKeyboardInput then return end
		keyCatcher:SetPropagateKeyboardInput(true)
		keyCatcher.propagates = true
	end
	AzerMind.nextAutoRefresh = GetTime() + db.settings.interval
	keyCatcher:Show()
end

---------------------------------------------------------------------------
-- Pixel strip (out)
---------------------------------------------------------------------------

local strip
local cellPool = {}
local stripPhysicalHeight

local function UpdateStripScale()
	if not strip then return end
	local physH = stripPhysicalHeight or 1080
	if GetPhysicalScreenSize then
		local _, h = GetPhysicalScreenSize()
		if type(h) == "number" and h > 0 and h < math.huge then physH = h end
	end
	if physH ~= stripPhysicalHeight then
		strip:SetScale(768 / physH)
		stripPhysicalHeight = physH
	end
end

local function EnsureStrip()
	if strip then return strip end
	strip = CreateFrame("Frame", "AzerMindStrip", UIParent)
	strip:SetFrameStrata("TOOLTIP")
	strip:SetFrameLevel(10000)
	-- Scale so that one UI unit is exactly one physical pixel (see Blizzard's PixelUtil).
	if strip.SetIgnoreParentScale then strip:SetIgnoreParentScale(true) end
	UpdateStripScale()
	strip:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	strip:SetSize(CELLS_PER_ROW * CELL, MAX_ROWS * CELL)
	strip:Hide()
	return strip
end

local function HideStrip()
	if strip then strip:Hide() end
	run.stripShown = nil
end

local function ShowStrip(id, payload)
	local cells = Codec.Encode(id % 65536, payload)
	local s = EnsureStrip()
	UpdateStripScale()
	local rows = math.ceil(#cells / CELLS_PER_ROW)
	s:SetSize(CELLS_PER_ROW * CELL, rows * CELL)
	local total = #cells
	for i = 1, total do
		local t = cellPool[i]
		if not t then
			t = s:CreateTexture(nil, "OVERLAY")
			t:SetSize(CELL, CELL)
			local c = (i - 1) % CELLS_PER_ROW
			local r = math.floor((i - 1) / CELLS_PER_ROW)
			t:SetPoint("TOPLEFT", s, "TOPLEFT", c * CELL, -r * CELL)
			cellPool[i] = t
		end
		local cr, cg, cb = Codec.CellColor(cells[i] or 0)
		t:SetColorTexture(cr, cg, cb, 1)
		t:Show()
	end
	for i = total + 1, #cellPool do
		cellPool[i]:Hide()
	end
	s:Show()
	run.stripShown = true
end

-- Record: session, chat, id, cwd, flags, name, [context,] text. Several records
-- per frame. The context field is only present when the flags carry "c", so the
-- bridge can tell it from a separator inside the text.
local function RecordFor(id, rec)
	local flags = Wire(rec.flags)
	local fields = { Wire(db.session), Wire(rec.chat), tostring(id), Wire(rec.cwd), flags, Wire(rec.name) }
	if rec.ctx ~= nil then
		fields[5] = flags == "" and "c" or (flags .. ";c")
		table.insert(fields, Wire(rec.ctx))
	end
	table.insert(fields, Wire(rec.text))
	return table.concat(fields, US)
end

-- Redraw the strip from every outbound message the bridge hasn't acknowledged.
local function RefreshStrip()
	local ids = {}
	for id, rec in pairs(run.outbound) do
		if not rec.acked then table.insert(ids, id) end
	end
	if #ids == 0 then
		HideStrip()
		return
	end
	table.sort(ids)
	-- Newest first; drop the oldest if the frame would overflow.
	local parts, size, latest = {}, 0, ids[#ids]
	for i = #ids, 1, -1 do
		local r = RecordFor(ids[i], run.outbound[ids[i]])
		if #r > STRIP_PAYLOAD then
			-- Hex chunks preserve UTF-8 bytes even when a boundary splits a character.
			local count = math.ceil(#r / FRAGMENT_BYTES)
			local part = math.floor(GetTime() / 0.75) % count + 1
			local payload = table.concat({ "F1", Wire(db.session), tostring(ids[i]), tostring(part), tostring(count), ToHex(r:sub((part - 1) * FRAGMENT_BYTES + 1, part * FRAGMENT_BYTES)) }, US)
			ShowStrip(ids[i], payload)
			return
		end
		if size + #r + 1 > STRIP_PAYLOAD then break end
		table.insert(parts, 1, r)
		size = size + #r + 1
	end
	ShowStrip(latest, table.concat(parts, RS))
end

---------------------------------------------------------------------------
-- Signals and slots (in)
---------------------------------------------------------------------------

-- Optional cheap poll: an empty .wav won't play, a valid one will. The bridge
-- fills sig/NNN.wav when reply NNN is ready. Self-disables if it misbehaves.
local signalAvailable = type(PlaySoundFile) == "function"
local signalStats = { checks = 0, hits = 0, lastHit = nil }

local function SoundValid(path)
	if not signalAvailable or not db.settings.signal then return false end
	signalStats.checks = signalStats.checks + 1
	local ok, willPlay, handle = pcall(PlaySoundFile, path, "Master")
	if not ok then
		signalAvailable = false
		signalStats.error = tostring(willPlay)
		return false
	end
	if willPlay and handle then pcall(StopSound, handle) end
	if willPlay then
		signalStats.hits = signalStats.hits + 1
		signalStats.lastHit = GetTime()
	end
	return willPlay and true or false
end

local function CheckSignal(kind, id)
	if run.signalUnreliable then return false end
	return SoundValid(string.format("Interface\\AddOns\\AzerMind\\%s\\%03d.wav", kind, SlotNumber(id)))
end

-- Heartbeat: the bridge flips act/NNN/kk.wav for the k-th action of message NNN.
local function ActPath(id, k)
	return string.format("Interface\\AddOns\\AzerMind\\act\\%03d\\%02d.wav", SlotNumber(id), k)
end

local function StartActivity(chat, id)
	local a = { next = 1, count = 0, startedAt = GetTime() }
	-- The bridge can't have written anything yet, so a valid first file means the
	-- client cached this slot number's files from an earlier use: don't trust them.
	if SoundValid(ActPath(id, 1)) then a.unreliable = true end
	run.act = run.act or {}
	run.act[chat.id] = a
end

-- Returns true if the counter moved.
local function PollActivity(chat)
	local a = run.act and run.act[chat.id]
	if not a or a.unreliable or not chat.pendingId then return false end
	local moved = false
	for _ = 1, 3 do
		if a.next > ACT_MAX then break end
		if not SoundValid(ActPath(chat.pendingId, a.next)) then break end
		a.count = a.count + 1
		a.next = a.next + 1
		a.last = GetTime()
		moved = true
	end
	return moved
end

-- Bridge presence. Evidence the bridge is alive comes from several places:
-- presence beats, acks, slot data (which carries the bridge's clock), replies.
local function NotedBridge(at)
	at = at or GetTime()
	if not run.bridgeSeen or at > run.bridgeSeen then run.bridgeSeen = at end
	run.pixelFailed = nil
end

local function PresencePath(k)
	return string.format("Interface\\AddOns\\AzerMind\\presence\\%04d.wav", k)
end

-- Valid presence files form a prefix 1..k, so a binary search finds the head.
local function FindPresenceHead()
	local lo, hi = 0, PRESENCE_MAX
	while lo < hi do
		local mid = math.ceil((lo + hi) / 2)
		if SoundValid(PresencePath(mid)) then lo = mid else hi = mid - 1 end
	end
	return lo
end

local function PollPresence()
	if not signalAvailable or not db.settings.signal then return end
	run.presence = run.presence or { last = FindPresenceHead() }
	local p = run.presence
	for _ = 1, 3 do
		local k = (p.last % PRESENCE_MAX) + 1
		if not SoundValid(PresencePath(k)) then break end
		p.last = k
		p.beats = (p.beats or 0) + 1
		NotedBridge()
	end
end

-- Whether the 30-second presence beats can reach us at all. When they can't
-- (self-test failed, or signal checks turned off), the only evidence of the
-- bridge is a slot read: the idle poll below and the replies themselves.
local function PresenceWorks()
	return signalAvailable and db ~= nil and db.settings.signal
end

-- Returns state ("ok" | "stale" | "down" | "unknown"), a color and a description.
-- With presence beats the bridge is heard from every 30 s, so 90 s of silence is
-- suspicious. Without them the addon only hears from it every IDLE_POLL_SECONDS,
-- so the windows have to be wider or the light could never stay green between
-- messages and every reply would be followed by a Reconnect.
function AzerMind.BridgeState()
	local seen = run.bridgeSeen
	if not seen then
		return "unknown", 0.6, 0.6, 0.6, "Bridge: not seen yet this session"
	end
	local age = GetTime() - seen
	local okFor, staleFor = 90, 300
	if not PresenceWorks() then
		okFor, staleFor = IDLE_POLL_SECONDS + 120, IDLE_POLL_SECONDS * 2 + 120
	end
	if age < okFor then
		return "ok", 0.2, 0.9, 0.3, "Bridge: connected (seen " .. FmtDur(age) .. " ago)"
	elseif age < staleFor then
		return "stale", 0.95, 0.8, 0.2, "Bridge: last seen " .. FmtDur(age) .. " ago"
	end
	return "down", 0.9, 0.25, 0.25, "Bridge: not seen for " .. FmtDur(age) .. " - is the bridge running?"
end

-- Same icons the friends list uses for online / away / busy / offline.
local STATE_ICON = {
	ok = "Interface\\FriendsFrame\\StatusIcon-Online",
	stale = "Interface\\FriendsFrame\\StatusIcon-Away",
	down = "Interface\\FriendsFrame\\StatusIcon-DnD",
	unknown = "Interface\\FriendsFrame\\StatusIcon-Offline",
}

function AzerMind.UpdateDot()
	local state, _, _, _, tip = AzerMind.BridgeState()
	if run.pixelFailed then state = "down" end
	if not signalAvailable and signalStats.selftest then
		tip = tip .. "\n(sound-file channel unavailable: " .. signalStats.selftest .. "; using slot checks only)"
	end
	for _, dot in ipairs({ ui.dot, ui.miniDot }) do
		if dot then
			dot:SetTexture(STATE_ICON[state] or STATE_ICON.unknown)
			if AzerMindTheme and AzerMindTheme.grimoire then
				local gem=state=="ok" and "connected" or (state=="stale" and "connecting" or "disconnected")
				dot:SetTexture(AzerMindTheme.artRoot.."gem-"..gem..".tga")
			end
			dot.tip = tip .. (run.statusText and ("\n"..run.statusText) or "")
		end
	end
end

-- Connected = the bridge has been seen recently. In pixel mode, sending needs this;
-- until then the Connect button takes the Send button's place. The reload
-- transport has no idea whether the bridge is there, so it never gates.
function AzerMind.IsConnected()
	if not db or db.settings.mode ~= "pixel" then return true end
	return AzerMind.BridgeState() == "ok" and not run.pixelFailed
end

-- Connect button: say hello to the bridge (it acks, refreshes the slots and
-- offers a restore), ignoring SayHello's throttle so a click always does something.
function AzerMind.Connect()
	if db.settings.mode ~= "pixel" then
		SafeReload()
		return
	end
	run.lastHelloAt = nil
	run.pixelFailed = nil
	run.connectFailed = nil
	run.connectingAt = GetTime()
	AzerMind.SayHello()
end

-- One word for the connection state, so Tick can tell when it changed.
local function ConnectionKey()
	if AzerMind.IsConnected() then return "ok" end
	if run.connectingAt then return "connecting" end
	if run.connectFailed then return "failed" end
	return AzerMind.BridgeState()
end

-- Called every tick: time out a Connect attempt, and redraw when the state flips
-- (light, button, status line, placeholder) without redrawing every tick.
function AzerMind.CheckConnection()
	if run.connectingAt then
		if AzerMind.IsConnected() then
			run.connectingAt, run.connectFailed = nil, nil
			-- A message typed while disconnected goes out now, without a second click,
			-- as long as the same chat is still in front and free.
			local queued = run.sendOnConnect
			run.sendOnConnect = nil
			local c = queued and ActiveChat()
			if c and c.id == queued.chat and not c.pendingId then
				if ui.input and Trim(ui.input:GetText() or "") == queued.text then ui.input:SetText("") end
				AzerMind.Send(queued.text, queued.allow)
			end
		elseif GetTime() - run.connectingAt > CONNECT_WAIT then
			run.connectingAt, run.connectFailed = nil, true
			run.sendOnConnect = nil -- the text is still in the box
		end
	elseif run.connectFailed and AzerMind.IsConnected() then
		run.connectFailed = nil
	end
	local key = ConnectionKey()
	if key ~= run.connKey then
		run.connKey = key
		AzerMind.Render()
	end
end

-- Swap Send and Connect depending on the state; part of UpdateStatus.
function AzerMind.UpdateConnect()
	if not ui.connect or not ui.send then return end
	local connected = AzerMind.IsConnected()
	local active = ActiveChat()
	ui.send:SetText(active and active.pendingId and "Stop" or "Send")
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.ActionIcon(ui.send,active and active.pendingId and "stop" or "send") end
	ui.send:SetShown(connected)
	ui.connect:SetShown(not connected)
	if connected then return end
	if run.connectingAt then
		ui.connect:SetText("Connecting...")
		ui.connect:Disable()
	else
		ui.connect:SetText(AzerMind.BridgeState() == "stale" and "Reconnect" or "Connect")
		ui.connect:Enable()
	end
end

-- Prove the sound-file trick actually distinguishes empty from valid files on this
-- client before trusting it for presence, heartbeats and readiness signals.
local function SelfTestSignals()
	if not signalAvailable then
		signalStats.selftest = "PlaySoundFile missing"
		return
	end
	local emptyLooksValid = SoundValid("Interface\\AddOns\\AzerMind\\ctl\\empty.wav")
	local validLooksValid = SoundValid("Interface\\AddOns\\AzerMind\\ctl\\valid.wav")
	if emptyLooksValid then
		signalAvailable = false
		signalStats.selftest = "an empty file reports as playable"
	elseif not validLooksValid then
		signalAvailable = false
		signalStats.selftest = "a valid file reports as unplayable (files not indexed? restart WoW)"
	else
		signalStats.selftest = "passed"
	end
end

local function ActivityLine(chat)
	local a = run.act and run.act[chat.id]
	local now = GetTime()
	local started = (a and a.startedAt) or run.sentAt or now
	local s = "running " .. FmtDur(now - started)
	if a and not a.unreliable then
		s = s .. " - " .. a.count .. (a.count == 1 and " action" or " actions")
		if a.last then
			local quiet = now - a.last
			s = s .. ", last " .. FmtDur(quiet) .. " ago"
			if quiet > 120 then s = s .. " (quiet for a while - stuck? /azermind cancel)" end
		elseif now - started > 60 then
			s = s .. ", no activity seen yet"
		end
	end
	return s
end

local function FreeSlot()
	for i = 1, SLOT_COUNT do
		local name = SlotName(i)
		if not C_AddOns.IsAddOnLoaded(name) then
			return name
		end
	end
end

local function ScheduleNextPoll()
	local idx = (run.polls or 0) + 1
	local t = POLL_SCHEDULE[idx]
	if not t then
		t = POLL_SCHEDULE[#POLL_SCHEDULE] + POLL_TAIL * (idx - #POLL_SCHEDULE)
	end
	run.nextPollAt = (run.sentAt or GetTime()) + t
end

local Finish -- defined below

-- The bridge has read this record: whatever game context rode on it is now
-- what the bridge knows, so later messages only carry it again if it changes.
local function NoteAcked(rec)
	rec.acked = true
	if rec.ctx ~= nil then run.contextSent = rec.ctx end
end

local function MarkAcked(id)
	local rec = run.outbound[id]
	if rec and not rec.acked then
		NoteAcked(rec)
		RefreshStrip()
	end
	NotedBridge()
end

-- Dispatch a list of reply records to the chats waiting for them.
local function ApplyReplies(replies)
	local matched = false
	for _, r in ipairs(replies or {}) do
		local outbound = run.outbound[r.id]
		if outbound and outbound.cancel and r.session == db.session and r.status == "cancel-ack" then MarkAcked(r.id) end
		if outbound and outbound.catalogRefresh and r.session==db.session and (r.status=="models-refreshed" or r.status=="models-error") then
			MarkAcked(r.id); run.modelsPending=nil
			if ui.codexSettings then ui.codexSettings.message=r.text; ui.codexSettings.Refresh() end
		end
		if outbound and outbound.settings and r.session == db.session and (r.status == "settings-saved" or r.status == "settings-error") then
			MarkAcked(r.id)
			run.settingsPending = nil
			if ui.codexSettings then
				ui.codexSettings.pending = false
				ui.codexSettings.dirty = r.status == "settings-error"
				ui.codexSettings.message = r.text
				if ui.codexSettings.Refresh then ui.codexSettings.Refresh() end
			end
		end
		if r.status == "ack" and r.session == db.session and outbound and outbound.forget == r.chat then
			MarkAcked(r.id)
			db.forget[r.chat] = nil
		end
		local c = FindChat(r.chat)
		if c and c.pendingId and r.id == c.pendingId then
			matched = true
			MarkAcked(r.id)
			local denied = type(r.denied) == "table" and #r.denied > 0 and r.denied or nil
			if r.status == "done" then
				Finish(c, "assistant", r.text or "", denied, r.agent, r.summary, AzerMind.CleanMacros(r.macros))
			elseif r.status == "error" then
				Finish(c, "system", "Bridge error: " .. tostring(r.text), denied)
			elseif r.status == "working" then
				c.progress = r.text
			end
		end
	end
	return matched
end

-- The bridge keeps every chat's transcript. After the client wipes our saved data,
-- it sends them back once, addressed to our new session token.
local function ImportRestore(r)
	if type(r) ~= "table" or r.token ~= db.session or db.restored then return end
	db.restored = true
	local added = 0
	local current = ActiveChat()
	for _, rc in ipairs(r.chats or {}) do
		-- Skip chats deleted here that the bridge hasn't been told about yet.
		if type(rc) == "table" and rc.id and not FindChat(rc.id) and not db.forget[rc.id] and #db.chats < MAX_CHATS then
			local chat = {
				id = rc.id,
				name = (rc.name and rc.name ~= "") and rc.name or ("Chat " .. (#db.chats + 1)),
				cwd = rc.cwd or DEFAULT_CWD,
				agent = "",
				history = {},
				unread = 0,
				created = time(),
			}
			for _, m in ipairs(rc.messages or {}) do
				local role, agent = m.role, m.agent
				if role == "claude" then role, agent = "assistant", agent or "claude" end -- an older bridge's transcript
				if agent == "" then agent = nil end
				table.insert(chat.history, { role = role, text = m.text, id = m.id, t = m.t, agent = agent })
			end
			-- Keep the chat we're currently using last so it stays where it was.
			table.insert(db.chats, math.max(1, #db.chats), chat)
			added = added + 1
		end
	end
	run.restoring = nil
	if added > 0 then
		if current and #current.history <= 2 then
			for _, ch in ipairs(db.chats) do
				if ch ~= current and ch.name == current.name then current.name = "New chat" end
			end
		end
		AddHistory(current, "system", "Restored " .. added .. " chat(s) from the bridge after the game reset the saved data.")
		AzerMind.RenderChatList()
	end
end

local function TryLoadSlot(why)
	local name = FreeSlot()
	if not name then
		run.slotsExhausted = true
		AzerMind.ArmAutoRefresh()
		AzerMind.UpdateStatus()
		return
	end
	AzerMind_SlotData = nil
	local loaded, reason = C_AddOns.LoadAddOn(name)
	if not loaded then
		run.slotError = reason
		if reason == "MISSING" or reason == "DISABLED" then
			run.slotsMissing = true
			AzerMind.ArmAutoRefresh()
		end
		AzerMind.UpdateStatus()
		return
	end
	run.polls = (run.polls or 0) + 1
	ScheduleNextPoll()
	local data = AzerMind_SlotData
	if type(data) == "table" and type(data.now) == "number" then
		-- The bridge's clock and ours are the same machine; translate to GetTime().
		NotedBridge(GetTime() - (time() - data.now))
	end
	if type(data) == "table" and type(data.cwd) == "string" and data.cwd ~= "" then run.bridgeCwd = data.cwd end
	if type(data) == "table" then
		if type(data.agent) == "string" and data.agent ~= "" then run.bridgeAgent = data.agent end
		if type(data.agents) == "table" and #data.agents > 0 then run.bridgeAgents = data.agents end
		if type(data.agentSettings) == "table" then run.agentSettings = data.agentSettings end
		if type(data.codexModels) == "table" then run.codexModels = data.codexModels end
		if type(data.aiDefaults) == "table" then run.aiDefaults = data.aiDefaults end
	end
	local matched = ApplyReplies(type(data) == "table" and data.replies or nil)
	if type(data) == "table" and data.restore then ImportRestore(data.restore) end
	if type(data) == "table" and data.map and AzerMindMap then AzerMindMap.Sync(data.map) end
	if why == "signal" and not matched then
		run.signalUnreliable = true
	end
	AzerMind.Render()
end

function AzerMind.UpdateLatency()
	if not ui.latency then return end
	local home, world
	if type(GetNetStats) == "function" then
		local ok, _, _, h, w = pcall(GetNetStats)
		if ok then home, world = h, w end
	end
	local function Value(v)
		return type(v) == "number" and v >= 0 and v < math.huge and string.format("%.0f", v) or "--"
	end
	ui.latency:SetText(Value(world or home) .. " ms")
	ui.latencyDetails = "Home " .. Value(home) .. " / World " .. Value(world) .. " ms"
end

local function PollHello(now)
	local hello = run.helloPoll
	if not hello or now < hello.startedAt + HELLO_POLL_SCHEDULE[hello.index] then return end
	run.helloPoll = nil
	-- The deadline poll can fall on the next tick when Connect was clicked
	-- between ticks. CheckConnection runs after this poll.
	if now > hello.startedAt + CONNECT_WAIT + TICK_SECONDS then return end
	-- The first poll can carry a restore or metadata even if a sound file
	-- already proved the bridge is alive.
	if hello.index > 1 and run.bridgeSeen and run.bridgeSeen >= hello.startedAt then return end
	TryLoadSlot("hello")
	if run.restoring then
		run.restoring = nil
		AzerMind.Render()
	end
	if run.slotsExhausted or run.slotsMissing or (run.bridgeSeen and run.bridgeSeen >= hello.startedAt) then return end
	for index = hello.index + 1, #HELLO_POLL_SCHEDULE do
		if hello.startedAt + HELLO_POLL_SCHEDULE[index] > now then
			hello.index = index
			run.helloPoll = hello
			break
		end
	end
end

local function Tick()
	if not db then return end
	local now = GetTime()
	if ui.frame and ui.frame:IsShown() and now >= (run.nextLatency or 0) then
		AzerMind.UpdateLatency(); run.nextLatency = now + 5
	end
	PollPresence()
	-- Without presence beats, the only evidence is a slot read; spend one every
	-- IDLE_POLL_SECONDS while idle so the light still reflects reality (and stays
	-- green while the bridge is up: BridgeState allows for this interval).
	if not PresenceWorks() and db.settings.mode == "pixel" and not AnyPending()
		and now - (run.lastIdlePoll or -1e9) >= IDLE_POLL_SECONDS then
		run.lastIdlePoll = now
		TryLoadSlot("idle")
	end
	if db.settings.mode == "pixel" then PollHello(now) end
	AzerMind.UpdateDot()
	AzerMind.CheckConnection()
	if db.settings.mode ~= "pixel" then return end
	local changed = false
	if run.restoring and now - run.restoring > 25 then
		run.restoring = nil
		AzerMind.Render()
	end
	-- Control messages have no waiting chat, so poll their explicit receipts too.
	for _, rec in pairs(run.outbound) do
		if (rec.forget or rec.settings or rec.catalogRefresh or rec.cancel) and not rec.acked and now - rec.sentAt >= 2
			and now - (run.lastControlPoll or -1e9) >= 4 then
			run.lastControlPoll = now
			TryLoadSlot("control")
			break
		end
	end
	for id, rec in pairs(run.outbound) do
		if not rec.settings and not rec.catalogRefresh and not rec.cancel and not rec.acked and CheckSignal("ack", id) then
			NoteAcked(rec)
			changed = true
			NotedBridge()
		end
		-- A hello only needs the bridge to have been seen; it never escalates.
		-- A forget is the same, but the bridge must have been seen a moment after
		-- the record went up, so it had a chance to read it.
		if rec.hello and not rec.acked and run.bridgeSeen and run.bridgeSeen >= rec.sentAt then
			NoteAcked(rec)
			changed = true
		end
		if rec.acked then
			if rec.forget then db.forget[rec.forget] = nil end
			run.outbound[id] = nil
			changed = true
		elseif rec.hello and now - rec.sentAt >= 20 then
			run.outbound[id] = nil
			changed = true
		elseif now - rec.sentAt >= STRIP_SECONDS then
			rec.tries = (rec.tries or 1) + 1
			if rec.tries <= STRIP_TRIES then
				-- Nobody picked it up: show it again.
				rec.sentAt = now
				changed = true
			elseif rec.forget then
				-- The bridge is away; db.forget keeps it for the next hello.
				run.outbound[id] = nil
				changed = true
			else
				-- Give up on pixels for this message; the reload path still has it.
				if rec.settings then
					run.settingsPending = nil
					if ui.codexSettings then ui.codexSettings.pending = false; ui.codexSettings.dirty = true; ui.codexSettings.message = "No confirmation. Reconnect and try saving again."; ui.codexSettings.Refresh() end
				end
				if rec.catalogRefresh then
					run.modelsPending=nil
					if ui.codexSettings then ui.codexSettings.message="No refresh confirmation. Reconnect and try again."; ui.codexSettings.Refresh() end
				end
				run.outbound[id] = nil
				run.pixelFailed = true
				changed = true
				AzerMind.ArmAutoRefresh()
			end
		end
	end
	if changed then
		RefreshStrip()
		AzerMind.UpdateStatus()
	end
	if not AnyPending() then return end
	local moved = false
	for _, c in ipairs(db.chats) do
		if c.pendingId and PollActivity(c) then moved = true end
	end
	if moved then AzerMind.Render() end
	for _, c in ipairs(db.chats) do
		if c.pendingId and CheckSignal("sig", c.pendingId) then
			TryLoadSlot("signal")
			return
		end
	end
	if run.nextPollAt and now >= run.nextPollAt then
		TryLoadSlot("schedule")
	end
end

-- Pull whatever bridge.js last wrote into Inbox.lua (the reload path).
local function ProcessInbox()
	local inbox = AzerMind_Inbox
	if type(inbox) ~= "table" then return end
	if type(inbox.cwd) == "string" and inbox.cwd ~= "" then run.bridgeCwd = inbox.cwd end
	if type(inbox.agent) == "string" and inbox.agent ~= "" then run.bridgeAgent = inbox.agent end
	if type(inbox.agents) == "table" and #inbox.agents > 0 then run.bridgeAgents = inbox.agents end
	ApplyReplies(inbox.replies)
	if inbox.restore then ImportRestore(inbox.restore) end
	if inbox.map and AzerMindMap then AzerMindMap.Sync(inbox.map) end
end

Finish = function(chat, role, text, denied, agent, summary, macros)
	AddHistory(chat, role, text, chat.pendingId, denied, agent, macros)
	chat.pendingId = nil
	chat.progress = nil
	if run.act then run.act[chat.id] = nil end
	NotedBridge()
	local visible = ui.frame and ui.frame:IsShown() and db.activeChat == chat.id
	if not visible then
		chat.unread = (chat.unread or 0) + 1
	end
	if not AnyPending() then
		keyCatcher:Hide()
	end
	if visible and ui.input and chat.draft and chat.draft ~= "" then
		ui.input:SetText(chat.draft)
		chat.draft = nil
	end
	AzerMind.Render()
	AzerMind.Notify(chat, text, agent, summary)
end

---------------------------------------------------------------------------
-- Game context and links
---------------------------------------------------------------------------

-- The agent only sees text, so two things about the game are spelled out for it:
-- who is asking (the character, where they are; sent with the hello and again
-- when it changes, and put into the agent's system prompt by the bridge), and
-- what the player shift-clicked into the message (item, spell and quest links
-- are meaningless markup to the agent; their tooltips are what the player sees).
-- Every game API here is optional: whatever the client lacks is left out.

local CONTEXT_MAX = 14000 -- Fits alongside a 48 KB question in the bounded multipart record.
local COMPLETED_QUEST_BYTES_MAX = 6000 -- Leave room for active quests and other character fields.
local LINK_LINES_MAX = 30 -- tooltip lines kept per link
local LINK_BYTES_MAX = 900 -- bytes kept per link

-- Call a game API that may not exist or may throw, and get its returns or nothing.
local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g = pcall(fn, ...)
	if ok then return a, b, c, d, e, f, g end
end

local function Money(copper)
	copper = tonumber(copper) or 0
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return g .. "g " .. s .. "s " .. c .. "c" end
	if s > 0 then return s .. "s " .. c .. "c" end
	return c .. "c"
end

-- A few lines about the game and the character, as the bridge will show them to the agent.
-- Profession and secondary skill lines by skill id (vanilla ids).
local PROFESSION_SKILL_IDS = {
	[164] = true, [165] = true, [171] = true, [182] = true, [186] = true, [197] = true, [202] = true,
	[333] = true, [393] = true, [129] = true, [185] = true, [356] = true,
}

-- The character's skill lines as { name, isHeader, rank, maxRank, skillID }.
-- Forever only has C_SkillInfo (one table per line); the classic globals
-- (multiple returns) are the fallback for other clients.
function AzerMind.SkillLines()
	local out = {}
	if C_SkillInfo and C_SkillInfo.GetNumSkillLines then
		local n = Try(C_SkillInfo.GetNumSkillLines)
		local seen = {}
		for i = 1, (type(n) == "number" and n or 0) do
			local sk = Try(C_SkillInfo.GetSkillLineInfo, i)
			-- Child lines (parentSkillLineID ~= 0) repeat their parent; Blizzard's
			-- skills frame skips them too.
			if type(sk) == "table" and type(sk.name) == "string" and (sk.parentSkillLineID or 0) == 0 then
				local key = sk.isHeader and ("h:" .. sk.name) or (sk.skillID or sk.name)
				if not seen[key] then
					seen[key] = true
					out[#out + 1] = { name = sk.name, isHeader = sk.isHeader, rank = sk.rank, maxRank = sk.maxRank, skillID = sk.skillID }
				end
			end
		end
		return out
	end
	local n = Try(GetNumSkillLines)
	for i = 1, (type(n) == "number" and n or 0) do
		local sname, isHeader, _, rank, _, _, maxRank = Try(GetSkillLineInfo, i)
		if type(sname) == "string" then
			out[#out + 1] = { name = sname, isHeader = isHeader and true or false, rank = rank, maxRank = maxRank }
		end
	end
	return out
end

-- Read the spellbook, not a trainer catalogue: only currently learned entries.
function AzerMind.LearnedSpells()
	local entries, seen, bytes, truncated = {}, {}, 0, false
	local function Add(name, rank, id)
		if type(name) ~= "string" or name == "" then return end
		local entry = name .. (type(rank) == "string" and rank ~= "" and (" (" .. rank .. ")") or " (rank unavailable)")
		if seen[entry] then return end
		seen[entry] = true
		if tonumber(id) then entry = entry .. " #" .. id end
		if bytes + #entry + 2 > 1800 then truncated = true; return end
		entries[#entries + 1] = entry; bytes = bytes + #entry + 2
	end
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		for tab = 1, math.min(tonumber(Try(C_SpellBook.GetNumSpellBookSkillLines)) or 0, 30) do
			local info = Try(C_SpellBook.GetSpellBookSkillLineInfo, tab)
			if type(info) == "table" then
				local offset = tonumber(info.itemIndexOffset) or 0
				for index = offset + 1, offset + math.min(tonumber(info.numSpellBookItems) or 0, 500) do
					local spell = Try(C_SpellBook.GetSpellBookItemInfo, index, bank)
					if type(spell) == "table" and spell.spellID then
						local name, rank = Try(C_SpellBook.GetSpellBookItemName, index, bank)
						rank = rank or Try(C_Spell and C_Spell.GetSpellSubtext, spell.spellID)
						Add(name or spell.name, rank, spell.spellID)
					end
				end
			end
		end
	else
		for tab = 1, math.min(tonumber(Try(GetNumSpellTabs)) or 0, 30) do
			local _, _, offset, count = Try(GetSpellTabInfo, tab)
			for index = (tonumber(offset) or 0) + 1, (tonumber(offset) or 0) + math.min(tonumber(count) or 0, 500) do
				local kind, id = Try(GetSpellBookItemInfo, index, BOOKTYPE_SPELL or "spell")
				if kind == "SPELL" then
					local name, rank = Try(GetSpellBookItemName, index, BOOKTYPE_SPELL or "spell")
					Add(name, rank, id)
				end
			end
		end
	end
	if #entries == 0 then return "Learned spells: unavailable from this client's spellbook API." end
	return "Learned player spells (spellbook ranks; no rank means unavailable, not rank 1): " .. table.concat(entries, "; ") .. (truncated and "; [partial list: size limit]" or "")
end

-- Character completion history is separate from ready-to-turn-in active quests.
-- Read each context afresh: quests delivered since the last question must appear.
local function CompletedQuestContext()
	local reported = Try(C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs)
	if type(reported) ~= "table" then
		return "Completed quest IDs (delivered; unavailable): client API unavailable or failed."
	end
	local ids, seen, invalid = {}, {}, false
	for _, id in pairs(reported) do
		if type(id) == "number" and id > 0 and id < math.huge and id == math.floor(id) then
			if not seen[id] then ids[#ids + 1] = id; seen[id] = true end
		else
			invalid = true
		end
	end
	table.sort(ids)
	local function Header(shown, limited)
		return "Completed quest IDs (delivered" .. ((limited or invalid) and "; partial" or "")
			.. "; " .. shown .. "/" .. #ids .. " shown" .. (limited and "; size limit" or "")
			.. (invalid and "; invalid entries omitted" or "") .. "): "
	end
	-- Reserve the largest header, including the size-limit notice, before adding IDs.
	-- Counts refer to unique valid IDs; a malformed API entry makes the result partial.
	local entries, bytes = {}, 0
	local budget = COMPLETED_QUEST_BYTES_MAX - #Header(#ids, true)
	for _, id in ipairs(ids) do
		local entry = string.format("%.0f", id)
		local size = #entry + (#entries > 0 and 1 or 0)
		if bytes + size > budget then break end
		entries[#entries + 1] = entry; bytes = bytes + size
	end
	local body = #ids == 0 and "none reported by client; absence does not prove a quest is unfinished." or table.concat(entries, ",")
	return Header(#entries, #entries < #ids) .. body
end

AzerMind.ContextCategories = {
	{"game", "Game and client version"}, {"character", "Name, class, race, level, faction"},
	{"identity", "Realm and guild (with character)"}, {"zone", "Zone and subzone"},
	{"position", "Map and exact coordinates"}, {"progress", "Money and XP"},
	{"talents", "Talent tree totals"}, {"professions", "Professions and levels"},
	{"skills", "Other skills and levels"}, {"spells", "Learned spells and ranks"},
	{"quests", "Active and completed quest IDs"}, {"equipment", "Equipped items and tooltips"},
}
function AzerMind.ContextOptions(mode)
	local selected = type(mode) == "table" and mode or (mode == nil and db.settings.contextFields)
	local full = (mode or db.settings.contextMode) == "full"
	local options = {}
	for _, field in ipairs(AzerMind.ContextCategories) do
		local key = field[1]
		if selected then options[key] = selected[key] == true
		else options[key] = full or key == "game" or key == "character" or key == "zone" end
	end
	return options
end
function AzerMind.ContextSettings()
	return AzerMind.ContextOptions(), db.settings.context
end
function AzerMind.ReplySound(value)
    local allowed={[0]=true,[3081]=true,[18019]=true,[3175]=true,[8960]=true,[7355]=true}
    if value~=nil and allowed[value] then db.settings.replySound=value end
    return db.settings.replySound==nil and 3081 or db.settings.replySound
end
function AzerMind.SaveContextSettings(options, enabled)
	db.settings.contextFields = AzerMind.ContextOptions(options)
	db.settings.contextMode = "custom"
	db.settings.context = enabled == true
	run.contextSent = nil
	AzerMind.Render()
end
function AzerMind.GameContext(mode)
	local options = AzerMind.ContextOptions(mode)
	local full = options.identity
	local lines = {}
	local version, build, _, toc = Try(GetBuildInfo)
	toc = tonumber(toc)
	local game = "World of Warcraft"
	if toc and toc >= 16000 and toc < 20000 then game = "World of Warcraft: Forever" end
	local client = ""
	if version then
		client = " (client " .. tostring(version) .. (build and ("." .. tostring(build)) or "") .. (toc and (", interface " .. toc) or "") .. ")"
	end
	if options.game then table.insert(lines, "Game: " .. game .. client) end

	local name = Try(UnitName, "player")
	if name and options.character then
		local realm = full and Try(GetRealmName)
		local level = Try(UnitLevel, "player")
		local race = Try(UnitRace, "player")
		local class = Try(UnitClass, "player")
		local faction = Try(UnitFactionGroup, "player")
		local guild = full and Try(GetGuildInfo, "player")
		local who = "Character: " .. tostring(name) .. (realm and (" on " .. tostring(realm)) or "")
		local desc = {}
		if level then table.insert(desc, "level " .. tostring(level)) end
		if race then table.insert(desc, tostring(race)) end
		if class then table.insert(desc, tostring(class)) end
		if #desc > 0 then who = who .. ", " .. table.concat(desc, " ") end
		if faction then who = who .. " (" .. tostring(faction) .. ")" end
		if guild then who = who .. ", guild <" .. tostring(guild) .. ">" end
		table.insert(lines, who)
	end

	local zone = Try(GetZoneText)
	local sub = Try(GetSubZoneText)
	if options.zone and zone and zone ~= "" then
		table.insert(lines, "Location: " .. zone .. ((sub and sub ~= "" and sub ~= zone) and (" - " .. sub) or ""))
	end


	if options.position then
	-- Map coordinates, as the minimap shows them (0-100 across the current map;
	-- addons get no world x/y/z). Modern C_Map first, the vanilla call as fallback.
	local x, y, mapName
	local mapId = Try(C_Map and C_Map.GetBestMapForUnit, "player")
	if type(mapId) == "number" then
		local pos = Try(C_Map.GetPlayerMapPosition, mapId, "player")
		if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then x, y = pos.x, pos.y end
		local info = Try(C_Map.GetMapInfo, mapId)
		if type(info) == "table" and type(info.name) == "string" then mapName = info.name end
	end
	if not x then
		local px, py = Try(GetPlayerMapPosition, "player")
		if type(px) == "number" and type(py) == "number" then x, y = px, py end
	end
	if x and y and (x > 0 or y > 0) then
		local where = (mapName and mapName ~= zone) and (" on " .. mapName) or ""
		table.insert(lines, string.format("Position: %.1f, %.1f%s%s", x * 100, y * 100, where, mapId and (" (map " .. mapId .. ")") or ""))
	end

	end -- position
	if options.progress then
	local progress = {}
	local copper = Try(GetMoney)
	if copper then table.insert(progress, "Money: " .. Money(copper)) end
	local xp, xpMax = Try(UnitXP, "player"), Try(UnitXPMax, "player")
	if type(xp) == "number" and type(xpMax) == "number" and xpMax > 0 then
		table.insert(progress, "XP: " .. xp .. "/" .. xpMax)
	end
	if #progress > 0 then table.insert(lines, table.concat(progress, "; ")) end

	end -- progress
	if options.quests then
	-- Keep active and delivered quest IDs ahead of verbose optional sections so
	-- dropping trailing context cannot remove the facts needed for route planning.
	local quests = {}
	local qn = Try(C_QuestLog and C_QuestLog.GetNumQuestLogEntries) or Try(GetNumQuestLogEntries)
	if type(qn) == "number" then
		for i = 1, math.min(qn, 40) do
			local id, header, complete
			local info = Try(C_QuestLog and C_QuestLog.GetInfo, i)
			if type(info) == "table" then
				id, header = info.questID, info.isHeader
				complete = Try(C_QuestLog.IsComplete, id)
			else
				local _, _, _, isHeader, _, isComplete, _, qid = Try(GetQuestLogTitle, i)
				id, header, complete = qid, isHeader, isComplete == 1 or isComplete == true
			end
			if not header and type(id) == "number" and id > 0 then
				table.insert(quests, tostring(id) .. (complete and "*" or ""))
			end
		end
	end
	if #quests > 0 then table.insert(lines, "Quest log (id, * = ready to turn in): " .. table.concat(quests, ","))
	else table.insert(lines, "Quest log: empty or unavailable from client API.") end
	table.insert(lines, CompletedQuestContext())
	end -- quests
	if options.talents then
	-- Classic-style talent tabs: name, icon, points spent.
	local tabs = Try(GetNumTalentTabs)
	if type(tabs) == "number" and tabs > 0 then
		local parts = {}
		for i = 1, tabs do
			local tname, _, points = Try(GetTalentTabInfo, i)
			if type(tname) == "string" and type(points) == "number" then
				table.insert(parts, tname .. " " .. points)
			end
		end
		if #parts > 0 then table.insert(lines, "Talents: " .. table.concat(parts, " / ")) end
	end

	table.insert(lines, "Individual talent ranks: not collected; tree totals only.")
	end -- talents
	if options.professions or options.skills then
	-- Skill lines under the Professions and Secondary Skills headers.
	local header, parts, otherSkills = nil, {}, {}
	local wanted = { [TRADE_SKILLS or "Professions"] = true, [SECONDARY_SKILLS or "Secondary Skills"] = true }
	for _, sk in ipairs(AzerMind.SkillLines()) do
		if sk.isHeader then
			header = sk.name
		elseif (header and wanted[header]) or PROFESSION_SKILL_IDS[sk.skillID] then
			table.insert(parts, sk.name .. (sk.rank and (" " .. tostring(sk.rank) .. (sk.maxRank and ("/" .. tostring(sk.maxRank)) or "")) or ""))
		else
			table.insert(otherSkills, sk.name .. (sk.rank and (" " .. tostring(sk.rank) .. (sk.maxRank and ("/" .. tostring(sk.maxRank)) or "")) or " (rank unavailable)"))
		end
	end
	if options.professions and #parts > 0 then table.insert(lines, "Professions: " .. table.concat(parts, ", ")) end
	if options.skills and #otherSkills > 0 then table.insert(lines, "Other skills (current/max, as reported by the client): " .. table.concat(otherSkills, ", ")) end
	end -- professions / skills
	if options.spells then table.insert(lines, AzerMind.LearnedSpells()) end

	if options.equipment then
	local equipment = AzerMind.EquipmentDraft(""):gsub("Equipment snapshot taken at [^\n]+", "Currently equipped items (not bag items).")
	table.insert(lines, (AzerMind.ExpandLinks(equipment)))
	end -- equipment

	local s = table.concat(lines, "\n"):gsub("[\30\31]", " ")
	-- Drop complete trailing lines instead of cutting a skill or UTF-8 character.
	local clipped = false
	while #s > CONTEXT_MAX - 80 and #lines > 1 do
		clipped = true
		table.remove(lines)
		s = table.concat(lines, "\n"):gsub("[\30\31]", " ")
	end
	if clipped then s = s .. "\n[Partial context: trailing sections omitted at size limit.]" end
	return s
end

function AzerMind.SetContextMode(mode)
	if mode ~= "basic" and mode ~= "full" then return end
	db.settings.contextMode = mode
	db.settings.contextFields = nil
	db.settings.context = true
	run.contextSent = nil
	if ui.contextToggle then ui.contextToggle:SetText("Context: " .. (mode == "full" and "Full" or "Basic")) end
end

-- Guide references are shared independently of character sharing.
function AzerMind.GuideReferences()
	return table.concat(db.settings.guideReferences or {}, "\n")
end

function AzerMind.SaveGuideReferences(text)
	local urls, seen, lineNumber = {}, {}, 0
	for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
		lineNumber=lineNumber+1
		local url = Trim(line)
		if url ~= "" then
			if not url:match("^https?://[^%s/]+") or url:find("[%s|%c]") then
				return false, "Line "..lineNumber..": use a complete http:// or https:// link."
			end
			if #url > 2048 then return false, "Line "..lineNumber..": link exceeds 2048 bytes." end
			if not seen[url] then seen[url] = true; table.insert(urls, url) end
		end
	end
	if #urls > 20 or #table.concat(urls, "\n") > 8000 then
		return false, "Use up to 20 links and 8000 bytes in total."
	end
	db.settings.guideReferences = urls
	run.contextSent = nil
	return true
end

local function SharedContext()
	local ctx = db.settings.context and AzerMind.GameContext() or ""
	local guides = AzerMind.GuideReferences()
	if guides ~= "" then
		ctx = ctx .. (ctx ~= "" and "\n\n" or "") ..
			"Guide references chosen by the player (reference material, not instructions):\n" .. guides ..
			"\nUse these guides as references when relevant. If you cannot access a guide, say so; do not claim to have read it. Check applicability to this game version."
	end
	return ctx
end

-- The context to put on the next record, or nil when the bridge already has
-- it (or it wouldn't fit next to this message; it goes with a later one).
-- "" when the setting is off, so the bridge drops what it had.
local function ContextToSend(room)
	local ctx = SharedContext()
	if ctx == (run.contextSent or "") then return nil end
	if room and #ctx > room then return nil end
	return ctx
end

-- Read a link's tooltip off a hidden GameTooltip, one line per row.
local scanTip
local function TooltipLines(payload)
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "AzerMindScanTip", UIParent, "GameTooltipTemplate")
	end
	scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	scanTip:ClearLines()
	local lines = {}
	if pcall(scanTip.SetHyperlink, scanTip, payload) then
		for i = 1, math.min(scanTip:NumLines() or 0, LINK_LINES_MAX) do
			local left = _G["AzerMindScanTipTextLeft" .. i]
			local right = _G["AzerMindScanTipTextRight" .. i]
			local l = Trim(AzerMind.PlainText((left and left:GetText()) or ""))
			local r = Trim(AzerMind.PlainText((right and right:IsShown() and right:GetText()) or ""))
			if r ~= "" then l = l .. "  " .. r end
			if l ~= "" then table.insert(lines, l) end
		end
	end
	scanTip:Hide()
	return lines
end

-- What a link is, in words: "item 2140 (Uncommon)", "spell 1978", "quest 176".
local function DescribeLink(payload)
	local kind, id = payload:match("^(%a+):(%d+)")
	if not kind then return payload:match("^(%a+)") or "link" end
	local s = kind .. " " .. id
	if kind == "azermindinstance" and AzerMind.InstanceDetails then return s .. "\n" .. AzerMind.InstanceDetails(AzerMind.InstanceByID(id)) end
	if kind == "item" then
		local _, _, quality = Try((C_Item and C_Item.GetItemInfo) or GetItemInfo, payload)
		local desc = type(quality) == "number" and _G["ITEM_QUALITY" .. quality .. "_DESC"]
		if desc then s = s .. " (" .. desc .. ")" end
	end
	return s
end

-- Turn the links in a message into text the agent can use: each becomes [Name]
-- in place, and a block at the end lists what the tooltip says about it.
-- Returns the new text and the number of links found.
function AzerMind.ExpandLinks(text)
	local links, seen = {}, {}
	local function Take(payload, name)
		if not seen[payload] then
			seen[payload] = true
			table.insert(links, { payload = payload, name = name })
		end
		return "[" .. name .. "]"
	end
	-- Coloured links first (|cAARRGGBB|H...|h[Name]|h|r), then bare ones.
	local out = text:gsub("|c%x%x%x%x%x%x%x%x|H([^|]+)|h%[([^%]]*)%]|h|r", Take)
	out = out:gsub("|H([^|]+)|h%[([^%]]*)%]|h", Take)
	out = AzerMind.PlainText(out)
	if #links == 0 then return text, 0 end
	local blocks = {}
	for _, l in ipairs(links) do
		local head = "[" .. l.name .. "] " .. DescribeLink(l.payload)
		local body = l.payload:match("^azermindinstance:") and "" or table.concat(TooltipLines(l.payload), "\n  ")
		local block = body ~= "" and (head .. "\n  " .. body) or head
		if not l.payload:match("^azermindinstance:") and #block > LINK_BYTES_MAX then block = block:sub(1, LINK_BYTES_MAX) .. "..." end
		table.insert(blocks, block)
	end
	return out .. "\n\n--- Linked from the game ---\n" .. table.concat(blocks, "\n"), #links
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- allow: optional list of permission rules to grant before this message runs.
function AzerMind.Send(text, allow)
	local c = ActiveChat()
	if not c then return end
	text = Trim(text or "")
	if c.pendingId then
		-- Typing while waiting: keep the draft, and check for the reply.
		if text ~= "" then c.draft = text end
		if db.settings.mode == "pixel" and not (run.slotsExhausted or run.slotsMissing) then
			TryLoadSlot("manual")
		else
			SafeReload()
		end
		return
	end
	if text == "" then return end
	if not AzerMind.IsConnected() then
		-- Not connected: the message stays in the box and we try to connect;
		-- CheckConnection sends it the moment the light turns green. If the bridge
		-- never answers, the text is still in the box for a later try.
		if ui.input then ui.input:SetText(text) end
		run.sendOnConnect = { chat = c.id, text = text, allow = allow }
		if not run.connectingAt then AzerMind.Connect() end
		AzerMind.Toggle(true)
		return
	end
	-- Shift-clicked links become [Name] plus their tooltip, which is what the agent can read.
	local links
	text, links = AzerMind.ExpandLinks(text)
	local limit = 48000
	if #text > limit then
		AddHistory(c, "system", "Message exceeds the " .. limit .. " byte limit, including linked item tooltips.")
		AzerMind.Render()
		return
	end
	-- The game context rides along when the bridge doesn't have this version yet.
	local ctx = ContextToSend(63000 - #text)

	db.lastSeq = db.lastSeq + 1
	local id = db.lastSeq
	local tokens = {}
	if c.resetNext then table.insert(tokens, "n") end
	if c.agent and c.agent ~= "" then table.insert(tokens, "agent=" .. c.agent) end
	do
		local options = AzerMind.ChatAISettings(c)
		if options.model and options.model ~= "" then table.insert(tokens, "model=" .. options.model) end
		if options.reasoning and options.reasoning ~= "" then table.insert(tokens, "reasoning=" .. options.reasoning) end
	end
	local allowHex
	if type(allow) == "table" and #allow > 0 then
		table.insert(tokens, "allow=" .. table.concat(allow, ","))
		allowHex = ToHex(table.concat(allow, US))
	end
	local flags = table.concat(tokens, ";")
	local newSession = c.resetNext and true or nil
	c.resetNext = nil
	db.outbox = {
		id = id,
		session = db.session,
		chat = c.id,
		text = ToHex(text),
		cwd = ToHex(c.cwd),
		ctx = ctx and ToHex(ctx) or nil,
		agent = (c.agent and c.agent ~= "") and c.agent or nil,
		allow = allowHex,
		newSession = newSession,
		model = AzerMind.ChatAISettings(c).model,
		reasoning = AzerMind.ChatAISettings(c).reasoning,
		t = time(),
	}
	c.pendingId = id
	c.draft = nil
	c.progress = nil
	AddHistory(c, "user", text, id)
	-- A chat still carrying its default name takes its title from the first message
	-- you send (system notes like "/azermind cd" before it don't count).
	if c.name:match("^Chat %d+$") then
		local first = true
		for _, m in ipairs(c.history) do
			if m.role == "user" and m.id ~= id then first = false break end
		end
		if first then c.name = AutoTitle(text) or c.name end
	end
	db.settings.shown = true

	if db.settings.mode == "pixel" then
		run.outbound[id] = { chat = c.id, cwd = c.cwd, flags = flags, name = c.name, text = text, ctx = ctx, sentAt = GetTime() }
		run.sentAt = GetTime()
		run.polls = 0
		StartActivity(c, id)
		ScheduleNextPoll()
		RefreshStrip()
		AzerMind.Render()
	else
		SafeReload()
	end
end

-- Forget: a record with no text telling the bridge a chat was deleted, so it drops
-- the transcript (which a later restore would otherwise bring back) and the
-- agent session. db.forget keeps the id until the bridge acks, so a delete made
-- while the bridge was away is sent again with the next hello.
local function SendForget(chatId)
	if db.settings.mode ~= "pixel" then return end
	for _, rec in pairs(run.outbound) do
		if rec.forget == chatId and not rec.acked then return end
	end
	local info = db.forget[chatId] or {}
	db.lastSeq = db.lastSeq + 1
	run.outbound[db.lastSeq] = { chat = chatId, cwd = info.cwd or "", flags = "d", name = info.name or "", text = "", sentAt = GetTime(), forget = chatId }
	RefreshStrip()
end

local function ForgetOnBridge(c)
	if not c or not c.id then return end
	db.forget[c.id] = { name = c.name, cwd = c.cwd }
	SendForget(c.id)
end

-- Hello: a record with no text that just announces our session token. The bridge
-- acks it, offers a restore if our saved data is fresh, and refreshes the slots,
-- so the status light and any lost chats come back before the first message.
-- The game context always rides on it (empty when turned off), so the bridge's
-- copy is brought in line at every login and Connect.
function AzerMind.SayHello()
	if db.settings.mode ~= "pixel" then return end
	local now = GetTime()
	if run.lastHelloAt and now - run.lastHelloAt < 60 then return end
	run.lastHelloAt = now
	db.lastSeq = db.lastSeq + 1
	local c = ActiveChat()
	local ctx = SharedContext()
	run.outbound[db.lastSeq] = { chat = c and c.id or "", cwd = c and c.cwd or "", flags = "h", name = c and c.name or "", text = "", ctx = ctx, sentAt = now, hello = true }
	run.helloPoll = { startedAt = now, index = 1 }
	-- Deletions the bridge never confirmed ride along with the hello.
	for id in pairs(db.forget) do SendForget(id) end
	-- Fresh saved data: show "restoring" instead of an empty panel until we hear back.
	if not db.restored then
		local empty = true
		for _, ch in ipairs(db.chats) do
			if #ch.history > 0 then empty = false end
		end
		if empty then run.restoring = now end
	end
	RefreshStrip()
	AzerMind.Render()
end

-- Put the active chat's pending message back on the strip.
function AzerMind.Resend()
	local c = ActiveChat()
	if not c or not c.pendingId then return end
	local text
	for i = #c.history, 1, -1 do
		if c.history[i].id == c.pendingId and c.history[i].role == "user" then
			text = c.history[i].text
			break
		end
	end
	if not text then return end
	run.outbound[c.pendingId] = { chat = c.id, cwd = c.cwd, flags = (c.agent and c.agent ~= "") and ("agent=" .. c.agent) or "", name = c.name, text = text, sentAt = GetTime() }
	do
		local options = AzerMind.ChatAISettings(c)
		local rec = run.outbound[c.pendingId]
		if options.model and options.model ~= "" then rec.flags = rec.flags .. ";model=" .. options.model end
		if options.reasoning and options.reasoning ~= "" then rec.flags = rec.flags .. ";reasoning=" .. options.reasoning end
	end
	run.sentAt = GetTime()
	run.polls = 0
	ScheduleNextPoll()
	RefreshStrip()
	AzerMind.UpdateStatus()
end

function AzerMind.CancelPending()
	local c = ActiveChat()
	if not c or not c.pendingId then return end
	local target = c.pendingId
	run.outbound[target] = nil
	if run.act then run.act[c.id] = nil end
	c.pendingId, c.progress = nil, nil
	AddHistory(c, "system", "Response stopped. Cancellation sent to the bridge.")
	db.lastSeq = db.lastSeq + 1
	run.outbound[db.lastSeq] = { chat = c.id, cwd = "", flags = "cancel=" .. target, name = c.name, text = "", sentAt = GetTime(), cancel = true }
	RefreshStrip()
	AzerMind.Render()
end

function AzerMind.EquipmentDraft(existing)
	local first, last = "--- Equipped items ---", "--- End equipped items ---"
	local text = tostring(existing or "")
	local startAt = text:find(first, 1, true)
	local endAt = startAt and text:find(last, startAt, true)
	if endAt then text = text:sub(1, startAt - 1) .. text:sub(endAt + #last) end
	local slots = {"Head", "Neck", "Shoulders", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrists", "Hands", "Ring 1", "Ring 2", "Trinket 1", "Trinket 2", "Back", "Main hand", "Off hand", "Ranged", "Tabard"}
	local lines = { first, "Equipment snapshot taken at " .. date("%H:%M:%S") .. ". These items are equipped, not just linked from bags." }
	for slot, label in ipairs(slots) do
		local link = Try(GetInventoryItemLink, "player", slot)
		if type(link) == "string" and link ~= "" then
			if AzerMind.NormalizeItemLink then link = AzerMind.NormalizeItemLink(link) end
			table.insert(lines, label .. ": " .. link)
		else
			local id = Try(GetInventoryItemID, "player", slot)
			local texture = Try(GetInventoryItemTexture, "player", slot)
			if id then
				table.insert(lines, label .. ": item " .. id .. " (details not loaded; refresh this snapshot before comparing stats)")
				if C_Item and C_Item.RequestLoadItemDataByID then Try(C_Item.RequestLoadItemDataByID, id) end
			else
				table.insert(lines, label .. (texture and ": details unavailable" or ": empty"))
			end
		end
	end
	table.insert(lines, last)
	text = Trim(text)
	return (text ~= "" and (text .. "\n\n") or "") .. table.concat(lines, "\n")
end

function AzerMind.AttachEquipment()
	if not ui.input then return end
	local text = AzerMind.EquipmentDraft(ui.input:GetText())
	ui.input:SetText(text)
	local c = ActiveChat()
	if c then c.draft = text end
	ui.input:SetFocus()
	if ui.input.SetCursorPosition then ui.input:SetCursorPosition(#text) end
end

function AzerMind.SendFromInput()
	if not ui.input then return end
	local text = ui.input:GetText()
	ui.input:SetText("")
	ui.input:ClearFocus() -- hand the keyboard back to the game after sending
	AzerMind.Send(text)
end

function AzerMind.ClearDraft()
	if not ui.input then return end
	ui.input:SetText("")
	local c = ActiveChat()
	if c then c.draft = nil end
	-- A message staged while disconnected must not be sent after clearing it.
	if run.sendOnConnect and c and run.sendOnConnect.chat == c.id then run.sendOnConnect = nil end
	ui.input:SetFocus()
	AzerMind.UpdateStatus()
end

function AzerMind.AppendQuestDraft(text, chatId)
	local c = ActiveChat()
	if not c or c.id ~= chatId or not ui.input then return false end
	local existing = Trim(ui.input:GetText() or "")
	local draft = existing ~= "" and (existing .. "\n\n" .. text) or text
	ui.input:SetText(draft); c.draft = draft; ui.input:SetFocus()
	if ui.input.SetCursorPosition then ui.input:SetCursorPosition(#draft) end
	return true
end

-- The Allow button: grant the rules a reply asked for, then tell the agent to carry on.
function AzerMind.Allow(chatId, rules)
	local c = FindChat(chatId)
	if not c or c.pendingId or not rules or #rules == 0 then return end
	if db.activeChat ~= c.id then AzerMind.SwitchChat(c.id) end
	for _, m in ipairs(c.history) do m.denied = nil end
	AddHistory(c, "system", "Allowed: " .. table.concat(rules, ", "))
	AzerMind.Send("Those actions are allowed now. Continue from where you left off.", rules)
end

---------------------------------------------------------------------------
-- Chats
---------------------------------------------------------------------------

function AzerMind.SwitchChat(id)
	local c = FindChat(id)
	if not c then return end
	local prev = ActiveChat()
	if prev and prev ~= c and ui.input then
		local typed = Trim(ui.input:GetText() or "")
		prev.draft = typed ~= "" and typed or nil
	end
	db.activeChat = c.id
	c.unread = 0
	if ui.input then
		ui.input:SetText(c.draft or "")
		c.draft = nil
	end
	AzerMind.Render()
	AzerMind.RenderChatList()
end

function AzerMind.NewChat(name)
	local c = AddChat(name and name ~= "" and name or nil)
	if not c then
		local a = ActiveChat()
		AddHistory(a, "system", "Chat limit reached (" .. MAX_CHATS .. "). Delete one first with /azermind delete.")
		AzerMind.Render()
		return
	end
	AzerMind.SwitchChat(c.id)
	AzerMind.Toggle(true)
end

-- Folder this chat's agent works in. Empty (or "-" / "default") = the bridge's
-- default. Relative paths are resolved by the bridge against that default.
function AzerMind.SetFolder(rest, c)
	c = c or ActiveChat()
	if not c then return end
	rest = Trim(rest or "")
	if rest == "-" or rest == "default" then rest = "" end
	local base = run.bridgeCwd or "the bridge's default folder"
	if rest ~= "" then
		local changed = rest ~= c.cwd
		c.cwd = rest
		local absolute = rest:match("^%a:[\\/]") or rest:match("^[\\/~]")
		local note = absolute and "" or (" (relative to " .. base .. ")")
		AddHistory(c, "system", "cwd set to " .. rest .. note .. (changed and #c.history > 1 and ("; the next message starts a fresh " .. ChatAgentName(c) .. " session there") or ""))
	elseif c.cwd ~= "" then
		c.cwd = ""
		AddHistory(c, "system", "cwd reset to the bridge's default: " .. base)
	else
		AddHistory(c, "system", "cwd is the bridge's default: " .. base .. " (/azermind cd <folder>, or right-click the chat and pick Folder, to change)")
	end
	AzerMind.Render()
end

StaticPopupDialogs["AZERMIND_FOLDER"] = {
	text = "Folder for this chat\n\nRelative to the bridge's folder (%s), ~, or a full path.\nEmpty = the bridge's default. Changing it starts a fresh agent session.",
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = 1,
	editBoxWidth = 320,
	maxLetters = 250,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnShow = function(dialog, data)
		local box = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
		if box then
			box:SetText(data and data.cwd or "")
			box:HighlightText()
			box:SetFocus()
		end
	end,
	OnAccept = function(dialog, data)
		local box = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
		local chat = data and FindChat(data.id)
		if chat and box then AzerMind.SetFolder(box:GetText(), chat) end
	end,
	EditBoxOnEnterPressed = function(box)
		local dialog = box:GetParent()
		StaticPopupDialogs["AZERMIND_FOLDER"].OnAccept(dialog, dialog.data)
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(box)
		box:GetParent():Hide()
	end,
}

-- Folder dialog for a chat (the active one when no id is given).
function AzerMind.FolderPrompt(id)
	local c = (id and FindChat(id)) or ActiveChat()
	if not c then return end
	StaticPopup_Show("AZERMIND_FOLDER", run.bridgeCwd or "unknown until connected", nil, { id = c.id, cwd = c.cwd })
end

-- The agent this chat talks to, by id. Empty (or
-- "-" / "default") = the bridge's default. The bridge starts a fresh session
-- when a chat changes agent, since a session belongs to the agent that made it.
local function AgentList()
	return run.bridgeAgents and table.concat(run.bridgeAgents, ", ") or "claude, codex, grok, agy, hermes"
end

function AzerMind.SetAgent(rest, c)
	c = c or ActiveChat()
	if not c then return end
	rest = Trim(rest or ""):lower()
	if rest == "-" or rest == "default" then rest = "" end
	if rest ~= "" and run.bridgeAgents and not Contains(run.bridgeAgents, rest) then
		AddHistory(c, "system", "Unknown agent \"" .. rest .. "\". The bridge knows: " .. AgentList())
		AzerMind.Render()
		return
	end
	local changed = rest ~= (c.agent or "")
	c.agent = rest
	if rest ~= "" then
		AddHistory(c, "system", "agent set to " .. AgentName(rest) .. (changed and #c.history > 1 and "; the next message starts a fresh session with it" or ""))
	elseif changed then
		AddHistory(c, "system", "agent reset to the bridge's default: " .. (run.bridgeAgent and AgentName(run.bridgeAgent) or "unknown until connected"))
	else
		AddHistory(c, "system", "agent is the bridge's default: " .. (run.bridgeAgent and AgentName(run.bridgeAgent) or "unknown until connected") .. " (/azermind agent <name>, or right-click the chat and pick Agent, to change; agents: " .. AgentList() .. ")")
	end
	AzerMind.Render()
end

StaticPopupDialogs["AZERMIND_AGENT"] = {
	text = "Agent for this chat\n\nOne of: %s.\nEmpty = the bridge's default (%s). Changing it starts a fresh session.",
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = 1,
	editBoxWidth = 200,
	maxLetters = 32,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnShow = function(dialog, data)
		local box = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
		if box then
			box:SetText(data and data.agent or "")
			box:HighlightText()
			box:SetFocus()
		end
	end,
	OnAccept = function(dialog, data)
		local box = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
		local chat = data and FindChat(data.id)
		if chat and box then AzerMind.SetAgent(box:GetText(), chat) end
	end,
	EditBoxOnEnterPressed = function(box)
		local dialog = box:GetParent()
		StaticPopupDialogs["AZERMIND_AGENT"].OnAccept(dialog, dialog.data)
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(box)
		box:GetParent():Hide()
	end,
}

-- Agent dialog for a chat (the active one when no id is given).
function AzerMind.AgentPrompt(id)
	local c = (id and FindChat(id)) or ActiveChat()
	if not c then return end
	StaticPopup_Show("AZERMIND_AGENT", AgentList(), run.bridgeAgent and AgentName(run.bridgeAgent) or "unknown until connected", { id = c.id, agent = c.agent or "" })
end

StaticPopupDialogs["AZERMIND_RENAME"] = {
	text = "Rename this chat",
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 24,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnShow = function(dialog, data)
		local box = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
		if box then
			box:SetText(data and data.name or "")
			box:HighlightText()
			box:SetFocus()
		end
	end,
	OnAccept = function(dialog, data)
		local box = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
		local chat = data and FindChat(data.id)
		local name = box and Trim(box:GetText() or "") or ""
		if chat and name ~= "" then
			chat.name = name:sub(1, 24)
			AzerMind.Render()
		end
	end,
	EditBoxOnEnterPressed = function(box)
		local dialog = box:GetParent()
		StaticPopupDialogs["AZERMIND_RENAME"].OnAccept(dialog, dialog.data)
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(box)
		box:GetParent():Hide()
	end,
}

-- Rename dialog for a chat (the active one when no id is given).
function AzerMind.RenamePrompt(id)
	local c = (id and FindChat(id)) or ActiveChat()
	if not c then return end
	StaticPopup_Show("AZERMIND_RENAME", nil, nil, { id = c.id, name = c.name })
end
AzerMind.RenameActive = AzerMind.RenamePrompt

-- Delete a chat (the active one when no id is given). The last chat is cleared
-- and renamed instead of removed, so there is always one to type into. Either
-- way the bridge is told to forget it, so a restore won't bring it back.
function AzerMind.DeleteChat(id)
	local c, idx = nil, nil
	if id then c, idx = FindChat(id) end
	if not c then c, idx = ActiveChat() end
	if not c then return end
	if ui.deletedMessage and ui.deletedMessage.chat==c.id then ui.deletedMessage=nil end
	ForgetOnBridge(c)
	if #db.chats == 1 then
		wipe(c.history)
		c.pendingId, c.progress, c.unread, c.draft = nil, nil, 0, nil
		c.name = "Chat 1"
		AzerMind.Render()
		AzerMind.RenderChatList()
		return
	end
	table.remove(db.chats, idx)
	if db.activeChat == c.id then
		AzerMind.SwitchChat(db.chats[math.min(idx, #db.chats)].id)
	else
		AzerMind.RenderChatList()
	end
end

-- The trash can on a chat row asks first; /azermind delete does not.
StaticPopupDialogs["AZERMIND_DELETE"] = {
	text = "Delete chat \"%s\"?\n\nIts transcript goes away (the last chat is cleared instead of removed).",
	button1 = OKAY,
	button2 = CANCEL,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(dialog, data)
		if data then AzerMind.DeleteChat(data.id) end
	end,
}

function AzerMind.ConfirmDelete(id)
	local c = (id and FindChat(id)) or ActiveChat()
	if not c then return end
	StaticPopup_Show("AZERMIND_DELETE", Display(c.name), nil, { id = c.id })
end

---------------------------------------------------------------------------
-- Macros
---------------------------------------------------------------------------

-- The agent can hand over ready-made macros (a ```wowmacro block the bridge turns
-- into `macros` on the reply). Each gets a button under its message that creates
-- the macro, or updates the one with that name, and puts it on the cursor to drop
-- on an action bar. The addon never runs a macro; the player's own click does.

local MACRO_ACCOUNT_MAX = (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS) or 120
local MACRO_CHAR_MAX = (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_CHARACTER_MACROS) or 30
local MACRO_DEFAULT_ICON = 134400 -- question mark: with #showtooltip the game shows the spell's icon

local function MacroSay(msg)
	print("|cff66ccff[AzerMind]|r " .. msg)
end

-- Only well-formed entries survive (the slot file is trusted, but not blindly).
function AzerMind.CleanMacros(list)
	if type(list) ~= "table" then return nil end
	local out = {}
	for _, m in ipairs(list) do
		if type(m) == "table" and type(m.name) == "string" and m.name ~= "" and type(m.body) == "string" and m.body ~= "" then
			out[#out + 1] = {
				name = m.name, body = m.body, char = m.char == true, risky = m.risky == true,
				icon = (type(m.icon) == "number" or type(m.icon) == "string") and m.icon or nil,
			}
		end
	end
	return #out > 0 and out or nil
end

-- The macro called `name` among account (1..120) or character (121..150) macros:
-- the same name may exist in both, and only the requested kind counts.
local function FindMacro(name, perCharacter)
	local first = perCharacter and MACRO_ACCOUNT_MAX + 1 or 1
	local last = perCharacter and MACRO_ACCOUNT_MAX + MACRO_CHAR_MAX or MACRO_ACCOUNT_MAX
	for i = first, last do
		local n, icon, body = Try(GetMacroInfo, i)
		if n == name then return i, icon, body end
	end
end

local function MacroIcon(icon)
	if type(icon) == "number" then return icon end
	if type(icon) == "string" then
		local id = Try(GetFileIDFromPath, "Interface\\Icons\\" .. icon)
		if type(id) == "number" and id > 0 then return id end
		return icon -- CreateMacro also takes a texture name
	end
	return MACRO_DEFAULT_ICON
end

function AzerMind.MacroLabel(m)
	local verb = FindMacro(m.name, m.char) and "Update" or "Create"
	return verb .. " macro: " .. Display(m.name) .. (m.char and " (character)" or "") .. (m.risky and "  |cffff6060(runs code)|r" or "")
end

StaticPopupDialogs["AZERMIND_MACRO"] = {
	text = "%s",
	button1 = OKAY,
	button2 = CANCEL,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(dialog, data)
		if data then AzerMind.InstallMacro(data, true) end
	end,
}

-- Create or update macro `m` ({ name, body, icon, char, risky }). Asks first when it
-- would replace a different macro of yours, or when it runs code (/run, /click...).
function AzerMind.InstallMacro(m, confirmed)
	if type(m) ~= "table" then return end
	if InCombatLockdown() then
		MacroSay("macros can't be changed in combat; click the button again afterwards.")
		return
	end
	local index, _, oldBody = FindMacro(m.name, m.char)
	if not confirmed then
		local why = {}
		if m.risky then table.insert(why, "This macro runs code or clicks buttons (/run, /script, /click). Only keep it if you trust what it does.") end
		if index and oldBody ~= m.body then table.insert(why, "It replaces your existing macro \"" .. m.name .. "\" (/azermind macro undo brings the old one back).") end
		if #why > 0 then
			-- Macro source must stay visible verbatim, including color-looking
			-- strings inside Lua code; only neutralize the markup delimiter.
			local preview=tostring(m.body or ""):gsub("|", "¦")
			StaticPopup_Show("AZERMIND_MACRO", table.concat(why, "\n\n") .. "\n\n" .. preview, nil, m)
			return
		end
	end
	-- Blizzard's macro window saves its edit box into its selected macro when it
	-- hides; close it first so that can't land on a macro we just moved.
	if MacroFrame and MacroFrame:IsShown() then
		Try(HideUIPanel, MacroFrame)
		index, _, oldBody = FindMacro(m.name, m.char)
	end
	local ok, newIndex
	if index then
		local _, oldIcon = FindMacro(m.name, m.char)
		ok, newIndex = pcall(EditMacro, index, m.name, m.icon ~= nil and MacroIcon(m.icon) or nil, m.body)
		if ok and type(newIndex) == "number" then
			db.macroUndo = { name = m.name, char = m.char, icon = oldIcon, body = oldBody }
		end
	else
		local acc, chr = Try(GetNumMacros)
		if m.char and type(chr) == "number" and chr >= MACRO_CHAR_MAX then
			MacroSay("your character macros are full (" .. MACRO_CHAR_MAX .. "); delete one in /macro first.")
			return
		elseif not m.char and type(acc) == "number" and acc >= MACRO_ACCOUNT_MAX then
			MacroSay("your account macros are full (" .. MACRO_ACCOUNT_MAX .. "); delete one in /macro first.")
			return
		end
		ok, newIndex = pcall(CreateMacro, m.name, MacroIcon(m.icon), m.body, m.char)
		if (not ok or type(newIndex) ~= "number") and m.icon ~= nil then
			ok, newIndex = pcall(CreateMacro, m.name, MACRO_DEFAULT_ICON, m.body, m.char)
		end
		if ok and type(newIndex) == "number" then
			db.macroUndo = { name = m.name, char = m.char, created = true }
		end
	end
	if not ok or type(newIndex) ~= "number" then
		MacroSay("could not save macro \"" .. m.name .. "\": " .. (ok and "the game refused it (is the list full?)" or tostring(newIndex)))
		return
	end
	-- EditMacro may move the macro (names are sorted): pick up the index it returned.
	Try(PickupMacro, newIndex)
	MacroSay("macro \"" .. m.name .. "\" " .. (index and "updated" or "created") .. " and on your cursor: click an action bar slot to place it (it is also in /macro).")
	AzerMind.Render()
end

function AzerMind.UndoMacro()
	local u = db.macroUndo
	if not u then MacroSay("nothing to undo."); return end
	if InCombatLockdown() then MacroSay("macros can't be changed in combat."); return end
	local index = FindMacro(u.name, u.char)
	if not index then MacroSay("macro \"" .. u.name .. "\" is gone already."); db.macroUndo = nil; return end
	if MacroFrame and MacroFrame:IsShown() then Try(HideUIPanel, MacroFrame); index = FindMacro(u.name, u.char) end
	if u.created then
		Try(DeleteMacro, index)
		MacroSay("removed macro \"" .. u.name .. "\".")
	else
		Try(EditMacro, index, u.name, u.icon, u.body)
		MacroSay("macro \"" .. u.name .. "\" is back to what it was.")
	end
	db.macroUndo = nil
	AzerMind.Render()
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

function AzerMind.PendingState(chat)
	local progress = tostring(chat and chat.progress or "")
	local state = "Thinking"
	for line in progress:gmatch("[^\n]+") do
		if line:match("^search:") then state = "Searching the web"
		elseif line:match("^fetch ") then state = "Reading sources" end
	end
	local rec = chat and run.outbound[chat.pendingId]
	if progress == "" and rec and not rec.acked then state = "Sending message" end
	return state
end

function AzerMind.UpdateStatus()
	if not ui.status then return end
	local c = ActiveChat()
	local mode = db.settings.mode
	local s
	if c and c.pendingId then
		local id = c.pendingId
		local elapsed = run.sentAt and (GetTime() - run.sentAt) or 0
		local rec = run.outbound[id]
		if mode == "pixel" then
			if run.slotsMissing then
				s = "Reply slots not installed (run install-slots.js, restart WoW). Using reload instead: Enter or Refresh"
			elseif run.slotsExhausted then
				s = "Slot pool used up this session - next keypress reloads to free it"
			elseif run.pixelFailed then
				s = "Bridge didn't see #" .. id .. " after " .. STRIP_TRIES .. " tries - next keypress switches to the reload path (or /azermind reload)"
			elseif c.progress or (run.act and run.act[c.id] and run.act[c.id].count > 0) then
				s = ChatAgentName(c) .. " is working on #" .. id .. " - " .. ActivityLine(c)
			elseif rec and not rec.acked then
				s = "Sending #" .. id .. (rec.tries and rec.tries > 1 and (" (try " .. rec.tries .. "/" .. STRIP_TRIES .. ")") or "") .. "..."
				local state = AzerMind.BridgeState()
				if state == "down" then s = s .. " - bridge not seen lately, is the bridge running?" end
			else
				s = "Waiting for #" .. id .. " (checked " .. (run.polls or 0) .. "x)"
				if elapsed > 45 then
					s = s .. " - no sign of the bridge. Is the bridge running? /azermind resend"
				end
			end
		else
			s = "Waiting for reply #" .. id .. ". Enter or Refresh checks now"
			if db.settings.autoRefresh then
				s = s .. "; auto on next keypress after " .. db.settings.interval .. "s"
			end
		end
	elseif not AzerMind.IsConnected() then
		if run.connectingAt and run.sendOnConnect then
			s = "Connecting to the bridge... your message goes out as soon as it answers"
		elseif run.connectingAt then
			s = "Connecting to the bridge..."
		elseif run.connectFailed then
			s = "No answer from the bridge. Is it running (npm start)? Connect tries again"
		elseif AzerMind.BridgeState() == "stale" then
			s = "Bridge not seen for a while - click Reconnect"
		else
			s = "Not connected - start the bridge, then click Connect"
		end
	elseif c and c.draft and c.draft ~= "" then
		s = "Reply arrived. Your draft is back in the box - Enter to send it"
	elseif run.restoring then
		s = "Connecting to the bridge..."
	else
		s = "Ready"
	end
	if c and c.pendingId then s = AzerMind.PendingState(c) .. "..." end
	local statusLabel=s
	if not (c and c.pendingId) and not AzerMind.IsConnected() then
		statusLabel=run.connectingAt and "Bridge connecting" or (AzerMind.BridgeState()=="stale" and "Bridge stale" or "Bridge offline")
	end
	ui.status:SetText(statusLabel)
	ui.status:SetWidth(150)
	run.statusText = s
	AzerMind.UpdateDot()
	AzerMind.UpdateConnect()
	if ui.title then
		local t = c and Display(c.name) or "AzerMind"
		ui.title:SetText(t)
		if AzerMindTheme then AzerMindTheme.Color(ui.title, "SetTextColor", "text") end
		if ui.layoutTitle then ui.layoutTitle() else ui.title:SetWidth(math.max(80,ui.frame:GetWidth()-150)) end
		ui.title:SetWordWrap(false)
	end
	local cwdText
	if c and c.cwd ~= "" then
		cwdText = Display(c.cwd)
	elseif run.bridgeCwd then
		cwdText = Display(run.bridgeCwd) .. " (bridge default)"
	else
		cwdText = "(bridge default - start the bridge in a folder, or right-click the chat and pick Folder)"
	end
	local agentText
	if c and c.agent and c.agent ~= "" then
		agentText = AgentName(c.agent)
	elseif run.bridgeAgent then
		agentText = AgentName(run.bridgeAgent) .. " (bridge default)"
	else
		agentText = "(bridge default)"
	end
	ui.cwd:SetText("cwd: " .. cwdText .. "   agent: " .. agentText .. "   mode: " .. mode)
	if ui.resend then ui.resend:SetShown(c and c.pendingId ~= nil and mode == "pixel") end
	if ui.codexButton then ui.codexButton:SetShown(c ~= nil) end
	if ui.refresh then ui.refresh:SetShown(mode ~= "pixel" or run.slotsExhausted or run.slotsMissing or run.pixelFailed or false) end
	AzerMind.UpdateMini()
end

-- One message bubble: accent bar, colored label, timestamp, wrapped body.
function AzerMind.DeleteMessage(chatId, entry)
	local chat=FindChat(chatId)
	if not chat then return false end
	for index, message in ipairs(chat.history) do
		if message==entry then
			ui.deletedMessage={chat=chatId,entry=message,index=index}
			table.remove(chat.history,index)
			AzerMind.Render()
			return true
		end
	end
	return false
end

function AzerMind.UndoMessageDeletion()
	local deleted=ui.deletedMessage
	local chat=deleted and FindChat(deleted.chat)
	if not chat or db.activeChat~=deleted.chat then return false end
	table.insert(chat.history,math.min(deleted.index,#chat.history+1),deleted.entry)
	ui.deletedMessage=nil
	AzerMind.Render()
	return true
end

local function GetBubble(i)
	local b = ui.bubbles[i]
	if b then return b end
	b = CreateFrame("Frame", nil, ui.content)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.accent = b:CreateTexture(nil, "BORDER")
	b.accent:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	b.accent:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	b.accent:SetWidth(3)
	b.who = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.who:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -6)
	b.who:SetJustifyH("LEFT")
	b.when = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	b.when:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -6)
	b.body = b:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	b.body:SetPoint("TOPLEFT", b.who, "BOTTOMLEFT", 0, -12)
	b.body:SetJustifyH("LEFT")
	b.body:SetJustifyV("TOP")
	b.body:SetWordWrap(true)
	b.body:SetNonSpaceWrap(true)
	if AzerMindTheme then AzerMindTheme.Type(b.body, "body") end
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Type(b.body,"paperBody") end
	b.allow = AzerMindTheme and AzerMindTheme.Button(b,"",160,22,nil) or CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
	b.allow:SetHeight(22)
	b.allow:SetPoint("TOPLEFT", b.body, "BOTTOMLEFT", 0, -6)
	b.allow:SetScript("OnClick", function(self)
		AzerMind.Allow(self.chatId, self.rules)
	end)
	b.allow:Hide()
	b.macroBtns = {}
	local function Action(label, action)
		local button = CreateFrame("Button", nil, b)
		button:SetSize(32, 32); button:SetScript("OnClick", action)
		local function Stroke(x, y, w, h)
			local t = button:CreateTexture(nil, "ARTWORK")
			t:SetPoint("TOPLEFT", button, "TOPLEFT", x, -y); t:SetSize(w, h)
			t:SetColorTexture(0.90, 0.82, 0.65, 1)
		end
		local function Outline(x, y)
			Stroke(x, y, 8, 1); Stroke(x, y+9, 8, 1); Stroke(x, y, 1, 10); Stroke(x+7, y, 1, 10)
		end
		if label == "Copy" then Outline(5, 3); Outline(8, 6)
		elseif label == "Delete" then
			Stroke(4, 5, 12, 1); Stroke(8, 3, 4, 1)
			Stroke(5, 6, 1, 10); Stroke(14, 6, 1, 10); Stroke(5, 15, 10, 1)
			Stroke(8, 8, 1, 5); Stroke(11, 8, 1, 5)
		else
			Stroke(5, 5, 10, 1); Stroke(4, 5, 1, 10); Stroke(5, 14, 10, 1)
			Stroke(12, 3, 1, 5); Stroke(13, 4, 1, 3); Stroke(14, 5, 1, 1)
		end
		local glow = button:CreateTexture(nil, "HIGHLIGHT"); glow:SetAllPoints(); glow:SetColorTexture(1, 0.85, 0.5, 0.12)
		if AzerMindTheme and AzerMindTheme.grimoire then
			for _,region in ipairs({button:GetRegions()}) do if region~=glow then region:Hide() end end
			local icon=AzerMindTheme.InkGlyph(button,label:lower())
			button.actionIcon=icon; button.actionKind=label:lower()
			button:HookScript("OnDisable",function() icon:SetAlpha(0.35) end)
			button:HookScript("OnEnable",function() icon:SetAlpha(1) end)
			button:HookScript("OnMouseDown",function() if button:IsEnabled() then icon:SetPoint("CENTER",button,"CENTER",1,-1) end end)
			button:HookScript("OnMouseUp",function() icon:ClearAllPoints(); icon:SetPoint("CENTER",button,"CENTER",0,0) end)
			button:HookScript("OnLeave",function() icon:ClearAllPoints(); icon:SetPoint("CENTER",button,"CENTER",0,0) end)
		end
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(label, 0.91, 0.87, 0.78)
			if label=="Delete" then GameTooltip:AddLine("Remove this message from local history. AI session memory is retained. Undo is available until the next deletion or UI reload.",1,1,1,true)
			elseif label=="Resend" then GameTooltip:AddLine("Send this message again. While another request is running, wait or stop it first.",1,1,1,true) end
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return button
	end
	b.copy = Action("Copy", function(self)
		local message = self:GetParent()
		AzerMind.ShowCopy(message.copyText)
	end)
	b.resend = Action("Resend", function()
		local chat = ActiveChat()
		if not chat or chat.id~=b.chatId or b.role ~= "user" or not b.entry then return end
		if chat.pendingId then if chat.pendingId == b.messageId then AzerMind.Resend() end; return end
		AzerMind.Send(b.entry.text)
	end)
	b.delete = Action("Delete", function()
		if b.entry then AzerMind.DeleteMessage(b.chatId,b.entry) end
	end)
	b.delete:SetPoint("TOPRIGHT", b, "TOPRIGHT", -14, -10)
	b.copy:SetPoint("RIGHT", b.delete, "LEFT", -6, 0)
	b.resend:SetPoint("RIGHT", b.copy, "LEFT", -6, 0)
	b.when:ClearAllPoints(); b.when:SetPoint("TOPRIGHT", b, "TOPRIGHT", -102, -6)
	if AzerMindTheme and AzerMindTheme.grimoire then
		-- Message cards share the leather reading surface; no ornamental frame.
		b.separator=b:CreateTexture(nil,"BORDER")
		b.separator:SetPoint("BOTTOMLEFT",b,"BOTTOMLEFT",14,0)
		b.separator:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-14,0)
		b.separator:SetHeight(1); b.separator:SetColorTexture(0.48,0.35,0.19,0.28)
		b.avatar=b:CreateTexture(nil,"ARTWORK"); b.avatar:SetSize(32,32); b.avatar:SetPoint("TOPLEFT",b,"TOPLEFT",12,-8)
		b.who:ClearAllPoints(); b.who:SetPoint("TOPLEFT",b,"TOPLEFT",48,-12)
		AzerMindTheme.Type(b.who,"senderName")
		b.provider=b:CreateFontString(nil,"OVERLAY"); AzerMindTheme.Type(b.provider,"label")
		b.provider:SetPoint("LEFT",b.who,"RIGHT",6,0); b.provider:SetWordWrap(false)
		AzerMindTheme.PaperFont(b.provider,true)
		AzerMindTheme.MessageOutline(b)
		b.body:ClearAllPoints(); b.body:SetPoint("TOPLEFT",b,"TOPLEFT",14,-54)
		b.when:ClearAllPoints(); b.when:SetPoint("TOPLEFT",b.who,"BOTTOMLEFT",0,-3)
		AzerMindTheme.Type(b.when,"timestamp"); b.when:SetJustifyH("LEFT")
		b.attachment=AzerMindTheme.Button(b,"",200,32,function(self) AzerMind.ShowCopy(self.snapshot) end)
		b.attachment.paper=true; AzerMindTheme.Selected(b.attachment,false)
		b.attachment:SetPoint("TOPLEFT",b,"TOPLEFT",14,-54)
		b.attachment.icon=b.attachment:CreateTexture(nil,"ARTWORK"); b.attachment.icon:SetSize(24,24)
		b.attachment.icon:SetPoint("LEFT",b.attachment,"LEFT",8,0)
		b.attachment.caption:ClearAllPoints(); b.attachment.caption:SetPoint("LEFT",b.attachment,"LEFT",40,0)
		AzerMindTheme.Type(b.attachment.caption,"mainLabel"); AzerMindTheme.PaperFont(b.attachment.caption)
		AzerMindTheme.Tooltip(b.attachment,function() return b.attachment:GetText() end,"Click to inspect the complete inventory snapshot.")
		b.attachment:Hide()
	end
	b:SetScript("OnUpdate", function(self)
		if self.activity then
			local step = math.floor(GetTime() / 0.4) % 3 + 1
			if self.activityStep ~= step then self.activityStep = step; self.body:SetText(self.activity .. string.rep(".", step)) end
		end
		self.copy:SetShown(self.canCopy)
		self.resend:SetShown(self.canResend)
		self.delete:SetShown(self.canCopy)
	end)
	-- FontStrings can't be selected, so a click opens the message in the copy box.
	b:EnableMouse(true)
	if AzerMind.SetupLinks then AzerMind.SetupLinks(b) end
	ui.bubbles[i] = b
	return b
end

function AzerMind.Render()
	if ui.contextToggle then ui.contextToggle:SetText("Context: " .. (not db.settings.context and "Off" or db.settings.contextMode == "full" and "Full" or db.settings.contextMode == "custom" and "Custom" or "Basic")) end
	local c = ActiveChat()
	if ui.undoDelete then ui.undoDelete:SetShown(c and ui.deletedMessage and ui.deletedMessage.chat==c.id or false)
        if ui.listScroll then
            ui.listScroll:ClearAllPoints()
            ui.listScroll:SetPoint("TOPLEFT",ui.listNew,"BOTTOMLEFT",0,-30)
            ui.listScroll:SetPoint("BOTTOMRIGHT",ui.listPanel,"BOTTOMRIGHT",-40,ui.undoDelete:IsShown() and 44 or 8)
        end
    end
	if ui.codexSettings and (not c or ui.codexSettings.chatId ~= c.id) then ui.codexSettings:Hide() end
	if ui.content and c then
		local oldScroll=ui.scroll:GetVerticalScroll() or 0
		local follow=ui.scrollChat~=c.id or oldScroll>=(ui.scroll:GetVerticalScrollRange() or 0)-24
		ui.scrollChat=c.id
		ui.renderVersion=(ui.renderVersion or 0)+1
		local version=ui.renderVersion
		local width = ui.scroll:GetWidth()
		if not width or width < 80 then width = 400 end
		ui.content:SetWidth(width)
		local y, n = 0, 0
		local function Place(role, text, when, dim, denied, agent, macros, messageId)
			n = n + 1
			local b = GetBubble(n)
			local st = ROLE_STYLE[role] or ROLE_STYLE.system
			b:SetWidth(width)
			b.bg:SetColorTexture(st.bg[1], st.bg[2], st.bg[3], st.bg[4])
			if AzerMindTheme and AzerMindTheme.grimoire then
				b.bg:SetColorTexture(0.60,0.40,0.20,role=="assistant" and 0.045 or 0)
				b.accent:Hide()
			end
			b.accent:SetColorTexture(st.color[1], st.color[2], st.color[3], 0.9)
			b.senderLabel=st==ROLE_STYLE.assistant and ("AzerMind - "..ReplyAgentName(c,agent)) or st.label
			b.who:SetText(b.provider and st==ROLE_STYLE.assistant and "AzerMind" or b.senderLabel)
			if b.provider then b.provider:SetText(st==ROLE_STYLE.assistant and ("- "..ReplyAgentName(c,agent)) or "");b.provider:SetShown(st==ROLE_STYLE.assistant) end
			b.who:SetTextColor(st.color[1], st.color[2], st.color[3])
			if AzerMindTheme and AzerMindTheme.grimoire then
				b.who:SetTextColor(role=="assistant" and 0.40 or 0.40,role=="assistant" and 0.12 or 0.28,role=="assistant" and 0.20 or 0.12)
			end
			local senderSpace=math.max(40,width-190)
			b.who:SetWordWrap(false); b.who:SetWidth(0)
			b.who:SetWidth(math.min(senderSpace,math.max(1,b.who:GetStringWidth())))
			if b.provider then b.provider:SetWidth(math.max(20,senderSpace-b.who:GetWidth()-6)) end
			if b.avatar then b.avatar:SetTexture(AzerMindTheme.artRoot..(role=="assistant" and "emblem" or "icon-user")..".tga") end
			b.when:SetText(when or "")
			b.body:SetWidth(width - 18)
			if AzerMindTheme and AzerMindTheme.grimoire then b.body:SetWidth(width-28) end
			local rendered
			local visible,attachment=text,nil
			if AzerMindTheme and AzerMindTheme.grimoire and AzerMind.PresentMessage then visible,attachment=AzerMind.PresentMessage(role,text) end
			local attachmentHeight=attachment and 40 or 0
			if b.attachment then
				b.attachment:SetShown(attachment~=nil)
				b.body:ClearAllPoints(); b.body:SetPoint("TOPLEFT",b,"TOPLEFT",14,-54-attachmentHeight)
				if attachment then
					b.attachment.snapshot=attachment.full; b.attachment:SetText(attachment.label)
					b.attachment.caption:SetWidth(width-80)
					b.attachment:SetWidth(math.min(width-28,math.max(200,b.attachment.caption:GetStringWidth()+52)))
					b.attachment.caption:SetWidth(b.attachment:GetWidth()-48)
					local icon=AzerMindTheme.artRoot.."icon-items.tga"
					local query=(C_Item and C_Item.GetItemInfo) or GetItemInfo
					if attachment.id and query then local info={pcall(query,attachment.id)}; if info[1] and info[11] then icon=info[11] end end
					b.attachment.icon:SetTexture(icon)
				end
			end
			if AzerMind.RichMessage then rendered, b.sources = AzerMind.RichMessage(role, visible)
			else rendered, b.sources = Display(AzerMind.MessageText(role, visible)), nil end
			if AzerMindTheme and AzerMindTheme.grimoire then rendered=AzerMindTheme.PaperText(rendered) end
			b.body:SetText(rendered)
			if dim then
				b.body:SetTextColor(0.72, 0.72, 0.72)
			else
				b.body:SetTextColor(0.93, 0.93, 0.93)
			end
			if AzerMindTheme and AzerMindTheme.grimoire then
				AzerMindTheme.PaperFont(b.body,dim); AzerMindTheme.PaperFont(b.when,true)
				b.who:SetShadowColor(0, 0, 0, 0)
				-- Preserve the authored bronze, parchment and violet icon palette.
			end
			local h = b.body:GetStringHeight()
			if not h or h < 1 then h = 14 end
			local extra = 0
			if denied then
				local label = "Allow " .. table.concat(denied, ", ") .. " & retry"
				b.allow:SetText(label)
				b.allow:SetWidth(math.min(width - 24, math.max(160, b.allow:GetFontString():GetStringWidth() + 30)))
				b.allow.chatId = c.id
				b.allow.rules = denied
				b.allow:Show()
				extra = 28
			else
				b.allow:Hide()
			end
			-- One button per macro the agent handed over.
			local shownMacros = 0
			for k, m in ipairs(macros or {}) do
				local mb = b.macroBtns[k]
				if not mb then
					mb = AzerMindTheme and AzerMindTheme.Button(b,"",160,22,nil) or CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
					mb:SetHeight(22)
					mb:SetScript("OnClick", function(self) AzerMind.InstallMacro(self.macro) end)
					mb:SetScript("OnEnter", function(self)
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
						GameTooltip:AddLine(Display(self.macro.name))
						GameTooltip:AddLine(Display(self.macro.body), 1, 1, 1, true)
						GameTooltip:Show()
					end)
					mb:SetScript("OnLeave", function() GameTooltip:Hide() end)
					b.macroBtns[k] = mb
				end
				mb.macro = m
				mb:SetText(AzerMind.MacroLabel(m))
				mb:SetWidth(math.min(width - 24, math.max(160, mb:GetFontString():GetStringWidth() + 30)))
				mb:ClearAllPoints()
				mb:SetPoint("TOPLEFT", b.body, "BOTTOMLEFT", 0, -6 - extra)
				mb:Show()
				extra = extra + 28
				shownMacros = k
			end
			for k = shownMacros + 1, #b.macroBtns do b.macroBtns[k]:Hide() end
			b.role, b.messageId = role, messageId
			b.activity = dim and role == "assistant" and c.pendingId and AzerMind.PendingState(c) or nil
			b.activityStep = nil
			local canCopy = not dim
			b.canCopy = canCopy
			b.copyText = AzerMind.CopyMessage and AzerMind.CopyMessage(role, text) or AzerMind.MessageText(role, text)
			b.entry = not dim and c.history[n] or nil
			b.chatId=c.id
			b.canResend = canCopy and role == "user"
			b.resend:SetEnabled(not c.pendingId or c.pendingId == messageId)
			b.latest = not dim and n == #c.history
			b.copy:SetShown(b.canCopy)
			b.copy:ClearAllPoints(); b.copy:SetPoint("RIGHT",b.delete,"LEFT",-6,0)
			b.resend:SetShown(b.canResend)
			b.delete:SetShown(b.canCopy)
			b:SetHeight(6 + 12 + 12 + h + 8 + extra)
			if AzerMindTheme and AzerMindTheme.grimoire then b:SetHeight(68+h+extra+attachmentHeight) end
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", ui.content, "TOPLEFT", 0, -y)
			b.text = text
			b:Show()
			y = y + b:GetHeight() + 4
		end
		local last = #c.history
		for i, m in ipairs(c.history) do
			-- The Allow button only makes sense on the newest reply, and only while idle.
			local denied = (i == last and not c.pendingId and type(m.denied) == "table" and #m.denied > 0) and m.denied or nil
			Place(m.role, m.text, m.t and date("%H:%M", m.t) or "", false, denied, m.agent, m.macros, m.id)
		end
		if c.pendingId then
			Place("assistant", AzerMind.PendingState(c) .. "...", "", true, nil, ChatAgent(c))
		elseif #c.history == 0 then
			if run.restoring then
				Place("system", "Connecting to the bridge and restoring your chats...", "", true)
			elseif not AzerMind.IsConnected() then
				Place("system", "Not connected to the bridge. Start it (npm start in the azermind folder, or azermind in your project), then click Connect below.", "", true)
			else
				Place("system", "Click the box below and type to start. Shift-click an item, spell or quest to link it into your message. /azermind help lists the commands; /ai <text> and /r work from the game chat too.", "", true)
			end
		end
		for i = n + 1, #ui.bubbles do
			ui.bubbles[i]:Hide()
		end
		ui.content:SetHeight(math.max(y, 1))
		C_Timer.After(0.05, function()
			if ui.scroll and version==ui.renderVersion and db.activeChat==c.id then
				ui.scroll:SetVerticalScroll(follow and ui.scroll:GetVerticalScrollRange() or math.min(oldScroll,ui.scroll:GetVerticalScrollRange()))
			end
		end)
	end
	AzerMind.UpdateStatus()
	AzerMind.RenderChatList()
end

-- Copy box (/azermind copy): a selectable EditBox with the last reply pre-highlighted for Ctrl+C.
function AzerMind.ShowCopy(text)
	if not ui.copy then
		local cf = CreateFrame("Frame", "AzerMindCopy", UIParent, "BackdropTemplate")
		cf:SetSize(560, 320)
		cf:SetPoint("CENTER")
		cf:SetFrameStrata("FULLSCREEN_DIALOG")
		cf:SetMovable(true)
		cf:SetClampedToScreen(true)
		cf:EnableMouse(true)
		cf:RegisterForDrag("LeftButton")
		cf:SetScript("OnDragStart", cf.StartMoving)
		cf:SetScript("OnDragStop", cf.StopMovingOrSizing)
		cf:SetBackdrop(BACKDROP)
		cf:SetBackdropColor(0.055, 0.049, 0.039, 1)
		if AzerMindTheme then AzerMindTheme.Glow(cf, 0.20); AzerMindTheme.FitDialog(cf) end
		cf:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
		tinsert(UISpecialFrames, "AzerMindCopy")

		local t = cf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, -12)
		t:SetText("Text is selected - press Ctrl+C, then Esc")

		local x = AzerMindTheme and AzerMindTheme.Button(cf,"x",24,24,nil) or CreateFrame("Button", nil, cf, "UIPanelCloseButton")
		x:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -4, -4)

		local sc = CreateFrame("ScrollFrame", "AzerMindCopyScroll", cf, "UIPanelScrollFrameTemplate")
		sc:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, -36)
		sc:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -32, 14)
		local eb = CreateFrame("EditBox", "AzerMindCopyBox", sc)
		eb:SetMultiLine(true)
		eb:SetAutoFocus(false)
		eb:SetFontObject(ChatFontNormal)
		if AzerMindTheme then AzerMindTheme.Type(eb, "body") end
		eb:SetMaxLetters(0)
		eb:SetSize(500, 260)
		eb:SetScript("OnEscapePressed", function() cf:Hide() end)
		sc:SetScrollChild(eb)
		sc:HookScript("OnSizeChanged", function(self, w) eb:SetWidth(w) end)
		ui.copy, ui.copyBox = cf, eb
		cf:SetScript("OnHide",function() eb:ClearFocus() end)
	end
	ui.copyBox:SetText(text)
	ui.copy:SetFrameLevel((ui.frame and ui.frame:GetFrameLevel() or 1)+240)
	ui.copy:Show()
	ui.copyBox:SetFocus()
	ui.copyBox:HighlightText()
end

function AzerMind.RenderChatList()
	if not ui.chatButtons then return end
	if ui.chatListContent then ui.chatListContent:SetHeight(math.max(1, #db.chats * 34)) end
	for i, btn in ipairs(ui.chatButtons) do
		local c = db.chats[i]
		if c then
			local label = Display(c.name)
			if c.pendingId then
				label = label .. " |cffffd100...|r"
			elseif (c.unread or 0) > 0 then
				label = label .. " |cff55ff55(" .. c.unread .. ")|r"
			end
			btn.label:SetText(label)
			btn.chatId = c.id
			btn.selected:SetShown(c.id == db.activeChat)
			if AzerMindTheme and AzerMindTheme.grimoire then
				local selected=c.id==db.activeChat
				local skin=AzerMindTheme.Frame(btn,selected and "conversation-selection" or "button-secondary",8)
				for i,part in ipairs(skin.parts) do part:SetAlpha(i==5 and 1 or (selected and 0.65 or 0.22)) end
				btn.selected:SetDrawLayer("ARTWORK",0)
				btn.label:SetTextColor(0.91,0.87,0.78)
				btn.del:Hide()
			end
			if btn.activeBar then btn.activeBar:SetDrawLayer("OVERLAY",1); btn.activeBar:SetShown(c.id == db.activeChat) end
			btn:Show()
		else
			btn:Hide()
		end
	end
end

function AzerMind.UpdateMini()
	if not ui.miniBadge then return end
	local unread, working = 0, 0
	for _, c in ipairs(db.chats) do
		unread = unread + (c.unread or 0)
		if c.pendingId then working = working + 1 end
	end
	local t
	if working > 0 and unread > 0 then
		t = "|cff55ff55" .. unread .. " new|r |cffffd100" .. working .. " working|r"
	elseif working > 0 then
		t = "|cffffd100" .. (working == 1 and "working..." or (working .. " working...")) .. "|r"
	elseif unread > 0 then
		t = "|cff55ff55" .. unread .. (unread == 1 and " new reply" or " new replies") .. "|r"
	else
		t = "|cff999999idle|r"
	end
	ui.miniBadge:SetText(t)
	if ui.miniPulse then
		if unread > 0 then
			if not ui.miniPulse:IsPlaying() then ui.miniPulse:Play() end
		else
			ui.miniPulse:Stop()
			ui.miniBadge:SetAlpha(1)
		end
	end
end

local ECHO_DEFAULT = 4000 -- characters of a reply to print into the game chat ("/azermind echo <n>")

local function ChatLinks(chat)
	return "  |Hazermind:reply:" .. chat.id .. "|h|cff55ff55[reply]|r|h |Hazermind:open:" .. chat.id .. "|h|cff7ec8ff[open]|r|h"
end

local SUMMARY_LINES = 3 -- lines of the agent's TL;DR block printed in "summary" mode
local SUMMARY_FALLBACK_LINES = 2 -- lines of the reply shown when it came without one

-- Print a reply into the game chat: prefix on the first line, then the text line
-- by line up to the limit, then clickable links. `short` prints one preview line.
-- `summary` (the default) prints the TL;DR block the bridge split off the reply,
-- or the first lines of the reply when the agent didn't write one; the full text
-- is in the window, behind [open].
local function EchoToChat(chat, text, agent, summary)
	local mode = db.settings.echo
	if mode == "off" then return end
	local prefix = "|cff7ec8ff[" .. ReplyAgentName(chat, agent) .. " · " .. Display(chat.name) .. "]|r "
	local body = Display(text)
	if mode == "short" then
		local flat = (body:gsub("%s+", " "))
		if #flat > 200 then flat = flat:sub(1, 200) .. " ..." end
		print(prefix .. flat .. ChatLinks(chat))
		return
	end
	if mode == "summary" then
		local source, max = Display(summary or ""), SUMMARY_LINES
		if not source:match("%S") then source, max = body, SUMMARY_FALLBACK_LINES end
		local lines, total = {}, 0
		for line in (source .. "\n"):gmatch("(.-)\n") do
			if line:match("%S") then
				total = total + 1
				if total <= max then table.insert(lines, line) end
			end
		end
		for i, line in ipairs(lines) do
			print((i == 1 and prefix or "    ") .. line)
		end
		if total > max then
			print("    |cff888888... click [open] to read it all|r")
		end
		print("    " .. ChatLinks(chat):sub(3))
		return
	end
	local limit = tonumber(mode) or ECHO_DEFAULT
	local first, shown = true, 0
	for line in (body .. "\n"):gmatch("(.-)\n") do
		if line:match("%S") then
			if shown + #line > limit then
				print("    |cff888888... " .. (#body - shown) .. " more characters, click [open] to read it all|r")
				break
			end
			print((first and prefix or "    ") .. line)
			first = false
			shown = shown + #line
		end
	end
	print("    " .. ChatLinks(chat):sub(3))
end

-- A reply landed. Always play the sound and echo it to the game chat; if that
-- chat isn't on screen, also flash the screen text and light up the mini bar.
function AzerMind.Notify(chat, text, agent, summary)
	local sound=db.settings.replySound
    if sound==nil then sound=3081 end
    if sound~=0 then pcall(PlaySound,sound,"Master") end
	AzerMind.UpdateMini()
	-- Until a real whisper arrives, /r replies to this chat.
	run.lastMessenger = "agent"
	run.lastReplyChat = chat.id
	EchoToChat(chat, text, agent, summary)
	if ui.frame and ui.frame:IsShown() and db.activeChat == chat.id then return end
	if UIErrorsFrame then
		UIErrorsFrame:AddMessage(ReplyAgentName(chat, agent) .. " replied in " .. Display(chat.name), 0.5, 0.8, 1, 1)
	end
end

-- /r goes to the agent when it was the last one to message you, exactly like
-- whisper reply, and the box shows a "To Codex [chat]:" header while you type.
--
-- The chat type underneath is left alone (a custom type would leak into chat
-- settings); instead the box remembers an agent target, the header is repainted
-- over the game's own, and the send entry points are intercepted. Any other chat
-- type, Tab, Esc or a cleared box drops the target again.
local AGENT_R, AGENT_G, AGENT_B = 0.49, 0.78, 1.0

local function PaintAgentHeader(eb, chat)
	local header = _G[eb:GetName() .. "Header"]
	local suffix = _G[eb:GetName() .. "HeaderSuffix"]
	if not header then return end
	eb.agentPainting = true
	eb:UpdateHeader() -- lay out normally first, then repaint
	eb.agentPainting = nil
	header:SetWidth(0)
	header:SetText("To " .. ChatAgentName(chat) .. " [" .. Display(chat.name) .. "]: ")
	header:SetTextColor(AGENT_R, AGENT_G, AGENT_B)
	if suffix then suffix:Hide() end
	eb:SetTextInsets(15 + header:GetWidth(), 13, 0, 0)
	eb:SetTextColor(AGENT_R, AGENT_G, AGENT_B)
end

local function SendBoxToAgent(eb)
	local chat = FindChat(eb.agentTarget)
	local text = Trim(eb:GetText() or "")
	eb.agentTarget = nil
	eb:ClearChat()
	if chat and db.activeChat ~= chat.id then AzerMind.SwitchChat(chat.id) end
	if text ~= "" then
		AzerMind.Send(text)
	else
		AzerMind.Toggle(true)
		if ui.input then ui.input:SetFocus() end
	end
end

local function HookReplyCommand()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local eb = _G["ChatFrame" .. i .. "EditBox"]
		if eb and eb.ProcessChatType and not eb.agentReplyHooked then
			eb.agentReplyHooked = true

			local origProcess = eb.ProcessChatType
			eb.ProcessChatType = function(self, msg, index, send, ...)
				if index ~= "REPLY" then
					self.agentTarget = nil
					return origProcess(self, msg, index, send, ...)
				end
				if not (db and run.lastMessenger == "agent") then
					return origProcess(self, msg, index, send, ...)
				end
				local chat = FindChat(run.lastReplyChat) or ActiveChat()
				if send == 1 then
					self:SetText(msg or "")
					self.agentTarget = chat and chat.id
					SendBoxToAgent(self)
					return true
				end
				self.agentTarget = chat and chat.id
				self:SetText(msg or "")
				if chat then PaintAgentHeader(self, chat) end
				return true
			end

			-- Enter arrives here; nothing below us ever sees an agent-targeted box.
			for _, name in ipairs({ "SendMessage", "SendText" }) do
				local orig = eb[name]
				if orig then
					eb[name] = function(self, ...)
						if self.agentTarget then
							SendBoxToAgent(self)
							return
						end
						return orig(self, ...)
					end
				end
			end

			-- Anything that repaints the header normally (Tab, /s, sticky reset) ends agent mode.
			hooksecurefunc(eb, "UpdateHeader", function(self)
				if not self.agentPainting then self.agentTarget = nil end
			end)
			hooksecurefunc(eb, "ClearChat", function(self)
				self.agentTarget = nil
			end)
		end
	end
end

-- Clicks on our [reply] / [open] links in the chat frame.
hooksecurefunc("SetItemRef", function(link)
	local action, chatId = tostring(link):match("^azermind:(%a+):(%w+)")
	if not action or not db then return end
	if FindChat(chatId) then AzerMind.SwitchChat(chatId) end
	AzerMind.Toggle(true)
	if action == "reply" and ui.input then ui.input:SetFocus() end
end)

-- Shift-clicking an item, spell, quest or name puts its link into the chat box
-- being typed in. Blizzard's insert function only knows its own boxes, so when
-- ours has the keyboard, take the link too. With no box focused the shift-click
-- keeps its normal meaning (splitting a stack, for one).
--
-- On this client (modern UI code, Blizzard_ChatFrameUtil) every shift-click
-- ends in ChatFrameUtil.InsertLink; ChatEdit_InsertLink is the older global
-- name, hooked only where the new one is missing so one click inserts once.
local function TakeLink(text)
	if text and text ~= "" and ui.input and ui.input:HasFocus() then
		if AzerMind.NormalizeItemLink then text = AzerMind.NormalizeItemLink(text) end
		ui.input:Insert(text)
	end
end
if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
	hooksecurefunc(ChatFrameUtil, "InsertLink", TakeLink)
elseif type(ChatEdit_InsertLink) == "function" then
	hooksecurefunc("ChatEdit_InsertLink", TakeLink)
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

local function MakeButton(parent, label, width, onClick, plain)
	if AzerMindTheme then
		local button=AzerMindTheme.Button(parent,label,width,22,onClick,nil,plain)
		if AzerMindTheme.grimoire then AzerMindTheme.Type(button.caption,"mainLabel") end
		return button
	end
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

-- Keep overrides scoped to the provider; old Codex choices remain compatible.
function AzerMind.ChatAISettings(c, agent)
	local id = agent or ChatAgent(c)
	if c.aiSettings and c.aiSettings[id] then return c.aiSettings[id] end
	if id == "codex" then return {model=c.codexModel, reasoning=c.codexReasoning} end
	return {}
end
function AzerMind.SettingsState(id, agent)
	local c = (id and FindChat(id)) or ActiveChat()
	local defaults = run.aiDefaults or {agent=run.bridgeAgent or "codex",model="",reasoning=""}
	local selected = agent or (c and ChatAgent(c)) or defaults.agent
	local meta = run.agentSettings and run.agentSettings[selected]
	local models = meta and meta.models or (selected == "codex" and run.codexModels or {}) or {}
	return c, defaults, models, run.bridgeAgents or {"codex","claude","grok","agy","hermes"}, run.settingsPending,
		meta or {model="",reasoning="",efforts=selected == "codex" and {"low","medium","high"} or {} }
end

function AzerMind.GetOpacity()
 return db and db.settings.opacity or 1
end
function AzerMind.SetOpacity(value)
 value=tonumber(value)
 if not value or value~=value then return false end
 value=math.max(0.35,math.min(1,value))
 db.settings.opacity=value
 if AzerMindTheme then AzerMindTheme.ApplyOpacity(value) end
 return true
end

function AzerMind.AttachSettingsPanel(panel)
	ui.codexSettings = panel
end

function AzerMind.ModelEfforts(agent,model)
	local _,_,models,_,_,meta=AzerMind.SettingsState(nil,agent)
	local selected=model~="" and model or meta.model
	for _,entry in ipairs(models) do
		if entry.model==selected then return entry.efforts or {},entry.effortsKnown~=false end
	end
	return {},false
end

function AzerMind.RefreshModelChoices()
	if not AzerMind.IsConnected() or db.settings.mode~="pixel" then return false,"Connect the bridge in pixel mode to refresh models." end
	if run.modelsPending or run.settingsPending then return false,"Wait for the current settings request." end
	local chat=ActiveChat(); if not chat then return false,"Conversation no longer exists." end
	db.lastSeq=db.lastSeq+1
	local seq=db.lastSeq
	run.outbound[seq]={chat=chat.id,cwd="",flags="settings",name="Refresh models",text='{"action":"refresh-models"}',sentAt=GetTime(),catalogRefresh=true}
	run.modelsPending=seq; RefreshStrip()
	return true,"Refreshing model choices..."
end

function AzerMind.SaveAISettings(id, scope, values)
	local c = (id and FindChat(id)) or ActiveChat()
	if not c then return false, "Conversation no longer exists." end
	if values.model ~= "" and (not values.model:match("^[%w][%w_./:@+%[%]%-]*$") or #values.model > 200) then
		return false, "Enter a model ID without spaces or control characters."
	end
	if not (scope=="conversation" and values.inherit) and values.reasoning~="" then
		local efforts,known=AzerMind.ModelEfforts(values.agent,values.model)
		local valid=false; for _,effort in ipairs(efforts) do if effort==values.reasoning then valid=true end end
		if not known or not valid then return false,"Select a reasoning level supported by this model, or use Automatic." end
	end
	if scope == "conversation" then
		if c.pendingId then return false, "Wait for the current reply before saving." end
		c.agent = values.inherit and "" or values.agent
		c.aiSettings = c.aiSettings or {}
		c.aiSettings[values.agent] = {model=values.inherit and "" or values.model, reasoning=values.inherit and "" or values.reasoning}
		if values.agent == "codex" then
			c.codexModel = values.inherit and "" or values.model
			c.codexReasoning = values.inherit and "" or values.reasoning
		end
		c.resetNext = true
		AzerMind.Render()
		return true, "Conversation settings saved. Next message starts a fresh session."
	end
	if not AzerMind.IsConnected() or db.settings.mode ~= "pixel" then return false, "Connect the bridge in pixel mode before saving defaults." end
	if run.settingsPending or run.modelsPending then return false, "Waiting for the current settings request." end
	db.lastSeq = db.lastSeq + 1
	local seq = db.lastSeq
	local function Json(s) return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
	local text = '{"agent":' .. Json(values.agent) .. ',"model":' .. Json(values.model) .. ',"reasoning":' .. Json(values.reasoning) .. '}'
	run.outbound[seq] = { chat = c.id, cwd = "", flags = "settings", name = "AI settings", text = text, sentAt = GetTime(), settings = true }
	run.settingsPending = seq
	RefreshStrip()
	return true, "Saving defaults... waiting for bridge confirmation."
end

local PANEL_W = 240

local function WindowBounds()
	local maxWidth = UIParent:GetWidth() * 0.95
	local maxHeight = UIParent:GetHeight() * 0.95
	return math.min(900, maxWidth), math.min(600, maxHeight), maxWidth, maxHeight
end

function AzerMind.ResetUI()
	if not ui.frame then return end
	local minW, minH, maxW, maxH = WindowBounds()
	local s = db.settings
	s.width, s.height = math.max(minW, math.min(820, maxW)), math.max(minH, math.min(540, maxH))
	s.point, s.relPoint, s.x, s.y = "CENTER", "CENTER", 0, 0
	ui.frame:StopMovingOrSizing()
	ui.frame:ClearAllPoints()
	ui.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	ui.frame:SetSize(s.width, s.height)
	AzerMind.Toggle(true)
	AzerMind.Render()
end

local function BuildUI()
	if ui.frame then return end
	local s = db.settings

	local f = CreateFrame("Frame", "AzerMindFrame", UIParent, "BackdropTemplate")
	ui.frame = f
	if AzerMindTheme then AzerMindTheme.RegisterOpacity(f) end
	local minW, minH, maxW, maxH = WindowBounds()
	s.width, s.height = math.max(minW, math.min(s.width, maxW)), math.max(minH, math.min(s.height, maxH))
	f:SetSize(s.width, s.height)
	if s.point then
		f:SetPoint(s.point, UIParent, s.relPoint or s.point, s.x or 0, s.y or 0)
	else
		f:SetPoint("CENTER")
	end
	if AzerMindTheme then AzerMindTheme.Window(f,"MEDIUM") else f:SetFrameStrata("MEDIUM"); f:SetToplevel(true) end
	f:SetMovable(true)
	f:SetResizable(true)
	f:SetClampedToScreen(true)
	f:SetResizeBounds(minW, minH, maxW, maxH)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		s.point, s.relPoint, s.x, s.y = point, relPoint, x, y
	end)
	f:SetBackdrop(BACKDROP)
	f:SetBackdropColor(0.055, 0.049, 0.039, 0.97)
	if AzerMindTheme then AzerMindTheme.Glow(f, 0.24) end
	f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Panel(f,"frame-window",32) end
	f:Hide()
	tinsert(UISpecialFrames, "AzerMindFrame")

	-- Status light: green = bridge seen recently, yellow = stale, red = gone.
	local function MakeDot(parent)
		local holder = CreateFrame("Frame", nil, parent)
		holder:SetSize(16, 16)
		local dot = holder:CreateTexture(nil, "OVERLAY")
		dot:SetAllPoints()
		dot:SetTexture("Interface\\FriendsFrame\\StatusIcon-Offline")
		holder:EnableMouse(true)
		holder:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(dot.tip or "Bridge status", 0.9, 0.9, 0.9, 1, true)
			if ui.latencyDetails then GameTooltip:AddLine(ui.latencyDetails,0.8,0.8,0.8) end
			GameTooltip:Show()
		end)
		holder:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return holder, dot
	end

	local dotHolder, dot = MakeDot(f)
	dotHolder:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -16)
	if AzerMindTheme and AzerMindTheme.grimoire then
		local emblem = f:CreateTexture(nil, "ARTWORK")
		emblem:SetSize(60,60); emblem:SetPoint("TOPLEFT", f, "TOPLEFT", 32, -28)
		emblem:SetTexture(AzerMindTheme.artRoot .. "emblem.tga")
		dotHolder:ClearAllPoints(); dotHolder:SetPoint("TOPLEFT", f, "TOPLEFT", 108, -52)
		local brand = AzerMindTheme.Label(f, "AzerMind", 108, -28, "GameFontNormal")
		AzerMindTheme.Type(brand,"brand")
		brand:SetTextColor(0.90, 0.74, 0.39)
	end
	ui.dot = dot

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	if AzerMindTheme then AzerMindTheme.Type(title, "title") end
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Type(title,"mainTitle") end
	local titleBand=CreateFrame("Frame",nil,f)
	titleBand:SetPoint("TOPLEFT",f,"TOPLEFT",PANEL_W+32,-21)
	titleBand:SetPoint("TOPRIGHT",f,"TOPRIGHT",-210,-21); titleBand:SetHeight(44)
	title:SetPoint("CENTER",titleBand,"CENTER",0,0)
	local function LayoutTitle()
		local width=math.max(80,titleBand:GetWidth()-96)
		title:SetWidth(width); title:SetWidth(math.min(width,math.max(60,title:GetStringWidth())))
	end
	ui.layoutTitle=LayoutTitle; f:HookScript("OnSizeChanged",LayoutTitle)
	if AzerMindTheme then AzerMindTheme.TitleOrnaments(titleBand,title); AzerMindTheme.Tooltip(titleBand,function() return title:GetText() end) end
	titleBand:EnableMouse(true); titleBand:RegisterForDrag("LeftButton")
	titleBand:SetScript("OnDragStart",function() f:StartMoving() end)
	titleBand:SetScript("OnDragStop",function()
		f:StopMovingOrSizing()
		local point,_,relPoint,x,y=f:GetPoint(); s.point,s.relPoint,s.x,s.y=point,relPoint,x,y
	end)
	ui.titleBand=titleBand; LayoutTitle()
	if AzerMindTheme then
		local seam=CreateFrame("Frame",nil,f); seam:SetPoint("TOPLEFT",f,"TOPLEFT",28,-16)
		seam:SetPoint("TOPRIGHT",f,"TOPRIGHT",-28,-16); seam:SetHeight(76)
		AzerMindTheme.Stitches(seam,0,true)
	end
	title:SetWordWrap(false); title:SetJustifyH("CENTER")
	title:SetText("AzerMind")
	ui.title = title
	ui.titleHorizontalInset = PANEL_W + 232
	local latency = f:CreateFontString("AzerMindLatency", "OVERLAY", "GameFontHighlightSmall")
	-- Network latency gets a separate row below bridge status.
	latency:SetTextColor(0.55, 0.55, 0.52, 1)
	latency:SetWordWrap(false)
	ui.latency = latency
	AzerMind.UpdateLatency()

	local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("LEFT", dotHolder, "RIGHT", 4, 0)
	status:SetWidth(PANEL_W - 24)
	if AzerMindTheme and AzerMindTheme.grimoire then status:SetWidth(PANEL_W - 90) end
	status:SetWordWrap(false)
	status:SetJustifyH("LEFT")
	ui.status = status
	local latencyIcon=CreateFrame("Frame","AzerMindLatencyIcon",f)
	latencyIcon:SetSize(12,12); latencyIcon:SetPoint("TOPLEFT",f,"TOPLEFT",110,-70)
	for i=0,2 do
		local bar=latencyIcon:CreateTexture(nil,"ARTWORK")
		bar:SetSize(2,3+i*3); bar:SetPoint("BOTTOMLEFT",latencyIcon,"BOTTOMLEFT",i*4,1)
		bar:SetColorTexture(0.70,0.60,0.40,1)
	end
	latency:SetPoint("LEFT",latencyIcon,"RIGHT",6,0)
	latency:SetWidth(76); latency:SetJustifyH("LEFT")

	-- Minimize button in the corner where a close X would be: this window is never
	-- closed from here, only collapsed to the mini bar (Esc does the same, see OnHide).
	-- The mini bar's own X is the one that hides everything.
	local mini
	if not (AzerMindTheme and AzerMindTheme.grimoire) and C_Texture and C_Texture.GetAtlasExists and C_Texture.GetAtlasExists("RedButton-MiniCondense") then
		local ok, b = pcall(CreateFrame, "Button", nil, f, "UIPanelHideButtonNoScripts")
		if ok and b then mini = b end
	end
	if not mini then
		mini = CreateFrame("Button", nil, f)
		mini:SetSize(24, 24)
		local dash = mini:CreateTexture(nil, "ARTWORK")
		dash:SetDrawLayer("OVERLAY",7)
		dash:SetSize(10, 2)
		dash:SetPoint("CENTER", mini, "CENTER", 0, -3)
		dash:SetColorTexture(0.9, 0.9, 0.9, 1)
		local hl = mini:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.15)
	end
	mini:SetSize(30,30)
	mini:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -28)
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Frame(mini,"button-secondary",6) end
	mini:SetScript("OnClick", function() AzerMind.Minimize(true) end)
	mini:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Minimize to the small bar  (Esc)", 0.91, 0.87, 0.78)
		GameTooltip:AddLine("The agent keeps working; the bar shows when a reply lands.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Esc (via UISpecialFrames) just calls Hide(); treat that as a minimize unless
	-- we're hiding on purpose. Ignore hides caused by the whole UI going away.
	f:SetScript("OnHide", function()
		if ui.input then ui.input:ClearFocus() end
		if ui.quitting then
			ui.quitting = nil
			return
		end
		if not db or not db.settings.shown or not UIParent:IsShown() then return end
		db.settings.minimized = true
		if ui.mini then ui.mini:Show() end
		AzerMind.UpdateMini()
	end)

	-- Left panel: chat list
	local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
	panel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -100)
	panel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 30)
	panel:SetWidth(PANEL_W)
	panel:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0.055, 0.049, 0.039, 1)
	if AzerMindTheme then AzerMindTheme.Surface(panel, "panel") end
	panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Panel(panel,"frame-panel",10); AzerMindTheme.Stitches(panel,6) end

	local newBtn = MakeButton(panel, "+ New chat", PANEL_W - 16, function() AzerMind.NewChat() end)
	newBtn:SetPoint("TOP", panel, "TOP", 0, -8)
	newBtn:SetHeight(36)
	if AzerMindTheme and AzerMindTheme.grimoire then newBtn.paper=true; AzerMindTheme.Selected(newBtn,false); AzerMindTheme.Type(newBtn.caption,"paperHeading") end
	local listTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	listTitle:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 4, -12)
	listTitle:SetText("CONVERSATIONS")
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Type(listTitle,"mainLabel"); listTitle:SetTextColor(0.90,0.74,0.39) end
	local listScroll = CreateFrame("ScrollFrame", "AzerMindConversationScroll", panel, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 0, -30)
	listScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -40, 8)
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Scrollbar(listScroll) end
    ui.listScroll=listScroll; ui.listNew=newBtn; ui.listPanel=panel
	ui.undoDelete=MakeButton(panel,"Undo deletion",PANEL_W-16,AzerMind.UndoMessageDeletion)
	ui.undoDelete:SetPoint("BOTTOM",panel,"BOTTOM",0,8); ui.undoDelete:Hide()
	local listContent = CreateFrame("Frame", nil, listScroll)
	listContent:SetSize(PANEL_W - 54, MAX_CHATS * 34)
	listScroll:SetScrollChild(listContent)
	ui.chatListContent = listContent

	-- Per-chat menu: Rename, Folder and Agent, opened by right-clicking a chat
	-- row. A plain frame of our own rather than a Blizzard dropdown, so it looks
	-- the same on every client.
	local menu = CreateFrame("Frame", "AzerMindChatMenu", f, "BackdropTemplate")
	menu:SetSize(150, 6 * 20 + 12)
	menu:SetFrameStrata("TOOLTIP")
	menu:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	menu:SetBackdropColor(0.085, 0.075, 0.058, 1)
	menu:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Material(menu,"leather"); AzerMindTheme.Panel(menu,"frame-popup",8) end
	menu:EnableMouse(true)
	menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -8)
	menu.title:SetPoint("RIGHT", menu, "RIGHT", -8, 0)
	menu.title:SetJustifyH("LEFT")
	menu.title:SetWordWrap(false)
	local function MenuItem(label, order, onClick)
		local it = CreateFrame("Button", nil, menu)
		it:SetSize(180 - 12, 24)
		it:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6 - order * 24)
		local hl = it:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.12)
		it.label = it:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		it.label:SetPoint("LEFT", it, "LEFT", 6, 0)
		it.label:SetText(label)
		it:SetScript("OnClick", function()
			menu:Hide()
			onClick(menu.chatId)
		end)
		return it
	end
	MenuItem("Rename...", 1, AzerMind.RenamePrompt)
	MenuItem("Folder...", 2, AzerMind.FolderPrompt)
	MenuItem("Agent...", 3, AzerMind.AgentPrompt)
	MenuItem("Clear local history", 4, function(id)
		local chat = FindChat(id)
		if chat then wipe(chat.history) end
		if ui.deletedMessage and ui.deletedMessage.chat==id then ui.deletedMessage=nil end
		AzerMind.Render()
	end)
	local codexItem = MenuItem("AI settings...", 5, AzerMind.CodexPrompt)
	MenuItem("Delete conversation...",7,AzerMind.ConfirmDelete)
	MenuItem("Reset AI session",6,function(id)
		local chat=FindChat(id)
		if not chat then return end
		chat.resetNext=true
		AddHistory(chat,"system","The next message starts a fresh AI session. Local history is kept.")
		AzerMind.Render()
	end)
	-- Close once the mouse has wandered away from the menu and the row it came from.
	menu:SetScript("OnUpdate", function(self, dt)
		if not MouseIsOver then return end
		if MouseIsOver(self) or (self.owner and MouseIsOver(self.owner)) then
			self.away = 0
		else
			self.away = (self.away or 0) + dt
			if self.away > 0.5 then self:Hide() end
		end
	end)
	menu:Hide()
	ui.chatMenu = menu

	function AzerMind.ShowChatMenu(chatId, anchor)
		local c = FindChat(chatId)
		if not c then return end
		if menu:IsShown() and menu.chatId == chatId then
			menu:Hide()
			return
		end
		menu.chatId = chatId
		codexItem:Show()
		menu:SetSize(180, 8 * 24 + 12)
		menu.owner = anchor
		menu.away = 0
		menu.title:SetText(Display(c.name))
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 8, 2)
		menu:Show()
	end

	ui.chatButtons = {}
	for i = 1, MAX_CHATS do
		local b = CreateFrame("Button", nil, listContent)
		b:SetSize(PANEL_W - 54, 32)
		b:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -(i - 1) * 34)
		if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Material(b,"leather",0) end
		b.selected = b:CreateTexture(nil, "BACKGROUND")
		b.selected:SetAllPoints()
		b.selected:SetColorTexture(0.12, 0.24, 0.23, 1)
		if AzerMindTheme and AzerMindTheme.grimoire then b.selected:SetColorTexture(0.29,0.07,0.08,1) end
		b.selected:Hide()
		b.activeBar = b:CreateTexture(nil, "BORDER")
		b.activeBar:SetPoint("TOPLEFT"); b.activeBar:SetPoint("BOTTOMLEFT"); b.activeBar:SetWidth(2)
		b.activeBar:SetColorTexture(0.60, 0.90, 0.95, 1); b.activeBar:Hide()
		if AzerMindTheme and AzerMindTheme.grimoire then b.activeBar:SetColorTexture(0.90,0.74,0.39,1) end
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(0.60, 0.90, 0.95, 0.08)
		if AzerMindTheme and AzerMindTheme.grimoire then hl:SetColorTexture(0.94,0.80,0.52,0.12) end

		-- Trash can: delete this chat (asks first). Blizzard's red delete button
		-- where the client has it, a plain X elsewhere.
		b.del = MakeButton(b, "", 24, function() AzerMind.ConfirmDelete(b.chatId) end)
		if AzerMindTheme then AzerMindTheme.Icon(b.del,"delete",4,-4) else b.del:SetText("Delete") end
		b.del:SetSize(24, 24)
		b.del:SetPoint("RIGHT", b, "RIGHT", -3, 0)
		b.menu=MakeButton(b,"...",20,function() AzerMind.ShowChatMenu(b.chatId,b) end)
		b.menu:SetPoint("RIGHT",b,"RIGHT",-6,0)
		if AzerMindTheme and AzerMindTheme.grimoire then
			b.menu.caption:SetText("")
			b.menu.fill:SetAlpha(0)
			b.menu.dots={}
			for offset=-5,5,5 do
				local dot=b.menu:CreateTexture(nil,"OVERLAY",nil,7)
				dot:SetSize(3,3); dot:SetPoint("CENTER",b.menu,"CENTER",0,offset)
				dot:SetColorTexture(0.78,0.66,0.43,1)
				b.menu.dots[#b.menu.dots+1]=dot
			end
			for _,part in ipairs(b.menu.grimoireFrame.parts) do part:SetAlpha(0) end
		end
		if AzerMindTheme then AzerMindTheme.Tooltip(b.menu,"Conversation actions","Rename, folder, agent, local history and AI settings.") end
		b.del:SetAlpha(1)
		b.del:SetScript("OnClick", function() AzerMind.ConfirmDelete(b.chatId) end)
		b.del:SetScript("OnEnter", function(self)
			self:SetAlpha(1)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Delete this chat", 0.91, 0.87, 0.78)
			GameTooltip:Show()
		end)
		b.del:SetScript("OnLeave", function(self)
			self:SetAlpha(1)
			GameTooltip:Hide()
		end)

		b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		if AzerMindTheme then AzerMindTheme.Type(b.label, "conversation") end
		b.label:SetPoint("LEFT", b, "LEFT", 9, 0)
		b.label:SetTextColor(0.93, 0.91, 0.85)
		b.label:SetPoint("RIGHT", b.menu, "LEFT", -4, 0)
		b.label:SetJustifyH("LEFT")
		b.label:SetWordWrap(false)
		b:SetScript("OnEnter", function(self)
			local chat = FindChat(self.chatId)
			if chat then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(Display(chat.name), 0.91, 0.87, 0.78); GameTooltip:AddLine("Right-click for conversation actions", 0.7, 0.7, 0.7); GameTooltip:Show() end
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		-- Left-click switches to the chat; right-click opens its menu (Rename,
		-- Folder, Agent). A second right-click on the same row closes the menu again.
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				AzerMind.ShowChatMenu(self.chatId, self)
			else
				AzerMind.SwitchChat(self.chatId)
			end
		end)
		b:SetScript("OnDoubleClick", function(self)
			AzerMind.SwitchChat(self.chatId)
			AzerMind.RenamePrompt(self.chatId)
		end)
		b:Hide()
		ui.chatButtons[i] = b
	end

	-- Transcript: a scrolling stack of message bubbles
	local reading=CreateFrame("Frame","AzerMindReadingPanel",f,"BackdropTemplate")
	if AzerMindTheme then AzerMindTheme.Material(reading,"parchment",4); AzerMindTheme.Panel(reading,"frame-input",10); AzerMindTheme.PaperBevel(reading) end
	local scroll = CreateFrame("ScrollFrame", "AzerMindScroll", f, "UIPanelScrollFrameTemplate")
	reading:SetPoint("TOPLEFT",scroll,"TOPLEFT",-8,8)
	reading:SetPoint("BOTTOMRIGHT",scroll,"BOTTOMRIGHT",36,-8)
	scroll:SetPoint("TOPLEFT", panel, "TOPRIGHT", 16, -8)
	scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -62, 188)
	ui.scroll = scroll
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Scrollbar(scroll) end
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Material(scroll, "parchment", 0) end

	local content = CreateFrame("Frame", "AzerMindContent", scroll)
	content:SetSize(500, 1)
	scroll:SetScrollChild(content)
	ui.content = content
	ui.bubbles = {}
	scroll:HookScript("OnSizeChanged", function(self, w, h)
		if ui.frame:IsShown() then AzerMind.Render() end
	end)

	-- Input box, with Send docked at its right end like a messaging app.
	local SEND_W = 140
	local inputBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
	inputBg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PANEL_W + 32, 30)
	inputBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32 - SEND_W - 12, 30)
	inputBg:SetHeight(112)
	inputBg:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	inputBg:SetBackdropColor(0, 0, 0, 0.6)
	inputBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
	if AzerMindTheme and AzerMindTheme.grimoire then
		AzerMindTheme.Material(inputBg, "parchment")
		inputBg:SetBackdropBorderColor(0.65, 0.48, 0.25, 1)
		AzerMindTheme.Panel(inputBg,"frame-input",8); AzerMindTheme.PaperBevel(inputBg)
	end

	local inScroll = CreateFrame("ScrollFrame", "AzerMindInputScroll", inputBg, "UIPanelScrollFrameTemplate")
	inScroll:SetPoint("TOPLEFT", inputBg, "TOPLEFT", 8, -6)
	inScroll:SetPoint("BOTTOMRIGHT", inputBg, "BOTTOMRIGHT", -24, 6)
	if AzerMindTheme and AzerMindTheme.grimoire then
		inScroll:ClearAllPoints(); inScroll:SetPoint("TOPLEFT",inputBg,"TOPLEFT",12,-10)
		inScroll:SetPoint("BOTTOMRIGHT",inputBg,"BOTTOMRIGHT",-40,36)
	end
	if AzerMindTheme and AzerMindTheme.grimoire then
		AzerMindTheme.Scrollbar(inScroll)
		local bar=inScroll.ScrollBar or _G["AzerMindInputScrollScrollBar"]
		if bar then
			bar:ClearAllPoints()
			bar:SetPoint("TOPRIGHT",inputBg,"TOPRIGHT",-12,-30)
			bar:SetPoint("BOTTOMRIGHT",inputBg,"BOTTOMRIGHT",-12,30)
		end
	end

	local input = CreateFrame("EditBox", "AzerMindInput", inScroll)
	input:SetMultiLine(true)
	if AzerMind.SetupLinks then
		AzerMind.SetupLinks(input)
		AzerMind.SetupLinks(inScroll)
	end
	input:SetAutoFocus(false)
	input:SetFontObject(ChatFontNormal)
	if AzerMindTheme then AzerMindTheme.Type(input, "body") end
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Type(input,"paperBody"); AzerMindTheme.PaperFont(input) end
	if AzerMindTheme and AzerMindTheme.grimoire then
		input:HookScript("OnEditFocusGained",function() AzerMindTheme.Focus(inputBg,true) end)
		input:HookScript("OnEditFocusLost",function() AzerMindTheme.Focus(inputBg,false) end)
		AzerMindTheme.Focus(inputBg,false)
	end
	input:SetMaxLetters(0)
	input:SetSize(500, 116)
	input:SetScript("OnEnterPressed", function(self)
		if IsShiftKeyDown and IsShiftKeyDown() then self:Insert("\n") else AzerMind.SendFromInput() end
	end)
	input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	inScroll:SetScrollChild(input)
	inScroll:HookScript("OnSizeChanged", function(self, w, h)
		input:SetWidth(w)
	end)
	inputBg:SetScript("OnMouseDown", function() input:SetFocus() end)
	if AzerMindTheme and AzerMindTheme.grimoire then
		inputBg.placeholder=AzerMindTheme.Label(inputBg,"Write your message...",14,-12)
		AzerMindTheme.Type(inputBg.placeholder,"paperBody"); AzerMindTheme.PaperFont(inputBg.placeholder,true)
		inputBg.hint=inputBg:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
		inputBg.hint:SetPoint("BOTTOMLEFT",inputBg,"BOTTOMLEFT",16,16)
		inputBg.hint:SetPoint("BOTTOMRIGHT",inputBg,"BOTTOMRIGHT",-34,16)
		inputBg.hint:SetJustifyH("LEFT"); inputBg.hint:SetWordWrap(false)
		AzerMindTheme.Type(inputBg.hint,"label")
		inputBg.hint:SetText("Enter to send - Shift+Enter for new line"); AzerMindTheme.PaperFont(inputBg.hint,true)
		input:HookScript("OnTextChanged",function(self) inputBg.placeholder:SetShown((self:GetText() or "")=="") end)
	end
	ui.input = input
	local equipment = MakeButton(f, "Items", 96, function() if AzerMind.ShowItemPicker then AzerMind.ShowItemPicker() end end)
	equipment:SetPoint("BOTTOMLEFT", inputBg, "TOPLEFT", 0, 6)
	equipment:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Attach items", 0.91, 0.87, 0.78)
		GameTooltip:AddLine("Browse your inventory or the item database. Select items to add to your message. Nothing is sent yet.", 0.75, 0.75, 0.75, true)
		GameTooltip:Show()
	end)
	equipment:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local quests = MakeButton(f, "Quests", 104, function() if AzerMind.ShowQuestPicker then AzerMind.ShowQuestPicker() end end)
	quests:SetPoint("LEFT", equipment, "RIGHT", 8, 0)
	quests:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Attach quests", 0.91, 0.87, 0.78)
		GameTooltip:AddLine("Browse your quest log or the quest database. Select quests to add to your message. Nothing is sent yet.", 0.75, 0.75, 0.75, true); GameTooltip:Show()
	end)
	quests:SetScript("OnLeave", function() GameTooltip:Hide() end)
	ui.contextToggle = MakeButton(f, "Context: " .. (db.settings.contextMode == "full" and "Full" or db.settings.contextMode == "custom" and "Custom" or "Basic"), 172, function()
		AzerMind.ShowContextSettings()
	end)
	ui.contextToggle:SetPoint("LEFT", quests, "RIGHT", 8, 0)
	ui.contextToggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Share character context")
		GameTooltip:AddLine("Choose which character data to share. Applies to future messages in every conversation. Open to customize or preview.", 0.75, 0.75, 0.75, true); GameTooltip:Show()
	end)
	ui.contextToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local instancesButton=MakeButton(f,"Dungeons & Raids",184,function() AzerMind.ShowInstancePicker() end)
	if AzerMindTheme then
		AzerMindTheme.IconLabel(equipment,"items"); AzerMindTheme.IconLabel(quests,"quests")
		AzerMindTheme.IconLabel(instancesButton,"instances"); AzerMindTheme.IconLabel(ui.contextToggle,"character")
	end
	for _,button in ipairs({equipment,quests,instancesButton,ui.contextToggle}) do
		button:SetHeight(32); if AzerMindTheme then AzerMindTheme.Type(button.caption,"toolbarLabel") end
	end
	local function LayoutComposerActions()
		local available=f:GetWidth()-PANEL_W-64
		local buttons={equipment,quests,instancesButton,ui.contextToggle}
		for _,button in ipairs(buttons) do button:ClearAllPoints() end
		equipment:SetPoint("BOTTOMLEFT",inputBg,"TOPLEFT",0,6)
		quests:SetPoint("LEFT",equipment,"RIGHT",8,0)
		instancesButton:SetPoint("LEFT",quests,"RIGHT",8,0)
		local twoRows=available<584
		if twoRows then ui.contextToggle:SetPoint("BOTTOMLEFT",equipment,"TOPLEFT",0,6)
		else ui.contextToggle:SetPoint("LEFT",instancesButton,"RIGHT",12,0) end
		scroll:ClearAllPoints()
		scroll:SetPoint("TOPLEFT",panel,"TOPRIGHT",16,-8)
		scroll:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-62,inputBg:GetHeight()+30+(twoRows and 88 or 54))
	end
	local measure=inputBg:CreateFontString(nil,"BACKGROUND")
	if AzerMindTheme then AzerMindTheme.Type(measure,"paperBody") else measure:SetFontObject(ChatFontNormal) end
	measure:SetWordWrap(true); measure:Hide()
	inputBg.draftMeasure=measure
	local function FitDraft()
		measure:SetWidth(math.max(80,inScroll:GetWidth()))
		measure:SetText((input:GetText() or "").." ")
		local height=math.max(112,math.min(180,f:GetHeight()*0.30,measure:GetStringHeight()+48))
		if inputBg:GetHeight()~=height then inputBg:SetHeight(height) end
		LayoutComposerActions()
	end
	input:HookScript("OnTextChanged",FitDraft)
	f:HookScript("OnSizeChanged",FitDraft)
	FitDraft()


	local clearDraft = MakeButton(f, "Clear draft", SEND_W, AzerMind.ClearDraft)
	clearDraft:SetHeight(30)
	clearDraft:SetPoint("BOTTOMLEFT", inputBg, "BOTTOMRIGHT", 12, 0)
	clearDraft:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Clear draft", 0.91, 0.87, 0.78)
		GameTooltip:AddLine("Clears only the message you are writing, including attached equipment. Conversation history is kept.", 0.75, 0.75, 0.75, true)
		GameTooltip:Show()
	end)
	clearDraft:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Send sits to the right of the input box, vertically centred on it.
	local send = MakeButton(f, "Send", SEND_W, function()
		local c = ActiveChat()
		if c and c.pendingId then AzerMind.CancelPending() else AzerMind.SendFromInput() end
	end, true)
	send:SetPoint("TOPLEFT", inputBg, "TOPRIGHT", 12, 0)
	send.subdued=true
	send:SetPoint("BOTTOMLEFT", clearDraft, "TOPLEFT", 0, 8)
	ui.send = send
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.ActionIcon(send,"send") end

	-- Connect stands in for Send until the bridge has been seen (see UpdateConnect).
	local connect = MakeButton(f, "Connect", SEND_W, AzerMind.Connect, true)
	connect:SetPoint("TOPLEFT", inputBg, "TOPRIGHT", 12, 0)
	connect.subdued=false
	connect:SetPoint("BOTTOMLEFT", clearDraft, "TOPLEFT", 0, 8)
	connect:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Connect to the bridge", 0.91, 0.87, 0.78)
		GameTooltip:AddLine("The bridge must be running on this PC (npm start in azermind, or azermind in your project). The light turns green once it answers.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	connect:SetScript("OnLeave", function() GameTooltip:Hide() end)
	connect:Hide()
	ui.connect = connect
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.ActionIcon(connect,"connect") end

	-- Reload is the fallback transport's button; it sits apart on the right and
	-- only shows when a reload would do something (see UpdateStatus).
	local refresh = MakeButton(f, "Reload", 70, function() SafeReload() end)
	refresh:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 16)
	refresh:Hide()
	ui.refresh = refresh

	-- Resend is attached to the pending user message; no footer action row.

	local codexButton = MakeButton(f, "Config", 124, function() AzerMind.CodexPrompt() end)
	codexButton:SetHeight(30)
	if AzerMindTheme then AzerMindTheme.IconLabel(codexButton,"settings") end
	codexButton:SetPoint("RIGHT", mini, "LEFT", -12, 0)
	codexButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("AI settings", 0.91, 0.87, 0.78)
		GameTooltip:AddLine("Choose the model and reasoning for this conversation.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	codexButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	codexButton:Hide()
	ui.codexButton = codexButton
	refresh:ClearAllPoints()
	refresh:SetPoint("RIGHT", codexButton, "LEFT", -6, 0)

    for _,spec in ipairs({{"AzerMindOpenChatKeyButton",function() AzerMind.Toggle(true) end},{"AzerMindNewChatKeyButton",function() AzerMind.NewChat() end}}) do
        local button=CreateFrame("Button",spec[1],UIParent)
        button:SetSize(1,1); button:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10,10); button:SetScript("OnClick",spec[2])
    end
	-- A named, always-present button so a keybinding can click it (see /azermind bind).
	local hotkey = CreateFrame("Button", "AzerMindRefreshButton", UIParent)
	hotkey:SetSize(1, 1)
	hotkey:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	hotkey:SetScript("OnClick", function()
		local c = ActiveChat()
		if c and c.pendingId then
			AzerMind.Send("")
		else
			AzerMind.Toggle()
		end
	end)

	local cwd = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cwd:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 4)
	cwd:SetPoint("RIGHT", f, "RIGHT", -30, 0)
	cwd:SetJustifyH("LEFT")
	cwd:SetWordWrap(false)
	ui.cwd = cwd
	cwd:Hide() -- Technical context stays available through diagnostics, not a footer.

	-- Resize grip
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(24, 24)
	grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	if AzerMindTheme and AzerMindTheme.grimoire then
		grip:SetNormalTexture(AzerMindTheme.artRoot.."resize-grip.tga")
		grip:SetPushedTexture(AzerMindTheme.artRoot.."resize-grip.tga")
	end
	grip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		s.width, s.height = f:GetSize()
	end)

	-- Mini bar: what the window collapses into. Click it to expand, drag to move.
	local m = CreateFrame("Frame", "AzerMindMini", UIParent, "BackdropTemplate")
	ui.mini = m
	if AzerMindTheme then AzerMindTheme.RegisterOpacity(m) end
	m:SetSize(250, 30)
	if s.miniPoint then
		m:SetPoint(s.miniPoint, UIParent, s.miniRelPoint or s.miniPoint, s.miniX or 0, s.miniY or 0)
	else
		m:SetPoint("TOP", UIParent, "TOP", 0, -40)
	end
	if AzerMindTheme then AzerMindTheme.Window(m,"MEDIUM") else m:SetFrameStrata("MEDIUM"); m:SetToplevel(true) end
	m:SetMovable(true)
	m:SetClampedToScreen(true)
	m:EnableMouse(true)
	m:RegisterForDrag("LeftButton")
	m:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:StartMoving()
	end)
	m:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		s.miniPoint, s.miniRelPoint, s.miniX, s.miniY = point, relPoint, x, y
		C_Timer.After(0, function() self.dragging = nil end)
	end)
	m:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and not self.dragging then
			AzerMind.Minimize(false)
		end
	end)
	m:SetBackdrop(BACKDROP)
	m:SetBackdropColor(0.055, 0.049, 0.039, 0.97)
	if AzerMindTheme then AzerMindTheme.Glow(m, 0.16) end
	m:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	if AzerMindTheme and AzerMindTheme.grimoire then AzerMindTheme.Panel(m,"frame-window",8) end
	m:Hide()

	local miniDotHolder, miniDot = MakeDot(m)
	miniDotHolder:SetPoint("LEFT", m, "LEFT", 9, 0)
	ui.miniDot = miniDot

	local mlabel = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mlabel:SetPoint("LEFT", miniDotHolder, "RIGHT", 6, 0)
	mlabel:SetText("AzerMind")

	local badge = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	badge:SetPoint("LEFT", mlabel, "RIGHT", 8, 0)
	badge:SetPoint("RIGHT", m, "RIGHT", -26, 0)
	badge:SetJustifyH("LEFT")
	badge:SetWordWrap(false)
	ui.miniBadge = badge

	local ok, pulse = pcall(function()
		local g = badge:CreateAnimationGroup()
		local a1 = g:CreateAnimation("Alpha")
		a1:SetFromAlpha(1)
		a1:SetToAlpha(0.25)
		a1:SetDuration(0.6)
		a1:SetOrder(1)
		local a2 = g:CreateAnimation("Alpha")
		a2:SetFromAlpha(0.25)
		a2:SetToAlpha(1)
		a2:SetDuration(0.6)
		a2:SetOrder(2)
		g:SetLooping("REPEAT")
		return g
	end)
	if ok then ui.miniPulse = pulse end

	local mclose = AzerMindTheme and AzerMindTheme.Button(m,"x",24,24,nil) or CreateFrame("Button", nil, m, "UIPanelCloseButton")
	mclose:SetSize(24, 24)
	mclose:SetPoint("RIGHT", m, "RIGHT", -2, 0)
	mclose:SetScript("OnClick", function() AzerMind.Toggle(false) end)
	mclose:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Quit: hide completely (/azermind brings it back)")
		GameTooltip:Show()
	end)
	mclose:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function AzerMind.Toggle(show)
	if not ui.frame then return end
	if show == nil then show = not ui.frame:IsShown() end
	if show then
		db.settings.minimized = false
		local c = ActiveChat()
		if c then c.unread = 0 end
	end
	if ui.mini then ui.mini:Hide() end
	if not show then ui.quitting = true end
	ui.frame:SetShown(show)
	ui.quitting = nil
	db.settings.shown = show
	if show then
		AzerMind.Render()
		ui.input:SetFocus()
		ui.input:SetCursorPosition(#ui.input:GetText())
		-- No automatic hello either: if the bridge hasn't been seen, the panel
		-- shows Connect in place of Send and waits for a click.
	end
	AzerMind.UpdateMini()
end

-- Labels for the game's native Key Bindings configuration.
BINDING_HEADER_AZERMIND = "AzerMind"
BINDING_NAME_AZERMIND_OPEN_CHAT = "Open chat"
BINDING_NAME_AZERMIND_NEW_CHAT = "New chat"

function AzerMind.Minimize(mini)
	if not ui.frame then return end
	if mini == nil then mini = not db.settings.minimized end
	if mini then
		db.settings.minimized = true
		db.settings.shown = true
		ui.frame:Hide() -- OnHide shows the mini bar
		if ui.mini and not ui.mini:IsShown() then ui.mini:Show() end
		AzerMind.UpdateMini()
	else
		AzerMind.Toggle(true)
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local HELP = table.concat({
	"/azermind                        toggle the window (/ai, /azermind and the old /wow-claude are the same command)",
	"/azermind mini                   collapse to the small bar (click the bar to expand)",
	"/azermind hide                   hide the window completely",
	"/ai <text>                         send <text> to the current chat straight from the game chat box (/azermind <text> too). A message that starts with a command word is still sent when the rest of the line doesn't fit that command",
	"/r <text>                          replies to the agent when it was the last to message you (else normal whisper reply)",
	"/azermind echo summary|full|short|off|<chars>   how much of each reply to print in the game chat (summary = the agent's closing TL;DR lines)",
	"/azermind longchat on|off        let the game chat box take 4000 characters (for long /ai messages)",
	"/azermind new [name]             start a new chat (its own agent session, like a new terminal)",
	"/azermind chat <n|name>          switch chats (or click one in the left panel)",
	"/azermind rename [name]          rename the current chat (no name = dialog; right-clicking the chat in the left panel offers it too)",
	"/azermind delete                 delete the current chat",
	"/azermind cd <folder>            folder this chat's agent works in (relative to the bridge's folder; no folder = back to default). Right-clicking the chat in the left panel and picking Folder does the same",
	"/azermind agent [name]           which agent this chat talks to (no name = show; default = the bridge's). Right-clicking the chat and picking Agent does the same",
	"/azermind reset                  next message in this chat starts a fresh agent session",
	"/azermind context [on|off]       what the agent is told about your character and where you are (no argument = show it)",
	"/azermind map [...]              map layers the agent drew, the route navigator and herb/ore nodes (no argument = status and subcommands; /aimap is the same)",
	"/azermind mode pixel             no-reload transport (default)",
	"/azermind mode reload            fallback transport: a /reload per step",
	"/azermind resend                 show the strip again if the bridge missed it",
	"/azermind reload                 reload now (also frees the slot pool)",
	"/azermind cancel                 stop waiting on this chat's reply",
	"/azermind copy                   open the last reply in a selectable box for Ctrl+C",
	"/azermind macro undo             undo the last macro the agent's button created or changed",
	"/azermind bind <key>             hotkey: checks for a reply while waiting, else toggles the window",
	"/azermind auto on|off            reload-mode only: auto-reload on your next keypress after the interval",
	"/azermind signal on|off          the cheap sound-file readiness check (off if it spams errors)",
	"/azermind slots                  how many reply slots are still free this session",
	"/azermind diag                   transport diagnostics (is the cheap sound-file channel working?)",
	"/azermind clear                  clear this chat's transcript",
}, "\n")

-- What each subcommand accepts, so that free text which happens to start with
-- one of these words ("delete the unused imports", "help me with this macro")
-- is sent as a message instead of run as a command. 0 = no arguments, 1 = at
-- most one word, a table = one of those words, a function decides, true = anything.
local function OnOffOrNumber(rest)
	return rest == "" or rest == "on" or rest == "off" or tonumber(rest) ~= nil
end

local function ChatArgument(rest)
	if rest == "" or tonumber(rest) or not rest:find("%s") then return true end
	for _, ch in ipairs(db.chats) do
		if ch.name:lower() == rest:lower() then return true end
	end
	return false
end

local COMMAND_ARGS = {
	mini = 0, min = 0, hide = 0, quit = 0, help = 0, clear = 0, delete = 0, reset = 0, copy = 0,
	cancel = 0, resend = 0, reload = 0, refresh = 0, slots = 0, diag = 0,
	resetui = 0,
	context = { [""] = true, on = true, off = true }, ctx = { [""] = true, on = true, off = true },
	mode = { [""] = true, pixel = true, reload = true },
	signal = { [""] = true, on = true, off = true }, longchat = { [""] = true, on = true, off = true },
	auto = OnOffOrNumber,
	echo = function(rest) return rest == "" or rest == "summary" or rest == "full" or rest == "short" or rest == "off" or tonumber(rest) ~= nil end,
	bind = 1, agent = 1,
	chat = ChatArgument, chats = ChatArgument,
	cd = true, new = true, rename = true,
	map = true, -- /azermind map ...: Map.lua (layers, navigator, herb/ore nodes)
	macro = { undo = true }, -- /azermind macro undo; "/ai macro for my warrior" still goes to the agent
}

local function IsCommand(cmd, rest)
	local spec = COMMAND_ARGS[cmd]
	if spec == nil then return false end
	if spec == true then return true end
	if spec == 0 then return rest == "" end
	if spec == 1 then return not rest:find("%s") end
	if type(spec) == "table" then return spec[rest:lower()] == true end
	return spec(rest) == true
end

local function ApplyLongChat()
	local box = ChatFrame1EditBox
	if not box or not box.SetMaxLetters then return end
	box:SetMaxLetters(db.settings.longchat and 4000 or 255)
end

SLASH_AZERMIND1 = "/azermind"
SLASH_AZERMIND2 = "/wow-ai" -- compatibility alias for existing macros
SLASH_AZERMIND3 = "/wow-claude" -- the project's old name, kept so old habits and macros still work
SLASH_AZERMIND4 = "/ai" -- the short form: /ai <text> sends, /ai agent codex and the rest work too
SLASH_AZERMIND5 = "/ask"
SlashCmdList["AZERMIND"] = function(msg)
	msg = Trim(msg or "")
	local cmd, rest = msg:match("^(%S+)%s*(.-)$")
	cmd = cmd and cmd:lower() or ""
	local s = db.settings
	local c = ActiveChat()

	-- Anything that isn't a command, or a command word followed by something it
	-- doesn't take, is a message for the agent.
	if cmd ~= "" and not IsCommand(cmd, rest) then
		AzerMind.Send(msg)
		return
	end
	if cmd == "" then
		AzerMind.Toggle()
	elseif cmd == "mini" or cmd == "min" then
		AzerMind.Minimize(true)
	elseif cmd == "new" then
		AzerMind.NewChat(rest)
	elseif cmd == "chat" or cmd == "chats" then
		local n = tonumber(rest)
		local target = n and db.chats[n]
		if not target and rest ~= "" then
			for _, ch in ipairs(db.chats) do
				if ch.name:lower() == rest:lower() then target = ch end
			end
		end
		if target then
			AzerMind.SwitchChat(target.id)
		else
			local lines = {}
			for i, ch in ipairs(db.chats) do
				table.insert(lines, i .. ". " .. ch.name .. (ch.id == db.activeChat and "  (current)" or "") .. (ch.pendingId and "  working" or "") .. ((ch.unread or 0) > 0 and ("  " .. ch.unread .. " new") or ""))
			end
			AddHistory(c, "system", "Chats:\n" .. table.concat(lines, "\n"))
			AzerMind.Render()
		end
		AzerMind.Toggle(true)
	elseif cmd == "rename" then
		if rest ~= "" then
			c.name = rest:sub(1, 24)
			AzerMind.Render()
		else
			AzerMind.RenameActive()
		end
		AzerMind.Toggle(true)
	elseif cmd == "delete" then
		AzerMind.DeleteChat()
	elseif cmd == "cd" then
		AzerMind.SetFolder(rest, c)
		AzerMind.Toggle(true)
	elseif cmd == "map" then
		if AzerMindMap then AzerMindMap.Command(rest) else print("|cff66ccff[AzerMind]|r the map module did not load") end
	elseif cmd == "agent" then
		AzerMind.SetAgent(rest, c)
		AzerMind.Toggle(true)
	elseif cmd == "resetui" then
		AzerMind.ResetUI()
	elseif cmd == "reset" then
		c.resetNext = true
		local where = ChatFolder(c)
		AddHistory(c, "system", "Next message starts a fresh " .. ChatAgentName(c) .. " session" .. (where ~= "" and (" in " .. where) or ""))
		AzerMind.Render()
		AzerMind.Toggle(true)
	elseif cmd == "context" or cmd == "ctx" then
		rest = rest:lower()
		if rest == "on" or rest == "off" then
			s.context = rest == "on"
			-- Make sure the next record carries the change, hello throttle or not.
			run.contextSent = nil
			run.lastHelloAt = nil
			if AzerMind.IsConnected() then AzerMind.SayHello() end
		end
		local ctx = AzerMind.GameContext()
		AddHistory(c, "system", (s.context
			and "Game context is ON: the agent is told this with each message (it goes into its system prompt, so unrelated projects are unaffected by anything but a few lines). /azermind context off to stop.\n\n"
			or "Game context is OFF: the agent is told nothing about the game. /azermind context on to send this:\n\n") .. ctx
			.. "\n\nTip: click the input box, then shift-click an item, spell or quest to link it into your message; the agent gets its tooltip.")
		AzerMind.Render()
		AzerMind.Toggle(true)
	elseif cmd == "mode" then
		if rest == "pixel" or rest == "reload" then
			s.mode = rest
			AddHistory(c, "system", "mode set to " .. rest)
		else
			AddHistory(c, "system", "mode is " .. s.mode .. " (pixel or reload)")
		end
		AzerMind.Render()
		AzerMind.Toggle(true)
	elseif cmd == "resend" then
		AzerMind.Resend()
	elseif cmd == "auto" then
		local n = tonumber(rest)
		if n then
			s.interval = math.max(5, math.floor(n))
			s.autoRefresh = true
		elseif rest == "on" then
			s.autoRefresh = true
		elseif rest == "off" then
			s.autoRefresh = false
		end
		AzerMind.UpdateStatus()
		AzerMind.ArmAutoRefresh()
	elseif cmd == "hide" or cmd == "quit" then
		AzerMind.Toggle(false)
	elseif cmd == "macro" and rest == "undo" then
		AzerMind.UndoMacro()
	elseif cmd == "copy" then
		for i = #c.history, 1, -1 do
			if c.history[i].role == "assistant" then
				AzerMind.ShowCopy(c.history[i].text)
				break
			end
		end
	elseif cmd == "echo" then
		if rest == "summary" or rest == "full" or rest == "short" or rest == "off" then
			s.echo = rest
		elseif tonumber(rest) then
			s.echo = tostring(math.max(200, math.floor(tonumber(rest))))
		end
		AddHistory(c, "system", "replies in game chat: " .. s.echo .. " (summary = the agent's TL;DR lines, full = " .. ECHO_DEFAULT .. " chars, short, off, or a number of characters)")
		AzerMind.Render()
	elseif cmd == "longchat" then
		if rest == "on" then s.longchat = true elseif rest == "off" then s.longchat = false end
		ApplyLongChat()
		AddHistory(c, "system", "game chat box limit: " .. (s.longchat and "4000 characters (fine for /ai; real chat over 255 may be rejected by the server)" or "255 (default)"))
		AzerMind.Render()
	elseif cmd == "signal" then
		if rest == "on" then s.signal = true elseif rest == "off" then s.signal = false end
		AddHistory(c, "system", "signal check is " .. (s.signal and "on" or "off"))
		AzerMind.Render()
	elseif cmd == "slots" then
		local free = 0
		for i = 1, SLOT_COUNT do
			if not C_AddOns.IsAddOnLoaded(SlotName(i)) then free = free + 1 end
		end
		AddHistory(c, "system", free .. " of " .. SLOT_COUNT .. " reply slots free this session (a reload frees all)")
		AzerMind.Render()
		AzerMind.Toggle(true)
	elseif cmd == "refresh" or cmd == "reload" then
		SafeReload()
	elseif cmd == "bind" then
		local key = rest:upper()
		if key ~= "" and not InCombatLockdown() then
			SetBinding(key, "CLICK AzerMindRefreshButton:LeftButton")
			SaveBindings(GetCurrentBindingSet())
			AddHistory(c, "system", key .. " is now bound: checks for a reply while waiting, otherwise toggles this window")
		end
		AzerMind.Render()
		AzerMind.Toggle(true)
	elseif cmd == "diag" then
		local free = 0
		for i = 1, SLOT_COUNT do
			if not C_AddOns.IsAddOnLoaded(SlotName(i)) then free = free + 1 end
		end
		local lines = {
			"sound channel: " .. (signalAvailable and "usable" or "UNUSABLE") .. " (self-test: " .. tostring(signalStats.selftest) .. ")" .. (signalStats.error and (" error: " .. signalStats.error) or ""),
			"signal setting: " .. tostring(s.signal) .. ", marked unreliable this session: " .. tostring(run.signalUnreliable or false),
			"sound checks: " .. signalStats.checks .. ", valid hits: " .. signalStats.hits .. (signalStats.lastHit and (", last hit " .. FmtDur(GetTime() - signalStats.lastHit) .. " ago") or ""),
			"slot polls this session: " .. (run.polls or 0) .. ", free slots: " .. free .. "/" .. SLOT_COUNT,
			"presence: head at " .. tostring(run.presence and run.presence.last or "?") .. ", beats seen: " .. tostring(run.presence and run.presence.beats or 0),
			select(5, AzerMind.BridgeState()),
			"mode: " .. s.mode .. ", session token: " .. tostring(db.session),
		}
		for _, ch in ipairs(db.chats) do
			local a = run.act and run.act[ch.id]
			if ch.pendingId then
				table.insert(lines, ch.name .. ": pending #" .. ch.pendingId .. (a and (", heartbeat " .. (a.unreliable and "unreliable" or (a.count .. " beats"))) or ", no heartbeat state"))
			end
		end
		AddHistory(c, "system", "Diagnostics:\n" .. table.concat(lines, "\n"))
		AzerMind.Render()
		AzerMind.Toggle(true)
	elseif cmd == "cancel" then
		AzerMind.CancelPending()
	elseif cmd == "clear" then
		wipe(c.history)
		if ui.deletedMessage and ui.deletedMessage.chat==c.id then ui.deletedMessage=nil end
		AzerMind.Render()
	elseif cmd == "help" then
		AddHistory(c, "system", HELP)
		AzerMind.Render()
		AzerMind.Toggle(true)
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UPDATE_MACROS")
ev:RegisterEvent("CHAT_MSG_WHISPER")
ev:RegisterEvent("CHAT_MSG_BN_WHISPER")
ev:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			InitDB()
		end
	elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
		-- A real person whispered: /r belongs to them again.
		run.lastMessenger = "player"
	elseif event == "PLAYER_LOGIN" then
		if not db then InitDB() end
		BuildUI()
		run = { outbound = {} }
		SelfTestSignals()
		ProcessInbox()
		if AnyPending() then
			-- Still waiting after a reload: resume polling with a fresh slot pool.
			run.sentAt = GetTime()
			run.polls = 0
			run.act = {}
			for _, ch in ipairs(db.chats) do
				if ch.pendingId then
					-- Beats already written stay valid, so the counter catches up on its own.
					run.act[ch.id] = { next = 1, count = 0, startedAt = GetTime() }
				end
			end
			ScheduleNextPoll()
		end
		local c = ActiveChat()
		if c and c.draft and c.draft ~= "" then
			ui.input:SetText(c.draft)
			if not c.pendingId then c.draft = nil end
		end
		AzerMind.Render()
		if db.settings.shown then
			if db.settings.minimized then
				AzerMind.Minimize(true)
			else
				AzerMind.Toggle(true)
			end
		end
		AzerMind.ArmAutoRefresh()
		AzerMind.UpdateDot()
		if db.settings.longchat then ApplyLongChat() end
		HookReplyCommand()
		C_Timer.NewTicker(TICK_SECONDS, Tick)
		C_Timer.NewTicker(0.75, function()
			-- Window/display changes can settle after their event. Recalibrate even
			-- a single-frame message while keeping the existing fragment timer.
			if run.stripShown then UpdateStripScale() end
			for id, rec in pairs(run.outbound) do
				if not rec.acked and #RecordFor(id, rec) > STRIP_PAYLOAD then RefreshStrip(); break end
			end
		end)
		C_Timer.After(3, AzerMind.SayHello)
	elseif event == "UPDATE_MACROS" then
		-- "Create" / "Update" on the macro buttons follows what exists now.
		if ui.frame and ui.frame:IsShown() then AzerMind.Render() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if AzerMind.reloadAfterCombat then
			AzerMind.reloadAfterCombat = nil
			ReloadUI()
		elseif db then
			AzerMind.ArmAutoRefresh()
		end
	end
end)
