local _, ns = ...

local L, Util, UI = ns.L, ns.Util, ns.UI
local Model, Lifecycle, Objectives = ns.Model, ns.Lifecycle, ns.Objectives

local Tracker = {}
ns.Tracker = Tracker

local WIDTH = 260
local LINE_HEIGHT = 12
local PAD = 8 -- left margin inside the tracker

-- Banner header like the game's "All Objectives": dark banner with gold lines,
-- and a red square button that folds the tracker. Drawn with the game's own
-- atlases; when one is missing the plain header is used instead.
local HEADER_ATLAS = "ui-questtracker-primary-objective-header"
local MINIMIZE_ATLAS = { collapse = "ui-questtrackerbutton-collapse-all", expand = "ui-questtrackerbutton-expand-all" }
local MINIMIZE_HIGHLIGHT = "ui-questtrackerbutton-red-highlight"
local BANNER_HEIGHT, PLAIN_HEIGHT = 32, 18

local function hasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local fancyHeader -- true when every atlas above exists
local headerHeight = PLAIN_HEIGHT

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
        b.turnin:SetScript("OnClick", function(self) if self.ready then ns.TurnIn.Open(b.questID) end end)
        b.turnin:SetScript("OnEnter", function(self)
            if not self.ready then return end
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
    fancyHeader = hasAtlas(HEADER_ATLAS) and hasAtlas(MINIMIZE_ATLAS.collapse) and hasAtlas(MINIMIZE_ATLAS.expand)
        and hasAtlas(MINIMIZE_HIGHLIGHT) and hasAtlas(MINIMIZE_ATLAS.collapse .. "-pressed")
        and hasAtlas(MINIMIZE_ATLAS.expand .. "-pressed")
    headerHeight = fancyHeader and BANNER_HEIGHT or PLAIN_HEIGHT
    header:SetSize(WIDTH, headerHeight)
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
    header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.text:SetPoint("LEFT", PAD, 0)
    header.text:SetWidth(WIDTH - PAD - 28) -- keeps clear of the fold button
    header.text:SetWordWrap(false)
    header.text:SetJustifyH("LEFT")
    if fancyHeader then
        header.background = header:CreateTexture(nil, "BACKGROUND")
        header.background:SetAtlas(HEADER_ATLAS, true)
        header.background:SetPoint("CENTER")
        -- 14 pt with a shadow, as in the game's tracker.
        local path = header.text:GetFont()
        header.text:SetFont(path, 14, "")
        header.text:SetShadowOffset(1, -1)
        header.text:SetShadowColor(0, 0, 0, 1)

        local minimize = CreateFrame("Button", nil, header)
        minimize:SetSize(18, 19)
        minimize:SetPoint("RIGHT", -1, 0)
        minimize:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        minimize:SetHighlightAtlas(MINIMIZE_HIGHLIGHT, "ADD")
        minimize:SetScript("OnClick", function()
            Model.char.trackerCollapsed = not Model.char.trackerCollapsed
            Tracker.Refresh()
        end)
        header.minimize = minimize
    end
    UI.Style.Text(header.text)

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
    if fancyHeader then
        header.text:SetText(("CustomQuests (%d)"):format(#tracked))
        local atlas = collapsed and MINIMIZE_ATLAS.expand or MINIMIZE_ATLAS.collapse
        header.minimize:SetNormalAtlas(atlas)
        header.minimize:SetPushedAtlas(atlas .. "-pressed")
    else
        header.text:SetText(("CustomQuests (%d)%s"):format(#tracked, collapsed and " +" or ""))
    end

    local y, n, nPlus, nTitle = -(headerHeight + 2), 0, 0, 0
    if not collapsed then
        for _, entry in ipairs(tracked) do
            local quest = entry.quest
            nTitle = nTitle + 1
            local title = getTitle(nTitle)
            local folded = Model.char.questCollapsed[entry.id]
            local stages = #quest.template.stages
            title.questID = entry.id
            -- The quest's icon sits in front of the title (a turn-in button once it is ready).
            UI.SetQuestIcon(title.turnin.tex, UI.QuestKind(quest.template, quest.templateID),
                quest.ready and "ready" or "progress")
            title.turnin.ready = quest.ready
            title.turnin:Show()
            title.text:ClearAllPoints()
            title.text:SetPoint("TOPLEFT", 18, 0)
            title.text:SetWidth(WIDTH - 30 - PAD - 18)
            title.text:SetText(("|cff%s%s|r%s%s"):format(UI.QUEST_COLOR,
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
