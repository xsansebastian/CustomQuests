local _, ns = ...

-- Progress engine. Each function updates quest.progress for the current stage
-- and returns true when anything changed. Game data comes from ns.api only.
local Objectives = {}
ns.Objectives = Objectives

local COUNTED = { item = true, kill = true, boss = true, manual = true }

function Objectives.Goal(obj)
    if obj.type == "level" then return obj.level end
    return COUNTED[obj.type] and obj.count or 1
end

function Objectives.IsDone(obj, value)
    return (value or 0) >= Objectives.Goal(obj)
end

function Objectives.CurrentStage(quest)
    return quest.template.stages[quest.stage]
end

function Objectives.IsStageDone(quest)
    for i, obj in ipairs(Objectives.CurrentStage(quest).objectives) do
        if not Objectives.IsDone(obj, quest.progress[i]) then return false end
    end
    return true
end

-- Calls fn(quest, index, objective) for every objective of the given type in
-- the current stage of every in-progress quest.
local function eachObjective(quests, objType, fn)
    local changed = false
    for _, quest in pairs(quests) do
        if quest.state == "active" then
            for i, obj in ipairs(Objectives.CurrentStage(quest).objectives) do
                if obj.type == objType and fn(quest, i, obj) then changed = true end
            end
        end
    end
    return changed
end

local function increment(quest, i, obj)
    local value = quest.progress[i] or 0
    if value >= Objectives.Goal(obj) then return false end
    quest.progress[i] = value + 1
    return true
end

-- Item objectives mirror what is in the bags right now (can go down).
function Objectives.UpdateItems(quests)
    return eachObjective(quests, "item", function(quest, i, obj)
        local count = math.min(ns.api.GetItemCount(obj.itemID), obj.count)
        if quest.progress[i] == count then return false end
        quest.progress[i] = count
        return true
    end)
end

-- npcID is nil when the kill's identity was secret; then only map-scoped
-- "any" objectives and fallbackAny objectives on this map can count it.
function Objectives.OnKill(quests, npcID, mapID)
    return eachObjective(quests, "kill", function(quest, i, obj)
        local sameMap = obj.mapID ~= nil and obj.mapID == mapID
        local matches, approx
        if npcID then
            if obj.npcID then
                matches = obj.npcID == npcID and (obj.mapID == nil or sameMap)
            else
                matches = sameMap
            end
        else
            matches = sameMap and (obj.npcID == nil or obj.fallbackAny)
            approx = obj.npcID ~= nil
        end
        if not matches or not increment(quest, i, obj) then return false end
        if approx then
            quest.approx = quest.approx or {}
            quest.approx[i] = true
        end
        return true
    end)
end

function Objectives.OnBoss(quests, encounterID)
    return eachObjective(quests, "boss", function(quest, i, obj)
        return obj.encounterID == encounterID and increment(quest, i, obj)
    end)
end

-- Zone and location objectives latch: once reached they stay done.
-- Zone objectives count a whole map; subzone objectives name a subzone
-- (compared ignoring case with the names the game shows now: set of lowercase
-- strings), optionally inside a map.
function Objectives.UpdateZone(quests, mapID, names)
    local function reached(quest, i, obj)
        if quest.progress[i] == 1 then return false end
        if obj.name and not (names and names[obj.name:lower():match("^%s*(.-)%s*$")]) then return false end
        if obj.mapID and not ns.api.IsMapInside(mapID, obj.mapID) then return false end
        quest.progress[i] = 1
        return true
    end
    local zones = eachObjective(quests, "zone", reached)
    return eachObjective(quests, "subzone", reached) or zones
end

function Objectives.UpdateLocation(quests)
    return eachObjective(quests, "location", function(quest, i, obj)
        if quest.progress[i] == 1 then return false end
        local x, y = ns.api.GetPlayerPosition(obj.mapID)
        if not x then return false end
        local dx, dy = x - obj.x, y - obj.y
        if dx * dx + dy * dy > obj.radius * obj.radius then return false end
        quest.progress[i] = 1
        return true
    end)
end

-- Level objectives show current/target level. level is passed in because
-- UnitLevel can lag behind PLAYER_LEVEL_UP's payload.
function Objectives.UpdateLevel(quests, level)
    return eachObjective(quests, "level", function(quest, i, obj)
        local value = math.min(level or 0, obj.level)
        if quest.progress[i] == value then return false end
        quest.progress[i] = value
        return true
    end)
end

function Objectives.NeedsLocationPolling(quests)
    local needed = false
    eachObjective(quests, "location", function(quest, i)
        if quest.progress[i] ~= 1 then needed = true end
    end)
    return needed
end

function Objectives.AdjustManual(quest, i, delta)
    local obj = Objectives.CurrentStage(quest).objectives[i]
    if not obj or obj.type ~= "manual" then return false end
    local value = math.max(0, math.min(obj.count, (quest.progress[i] or 0) + delta))
    if value == (quest.progress[i] or 0) then return false end
    quest.progress[i] = value
    return true
end
