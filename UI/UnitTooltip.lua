local _, ns = ...

local UI, L = ns.UI, ns.L

-- NPC tooltips say when the player has to get close to or talk to that NPC
-- for a quest, and which quest.
local UnitTooltip = {}
ns.UnitTooltip = UnitTooltip

local function addLines(tooltip, npcID)
    if not ns.Model.char then return end
    local first = true
    for _, hit in ipairs(ns.Objectives.FindNear(ns.Model.char.active, npcID)) do
        if ns.Lifecycle.IsUnlocked(hit.quest) then
            if first then
                tooltip:AddLine(" ")
                tooltip:AddLine("CQuests", 1, 0.82, 0)
                first = false
            end
            local icon = UI.QuestIconMarkup(UI.QuestKind(hit.quest.template, hit.quest.templateID), "ready", 16)
            local quest = hit.quest
            tooltip:AddLine(("%s %s"):format(icon, UI.QuestText(quest.template.title)), 1, 1, 1)
            tooltip:AddLine(UI.ObjectiveLabel(hit.obj), 0.8, 0.8, 0.8)
        end
    end
end

function UnitTooltip.Init()
    UnitTooltip.hooked = ns.api.HookUnitTooltip(addLines)
end
