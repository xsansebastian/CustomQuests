local _, ns = ...

local Model, Objectives, Util = ns.Model, ns.Objectives, ns.Util
local Lifecycle = {}
ns.Lifecycle = Lifecycle

local MAX_HISTORY = 1000

local function quests()
    return Model.char.active
end

function Lifecycle.Get(questID)
    return quests()[questID]
end

-- Active and waiting-for-reset quests, newest first.
function Lifecycle.List()
    local list = {}
    for id, quest in pairs(quests()) do list[#list + 1] = { id = id, quest = quest } end
    table.sort(list, function(a, b)
        if a.quest.state ~= b.quest.state then return a.quest.state == "active" end
        return (a.quest.acceptedAt or 0) > (b.quest.acceptedAt or 0)
    end)
    return list
end

function Lifecycle.FindByTemplate(templateID)
    for id, quest in pairs(quests()) do
        if quest.templateID == templateID then return id, quest end
    end
end

-- True when this character has completed the template at least once.
function Lifecycle.HasCompleted(templateID)
    local char = ns.api.GetCharacterKey()
    for _, entry in ipairs(Model.account.history) do
        if entry.templateID == templateID and entry.char == char then return true end
    end
    return false
end

-- False for a quest that belongs to a chain while its predecessor hasn't been
-- turned in (or is being done again): it is kept out of the tracker until then.
function Lifecycle.IsUnlocked(quest)
    local template = Model.GetTemplate(quest.templateID) or quest.template
    local requires = template.requires
    if not requires or not Model.GetTemplate(requires) then return true end
    if not Lifecycle.HasCompleted(requires) then return false end
    local _, running = Lifecycle.FindByTemplate(requires)
    return not (running and running.state == "active")
end

-- Returns true, or nil plus an error key from ns.L and its format argument.
function Lifecycle.CanAccept(templateID)
    local template = Model.GetTemplate(templateID)
    if not template then return nil, "ERR_NO_TEMPLATE" end
    local _, existing = Lifecycle.FindByTemplate(templateID)
    if existing then
        return nil, existing.state == "done" and "ERR_WAIT_RESET" or "ERR_ALREADY_ACTIVE"
    end
    local level = ns.api.GetPlayerLevel()
    if template.minLevel and level < template.minLevel then return nil, "ERR_LEVEL_LOW", template.minLevel end
    if template.maxLevel and level > template.maxLevel then return nil, "ERR_LEVEL_HIGH", template.maxLevel end
    local prerequisite = template.requires and Model.GetTemplate(template.requires)
    if prerequisite and not Lifecycle.HasCompleted(template.requires) then
        return nil, "ERR_LOCKED", prerequisite.title
    end
    return true
end

-- Returns the new quest id, or nil, an error key from ns.L and its argument.
function Lifecycle.Accept(templateID)
    local ok, err, arg = Lifecycle.CanAccept(templateID)
    if not ok then return nil, err, arg end
    local template = Model.GetTemplate(templateID)
    local now = ns.api.Now()
    local id = Model.NewID("q", now)
    quests()[id] = {
        templateID = templateID,
        template = Util.DeepCopy(template), -- edits to the template don't break this run
        stage = 1,
        progress = {},
        state = "active",
        acceptedAt = now,
    }
    Model.char.tracked[id] = true
    Util.Fire("QUESTS_CHANGED")
    return id
end

function Lifecycle.Abandon(questID)
    quests()[questID] = nil
    Model.char.tracked[questID] = nil
    Util.Fire("QUESTS_CHANGED")
end

function Lifecycle.SetTracked(questID, tracked)
    Model.char.tracked[questID] = tracked or nil
    Util.Fire("QUESTS_CHANGED")
end

-- Follow-ups unlocked during Advance; accepted after the loop because adding
-- quests while iterating them with pairs() is undefined in Lua.
local pendingFollowUps = {}

local function complete(questID, quest)
    local now = ns.api.Now()
    local history = Model.account.history
    history[#history + 1] = {
        templateID = quest.templateID,
        title = quest.template.title,
        completedAt = now,
        char = ns.api.GetCharacterKey(),
    }
    while #history > MAX_HISTORY do table.remove(history, 1) end

    Util.Fire("QUEST_COMPLETED", questID, quest)
    for _, nextID in ipairs(Model.GetFollowUps(quest.templateID)) do
        pendingFollowUps[#pendingFollowUps + 1] = nextID
    end
    if quest.template.repeatMode == "none" then
        quests()[questID] = nil
        Model.char.tracked[questID] = nil
    else
        quest.state = "done"
        quest.completedAt = now
        quest.resetAt = now + (ns.api.GetSecondsUntilReset(quest.template.repeatMode) or 86400)
    end
end

-- Next links of a chain start on their own when the character qualifies.
local function startFollowUps()
    while #pendingFollowUps > 0 do
        local nextID = table.remove(pendingFollowUps, 1)
        local questID, err, arg = Lifecycle.Accept(nextID)
        Util.Fire("CHAIN_NEXT", nextID, questID, err, arg)
    end
end

-- Advances finished stages. A quest whose last stage is done becomes "ready"
-- and stays in the log until the player turns it in. Returns true if any
-- quest changed stage or became ready; callers then re-run objective updates,
-- since a new stage may already be satisfied (items already in the bags).
function Lifecycle.Advance()
    local changed = false
    for id, quest in pairs(quests()) do
        if quest.state == "active" and not quest.ready and Objectives.IsStageDone(quest) then
            changed = true
            if quest.stage < #quest.template.stages then
                quest.stage = quest.stage + 1
                quest.progress = {}
                quest.approx = nil
                Util.Fire("STAGE_ADVANCED", id, quest)
            else
                quest.ready = true
                Util.Fire("QUEST_READY", id, quest)
            end
        end
    end
    return changed
end

-- Player turns in a ready quest; returns true on success.
function Lifecycle.TurnIn(questID)
    local quest = quests()[questID]
    if not quest or quest.state ~= "active" or not quest.ready then return false end
    complete(questID, quest)
    startFollowUps()
    Util.Fire("QUESTS_CHANGED")
    return true
end

-- Repeatable quests become active again, from the start, after their reset.
function Lifecycle.CheckResets(now)
    local changed = false
    for _, quest in pairs(quests()) do
        if quest.state == "done" and quest.resetAt and now >= quest.resetAt then
            local template = Model.GetTemplate(quest.templateID)
            if template then quest.template = Util.DeepCopy(template) end
            quest.state = "active"
            quest.stage = 1
            quest.progress = {}
            quest.approx = nil
            quest.ready = nil
            quest.resetAt = nil
            quest.acceptedAt = now
            changed = true
        end
    end
    return changed
end

-- Times completed and last completion for a template, from account history.
function Lifecycle.GetStats(templateID)
    local count, last = 0, nil
    for _, entry in ipairs(Model.account.history) do
        if entry.templateID == templateID then
            count = count + 1
            if not last or entry.completedAt > last then last = entry.completedAt end
        end
    end
    return count, last
end

-- History grouped by template title, most recent first.
function Lifecycle.GetHistorySummary()
    local byKey, list = {}, {}
    for _, entry in ipairs(Model.account.history) do
        local key = entry.templateID or entry.title
        local row = byKey[key]
        if not row then
            row = { title = entry.title, count = 0, last = 0 }
            byKey[key] = row
            list[#list + 1] = row
        end
        row.count = row.count + 1
        if entry.completedAt > row.last then row.last = entry.completedAt end
    end
    table.sort(list, function(a, b) return a.last > b.last end)
    return list
end
