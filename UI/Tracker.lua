local _, ns = ...

local L, Util, UI = ns.L, ns.Util, ns.UI
local Model, Lifecycle, Objectives = ns.Model, ns.Lifecycle, ns.Objectives

local Tracker = {}
ns.Tracker = Tracker

local WIDTH = 260
local LINE_HEIGHT = 12
local PAD = 8 -- left margin inside the tracker

local frame, header
local lines, plusButtons, titleButtons = {}, {}, {}
local savePosition

local function getLine(i)
    local fs = lines[i]
    if not fs then
        fs = UI.Style.Text(frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetWidth(WIDTH - 30 - PAD)
        lines[i] = fs
    end
    fs:Show()
    return fs
end

local function startMove()
    if IsShiftKeyDown() then frame:StartMoving() end
end

local function stopMove()
    frame:StopMovingOrSizing()
    savePosition()
end

-- Quest title: right-click folds or unfolds that quest. Shift+drag moves the tracker.
local function getTitle(i)
    local b = titleButtons[i]
    if not b then
        b = CreateFrame("Button", nil, frame)
        b.text = UI.Style.Text(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        b.text:SetPoint("TOPLEFT")
        b.text:SetJustifyH("LEFT")
        b.text:SetWidth(WIDTH - 30 - PAD)
        b:SetWidth(WIDTH - 30)
        b:RegisterForDrag("LeftButton")
        b:RegisterForClicks("RightButtonUp")
        b:SetScript("OnDragStart", startMove)
        b:SetScript("OnDragStop", stopMove)
        b:SetScript("OnClick", function(self)
            local folded = Model.char.questCollapsed
            folded[self.questID] = not folded[self.questID] or nil
            Tracker.Refresh()
        end)
        -- Yellow "?" on the right of a ready quest: opens the turn-in window.
        b.turnin = CreateFrame("Button", nil, b)
        b.turnin:SetSize(16, 16)
        b.turnin:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b.turnin.tex = b.turnin:CreateTexture(nil, "ARTWORK")
        b.turnin.tex:SetAllPoints()
        b.turnin:SetScript("OnClick", function() ns.TurnIn.Open(b.questID) end)
        b.turnin:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(L["TURNIN_TITLE"])
            GameTooltip:AddLine(L["TURNIN_HELP"], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b.turnin:SetScript("OnLeave", GameTooltip_Hide)
        titleButtons[i] = b
    end
    b:Show()
    return b
end

local function getPlus(i)
    local b = plusButtons[i]
    if not b then
        b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(18, 14)
        b:SetText("+")
        b:SetScript("OnClick", function(self, mouse)
            local quest = Lifecycle.Get(self.questID)
            if quest then
                ns.ApplyChange(Objectives.AdjustManual(quest, self.index, mouse == "RightButton" and -1 or 1))
            end
        end)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        plusButtons[i] = b
    end
    b:Show()
    return b
end

-- Always anchored by its top-left corner so folding quests only moves the bottom edge.
function savePosition()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    Model.char.trackerPos = { "TOPLEFT", "BOTTOMLEFT", left, top }
end

local function create()
    frame = CreateFrame("Frame", "CustomQuestsTracker", UIParent)
    frame:SetSize(WIDTH, 40)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Background and border live in a separate frame behind the tracker, so the
    -- tracker's own text (regions of `frame`) is drawn on top of it.
    local bg = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    bg:SetFrameStrata(frame:GetFrameStrata())
    bg:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 6)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -6)
    UI.Style.Box(bg)
    frame:HookScript("OnShow", function() bg:Show() end)
    frame:HookScript("OnHide", function() bg:Hide() end)
    bg:SetShown(frame:IsShown())

    header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetSize(WIDTH, 18)
    header:RegisterForDrag("LeftButton")
    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    header:SetScript("OnDragStart", startMove)
    header:SetScript("OnDragStop", stopMove)
    header:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            Model.char.trackerCollapsed = not Model.char.trackerCollapsed
            Tracker.Refresh()
        elseif ns.Journal then
            ns.Journal.Toggle()
        end
    end)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("CustomQuests")
        GameTooltip:AddLine(L["TRACKER_TOOLTIP"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", GameTooltip_Hide)
    header.text = UI.Style.Text(header:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    header.text:SetPoint("LEFT", PAD, 0)

    local pos = Model.char.trackerPos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", -340, -250)
    end
    -- Positions saved with another anchor are converted to top-left.
    if not pos or pos[1] ~= "TOPLEFT" or pos[2] ~= "BOTTOMLEFT" then savePosition() end
end

function Tracker.Refresh()
    if not frame then return end
    for _, fs in ipairs(lines) do fs:Hide() end
    for _, b in ipairs(plusButtons) do b:Hide() end
    for _, b in ipairs(titleButtons) do b:Hide() end
    Model.char.questCollapsed = Model.char.questCollapsed or {}

    if not Model.char.trackerShown then frame:Hide() return end

    local tracked = {}
    for _, entry in ipairs(Lifecycle.List()) do
        if entry.quest.state == "active" and Model.char.tracked[entry.id] then tracked[#tracked + 1] = entry end
    end
    if #tracked == 0 then frame:Hide() return end
    frame:Show()

    local collapsed = Model.char.trackerCollapsed
    header.text:SetText(("CustomQuests (%d)%s"):format(#tracked, collapsed and " +" or ""))

    local y, n, nPlus, nTitle = -20, 0, 0, 0
    if not collapsed then
        for _, entry in ipairs(tracked) do
            local quest = entry.quest
            nTitle = nTitle + 1
            local title = getTitle(nTitle)
            local folded = Model.char.questCollapsed[entry.id]
            local stages = #quest.template.stages
            title.questID = entry.id
            local ready = quest.ready and UI.SetTurnInTexture(title.turnin.tex)
            title.turnin:SetShown(ready or false)
            -- The "?" sits in front of the title, so the text makes room for it.
            title.text:ClearAllPoints()
            title.text:SetPoint("TOPLEFT", ready and 18 or 0, 0)
            title.text:SetWidth(WIDTH - 30 - PAD - (ready and 18 or 0))
            title.text:SetText(("%s|cff%s%s|r%s%s"):format(UI.InlineIcon(quest.template, 12), UI.QUEST_COLOR,
                UI.QuestText(quest.template.title),
                stages > 1 and (" (" .. quest.stage .. "/" .. stages .. ")") or "", folded and " [+]" or ""))
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
            title:SetHeight(title.text:GetStringHeight())
            y = y - title.text:GetStringHeight() - 1

            for i, obj in ipairs(folded and {} or Objectives.CurrentStage(quest).objectives) do
                n = n + 1
                local line = getLine(n)
                local text, done = UI.ObjectiveLine(quest, i, obj)
                line:SetText("- " .. text)
                line:SetPoint("TOPLEFT", frame, "TOPLEFT", 8 + PAD, y)
                if obj.type == "manual" and not done then
                    nPlus = nPlus + 1
                    local b = getPlus(nPlus)
                    b.questID, b.index = entry.id, i
                    b:SetPoint("TOPRIGHT", frame, "TOPLEFT", WIDTH, y + 1)
                end
                y = y - math.max(line:GetStringHeight(), LINE_HEIGHT)
            end
            y = y - 4
        end
    end
    frame:SetHeight(-y)
end

function Tracker.Toggle()
    Model.char.trackerShown = not Model.char.trackerShown
    Tracker.Refresh()
end

function Tracker.Init()
    if frame then return end
    create()
    Util.On("QUESTS_CHANGED", Tracker.Refresh)
    Util.On("STYLE_CHANGED", Tracker.Refresh)
    Tracker.Refresh()
end
