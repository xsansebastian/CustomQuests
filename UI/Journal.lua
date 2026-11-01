local _, ns = ...

local L, Util, UI = ns.L, ns.Util, ns.UI
local Model, Lifecycle, Objectives = ns.Model, ns.Lifecycle, ns.Objectives

local Journal = {}
ns.Journal = Journal

local WIDTH, HEIGHT = 660, 460
local LIST_WIDTH = 230
local ROW_HEIGHT = 38
local DETAIL_WIDTH = WIDTH - LIST_WIDTH - 90

local window, list, detail
local tabButtons = {}
-- main: the last of Active/History shown, so the swap button still has a meaning on Templates.
local state = { tab = "active", main = "active", selected = {} } -- selected[tab] = id

-- The view the swap button leads to: the one of Active/History you are not in.
local function swapTarget()
    return state.main == "active" and "history" or "active"
end

-- List -----------------------------------------------------------------------

local rows = {}

local function getRow(i)
    local row = rows[i]
    if row then row:Show() return row end
    row = CreateFrame("Button", nil, list.content)
    row:SetSize(LIST_WIDTH - 4, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.selectedTex = row:CreateTexture(nil, "BACKGROUND")
    row.selectedTex:SetAllPoints()
    row.selectedTex:SetColorTexture(1, 0.82, 0, 0.15)
    -- Fold button for quests that have follow-ups in a chain.
    row.toggle = CreateFrame("Button", nil, row)
    row.toggle:SetSize(14, 14)
    row.toggle:SetScript("OnClick", function(self)
        local id = self:GetParent().id
        local collapsed = Model.account.chainCollapsed
        collapsed[id] = not collapsed[id] or nil
        -- A fold that hides the selected quest selects the one that stays.
        if collapsed[id] then state.selected.templates = id end
        Journal.Refresh()
    end)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 4, 0)
    row.title = UI.CreateLabel(row, "", "GameFontNormal")
    -- Text is anchored to the row, not the icon, so the two lines keep their distance.
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -5)
    row.title:SetWidth(LIST_WIDTH - 40)
    row.title:SetWordWrap(false)
    row.sub = UI.CreateLabel(row, "", "GameFontHighlightSmall")
    row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 32, 5)
    row.sub:SetWidth(LIST_WIDTH - 40)
    row.sub:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        state.selected[state.tab] = self.id
        Journal.Refresh()
    end)
    rows[i] = row
    return row
end


local function repeatLabel(mode)
    return L["REPEAT_" .. mode:upper()]
end

local function kindLabel(kind)
    return L["KIND_" .. kind:upper()]
end

-- Builds { id, icon, title, sub } entries for the current tab.
local function buildEntries()
    local entries = {}
    if state.tab == "active" then
        for _, e in ipairs(Lifecycle.List()) do
            local q = e.quest
            local sub
            local ready = q.state == "active" and q.ready
            if ready then
                sub = "|cffffd200" .. L["READY_SHORT"] .. "|r"
            elseif q.state == "done" then
                sub = L["RESETS_IN"]:format(UI.FormatDuration((q.resetAt or 0) - ns.api.Now()))
            else
                local stage = Objectives.CurrentStage(q)
                local done = 0
                for i, obj in ipairs(stage.objectives) do
                    if Objectives.IsDone(obj, q.progress[i]) then done = done + 1 end
                end
                sub = L["PROGRESS_SUMMARY"]:format(q.stage, #q.template.stages, done, #stage.objectives)
            end
            entries[#entries + 1] = { id = e.id, kind = UI.QuestKind(q.template, q.templateID),
                iconState = ready and "ready" or (q.state == "done" and "available" or "progress"),
                title = UI.QuestText(q.template.title), sub = sub }
        end
    elseif state.tab == "templates" then
        -- Chains are a tree: the first quest is the chain's title, the rest hang below it.
        for _, node in ipairs(Model.TemplateTree(Model.account.chainCollapsed)) do
            local t = Model.GetTemplate(node.id)
            local sub = kindLabel(t.kind) .. " · " .. repeatLabel(t.repeatMode)
            if node.hasChildren and node.depth == 0 then sub = L["CHAIN_COUNT"]:format(node.count) .. " · " .. sub end
            local ok, err = Lifecycle.CanAccept(node.id)
            if not ok and (err == "ERR_LOCKED" or err == "ERR_LEVEL_LOW" or err == "ERR_LEVEL_HIGH") then
                sub = "|cff808080" .. sub .. " · " .. L["LOCKED_SHORT"] .. "|r"
            elseif err == "ERR_CHAIN_AUTO" then
                sub = "|cff808080" .. sub .. " · " .. L["CHAIN_AUTO_SHORT"] .. "|r"
            end
            entries[#entries + 1] = { id = node.id, kind = UI.QuestKind(t, node.id), iconState = "available",
                title = UI.QuestText(t.title), sub = sub, depth = node.depth, hasChildren = node.hasChildren,
                collapsed = node.collapsed }
        end
    else
        for i, row in ipairs(Lifecycle.GetHistorySummary()) do
            entries[#entries + 1] = { id = i, icon = "Interface\\Icons\\INV_Misc_Book_09",
                title = UI.QuestText(row.title), sub = L["HISTORY_ROW"]:format(row.count, UI.FormatDate(row.last)) }
        end
    end
    return entries
end

local function refreshList(entries)
    for _, row in ipairs(rows) do row:Hide() end
    for i, entry in ipairs(entries) do
        local row = getRow(i)
        row.id = entry.id
        if entry.kind then
            UI.SetQuestIcon(row.icon, entry.kind, entry.iconState)
        else
            row.icon:SetTexture(entry.icon)
            row.icon:SetTexCoord(0, 1, 0, 1)
        end
        -- Indent by depth; the fold button sits in front of quests with follow-ups.
        local indent = (entry.depth or 0) * 14
        row.toggle:ClearAllPoints()
        row.toggle:SetPoint("LEFT", row, "LEFT", 2 + indent, 0)
        row.toggle:SetShown(entry.hasChildren or false)
        if entry.hasChildren then
            row.toggle:SetNormalTexture(entry.collapsed and "Interface\\Buttons\\UI-PlusButton-Up"
                or "Interface\\Buttons\\UI-MinusButton-Up")
        end
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", row, "LEFT", 18 + indent, 0)
        row.title:ClearAllPoints()
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 44 + indent, -5)
        row.title:SetWidth(LIST_WIDTH - 50 - indent)
        row.sub:ClearAllPoints()
        row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 44 + indent, 5)
        row.sub:SetWidth(LIST_WIDTH - 50 - indent)
        row.title:SetText(entry.title)
        row.sub:SetText(entry.sub)
        row.selectedTex:SetShown(entry.id == state.selected[state.tab])
    end
    list.content:SetHeight(math.max(1, #entries * ROW_HEIGHT))
    list.empty:SetShown(#entries == 0)
    list.empty:SetText(L["EMPTY_" .. state.tab:upper()])
end

-- Detail -----------------------------------------------------------------------

local objectiveRows = {}
local OBJECTIVE_ROW_HEIGHT = 18

local function getObjectiveRow(i)
    local r = objectiveRows[i]
    if r then r:Show() return r end
    r = CreateFrame("Frame", nil, detail.content)
    -- One compact line: label with its count, then +/- for manual goals.
    r:SetSize(DETAIL_WIDTH, OBJECTIVE_ROW_HEIGHT)
    r.label = UI.CreateLabel(r, "", "GameFontHighlightSmall")
    r.label:SetPoint("LEFT")
    r.label:SetWordWrap(false)
    r.plus = UI.CreateButton(r, "+", 20)
    r.plus:SetHeight(16)
    r.plus:SetPoint("RIGHT")
    r.minus = UI.CreateButton(r, "-", 20)
    r.minus:SetHeight(16)
    r.minus:SetPoint("RIGHT", r.plus, "LEFT", -2, 0)
    local function adjust(self, delta)
        local quest = Lifecycle.Get(state.selected.active)
        if quest then ns.ApplyChange(Objectives.AdjustManual(quest, self:GetParent().index, delta)) end
    end
    r.minus:SetScript("OnClick", function(self) adjust(self, -1) end)
    r.plus:SetScript("OnClick", function(self) adjust(self, 1) end)
    objectiveRows[i] = r
    return r
end

local function bodyText(template, stageIndex)
    local parts = {}
    if template.giver and template.giver ~= "" then
        parts[#parts + 1] = L["GIVER"]:format(UI.QuestText(template.giver))
    end
    if template.description and template.description ~= "" then
        parts[#parts + 1] = UI.QuestText(template.description)
    end
    local stage = stageIndex and template.stages[stageIndex]
    if stage and stage.text and stage.text ~= "" then
        parts[#parts + 1] = "|cff" .. UI.QUEST_COLOR .. UI.QuestText(stage.text) .. "|r"
    end
    if template.rewardText and template.rewardText ~= "" then
        parts[#parts + 1] = L["REWARD"]:format(UI.QuestText(template.rewardText))
    end
    return table.concat(parts, "\n\n")
end

local function setButtons(specs)
    for _, b in ipairs(detail.buttons) do b:Hide() end
    local prev
    for i, spec in ipairs(specs) do
        local b = detail.buttons[i]
        if not b then
            b = UI.CreateButton(detail.frame, "", 86)
            detail.buttons[i] = b
        end
        b:ClearAllPoints()
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("BOTTOMLEFT", detail.frame, "BOTTOMLEFT", 0, 0) end
        b:SetText(spec[1])
        b:SetEnabled(spec[3] ~= false)
        b:SetScript("OnClick", spec[2])
        b:Show()
        prev = b
    end
end

-- Lays out title, meta, an optional widget and the body; returns the y after them.
local function layoutDetail(title, meta, body, widget)
    detail.title:SetText(title)
    detail.meta:SetText(meta)
    detail.body:SetText(body)
    local y = -(detail.title:GetStringHeight() + detail.meta:GetStringHeight() + 10)
    if widget then
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", 0, y)
        widget:Show()
        y = y - widget:GetHeight() - 8
    end
    detail.body:SetPoint("TOPLEFT", 0, y)
    if body ~= "" then y = y - detail.body:GetStringHeight() - 12 end
    return y
end

-- The quest's icon in front of the detail title (a turn-in button when ready);
-- the title and the line under it move right to make room.
local function showTitleIcon(kind, iconState, questID, ready)
    UI.SetQuestIcon(detail.turnin.tex, kind, iconState)
    detail.turnin.questID, detail.turnin.ready = questID, ready
    detail.turnin:Show()
    detail.title:ClearAllPoints()
    detail.title:SetPoint("TOPLEFT", 28, 0)
    detail.title:SetWidth(DETAIL_WIDTH - 28)
    detail.meta:ClearAllPoints()
    detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", -28, -4)
end

local function showActive(id)
    local quest = Lifecycle.Get(id)
    local template = quest.template
    local meta = kindLabel(template.kind) .. " · " .. repeatLabel(template.repeatMode)
    if #template.stages > 1 then meta = meta .. " · " .. L["STAGE_N"]:format(quest.stage, #template.stages) end
    if quest.state == "done" then
        meta = meta .. "\n" .. L["RESETS_IN"]:format(UI.FormatDuration((quest.resetAt or 0) - ns.api.Now()))
    end
    local active = quest.state == "active"
    local ready = active and quest.ready
    showTitleIcon(UI.QuestKind(template, quest.templateID),
        ready and "ready" or (active and "progress" or "available"), id, ready)
    local y = layoutDetail("|cff" .. UI.QUEST_COLOR .. UI.QuestText(template.title) .. "|r",
        meta, bodyText(template, quest.stage))

    if quest.state == "active" then
        for i, obj in ipairs(Objectives.CurrentStage(quest).objectives) do
            local r = getObjectiveRow(i)
            r.index = i
            r:SetPoint("TOPLEFT", 0, y)
            r.label:SetText("- " .. UI.ObjectiveLine(quest, i, obj))
            local manual = obj.type == "manual"
            r.minus:SetShown(manual)
            r.plus:SetShown(manual)
            r.label:SetWidth(DETAIL_WIDTH - (manual and 48 or 0))
            y = y - OBJECTIVE_ROW_HEIGHT
        end
    end
    detail.content:SetHeight(-y)

    local tracked = Model.char.tracked[id]
    local buttons = {
        { tracked and L["UNTRACK"] or L["TRACK"], function() Lifecycle.SetTracked(id, not tracked) end },
        { L["ABANDON"], function()
            ns.Dialogs.Confirm(L["CONFIRM_ABANDON"]:format(UI.QuestText(template.title)), function()
                Lifecycle.Abandon(id)
            end)
        end },
    }
    if ready then table.insert(buttons, 1, { L["TURNIN_COMPLETE_SHORT"], function() ns.TurnIn.Open(id) end }) end
    setButtons(buttons)
end

local function showTemplate(id)
    local template = Model.GetTemplate(id)
    local count, last = Lifecycle.GetStats(id)
    local meta = kindLabel(template.kind) .. " · " .. repeatLabel(template.repeatMode)
        .. "\n" .. L["STATS"]:format(count, UI.FormatDate(last))
    local requirements = UI.TemplateRequirements(template, id)
    if requirements ~= "" then meta = meta .. "\n" .. requirements end

    -- Every stage with its objectives, as plain lines.
    local lines = { bodyText(template) }
    for s, stage in ipairs(template.stages) do
        local stageTitle = L["STAGE_N"]:format(s, #template.stages)
        if stage.text and stage.text ~= "" then stageTitle = stageTitle .. ": " .. UI.QuestText(stage.text) end
        lines[#lines + 1] = "|cff" .. UI.QUEST_COLOR .. stageTitle .. "|r"
        for _, obj in ipairs(stage.objectives) do
            local goal = Objectives.Goal(obj)
            lines[#lines + 1] = "  - " .. UI.ObjectiveLabel(obj) .. (goal > 1 and (" x" .. goal) or "")
        end
    end
    showTitleIcon(UI.QuestKind(template, id), "available", id, false)
    local y = layoutDetail("|cff" .. UI.QUEST_COLOR .. UI.QuestText(template.title) .. "|r",
        meta, table.concat(lines, "\n"), detail.followUp)
    detail.content:SetHeight(-y)
    detail.followUp:SetScript("OnClick", function() ns.Editor.Open(nil, id) end)

    local _, acceptErr = Lifecycle.CanAccept(id)
    setButtons({
        { L["ACCEPT"], function()
            local _, err, arg = Lifecycle.Accept(id)
            if err then ns.api.Print(UI.ErrorText(err, arg)) return end
            ns.RefreshAll(true)
            state.tab = "active"
            state.selected.active = Lifecycle.FindByTemplate(id)
            Journal.Refresh()
        end, acceptErr ~= "ERR_CHAIN_AUTO" },
        { L["EDIT"], function() ns.Editor.Open(id) end },
        { L["EXPORT"], function() ns.Dialogs.ShowExport(id) end },
        { DELETE, function()
            ns.Dialogs.Confirm(L["CONFIRM_DELETE"]:format(UI.QuestText(template.title)), function()
                Model.DeleteTemplate(id)
                state.selected.templates = nil
                Journal.Refresh()
            end)
        end },
    })
end

local function showHistory(index)
    local row = Lifecycle.GetHistorySummary()[index]
    local y = layoutDetail("|cff" .. UI.QUEST_COLOR .. UI.QuestText(row.title) .. "|r",
        L["HISTORY_ROW"]:format(row.count, UI.FormatDate(row.last)), "")
    detail.content:SetHeight(-y)
    setButtons({})
end

local function refreshDetail(entries)
    detail.followUp:Hide()
    for _, r in ipairs(objectiveRows) do r:Hide() end
    detail.turnin:Hide()
    detail.title:ClearAllPoints()
    detail.title:SetPoint("TOPLEFT")
    detail.title:SetWidth(DETAIL_WIDTH)
    detail.meta:ClearAllPoints()
    detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -4)
    local selected = state.selected[state.tab]
    local exists = false
    for _, e in ipairs(entries) do if e.id == selected then exists = true end end
    if not exists then
        selected = entries[1] and entries[1].id
        state.selected[state.tab] = selected
    end
    detail.frame:SetShown(selected ~= nil)
    if not selected then return end
    if state.tab == "active" then showActive(selected)
    elseif state.tab == "templates" then showTemplate(selected)
    else showHistory(selected) end
end

-- Window -----------------------------------------------------------------------

local function createScroll(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end

local function create()
    window = UI.CreateWindow("CustomQuestsJournal", WIDTH, HEIGHT, "CustomQuests")

    -- Two buttons: Templates, and a swap between Active and History that always
    -- offers the view you are not in.
    local templates = UI.CreateButton(window, L["TAB_TEMPLATES"], 100, function()
        state.tab = "templates"
        Journal.Refresh()
    end)
    templates:SetPoint("TOPRIGHT", -14, -30)
    tabButtons.templates = templates

    tabButtons.swap = UI.CreateButton(window, "", 100, function()
        -- On Templates this is "Back": return to the Active/History view you came from.
        state.tab = state.tab == "templates" and state.main or swapTarget()
        Journal.Refresh()
    end)
    tabButtons.swap:SetPoint("TOPLEFT", 14, -30)

    -- New and Import only make sense on the Templates view, where its own button is hidden.
    local newButton = UI.CreateButton(window, L["NEW"], 90, function() ns.Editor.Open(nil) end)
    newButton:SetPoint("TOPRIGHT", -14, -30)
    local importButton = UI.CreateButton(window, L["IMPORT"], 90, function()
        ns.Dialogs.ShowImport(function(id)
            state.tab = "templates"
            state.selected.templates = id
            Journal.Refresh()
        end)
    end)
    importButton:SetPoint("RIGHT", newButton, "LEFT", -4, 0)
    tabButtons.templateActions = { newButton, importButton }

    list = {}
    list.scroll, list.content = createScroll(window, LIST_WIDTH - 4)
    list.scroll:SetPoint("TOPLEFT", 12, -60)
    list.scroll:SetSize(LIST_WIDTH - 4, HEIGHT - 76)
    list.empty = UI.CreateLabel(window, "", "GameFontDisableSmall")
    list.empty:SetPoint("TOPLEFT", list.scroll, "TOPLEFT", 4, -4)
    list.empty:SetWidth(LIST_WIDTH - 20)

    local divider = window:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetSize(1, HEIGHT - 76)
    divider:SetPoint("TOPLEFT", LIST_WIDTH + 30, -60)

    detail = { buttons = {} }
    detail.frame = CreateFrame("Frame", nil, window)
    detail.frame:SetPoint("TOPLEFT", LIST_WIDTH + 42, -60)
    detail.frame:SetPoint("BOTTOMRIGHT", -14, 14)
    detail.scroll, detail.content = createScroll(detail.frame, DETAIL_WIDTH)
    detail.scroll:SetPoint("TOPLEFT")
    detail.scroll:SetPoint("BOTTOMRIGHT", -24, 30)
    detail.title = UI.CreateLabel(detail.content, "", "GameFontNormalLarge")
    detail.title:SetPoint("TOPLEFT")
    detail.title:SetWidth(DETAIL_WIDTH)
    -- Yellow "?" next to the title of a quest that is ready: opens the turn-in window.
    detail.turnin = CreateFrame("Button", nil, detail.content)
    detail.turnin:SetSize(22, 22)
    detail.turnin:SetPoint("TOPLEFT", 0, 0)
    detail.turnin.tex = detail.turnin:CreateTexture(nil, "ARTWORK")
    detail.turnin.tex:SetAllPoints()
    detail.turnin:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    detail.turnin:SetScript("OnClick", function(self) if self.ready then ns.TurnIn.Open(self.questID) end end)
    detail.turnin:SetScript("OnEnter", function(self)
        if not self.ready then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["TURNIN_TITLE"])
        GameTooltip:AddLine(L["TURNIN_HELP"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    detail.turnin:SetScript("OnLeave", GameTooltip_Hide)
    detail.turnin:Hide()
    detail.meta = UI.CreateLabel(detail.content, "", "GameFontHighlightSmall")
    detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -4)
    detail.meta:SetWidth(DETAIL_WIDTH)
    detail.followUp = UI.CreateButton(detail.content, L["ADD_FOLLOW_UP"], 190)
    detail.followUp:Hide()
    detail.body = UI.CreateLabel(detail.content, "", "GameFontHighlight")
    detail.body:SetWidth(DETAIL_WIDTH)
    detail.body:SetSpacing(2)

    window:SetScript("OnShow", Journal.Refresh)
    Util.On("QUESTS_CHANGED", function() if window:IsShown() then Journal.Refresh() end end)
end

function Journal.Refresh()
    if not window then return end
    local onTemplates = state.tab == "templates"
    if not onTemplates then state.main = state.tab end
    tabButtons.templates:SetShown(not onTemplates)
    tabButtons.swap:SetText(onTemplates and L["BACK"] or L["TAB_" .. swapTarget():upper()])
    for _, b in ipairs(tabButtons.templateActions) do b:SetShown(onTemplates) end
    window.TitleText:SetText("CustomQuests · " .. L["TAB_" .. state.tab:upper()])
    local entries = buildEntries()
    refreshList(entries)
    refreshDetail(entries)
end

function Journal.ShowTemplate(id)
    state.tab = "templates"
    state.selected.templates = id
    -- Unfold the chain so the quest is visible in the tree.
    local step, ancestor = 0, Model.GetTemplate(id)
    while ancestor and ancestor.requires and step < 30 do
        Model.account.chainCollapsed[ancestor.requires] = nil
        ancestor = Model.GetTemplate(ancestor.requires)
        step = step + 1
    end
    if window and window:IsShown() then Journal.Refresh() else Journal.Toggle() end
end

function Journal.Toggle()
    if not window then create() end
    window:SetShown(not window:IsShown())
end
