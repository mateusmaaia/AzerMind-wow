-- Read-only access to the loaded Forever Dungeon Journal and the bundled snapshot.
local MAX_LOOT_ITEMS = 1200
local MAX_DUNGEON_SOURCES = 128
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value, detail = pcall(fn, ...)
    if ok then return value, detail end
end

local function Plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function Text(value)
    value = Plain(value)
    if type(value) == "string" and value ~= "" then return value end
end

local function Normalize(value)
    return ((Text(value) or ""):lower():gsub("[%c%p%s]+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function ID(value)
    value = tonumber(Plain(value))
    if value and value > 0 and value % 1 == 0 then return value end
end

local function Table(value)
    if type(value) == "table" then return value end
    return {}
end

local function Journal()
    return Table(_G.ForeverDungeonJournal_NS)
end

local function IsDungeon(record)
    return type(record) == "table" and not (record.questChainPage or record.recipeSearch or record.lootFilterPage)
end

local function SnapshotByName(name)
    local wanted = Normalize(name):gsub("^the ", "")
    if wanted == "" then return nil end
    for _, record in ipairs(Table(AzerMindInstanceData)) do
        if type(record) == "table" and Normalize(record.name):gsub("^the ", "") == wanted then return record end
    end
end

local function LiveDungeonName(journal, name)
    name = Text(name)
    if not name then return nil end
    local db = Table(journal.DB)
    if IsDungeon(db[name]) then return name end
    local resolved = Text(Call(journal.DungeonFromInstanceName, name))
    if resolved and IsDungeon(db[resolved]) then return resolved end
    local wanted = Normalize(name):gsub("^the ", "")
    if wanted == "" then return nil end
    for key, record in pairs(db) do
        if type(key) == "string" and IsDungeon(record) and Normalize(key):gsub("^the ", "") == wanted then return key end
    end
end

local function CurrentDungeonName(journal)
    local inside, instanceType = Call(IsInInstance)
    if Plain(inside) ~= true then return nil end
    instanceType = Text(instanceType)
    if instanceType ~= "party" and instanceType ~= "raid" then return nil end
    local current = LiveDungeonName(journal, Call(journal.CurrentDungeon))
    if current then return current end
    local name = Call(GetInstanceInfo)
    local record = SnapshotByName(name)
    return LiveDungeonName(journal, name) or (record and record.name)
end

function AzerMind.ResolveDungeonQuestion(rawText)
    local journal = Journal()
    local candidates, matches, foundLink = {}, {}, false
    local text = (Text(rawText) or ""):gsub("|H([^|]+)|h.-|h", function(payload)
        if payload:match("^azermindinstance:") then
            foundLink = true
            local id = ID(payload:match("^azermindinstance:(%d+)$"))
            local record = id and Call(AzerMind.InstanceByID, id)
            if type(record) == "table" and Text(record.name) then
                candidates[LiveDungeonName(journal, record.name) or record.name] = true
            end
        end
        return " "
    end)
    text = " " .. Normalize(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) .. " "

    local function Match(name, alias)
        local phrase = Normalize(alias)
        if phrase == "" then return end
        phrase = " " .. phrase .. " "
        local start, finish = text:find(phrase, 1, true)
        while start do
            matches[#matches + 1] = { name = name, start = start, finish = finish }
            start, finish = text:find(phrase, finish, true)
        end
    end

    local known = {}
    for _, record in ipairs(Table(AzerMindInstanceData)) do
        if type(record) == "table" and Text(record.name) then
            known[LiveDungeonName(journal, record.name) or record.name] = true
        end
    end
    for name, record in pairs(Table(journal.DB)) do
        if Text(name) and IsDungeon(record) then known[name] = true end
    end
    local aliases = Table(journal.DUNGEON_SEARCH_ALIASES)
    for name in pairs(known) do
        -- Removing the article also matches the full name because of the word boundaries.
        Match(name, Normalize(name):gsub("^the ", ""))
        for _, alias in ipairs(Table(aliases[name])) do Match(name, alias) end
    end
    -- Prefer the more specific phrase at the same location, for example DM West over DM.
    table.sort(matches, function(a, b)
        if a.start == b.start then return a.finish > b.finish end
        return a.start < b.start
    end)
    local widest
    for _, match in ipairs(matches) do
        if not widest or match.finish > widest.finish then widest = match end
        if match.start == widest.start and match.finish == widest.finish then
            candidates[match.name] = true
        end
    end

    local names = {}
    for name in pairs(candidates) do names[#names + 1] = name end
    if #names == 1 then return { status = "ok", name = names[1], provenance = "explicit" } end
    if #names > 1 then
        table.sort(names)
        return { status = "ambiguous", provenance = "explicit", candidates = names }
    end
    if foundLink then return { status = "unknown", provenance = "explicit" } end
    local current = CurrentDungeonName(journal)
    if current then return { status = "ok", name = current, provenance = "current" } end
    return { status = next(known) and "unknown" or "unavailable" }
end

local function Version()
    local version = Call(Table(C_AddOns).GetAddOnMetadata, "ForeverDungeonJournal", "Version")
    return Text(version) or Text(Call(GetAddOnMetadata, "ForeverDungeonJournal", "Version"))
end

local function QuestCompleted(id)
    if not id then return nil end
    local checker = Table(C_QuestLog).IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
    local completed = Plain(Call(checker, id))
    if type(completed) == "boolean" then return completed end
end

function AzerMind.ReadDungeonLoot(name)
    local journal = Journal()
    local liveName = LiveDungeonName(journal, name)
    local snapshot = not liveName and SnapshotByName(name)
    local result = { status = "unavailable", name = Text(name), entries = {} }
    if not liveName and not snapshot then
        result.reason = "Dungeon loot is unavailable from the loaded journal and bundled snapshot."
        return result
    end

    local dungeon
    if liveName then
        dungeon = journal.DB[liveName]
        result.name, result.source, result.version = liveName, "ForeverDungeonJournal", Version()
        if dungeon.previewOnly or type(dungeon.bosses) ~= "table" then result.partial = true end
    else
        dungeon = snapshot
        result.name, result.source = snapshot.name, "AzerMind bundled dungeon snapshot"
        result.partial = true
        result.reason = "The bundled snapshot only covers listed loot."
    end

    local remainingItems = MAX_LOOT_ITEMS
    local limited
    local function AddItems(items, seen, kind, sourceName, npcID, questID, questCompleted, questFaction, shared)
        if items ~= nil and type(items) ~= "table" then result.partial = true end
        for _, item in ipairs(Table(items)) do
            remainingItems = remainingItems - 1
            local fields = Table(item)
            local itemID = ID(snapshot and fields.id or fields[1])
            local itemName = Text(snapshot and fields.name or fields[2])
            if not itemID then
                result.partial = true
            elseif not seen[itemID] then
                seen[itemID] = true
                result.entries[#result.entries + 1] = {
                    itemID = itemID, name = itemName, kind = kind, sourceName = sourceName,
                    npcID = npcID, questID = questID, questCompleted = questCompleted,
                    questFaction = questFaction, shared = shared,
                }
            end
            if remainingItems == 0 then
                limited = true
                break
            end
        end
    end

    for index, boss in ipairs(Table(dungeon.bosses)) do
        if type(boss) ~= "table" then
            result.partial = true
        elseif not boss.recipeTab and not boss.fdjDungeon then
            local seen = {}
            local kind = snapshot and "listed" or (boss.trash and "trash" or "boss")
            local sourceName, npcID = Text(boss.name), ID(boss.npcID)
            AddItems(boss.loot, seen, kind, sourceName, npcID)
            if remainingItems > 0 and kind == "boss" then
                if type(journal.GetBossSharedLoot) == "function" then
                    local ok, items = pcall(journal.GetBossSharedLoot, liveName, boss)
                    if ok then
                        AddItems(items, seen, kind, sourceName, npcID, nil, nil, nil, true)
                    else
                        result.partial = true
                    end
                else
                    result.partial = true
                end
            end
        end
        if index == MAX_DUNGEON_SOURCES then limited = true end
        if remainingItems == 0 or index == MAX_DUNGEON_SOURCES then break end
    end

    if liveName and remainingItems > 0 then
        for index, quest in ipairs(Table(dungeon.quests)) do
            if type(quest) ~= "table" then
                result.partial = true
            elseif quest.rewardItems or quest.additionalRewardItems then
                local seen = {}
                local questID, questName = ID(quest.id), Text(quest.name)
                local completed, faction = QuestCompleted(questID), Text(quest.faction)
                AddItems(quest.rewardItems, seen, "quest", questName, nil, questID, completed, faction)
                if remainingItems > 0 then
                    AddItems(quest.additionalRewardItems, seen, "quest", questName, nil, questID, completed, faction)
                end
            end
            if index == MAX_DUNGEON_SOURCES then limited = true end
            if remainingItems == 0 or index == MAX_DUNGEON_SOURCES then break end
        end
    end

    if limited then
        result.partial = true
        result.reason = (result.reason and result.reason .. " " or "") .. "Dungeon loot inspection reached its limit."
    end
    if #result.entries == 0 then result.partial = true end
    result.status = result.partial and "partial" or "ok"
    if result.partial and not result.reason then result.reason = "The loaded journal's loot coverage is incomplete." end
    return result
end
