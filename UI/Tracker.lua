local _, ns = ...

local L, Util, UI = ns.L, ns.Util, ns.UI
local Model, Lifecycle, Objectives = ns.Model, ns.Lifecycle, ns.Objectives

local Tracker = {}
ns.Tracker = Tracker

local DEFAULT_WIDTH, MIN_WIDTH, MAX_WIDTH = 260, 200, 520
local MIN_HEIGHT, MAX_HEIGHT = 90, 900
local width = DEFAULT_WIDTH -- the tracker's size: hold Shift and drag its corner to change it
local userHeight -- nil: as tall as the quests need; a number: that tall, scrolling when they don't fit
local LINE_HEIGHT = 12
local PAD = 8 -- left margin inside the tracker
local ICON_SIZE = 24 -- quest icon in front of each title, as big as the game's own tracker icons

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

local frame, header, scroll, content -- content holds the quests and scrolls inside the frame
local lines, plusButtons, titleButtons, sectionHeaders = {}, {}, {}, {}
local SECTION_HEIGHT = 24
local savePosition

local function getLine(i)
    local fs = lines[i]
    if not fs then
        fs = UI.Style.Text(content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetWidth(width - 30 - PAD)
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

-- Quest title: left-click opens it in the Journal, shift-click stops tracking it, right-click folds or unfolds it. Shift+drag moves the tracker.
local function getTitle(i)
    local b = titleButtons[i]
    if not b then
        b = CreateFrame("Button", nil, content)
        b.text = UI.Style.Text(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        b.text:SetPoint("TOPLEFT")
        b.text:SetJustifyH("LEFT")
        b.text:SetWidth(width - 30 - PAD)
        b:SetWidth(width - 30)
        b:RegisterForDrag("LeftButton")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnDragStart", startMove)
        b:SetScript("OnDragStop", stopMove)
        b:SetScript("OnClick", function(self, mouse)
            if mouse == "LeftButton" and IsShiftKeyDown() then
                Lifecycle.SetTracked(self.questID, false)
            elseif mouse == "RightButton" then
                local folded = Model.char.questCollapsed
                folded[self.questID] = not folded[self.questID] or nil
                Tracker.Refresh()
            elseif ns.Journal then
                ns.Journal.ShowQuest(self.questID)
            end
        end)
        -- Yellow "?" on the right of a ready quest: opens the turn-in window.
        b.turnin = CreateFrame("Button", nil, b)
        b.turnin:SetSize(ICON_SIZE, ICON_SIZE)
        b.turnin:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b.turnin.tex = b.turnin:CreateTexture(nil, "ARTWORK")
        b.turnin.tex:SetPoint("CENTER")
        b.turnin.tex:SetSize(ICON_SIZE, ICON_SIZE)
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

-- Section bar, like the game's "Quests" header: left click or right click folds it.
-- Shift+drag moves the tracker, as everywhere else on it.
local function getSectionHeader(i)
    local h = sectionHeaders[i]
    if not h then
        h = UI.CreateSectionHeader(content, SECTION_HEIGHT, true)
        h:SetWidth(width)
        h:RegisterForDrag("LeftButton")
        h:SetScript("OnDragStart", startMove)
        h:SetScript("OnDragStop", stopMove)
        h.onClick = function()
            local folded = Model.char.sectionCollapsed.tracker
            folded[h.sectionID] = not folded[h.sectionID] or nil
            Tracker.Refresh()
        end
        sectionHeaders[i] = h
    end
    h:Show()
    return h
end

local function getPlus(i)
    local b = plusButtons[i]
    if not b then
        b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
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
    width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, tonumber(Model.char.trackerWidth) or DEFAULT_WIDTH))
    local savedHeight = tonumber(Model.char.trackerHeight)
    userHeight = savedHeight and math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, savedHeight)) or nil
    frame:SetSize(width, 40)
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

    scroll = CreateFrame("ScrollFrame", nil, frame)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 30)))
    end)

    header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT")
    fancyHeader = hasAtlas(HEADER_ATLAS) and hasAtlas(MINIMIZE_ATLAS.collapse) and hasAtlas(MINIMIZE_ATLAS.expand)
        and hasAtlas(MINIMIZE_HIGHLIGHT) and hasAtlas(MINIMIZE_ATLAS.collapse .. "-pressed")
        and hasAtlas(MINIMIZE_ATLAS.expand .. "-pressed")
    headerHeight = fancyHeader and BANNER_HEIGHT or PLAIN_HEIGHT
    header:SetSize(width, headerHeight)
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
    header.text:SetWidth(width - PAD - 28) -- keeps clear of the fold button
    header.text:SetWordWrap(false)
    header.text:SetJustifyH("LEFT")
    if fancyHeader then
        header.background = header:CreateTexture(nil, "BACKGROUND")
        header.background:SetAtlas(HEADER_ATLAS)
        local info = C_Texture.GetAtlasInfo(HEADER_ATLAS)
        header.background:SetPoint("LEFT")
        header.background:SetPoint("RIGHT")
        header.background:SetHeight(info and info.height or headerHeight)
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

    -- Hold Shift and a grip shows in the bottom-right corner: drag it to change the size;
    -- right-click it to go back to a height that fits the quests.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnClick", function()
        userHeight = nil
        Model.char.trackerHeight = nil
        Tracker.Refresh()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["TRACKER_RESIZE_TIP"])
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", GameTooltip_Hide)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    local resizing = false
    local function updateGrip() grip:SetShown(resizing or (frame:IsShown() and IsShiftKeyDown())) end
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        resizing = true
        self:SetScript("OnUpdate", function()
            local scale = frame:GetEffectiveScale()
            local x = GetCursorPosition() / scale - frame:GetLeft()
            local _, cursorY = GetCursorPosition()
            local newWidth = math.max(MIN_WIDTH, math.min(MAX_WIDTH, math.floor(x + 0.5)))
            local newHeight = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, math.floor(frame:GetTop() - cursorY / scale + 0.5)))
            if newWidth ~= width or newHeight ~= userHeight then
                width, userHeight = newWidth, newHeight
                Tracker.Refresh()
            end
        end)
    end)
    grip:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        resizing = false
        self:SetScript("OnUpdate", nil)
        Model.char.trackerWidth = width
        Model.char.trackerHeight = userHeight
        updateGrip()
    end)
    frame:RegisterEvent("MODIFIER_STATE_CHANGED")
    frame:SetScript("OnEvent", updateGrip)
    frame:HookScript("OnShow", updateGrip)
    grip:Hide()

    local pos = Model.char.trackerPos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", -340, -250)
    end
    -- Positions saved with another anchor are converted to top-left.
    if not pos or pos[1] ~= "TOPLEFT" or pos[2] ~= "BOTTOMLEFT" then savePosition() end
end

-- Applies `width` to the parts that are built once and reused.
local function applyWidth()
    frame:SetWidth(width)
    content:SetWidth(width)
    header:SetWidth(width)
    header.text:SetWidth(width - PAD - 28)
    for _, fs in ipairs(lines) do fs:SetWidth(width - 30 - PAD) end
    for _, b in ipairs(titleButtons) do
        b:SetWidth(width - 30)
        b.text:SetWidth(width - 30 - PAD)
    end
    for _, h in ipairs(sectionHeaders) do h:SetWidth(width) end
end

function Tracker.Refresh()
    if not frame then return end
    applyWidth()
    for _, fs in ipairs(lines) do fs:Hide() end
    for _, b in ipairs(plusButtons) do b:Hide() end
    for _, b in ipairs(titleButtons) do b:Hide() end
    for _, h in ipairs(sectionHeaders) do h:Hide() end
    Model.char.questCollapsed = Model.char.questCollapsed or {}

    if not Model.char.trackerShown then frame:Hide() return end

    local tracked = {}
    for _, entry in ipairs(Lifecycle.List()) do
        if entry.quest.state == "active" and Model.char.tracked[entry.id] and Lifecycle.IsUnlocked(entry.quest) then
            tracked[#tracked + 1] = entry
        end
    end
    if #tracked == 0 then frame:Hide() return end
    frame:Show()

    local collapsed = Model.char.trackerCollapsed
    if fancyHeader then
        header.text:SetText(("%s (%d)"):format(Model.CleanTrackerTitle(UI.Style.Options().title), #tracked))
        local atlas = collapsed and MINIMIZE_ATLAS.expand or MINIMIZE_ATLAS.collapse
        header.minimize:SetNormalAtlas(atlas)
        header.minimize:SetPushedAtlas(atlas .. "-pressed")
    else
        header.text:SetText(("%s (%d)%s"):format(Model.CleanTrackerTitle(UI.Style.Options().title), #tracked,
            collapsed and " +" or ""))
    end

    local y, n, nPlus, nTitle = 0, 0, 0, 0
    if not collapsed then
        local groups = Model.GroupBySection(tracked, function(entry)
            local quest = entry.quest
            return Model.SectionOf(Model.GetTemplate(quest.templateID) or quest.template)
        end, Model.char.sectionCollapsed.tracker)
        local nHeader = 0
        for _, group in ipairs(groups) do
            if group.header then
                nHeader = nHeader + 1
                local h = getSectionHeader(nHeader)
                h.sectionID = group.header.id
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                h:SetSection(group.header.name and UI.QuestText(group.header.name) or L["SECTION_NONE"], group.collapsed)
                y = y - SECTION_HEIGHT - 2
            end
            local entry = group.item
            if entry then
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
                title.text:SetPoint("LEFT", ICON_SIZE + 4, 0)
                title.text:SetWidth(width - 30 - PAD - ICON_SIZE - 4)
                title.text:SetText(("|cff%s%s|r%s%s"):format(UI.QUEST_COLOR,
                    UI.QuestText(quest.template.title),
                    stages > 1 and (" (" .. quest.stage .. "/" .. stages .. ")") or "", folded and " [+]" or ""))
                title:ClearAllPoints()
                title:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
                local titleHeight = math.max(title.text:GetStringHeight(), ICON_SIZE)
                title:SetHeight(titleHeight)
                y = y - titleHeight - 1

                for i, obj in ipairs(folded and {} or Objectives.CurrentStage(quest).objectives) do
                    n = n + 1
                    local line = getLine(n)
                    local text, done = UI.ObjectiveLine(quest, i, obj)
                    line:SetText("- " .. text)
                    line:SetPoint("TOPLEFT", content, "TOPLEFT", 8 + PAD, y)
                    if obj.type == "manual" and not done then
                        nPlus = nPlus + 1
                        local b = getPlus(nPlus)
                        b.questID, b.index = entry.id, i
                        b:SetPoint("TOPRIGHT", content, "TOPLEFT", width, y + 1)
                    end
                    y = y - math.max(line:GetStringHeight(), LINE_HEIGHT)
                end
                y = y - 4
            end
        end
    end
    -- The quests sit in a scroll area under the banner. With a height chosen by the
    -- player the frame keeps it (unless the tracker is folded); otherwise it fits them.
    local top = headerHeight + 2
    content:SetHeight(math.max(1, -y))
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -top)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    if userHeight and not collapsed then
        frame:SetHeight(userHeight)
    else
        frame:SetHeight(top + (collapsed and 0 or -y))
    end
    local range = math.max(0, -y - (frame:GetHeight() - top))
    if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
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
