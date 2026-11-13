-- Read the installed GearQuest active hunts without opening its UI or changing settings.
local MAX_HUNTS = 200
local MAX_SLOTS = 32

local function Text(value)
    if type(value) == "string" and #value > 0 and #value <= 256 then
        return value
    end
end

local function ItemID(value)
    local id = tonumber(value)
    if id and id > 0 and id <= 2147483647 and id == math.floor(id) then
        return id
    end
end

local function Unavailable(result, reason)
    result.status = "unavailable"
    result.reason = reason
end

local function Partial(result, reason)
    result.status = "partial"
    result.partial = true
    result.reason = result.reason or reason
end

local function ReadSlot(data, log, slot)
    if slot == "MainHand" then
        return log:FilteredWeaponEntries()
    end
    if slot == "SecondaryHand" then
        if type(data.UsesTwoHandOnlyWeapons) == "function" and data:UsesTwoHandOnlyWeapons() then
            return {}
        end
        return log:HeldOffHandEntries()
    end
    return log:GetActiveSlotListEntries(slot)
end

local function ReadEntry(data, entry, slot, result)
    local itemID = type(entry) == "table" and ItemID(entry.itemId)
    if not itemID then
        Partial(result, "Some GearQuest hunts lacked a valid item ID.")
        return
    end
    if type(data.EntryMatchesPlayer) == "function" then
        local ok, eligible = pcall(data.EntryMatchesPlayer, data, entry)
        if not ok or type(eligible) ~= "boolean" then
            Partial(result, "Some GearQuest hunt eligibility could not be checked.")
            return
        end
        if not eligible then return end
    end

    local name
    if type(data.GetItemDisplayName) == "function" then
        local ok, displayName = pcall(data.GetItemDisplayName, data, itemID)
        if ok then name = Text(displayName) end
    end

    local owned
    local suffix = Text(entry.suffix)
    if type(data.PlayerOwnsEntryItem) == "function" then
        -- GearQuest can enrich a suffix on the argument while checking bags.
        local entryCopy = {}
        for key, value in pairs(entry) do
            entryCopy[key] = value
        end
        local ok, found = pcall(data.PlayerOwnsEntryItem, data, entryCopy)
        if ok then suffix = Text(entryCopy.suffix) or suffix end
        if ok and type(found) == "boolean" then
            owned = found
        else
            Partial(result, "Some GearQuest hunt ownership could not be checked.")
        end
    end

    local entries = result.entries
    entries[#entries + 1] = {
        itemID = itemID,
        name = name or Text(entry.name) or ("Item #" .. itemID),
        slot = Text(entry.slot) or slot,
        suffix = suffix,
        sourceType = Text(entry.sourceType),
        questID = ItemID(entry.questID or entry.questId),
        owned = owned,
    }
end

local function ReadHunts(gq, result)
    local data, log = gq.Data, gq.Log
    if type(data) ~= "table" or type(log) ~= "table"
        or type(gq.GetEffectiveClass) ~= "function" or type(gq.IsPreviewEnabled) ~= "function"
        or type(data.GetSlotsForClass) ~= "function" or type(log.GetActiveSlotListEntries) ~= "function" then
        Unavailable(result, "GearQuest active hunt methods are unavailable.")
        return
    end

    if gq:IsPreviewEnabled() then
        result.status = "preview"
        result.reason = "GearQuest is in simulation mode."
        return
    end
    local class = Text(gq:GetEffectiveClass())
    if not class or (type(data.IsClassExpanded) == "function" and not data:IsClassExpanded(class)) then
        Unavailable(result, "GearQuest class data is unavailable.")
        return
    end
    result.class = class
    if type(gq.GetEffectiveSpec) == "function" then
        result.spec = Text(gq:GetEffectiveSpec())
    end

    local slots = data:GetSlotsForClass(class)
    if type(slots) ~= "table" then
        Unavailable(result, "GearQuest hunt slots are unavailable.")
        return
    end
    result.status = "ok"
    if type(log.EnsureActiveListCaches) == "function" then
        local ok = pcall(log.EnsureActiveListCaches, log)
        if not ok then
            Partial(result, "GearQuest active hunt lists could not be refreshed.")
        end
    end

    local inspected = 0
    local seenSlots = {}
    for index, slot in ipairs(slots) do
        if index > MAX_SLOTS then
            Partial(result, "GearQuest hunt slot limit reached.")
            return
        end
        if not Text(slot) then
            Partial(result, "Some GearQuest hunt slots could not be read.")
        elseif not seenSlots[slot] then
            seenSlots[slot] = true
            local ok, entries = pcall(ReadSlot, data, log, slot)
            if not ok or type(entries) ~= "table" then
                Partial(result, "Some GearQuest hunt slots could not be read.")
            else
                for _, entry in ipairs(entries) do
                    inspected = inspected + 1
                    if inspected > MAX_HUNTS then
                        Partial(result, "GearQuest hunt list limit reached.")
                        result.total = inspected
                        return
                    end
                    ReadEntry(data, entry, slot, result)
                end
            end
        end
    end
    result.total = #result.entries
end

function AzerMind.ReadGearQuestHunts()
    local result = { status = "unavailable", entries = {} }
    local gq = _G.GearQuest
    if type(gq) ~= "table" then
        Unavailable(result, "GearQuest Forever is unavailable.")
        return result
    end
    result.version = Text(gq.VERSION)
    local ok = pcall(function()
        if type(gq.WithContextSnapshot) == "function" then
            gq:WithContextSnapshot(ReadHunts, gq, result)
        else
            ReadHunts(gq, result)
        end
    end)
    if not ok then
        if result.status == "ok" or result.status == "partial" then
            Partial(result, "GearQuest hunt data could only be read in part.")
        else
            Unavailable(result, "GearQuest hunt data could not be read.")
        end
    end
    return result
end
