local _, ns = ...

local UI, L = ns.UI, ns.L

-- Item tooltips say when the item is part of an active quest: which quest and
-- how many you have of how many it asks for.
local ItemTooltip = {}
ns.ItemTooltip = ItemTooltip

local function addLines(tooltip, itemID)
    ItemTooltip.seen = itemID
    if not ns.Model.char then return end
    local found = ns.Objectives.FindItem(ns.Model.char.active, itemID)
    ItemTooltip.hits = #found
    local first = true
    for _, hit in ipairs(found) do
        if ns.Lifecycle.IsUnlocked(hit.quest) then
            if first then
                tooltip:AddLine(" ")
                tooltip:AddLine("CQuests", 1, 0.82, 0)
                first = false
            end
            local have = hit.quest.progress[hit.index] or 0
            local goal = ns.Objectives.Goal(hit.obj)
            local done = have >= goal
            tooltip:AddLine(("%s - %d/%d"):format(UI.QuestText(hit.quest.template.title), have, goal),
                done and 0.125 or 1, 1, done and 0.125 or 1)
        end
    end
end

function ItemTooltip.Init()
    ItemTooltip.hooked = ns.api.HookItemTooltip(addLines)
end

-- /cq debug prints this: is the hook in place, which item was seen last, and
-- what do the active quests ask for.
function ItemTooltip.Debug()
    local print = ns.api.Print
    print(("item tooltip hook: %s, last item seen: %s, quests matching it: %s"):format(
        tostring(ItemTooltip.hooked), tostring(ItemTooltip.seen), tostring(ItemTooltip.hits)))
    for _, quest in pairs(ns.Model.char.active) do
        if quest.state == "active" then
            for _, obj in ipairs(ns.Objectives.CurrentStage(quest).objectives) do
                if obj.type == "item" then
                    print(("%s asks for item %s"):format(quest.template.title, tostring(obj.itemID)))
                end
            end
        end
    end
end
