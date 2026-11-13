-- The Forever client exposes its three talent branches as groups in one trait tree.
local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f = pcall(fn, ...)
	if ok then return a, b, c, d, e, f end
end

local function Count(value)
	return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

local function ID(value)
	return Count(value) and value > 0
end

local function Name(value)
	if type(value) ~= "string" then return nil end
	local name = value:gsub("%c", " "):match("^%s*(.-)%s*$")
	if name ~= "" then return name end
end

local function Snapshot()
	return {totals = {}, ranks = {}}
end

local function AddRank(snapshot, name, rank, maxRanks, groups)
	if not name then
		snapshot.ranksPartial = true
		return
	end
	local text = name .. " " .. rank
	if Count(maxRanks) and maxRanks >= rank then
		text = text .. "/" .. maxRanks
	else
		snapshot.ranksPartial = true
	end
	if #groups > 0 then text = text .. " (" .. table.concat(groups, " / ") .. ")" end
	table.insert(snapshot.ranks, text)
end

local function ReadGroups(snapshot, configID, treeID)
	local groups = Try(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
	local names, ids = {}, {}
	if type(groups) == "table" then
		for _, group in ipairs(groups) do
			local id = type(group) == "table" and group.groupID
			local name = id and Name(group.displayName)
			if ID(id) and name then
				if not names[id] then table.insert(ids, id) end
				names[id] = name
			else
				snapshot.totalsPartial = true
			end
		end
	end
	if #ids == 0 then
		snapshot.totalsPartial = true
		return names
	end

	local currencies = Try(C_Traits.GetGroupCurrencyInfo, configID, ids)
	if type(currencies) ~= "table" then
		snapshot.totalsPartial = true
		return names
	end
	local spentByGroup = {}
	local malformed = false
	for _, group in ipairs(currencies) do
		local id = type(group) == "table" and group.traitNodeGroupID
		if not ID(id) then
			malformed = true
		elseif names[id] then
			local currency = type(group.currencyInfos) == "table" and group.currencyInfos[1]
			spentByGroup[id] = type(currency) == "table" and currency.spent or false
		end
	end
	for _, id in ipairs(ids) do
		local spent = spentByGroup[id]
		-- The Forever talent panel displays zero when a group has no currency record.
		if spent == nil and not malformed then spent = 0 end
		if Count(spent) then
			table.insert(snapshot.totals, names[id] .. " " .. spent)
		else
			snapshot.totalsPartial = true
		end
	end
	return names
end

local function SpellName(spellID)
	if not ID(spellID) or type(C_Spell) ~= "table" then return nil end
	local name = Name(Try(C_Spell.GetSpellName, spellID))
	if name then return name end
	local info = Try(C_Spell.GetSpellInfo, spellID)
	if type(info) == "table" then return Name(info.name) end
end

local function ReadTraitRank(snapshot, configID, nodeID, names)
	local node = Try(C_Traits.GetNodeInfo, configID, nodeID)
	local rank = type(node) == "table" and node.ranksPurchased
	if not Count(rank) then
		snapshot.ranksPartial = true
		return
	end
	if rank == 0 then return end

	local entryID = type(node.activeEntry) == "table" and node.activeEntry.entryID
	if not ID(entryID) and type(node.entryIDs) == "table" and #node.entryIDs == 1 then entryID = node.entryIDs[1] end
	local entry = ID(entryID) and Try(C_Traits.GetEntryInfo, configID, entryID)
	local definitionID = type(entry) == "table" and entry.definitionID
	local definition = ID(definitionID) and Try(C_Traits.GetDefinitionInfo, definitionID)
	local name = type(definition) == "table" and (Name(definition.overrideName) or SpellName(definition.spellID))

	-- Display a shared node once, with all of its named groups.
	local groups = {}
	if type(node.groupIDs) == "table" then
		for _, id in ipairs(node.groupIDs) do
			if ID(id) and names[id] then table.insert(groups, names[id]) end
		end
	end
	local maxRanks = type(entry) == "table" and entry.maxRanks
	if not Count(maxRanks) or maxRanks < rank then maxRanks = node.maxRanks end
	AddRank(snapshot, name, rank, maxRanks, groups)
end

local function ReadTree(snapshot, seen, configID, treeID)
	if not ID(treeID) then
		snapshot.totalsPartial, snapshot.ranksPartial = true, true
		return
	end
	local names = ReadGroups(snapshot, configID, treeID)
	local nodes = Try(C_Traits.GetTreeNodes, treeID)
	if type(nodes) ~= "table" or #nodes == 0 then
		snapshot.ranksPartial = true
		return
	end
	for _, nodeID in ipairs(nodes) do
		if not ID(nodeID) then
			snapshot.ranksPartial = true
		elseif not seen[nodeID] then
			seen[nodeID] = true
			ReadTraitRank(snapshot, configID, nodeID, names)
		end
	end
end

local function ReadTraits()
	if type(C_ClassTalents) ~= "table" or type(C_Traits) ~= "table" then return nil end
	local configID = Try(C_ClassTalents.GetActiveConfigID)
	if not ID(configID) then return nil end
	-- This config's node and group APIs can also reflect uncommitted UI edits.
	local staged = Try(C_Traits.ConfigHasStagedChanges, configID)
	if staged == true then return {pending = true} end
	if staged ~= false then return nil end

	local config = Try(C_Traits.GetConfigInfo, configID)
	local trees = type(config) == "table" and config.treeIDs
	if type(trees) ~= "table" or #trees == 0 then return nil end
	local snapshot, seen = Snapshot(), {}
	for _, treeID in ipairs(trees) do
		ReadTree(snapshot, seen, configID, treeID)
	end
	-- Only a single unambiguous talent currency can be reported as unspent points.
	if #trees == 1 and ID(trees[1]) then
		local currencies = Try(C_Traits.GetTreeCurrencyInfo, configID, trees[1], true)
		local currency = type(currencies) == "table" and #currencies == 1 and currencies[1]
		if type(currency) == "table" and Count(currency.quantity) then snapshot.unspent = currency.quantity end
	end
	return snapshot
end

local function ReadLegacyTalents()
	local tabs = Try(GetNumTalentTabs)
	if not Count(tabs) or tabs == 0 then return nil end
	local snapshot = Snapshot()
	for tab = 1, tabs do
		local first, second, third, _, fifth = Try(GetTalentTabInfo, tab)
		-- Current classic clients prefix the older tab name with a numeric ID.
		local idFirst = type(first) == "number"
		local name = Name(idFirst and second or first)
		local spent = idFirst and fifth or third
		if name and Count(spent) then
			table.insert(snapshot.totals, name .. " " .. spent)
		else
			snapshot.totalsPartial = true
		end
		local count = Try(GetNumTalents, tab)
		if not Count(count) or count == 0 then
			snapshot.ranksPartial = true
		else
			for index = 1, count do
				local talent, _, _, _, rank, maxRanks = Try(GetTalentInfo, tab, index)
				if not Count(rank) then
					snapshot.ranksPartial = true
				elseif rank > 0 then
					AddRank(snapshot, Name(talent), rank, maxRanks, name and {name} or {})
				end
			end
		end
	end
	local unspent = Try(GetUnspentTalentPoints)
	if Count(unspent) then snapshot.unspent = unspent end
	return snapshot
end

-- Keep the talent section within 3,000 UTF-8 bytes by dropping whole entries.
local function FormatList(label, entries, separator, budget, partial, empty)
	if #entries == 0 then return label .. (partial and "unavailable from client API." or empty) end
	local shown, bytes = {}, 0
	for _, entry in ipairs(entries) do
		local entryBytes = #entry + (#shown > 0 and #separator or 0)
		if bytes + entryBytes > budget then break end
		table.insert(shown, entry)
		bytes = bytes + entryBytes
	end
	if #shown == 0 then return label .. "omitted at size limit." end
	local suffix = ""
	if #shown < #entries then
		suffix = " [partial: size limit]"
	elseif partial then
		suffix = " [partial: some data unavailable]"
	end
	return label .. table.concat(shown, separator) .. suffix
end

function AzerMind.TalentContext()
	local snapshot = ReadTraits()
	if snapshot and snapshot.pending then return "Talents: unavailable while talent changes are pending." end
	if not snapshot or (#snapshot.totals == 0 and #snapshot.ranks == 0 and snapshot.ranksPartial) then
		snapshot = ReadLegacyTalents() or snapshot
	end
	if not snapshot then return "Talents: unavailable from client API." end

	local lines = {FormatList("Talents: ", snapshot.totals, " / ", 480, snapshot.totalsPartial, "no tree totals reported.")}
	if snapshot.unspent then table.insert(lines, "Unspent talent points: " .. snapshot.unspent) end
	table.insert(lines, FormatList("Purchased talent ranks: ", snapshot.ranks, ", ", 2300, snapshot.ranksPartial, "none reported by client."))
	return table.concat(lines, "\n")
end
