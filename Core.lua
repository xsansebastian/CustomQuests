local ADDON_NAME, ns = ...

local L, Util = ns.L, ns.Util
local Model, Objectives, Lifecycle = ns.Model, ns.Objectives, ns.Lifecycle

local frame = CreateFrame("Frame")
local locationTicker

-- Runs every objective source, then advances stages until stable (a new
-- stage can already be complete, e.g. items already in the bags).
-- force: the caller already changed something, so notify the UI regardless.
function ns.RefreshAll(force)
    local quests = Model.char.active
    local changed = Lifecycle.CheckResets(ns.api.Now()) or force
    for _ = 1, Model.MAX_STAGES + 1 do
        local updated = Objectives.UpdateItems(quests)
        updated = Objectives.UpdateZone(quests, ns.api.GetPlayerMapID(), ns.api.GetSubZoneNames()) or updated
        updated = Objectives.UpdateLocation(quests) or updated
        updated = Objectives.UpdateLevel(quests, ns.playerLevel or ns.api.GetPlayerLevel()) or updated
        local advanced = Lifecycle.Advance()
        changed = changed or updated or advanced
        if not advanced then break end
    end
    ns.UpdateLocationTicker()
    if changed then Util.Fire("QUESTS_CHANGED") end
end

-- Applies an incremental update (kill, boss, manual) and settles the result.
function ns.ApplyChange(changed)
    if changed then ns.RefreshAll(true) end
end

function ns.UpdateLocationTicker()
    local needed = Objectives.NeedsLocationPolling(Model.char.active)
    if needed and not locationTicker then
        locationTicker = C_Timer.NewTicker(1, function()
            ns.ApplyChange(Objectives.UpdateLocation(Model.char.active))
        end)
    elseif not needed and locationTicker then
        locationTicker:Cancel()
        locationTicker = nil
    end
end

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON_NAME then return end
    CustomQuestsDB, CustomQuestsCharDB = Model.InitDB(CustomQuestsDB, CustomQuestsCharDB)
    frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_LOGIN()
    if not ns.api.IsExpectedClient() then
        ns.api.Print(L["WRONG_CLIENT"]:format(ns.target))
    end
    ns.api.Print(L["LOADED"]:format(ns.api.GetMetadata("Version") or "?"))
    if ns.Tracker then ns.Tracker.Init() end
    ns.RefreshAll()
    ns.TrackProgress() -- records the starting point so login doesn't announce old progress
    C_Timer.NewTicker(60, function()
        ns.ApplyChange(Lifecycle.CheckResets(ns.api.Now()))
    end)
end

function handlers.BAG_UPDATE_DELAYED()
    ns.ApplyChange(Objectives.UpdateItems(Model.char.active))
end

function handlers.PLAYER_LEVEL_UP(level)
    ns.playerLevel = level
    ns.ApplyChange(Objectives.UpdateLevel(Model.char.active, level))
    ns.playerLevel = nil
end

function handlers.ZONE_CHANGED_NEW_AREA()
    ns.RefreshAll()
end
handlers.PLAYER_ENTERING_WORLD = handlers.ZONE_CHANGED_NEW_AREA
handlers.ZONE_CHANGED = handlers.ZONE_CHANGED_NEW_AREA
handlers.ZONE_CHANGED_INDOORS = handlers.ZONE_CHANGED_NEW_AREA

-- PARTY_KILL payload is secret when unit identity is restricted (instances in
-- combat). A secret GUID is never inspected: it counts as an unidentified kill.
function handlers.PARTY_KILL(_, targetGUID)
    local npcID
    if not ns.api.IsSecret(targetGUID) then
        npcID = Util.NPCIDFromGUID(targetGUID)
        if not npcID then return end -- players, pets, objects
    end
    ns.ApplyChange(Objectives.OnKill(Model.char.active, npcID, ns.api.GetPlayerMapID()))
end

-- Item names arrive asynchronously; redraw once per burst.
local itemRedrawPending = false
function handlers.GET_ITEM_INFO_RECEIVED()
    if itemRedrawPending then return end
    itemRedrawPending = true
    C_Timer.After(0.3, function()
        itemRedrawPending = false
        Util.Fire("QUESTS_CHANGED")
    end)
end

function handlers.ENCOUNTER_START(encounterID, encounterName)
    ns.lastEncounter = { id = encounterID, name = encounterName }
end

function handlers.ENCOUNTER_END(encounterID, encounterName, _, _, success)
    ns.lastEncounter = { id = encounterID, name = encounterName }
    if success == 1 then
        ns.ApplyChange(Objectives.OnBoss(Model.char.active, encounterID))
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    -- Nothing to update until SavedVariables are loaded.
    if event ~= "ADDON_LOADED" and not Model.char then return end
    handlers[event](...)
end)
for event in pairs(handlers) do frame:RegisterEvent(event) end

Util.On("QUEST_COMPLETED", function(_, quest)
    ns.api.Print(L["QUEST_COMPLETED"]:format(ns.UI.QuestText(quest.template.title)))
    local sound = SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE
    if sound then PlaySound(sound) end
end)

-- Next quest of a chain: accepted automatically, or why it couldn't be.
Util.On("CHAIN_NEXT", function(templateID, questID, err, arg)
    local template = Model.GetTemplate(templateID)
    if not template then return end
    local title = ns.UI.QuestText(template.title)
    if questID then
        ns.api.Print(L["CHAIN_ACCEPTED"]:format(title))
    elseif err ~= "ERR_ALREADY_ACTIVE" then
        ns.api.Print(L["CHAIN_UNLOCKED"]:format(title, ns.UI.ErrorText(err, arg)))
    end
end)

-- Objective progress on screen ---------------------------------------------
-- snapshots[questID] = { objs = stage objectives, values = last seen progress }.
-- Diffed on every change; the first run (login) only records, silently.

local snapshots, snapshotsReady = {}, false

local function objectiveMessage(obj, value)
    local goal = Objectives.Goal(obj)
    local text = ns.UI.ObjectiveLabel(obj)
    if goal > 1 and obj.type ~= "level" then
        text = ("%s: %d/%d"):format(text, math.min(value, goal), goal)
    end
    if value >= goal then text = text .. " (" .. L["OBJECTIVE_DONE"] .. ")" end
    return text
end

-- The stage or quest ended: whatever wasn't seen as done finished just now.
local function finishSnapshot(questID)
    local snap = snapshots[questID]
    snapshots[questID] = nil
    if not snap then return end
    local any = false
    for i, obj in ipairs(snap.objs) do
        local goal = Objectives.Goal(obj)
        if (snap.values[i] or 0) < goal then
            ns.api.Splash(objectiveMessage(obj, goal))
            any = true
        end
    end
    if any then ns.api.PlayObjectiveSound() end
end

local function trackProgress()
    local seen, completed = {}, false
    for _, entry in ipairs(Lifecycle.List()) do
        local quest = entry.quest
        if quest.state == "active" then
            seen[entry.id] = true
            local objs = Objectives.CurrentStage(quest).objectives
            local old = snapshots[entry.id] and snapshots[entry.id].values or {}
            local values = {}
            for i, obj in ipairs(objs) do
                local value, before = quest.progress[i] or 0, old[i] or 0
                values[i] = value
                if snapshotsReady and value > before then
                    ns.api.Splash(objectiveMessage(obj, value))
                    completed = completed or (value >= Objectives.Goal(obj) and before < Objectives.Goal(obj))
                end
            end
            snapshots[entry.id] = { objs = objs, values = values }
        end
    end
    for id in pairs(snapshots) do
        if not seen[id] then snapshots[id] = nil end
    end
    snapshotsReady = true
    if completed then ns.api.PlayObjectiveSound() end
end

ns.TrackProgress = trackProgress
Util.On("QUESTS_CHANGED", trackProgress)
-- All objectives done: the quest now waits to be turned in.
Util.On("QUEST_READY", function(questID, quest)
    finishSnapshot(questID)
    local title = ns.UI.QuestText(quest.template.title)
    ns.api.Splash(L["QUEST_READY"]:format(title))
    ns.api.Print(L["QUEST_READY"]:format(title))
    ns.api.PlayObjectiveSound()
end)

Util.On("STAGE_ADVANCED", function(questID, quest)
    finishSnapshot(questID)
    ns.api.Splash(L["STAGE_ADVANCED"]:format(ns.UI.QuestText(quest.template.title), quest.stage, #quest.template.stages))
end)

Util.On("QUEST_COMPLETED", function(_, quest)
    ns.api.Splash(L["QUEST_COMPLETED"]:format(ns.UI.QuestText(quest.template.title)))
end)

Util.On("STAGE_ADVANCED", function(_, quest)
    ns.api.Print(L["STAGE_ADVANCED"]:format(ns.UI.QuestText(quest.template.title), quest.stage, #quest.template.stages))
end)

-- Slash commands ------------------------------------------------------------

local commands = {}

function commands.tracker()
    if ns.Tracker then ns.Tracker.Toggle() end
end

function commands.debug()
    local mapID = ns.api.GetPlayerMapID()
    ns.api.Print(("target=%s map=%s (%s) lastEncounter=%s"):format(
        ns.target, tostring(mapID), tostring(ns.api.GetMapName(mapID)),
        ns.lastEncounter and (ns.lastEncounter.id .. " " .. tostring(ns.lastEncounter.name)) or "-"))
    for _, entry in ipairs(Lifecycle.List()) do
        local q = entry.quest
        ns.api.Print(("  %s [%s] stage %d resetAt=%s"):format(Util.SafeText(q.template.title), q.state, q.stage, tostring(q.resetAt)))
    end
end

-- Forces every repeatable completed quest to reset now (testing).
function commands.reset()
    for _, entry in ipairs(Lifecycle.List()) do
        if entry.quest.state == "done" then entry.quest.resetAt = 0 end
    end
    ns.RefreshAll(true)
end

-- Creates (or refreshes) the sample templates and shows them.
function commands.sample()
    local id = ns.Samples.InstallAll()
    if ns.Journal then ns.Journal.ShowTemplate(id) end
end

function commands.help()
    ns.api.Print(L["HELP"])
end

SLASH_CUSTOMQUESTS1 = "/cq"
SLASH_CUSTOMQUESTS2 = "/customquests"
SlashCmdList["CUSTOMQUESTS"] = function(msg)
    local cmd = (msg or ""):match("^%s*(%S*)"):lower()
    if cmd == "" then
        if ns.Journal then ns.Journal.Toggle() end
    elseif commands[cmd] then
        commands[cmd]()
    else
        commands.help()
    end
end
