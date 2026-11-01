local _, ns = ...

local L, Util, UI = ns.L, ns.Util, ns.UI
local Model, Lifecycle, Objectives = ns.Model, ns.Lifecycle, ns.Objectives

local Journal = {}
ns.Journal = Journal

local WIDTH, HEIGHT = 660, 460
local LIST_DEFAULT, MIN_LIST = 230, 170
local listPref = LIST_DEFAULT -- the width the player chose for the tree panel
local listWidth = LIST_DEFAULT -- listPref, kept inside what the window allows
local ROW_HEIGHT = 38
local HEADER_HEIGHT = 24 -- section header bar
local MIN_SIZE, MAX_SIZE = { 560, 380 }, { 1100, 900 }
local detailWidth = WIDTH - listWidth - 90 -- follows the window width
local META_GAP = 10 -- space between the detail title and the line under it

local window, list, detail
local tabButtons = {}
-- main: the last of Active/History shown, so the swap button still has a meaning on Templates.
local state = { tab = "active", main = "active", selected = {}, checked = {}, search = "" } -- selected[tab] = id; checked[id] = true
local CHECK_WIDTH = 20 -- room the Templates checkbox takes in front of each row

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
    row:SetSize(listWidth - 4, ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.selectedTex = row:CreateTexture(nil, "BACKGROUND")
    row.selectedTex:SetAllPoints()
    row.selectedTex:SetColorTexture(1, 0.82, 0, 0.15)
    -- Checkbox to pick templates for a multiple delete (Templates only).
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(18, 18)
    row.check:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.check:SetScript("OnClick", function(self)
        state.checked[self:GetParent().id] = self:GetChecked() or nil
        Journal.UpdateDeleteButton()
    end)
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
    row.title:SetWidth(listWidth - 40)
    row.title:SetWordWrap(false)
    row.sub = UI.CreateLabel(row, "", "GameFontHighlightSmall")
    row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 32, 5)
    row.sub:SetWidth(listWidth - 40)
    row.sub:SetWordWrap(false)
    -- Right-click on a template (Templates) or an active quest (Active): its
    -- menu (share, export...). Shift-click puts a link to it in the open chat box.
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            if state.tab == "templates" then
                Journal.TemplateMenu(self, self.id)
                return
            elseif state.tab == "active" then
                Journal.ActiveMenu(self, self.id)
                return
            end
        end
        if IsShiftKeyDown() then
            local templateID = state.tab == "templates" and self.id
                or state.tab == "active" and Journal.ActiveTemplateID(self.id)
            if templateID then
                ns.Dialogs.LinkInChat("quest", templateID)
                return
            end
        end
        state.selected[state.tab] = self.id
        Journal.Refresh()
    end)
    rows[i] = row
    return row
end

-- Section headers: their own pool, since they are shorter than the quest rows.
local headers = {}

local function sectionStore()
    return state.tab == "templates" and Model.account.sectionCollapsed or Model.char.sectionCollapsed.log
end

local function getHeader(i)
    local header = headers[i]
    if header then header:Show() return header end
    header = UI.CreateSectionHeader(list.content, HEADER_HEIGHT)
    header.onClick = function(mouse)
        if mouse == "RightButton" and state.tab == "templates" and header.sectionID ~= Model.NO_SECTION then
            Journal.SectionMenu(header, header.sectionID)
            return
        end
        local store = sectionStore()
        store[header.sectionID] = not store[header.sectionID] or nil
        Journal.Refresh()
    end
    headers[i] = header
    return header
end

local function sectionName(header)
    return header.name and UI.QuestText(header.name) or L["SECTION_NONE"]
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
            -- The live template decides the section; the copy is only a fallback.
            local live = Model.GetTemplate(q.templateID) or q.template
            entries[#entries + 1] = { id = e.id, kind = UI.QuestKind(q.template, q.templateID),
                iconState = ready and "ready" or (q.state == "done" and "available" or "progress"),
                title = UI.QuestText(q.template.title), sub = sub, section = Model.SectionOf(live) }
        end
        local grouped = {}
        for _, g in ipairs(Model.GroupBySection(entries, function(entry) return entry.section end,
                Model.char.sectionCollapsed.log)) do
            grouped[#grouped + 1] = g.item or { header = g.header, collapsed = g.collapsed, count = g.count }
        end
        entries = grouped
    elseif state.tab == "templates" then
        -- Chains are a tree: the first quest is the chain's title, the rest hang below it.
        -- While searching, folded sections and chains stay open so no match is hidden.
        local searching = state.search:find("%S") ~= nil
        local filter = searching and function(id)
            return Model.MatchesSearch(Model.account.templates[id], state.search)
        end or nil
        local sectionFolds = searching and {} or Model.account.sectionCollapsed
        local chainFolds = searching and {} or Model.account.chainCollapsed
        for _, g in ipairs(Model.SectionedTree(sectionFolds, chainFolds, filter)) do
            if g.header then
                entries[#entries + 1] = { header = g.header, collapsed = g.collapsed, count = g.count }
            else
                local node = g.row
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
    for _, header in ipairs(headers) do header:Hide() end
    local nRow, nHeader, y = 0, 0, 0
    for _, entry in ipairs(entries) do
        if entry.header then
            nHeader = nHeader + 1
            local header = getHeader(nHeader)
            header.sectionID = entry.header.id
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -y)
            header:SetPoint("TOPRIGHT", list.content, "TOPRIGHT", 0, -y)
            header:SetSection(("%s (%d)"):format(sectionName(entry.header), entry.count), entry.collapsed)
            y = y + HEADER_HEIGHT + 2
        else
            nRow = nRow + 1
            local row = getRow(nRow)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -y)
            y = y + ROW_HEIGHT
            row.id = entry.id
            if entry.kind then
                UI.SetQuestIcon(row.icon, entry.kind, entry.iconState)
            else
                row.icon:SetTexture(entry.icon)
                row.icon:SetTexCoord(0, 1, 0, 1)
            end
            -- Indent by depth; the fold button sits in front of quests with follow-ups.
            -- On Templates the checkbox comes first and pushes everything right.
            local picking = state.tab == "templates" and state.editing
            row.check:SetShown(picking)
            row.check:SetChecked(picking and state.checked[entry.id] or false)
            local indent = (entry.depth or 0) * 14 + (picking and CHECK_WIDTH or 0)
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
            row.title:SetWidth(listWidth - 50 - indent)
            row.sub:ClearAllPoints()
            row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 44 + indent, 5)
            row.sub:SetWidth(listWidth - 50 - indent)
            row.title:SetText(entry.title)
            row.sub:SetText(entry.sub)
            row.selectedTex:SetShown(entry.id == state.selected[state.tab])
        end
    end
    list.content:SetHeight(math.max(1, y))
    list.empty:SetShown(#entries == 0)
    local searching = state.tab == "templates" and state.search:find("%S") ~= nil
    list.empty:SetText(searching and L["EMPTY_SEARCH"] or L["EMPTY_" .. state.tab:upper()])
end

-- Moves the ticked templates into a section (nil: out of any section).
local function moveChecked(sectionID)
    local ids = {}
    for id in pairs(state.checked) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids > 0 then
        Model.SetSection(ids, sectionID)
        if sectionID then Model.account.sectionCollapsed[sectionID] = nil end
        state.checked = {}
        ns.RefreshAll(true)
    end
    Journal.Refresh()
end

-- The "Move to" menu under the list while editing.
local function buildMoveMenu(_, root)
    root:CreateButton(L["SECTION_NO_SECTION"], function() moveChecked(nil) end)
    for _, section in ipairs(Model.ListSections()) do
        root:CreateButton(UI.QuestText(section.name), function() moveChecked(section.id) end)
    end
    root:CreateDivider()
    root:CreateButton(L["SECTION_NEW"], function()
        ns.Dialogs.NewSection(function(id) moveChecked(id) end)
    end)
end

-- Right-click on a section header in Templates.
function Journal.SectionMenu(owner, sectionID)
    local section = Model.SectionByID(sectionID)
    if not (section and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local function changed()
        ns.RefreshAll(true)
        Journal.Refresh()
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(UI.QuestText(section.name))
        root:CreateButton(L["SECTION_RENAME"], function() ns.Dialogs.RenameSection(sectionID, changed) end)
        root:CreateButton(L["SECTION_MOVE_UP"], function() if Model.MoveSection(sectionID, -1) then changed() end end)
        root:CreateButton(L["SECTION_MOVE_DOWN"], function() if Model.MoveSection(sectionID, 1) then changed() end end)
        root:CreateButton(L["SECTION_EXPORT"], function() ns.Dialogs.ShowSectionExport(sectionID) end)
        ns.Dialogs.AddShareMenu(root, "section", sectionID)
        root:CreateDivider()
        root:CreateButton(L["SECTION_DELETE"], function() ns.Dialogs.ConfirmDeleteSection(sectionID, changed) end)
    end)
end

-- Right-click on a template row in Templates.
function Journal.TemplateMenu(owner, templateID)
    local template = Model.GetTemplate(templateID)
    if not (template and MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(UI.QuestText(template.title))
        ns.Dialogs.AddShareMenu(root, "quest", templateID)
        root:CreateButton(L["EXPORT"], function() ns.Dialogs.ShowExport(templateID) end)
        root:CreateButton(L["EDIT"], function() ns.Editor.Open(templateID) end)
    end)
end

-- The template an active quest came from, when it still exists, or nil.
function Journal.ActiveTemplateID(questID)
    local quest = questID and Lifecycle.Get(questID)
    return quest and Model.GetTemplate(quest.templateID) and quest.templateID or nil
end

-- Right-click on a row in Active: share the quest it came from.
function Journal.ActiveMenu(owner, questID)
    local templateID = Journal.ActiveTemplateID(questID)
    if not (templateID and MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(UI.QuestText(Model.GetTemplate(templateID).title))
        ns.Dialogs.AddShareMenu(root, "quest", templateID)
    end)
end

-- The template selected in the journal (on Active: the template of the
-- selected quest, when it still exists), or nil. Used by /cq share.
function Journal.SelectedTemplate()
    if state.tab == "active" then
        return Journal.ActiveTemplateID(state.selected.active)
    end
    local id = state.selected.templates
    return id and Model.GetTemplate(id) and id or nil
end

-- Detail -----------------------------------------------------------------------

local objectiveRows = {}
local OBJECTIVE_ROW_HEIGHT = 18

local function getObjectiveRow(i)
    local r = objectiveRows[i]
    if r then r:Show() return r end
    r = CreateFrame("Frame", nil, detail.content)
    -- One compact line: label with its count, then +/- for manual goals.
    r:SetSize(detailWidth, OBJECTIVE_ROW_HEIGHT)
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

local BUTTON_WIDTH, BUTTON_GAP, BUTTON_ROW = 86, 6, 28
local buttonCount = 0

-- Lays the detail buttons out along the bottom, wrapping onto more rows when the
-- detail panel is too narrow for them all, and keeps the text above them.
local function layoutButtons()
    local perRow = math.max(1, math.floor((detailWidth + BUTTON_GAP) / (BUTTON_WIDTH + BUTTON_GAP)))
    local rowCount = math.max(1, math.ceil(buttonCount / perRow))
    for i = 1, buttonCount do
        local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
        detail.buttons[i]:ClearAllPoints()
        detail.buttons[i]:SetPoint("BOTTOMLEFT", detail.frame, "BOTTOMLEFT",
            col * (BUTTON_WIDTH + BUTTON_GAP), (rowCount - 1 - row) * BUTTON_ROW)
    end
    detail.scroll:SetPoint("BOTTOMRIGHT", -24, 30 + (rowCount - 1) * BUTTON_ROW)
end

local function setButtons(specs)
    for _, b in ipairs(detail.buttons) do b:Hide() end
    buttonCount = #specs
    for i, spec in ipairs(specs) do
        local b = detail.buttons[i]
        if not b then
            b = UI.CreateButton(detail.frame, "", BUTTON_WIDTH)
            detail.buttons[i] = b
        end
        b:SetText(spec[1])
        b:SetEnabled(spec[3] ~= false)
        b:SetScript("OnClick", spec[2])
        b:Show()
    end
    layoutButtons()
end

-- Lays out title, meta, an optional widget and the body; returns the y after them.
local function layoutDetail(title, meta, body, widget)
    detail.title:SetText(title)
    detail.meta:SetText(meta)
    detail.body:SetText(body)
    local y = -(detail.title:GetStringHeight() + detail.meta:GetStringHeight() + META_GAP + 6)
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
    detail.title:SetWidth(detailWidth - 28)
    detail.meta:ClearAllPoints()
    detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", -28, -META_GAP)
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
            r:SetWidth(detailWidth)
            r.label:SetText("- " .. UI.ObjectiveLine(quest, i, obj))
            local manual = obj.type == "manual"
            r.minus:SetShown(manual)
            r.plus:SetShown(manual)
            r.label:SetWidth(detailWidth - (manual and 48 or 0))
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
        { DELETE, function() ns.Dialogs.ConfirmDelete({ id }, Journal.AfterDelete) end },
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
    detail.title:SetWidth(detailWidth)
    detail.meta:ClearAllPoints()
    detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -META_GAP)
    local selected = state.selected[state.tab]
    local exists, first = false, nil
    for _, e in ipairs(entries) do
        if not e.header then
            first = first or e.id
            if e.id == selected then exists = true end
        end
    end
    if not exists then
        selected = first
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
    local savedList = tonumber(Model.account.windowSizes.journalList)
    if savedList then listPref = math.max(MIN_LIST, savedList) end
    listWidth = listPref

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
    local sectionButton = UI.CreateButton(window, L["SECTION_ADD"], 110, function()
        ns.Dialogs.NewSection(function() Journal.Refresh() end)
    end)
    sectionButton:SetPoint("RIGHT", importButton, "LEFT", -4, 0)
    -- Under the tree: "Edit list" turns on the checkboxes; then "Delete (N)" removes
    -- the ticked templates and "Done" turns them off again.
    local editButton = UI.CreateButton(window, L["LIST_EDIT"], listWidth - 10, function()
        state.editing = not state.editing
        state.checked = {}
        Journal.Refresh()
    end)
    editButton:SetPoint("BOTTOMRIGHT", window, "BOTTOMLEFT", listWidth + 4, 12)
    tabButtons.edit = editButton
    local deleteButton = UI.CreateButton(window, DELETE, listWidth - 114, function()
        local ids = {}
        for id in pairs(state.checked) do ids[#ids + 1] = id end
        if #ids == 0 then return end
        table.sort(ids)
        ns.Dialogs.ConfirmDelete(ids, Journal.AfterDelete)
    end)
    deleteButton:SetPoint("BOTTOMLEFT", 14, 12)
    tabButtons.delete = deleteButton
    -- While editing, a menu above them moves the ticked templates between sections.
    local moveButton = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
    moveButton:SetWidth(listWidth - 10)
    moveButton:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 14, 38)
    moveButton:SetDefaultText(L["MOVE_TO"])
    moveButton:SetupMenu(buildMoveMenu)
    tabButtons.move = moveButton
    tabButtons.templateActions = { newButton, importButton, sectionButton, editButton }

    -- Filters the Templates list as you type.
    local search = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
    search:SetSize(listWidth - 12, 20)
    search:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -62)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search:HookScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if text == state.search then return end
        state.search = text
        Journal.Refresh()
    end)
    tabButtons.search = search

    list = {}
    list.scroll, list.content = createScroll(window, listWidth - 4)
    list.scroll:SetPoint("TOPLEFT", 12, -60)
    list.scroll:SetWidth(listWidth - 4)
    list.empty = UI.CreateLabel(window, "", "GameFontDisableSmall")
    list.empty:SetPoint("TOPLEFT", list.scroll, "TOPLEFT", 4, -4)
    list.empty:SetWidth(listWidth - 20)

    local divider = window:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", listWidth + 30, -60)
    divider:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", listWidth + 30, 16)

    local splitter = CreateFrame("Button", nil, window)
    splitter:SetWidth(8)
    splitter:SetFrameLevel(window:GetFrameLevel() + 10)
    local splitterGlow = splitter:CreateTexture(nil, "HIGHLIGHT")
    splitterGlow:SetColorTexture(1, 0.82, 0, 0.35)
    splitterGlow:SetWidth(2)
    splitterGlow:SetPoint("TOP")
    splitterGlow:SetPoint("BOTTOM")

    detail = { buttons = {} }
    detail.frame = CreateFrame("Frame", nil, window)
    detail.frame:SetPoint("TOPLEFT", listWidth + 42, -60)
    detail.frame:SetPoint("BOTTOMRIGHT", -14, 14)
    detail.scroll, detail.content = createScroll(detail.frame, detailWidth)
    detail.scroll:SetPoint("TOPLEFT")
    detail.scroll:SetPoint("BOTTOMRIGHT", -24, 30)
    detail.title = UI.CreateLabel(detail.content, "", "GameFontNormalLarge")
    detail.title:SetPoint("TOPLEFT")
    detail.title:SetWidth(detailWidth)
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
    detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -META_GAP)
    detail.meta:SetWidth(detailWidth)
    detail.followUp = UI.CreateButton(detail.content, L["ADD_FOLLOW_UP"], 190)
    detail.followUp:Hide()
    detail.body = UI.CreateLabel(detail.content, "", "GameFontHighlight")
    detail.body:SetWidth(detailWidth)
    detail.body:SetSpacing(2)

    window:SetScript("OnShow", Journal.Refresh)
    -- Fits everything that depends on the tree panel's width: the panel itself,
    -- the divider, the detail beside it and the buttons under the tree.
    local function relayout(windowWidth)
        listWidth = math.min(listPref, math.max(MIN_LIST, windowWidth - 300))
        list.content:SetWidth(listWidth - 4)
        list.scroll:SetWidth(listWidth - 4)
        list.empty:SetWidth(listWidth - 20)
        tabButtons.search:SetWidth(listWidth - 12)
        for _, row in ipairs(rows) do row:SetWidth(listWidth - 4) end
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", listWidth + 30, -60)
        divider:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", listWidth + 30, 16)
        splitter:ClearAllPoints()
        splitter:SetPoint("TOPLEFT", listWidth + 26, -60)
        splitter:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", listWidth + 26, 16)
        detail.frame:ClearAllPoints()
        detail.frame:SetPoint("TOPLEFT", listWidth + 42, -60)
        detail.frame:SetPoint("BOTTOMRIGHT", -14, 14)
        tabButtons.edit:ClearAllPoints()
        tabButtons.edit:SetPoint("BOTTOMRIGHT", window, "BOTTOMLEFT", listWidth + 4, 12)
        tabButtons.delete:SetWidth(listWidth - 114)
        tabButtons.move:SetWidth(listWidth - 10)
        detailWidth = windowWidth - listWidth - 90
        detail.content:SetWidth(detailWidth)
        detail.meta:SetWidth(detailWidth)
        detail.body:SetWidth(detailWidth)
        layoutButtons()
    end

    -- Drag the divider to change how wide the tree panel is.
    splitter:SetScript("OnMouseDown", function(self)
        self:SetScript("OnUpdate", function()
            local x = GetCursorPosition() / window:GetEffectiveScale() - window:GetLeft()
            listPref = math.max(MIN_LIST, math.min(x - 30, window:GetWidth() - 300))
            relayout(window:GetWidth())
            Journal.Refresh()
        end)
    end)
    splitter:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        Model.account.windowSizes.journalList = math.floor(listPref + 0.5)
    end)

    -- The tree keeps the width you gave it; the detail takes whatever the window gains.
    UI.MakeResizable(window, MIN_SIZE[1], MIN_SIZE[2], MAX_SIZE[1], MAX_SIZE[2], function(w)
        relayout(w)
        if window:IsShown() then Journal.Refresh() end
    end)
    Util.On("QUESTS_CHANGED", function() if window:IsShown() then Journal.Refresh() end end)
end

-- "Delete (N)" counts the ticked templates and is off when there are none.
function Journal.UpdateDeleteButton()
    local count = 0
    for _ in pairs(state.checked) do count = count + 1 end
    tabButtons.delete:SetText(count > 0 and (DELETE .. " (" .. count .. ")") or DELETE)
    tabButtons.delete:SetEnabled(count > 0)
end

-- Runs once templates are deleted: nothing stays ticked or selected.
function Journal.AfterDelete()
    state.checked = {}
    state.selected.templates = nil
    Journal.Refresh()
end

function Journal.Refresh()
    if not window then return end
    local onTemplates = state.tab == "templates"
    if not onTemplates then
        state.main = state.tab
        state.checked = {}
        state.editing = false
    end
    -- Ticks of templates that no longer exist (deleted elsewhere) are dropped.
    for id in pairs(state.checked) do
        if not Model.GetTemplate(id) then state.checked[id] = nil end
    end
    Journal.UpdateDeleteButton()
    tabButtons.templates:SetShown(not onTemplates)
    tabButtons.swap:SetText(onTemplates and L["BACK"] or L["TAB_" .. swapTarget():upper()])
    for _, b in ipairs(tabButtons.templateActions) do b:SetShown(onTemplates) end
    -- While editing, Delete takes the left of the row and Edit shrinks to "Done".
    local editing = onTemplates and state.editing
    tabButtons.delete:SetShown(editing)
    tabButtons.move:SetShown(editing)
    tabButtons.edit:SetText(editing and DONE or L["LIST_EDIT"])
    tabButtons.edit:SetWidth(editing and 100 or listWidth - 10)
    -- On Templates the tree stops higher, to leave room for the buttons under it.
    list.scroll:ClearAllPoints()
    tabButtons.search:SetShown(onTemplates)
    list.scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 12, onTemplates and -88 or -60)
    list.scroll:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 12, onTemplates and (editing and 70 or 46) or 16)
    window.TitleText:SetText("CustomQuests · " .. L["TAB_" .. state.tab:upper()])
    local entries = buildEntries()
    refreshList(entries)
    refreshDetail(entries)
end

function Journal.ShowTemplate(id)
    state.tab = "templates"
    state.selected.templates = id
    -- Unfold its section and the chain so the quest is visible in the tree.
    local section = Model.SectionOf(Model.GetTemplate(id))
    if section then Model.account.sectionCollapsed[section] = nil end
    local step, ancestor = 0, Model.GetTemplate(id)
    while ancestor and ancestor.requires and step < 30 do
        Model.account.chainCollapsed[ancestor.requires] = nil
        ancestor = Model.GetTemplate(ancestor.requires)
        step = step + 1
    end
    if window and window:IsShown() then Journal.Refresh() else Journal.Toggle() end
end

-- Opens the Journal on an active quest (used by the tracker's left click).
function Journal.ShowQuest(id)
    local quest = Lifecycle.Get(id)
    if not quest then return end
    state.tab = "active"
    state.selected.active = id
    -- Unfold its section so the quest is visible in the list.
    local section = Model.SectionOf(Model.GetTemplate(quest.templateID) or quest.template)
    if section then Model.char.sectionCollapsed.log[section] = nil end
    if window and window:IsShown() then Journal.Refresh() else Journal.Toggle() end
end

function Journal.Toggle()
    if not window then create() end
    window:SetShown(not window:IsShown())
end
