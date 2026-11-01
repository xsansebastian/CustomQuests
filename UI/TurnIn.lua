local _, ns = ...

local L, Util, UI = ns.L, ns.Util, ns.UI
local Lifecycle = ns.Lifecycle

-- Window where a ready quest is turned in: shows its completion text and reward.
local TurnIn = {}
ns.TurnIn = TurnIn

local WIDTH, HEIGHT = 420, 380
local window, questID

local function render()
    local quest = Lifecycle.Get(questID)
    if not quest or not quest.ready or quest.state ~= "active" then
        window:Hide()
        return
    end
    local template = quest.template
    window.title:SetText(UI.QuestIconMarkup(UI.QuestKind(template, quest.templateID), "ready", 22) .. " |cff" .. UI.QUEST_COLOR .. UI.QuestText(template.title) .. "|r")

    local parts = {}
    if template.completionText and template.completionText ~= "" then
        parts[#parts + 1] = UI.QuestText(template.completionText)
    else
        parts[#parts + 1] = L["TURNIN_DEFAULT"]
    end
    if template.rewardText and template.rewardText ~= "" then
        parts[#parts + 1] = L["REWARD"]:format(UI.QuestText(template.rewardText))
    end
    window.body:SetText(table.concat(parts, "\n\n"))
    window.content:SetHeight(window.title:GetStringHeight() + window.body:GetStringHeight() + 20)
end

local function create()
    window = UI.CreateWindow("CustomQuestsTurnIn", WIDTH, HEIGHT, L["TURNIN_TITLE"])

    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -34)
    scroll:SetPoint("BOTTOMRIGHT", -34, 50)
    window.content = CreateFrame("Frame", nil, scroll)
    window.content:SetSize(WIDTH - 60, 1)
    scroll:SetScrollChild(window.content)

    window.title = UI.CreateLabel(window.content, "", "GameFontNormalLarge")
    window.title:SetPoint("TOPLEFT")
    window.title:SetWidth(WIDTH - 60)
    window.body = UI.CreateLabel(window.content, "", "GameFontHighlight")
    window.body:SetPoint("TOPLEFT", window.title, "BOTTOMLEFT", 0, -14)
    window.body:SetWidth(WIDTH - 60)
    window.body:SetSpacing(2)

    local complete = UI.CreateButton(window, L["TURNIN_COMPLETE"], 140, function()
        local id = questID
        window:Hide()
        if Lifecycle.TurnIn(id) then ns.RefreshAll(true) end
    end)
    complete:SetPoint("BOTTOMLEFT", 16, 14)
    UI.CreateButton(window, CANCEL, 100, function() window:Hide() end):SetPoint("LEFT", complete, "RIGHT", 6, 0)

    Util.On("QUESTS_CHANGED", function() if window:IsShown() then render() end end)
end

function TurnIn.Open(id)
    if not window then create() end
    questID = id
    window:Show()
    render()
end
