local _, ns = ...

local UI, L = ns.UI, ns.L

-- Item tooltips say when the item is part of an active quest: which quest and
-- how many you have of how many it asks for.
local ItemTooltip = {}
ns.ItemTooltip = ItemTooltip

local function addLines(tooltip, itemID)
    if not ns.Model.account or not ns.Model.account.options.itemTooltip then return end
    local found = ns.Objectives.FindItem(ns.Model.char.active, itemID)
    local first = true
    for _, hit in ipairs(found) do
        if ns.Lifecycle.IsUnlocked(hit.quest) then
            if first then
                tooltip:AddLine(" ")
                first = false
            end
            local have = hit.quest.progress[hit.index] or 0
            local goal = ns.Objectives.Goal(hit.obj)
            local done = have >= goal
            tooltip:AddDoubleLine(
                L["TOOLTIP_QUEST"]:format(UI.QuestText(hit.quest.template.title)),
                ("%d/%d"):format(have, goal),
                1, 0.82, 0, done and 0.125 or 1, done and 1 or 1, done and 0.125 or 1)
        end
    end
end

function ItemTooltip.Init()
    ns.api.HookItemTooltip(addLines)
end

ItemTooltip.AddLines = addLines
