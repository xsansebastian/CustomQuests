local _, ns = ...

local L, Util, UI = ns.L, ns.Util, ns.UI
local Model = ns.Model

local Editor = {}
ns.Editor = Editor

-- Three tabs: general settings, texts, and stages with their objectives.
local WIDTH, HEIGHT = 620, 540 -- also the smallest size the window can take
local MAX_SIZE = { 1100, 900 }
local ROW_HEIGHT = 34
local MAX_FIELDS = 4
local TABS = { "general", "texts", "objectives" }

local window, fields, stageLabel, stageText, errorText
local panels, tabButtons = {}, {}
local objectiveRows = {}
local draft, draftID, stageIndex
local innerWidth = WIDTH - 40 -- width of what fills a panel; follows the window
local textAreas = {} -- the Texts tab boxes that stretch with the window

-- Field specs per objective type. kind: "number" | "string" | "item";
-- scale converts stored 0..1 values to the percentages shown to the user.
local FIELD_SPECS = {
    item = { { "itemID", "F_ITEM", 120, "item" }, { "count", "F_COUNT", 50, "number" } },
    kill = { { "npcID", "F_NPC", 60, "number" }, { "name", "F_NAME", 100, "string" },
             { "count", "F_COUNT", 40, "number" }, { "mapID", "F_MAP", 50, "number" } },
    boss = { { "encounterID", "F_ENCOUNTER", 70, "number" }, { "name", "F_NAME", 140, "string" },
             { "count", "F_COUNT", 45, "number" } },
    zone = { { "mapID", "F_MAP", 70, "number" } },
    subzone = { { "name", "F_SUBZONE", 170, "string" }, { "mapID", "F_MAP", 60, "number" } },
    location = { { "mapID", "F_MAP", 55, "number" }, { "x", "F_X", 45, "number", 100 },
                 { "y", "F_Y", 45, "number", 100 }, { "radius", "F_RADIUS", 45, "number", 100 } },
    level = { { "level", "F_LEVEL", 50, "number" } },
    manual = { { "text", "F_TEXT", 240, "string" }, { "count", "F_COUNT", 45, "number" } },
}

local function currentStage()
    return draft.stages[stageIndex]
end

local function formatValue(value, scale)
    if value == nil then return "" end
    if scale then return tostring(math.floor(value * scale * 10 + 0.5) / 10) end
    return tostring(value)
end

local function parseValue(text, kind, scale)
    if kind == "string" then return text end
    if kind == "item" then return Util.ParseItemID(text) end
    local n = tonumber(text)
    if n and scale then n = n / scale end
    return n
end

-- Helper actions fill fields from the game: target, map, position, last boss.
local HELPERS = {
    kill = { "H_TARGET", function(obj)
        local npcID, name = ns.api.GetTargetNPC()
        if not npcID then ns.api.Print(L["ERR_NO_TARGET"]) return end
        obj.npcID, obj.name = npcID, name or obj.name
    end },
    boss = { "H_LAST_BOSS", function(obj)
        if not ns.lastEncounter then ns.api.Print(L["ERR_NO_ENCOUNTER"]) return end
        obj.encounterID, obj.name = ns.lastEncounter.id, ns.lastEncounter.name
    end },
    zone = { "H_CURRENT_MAP", function(obj) obj.mapID = ns.api.GetPlayerMapID() end },
    subzone = { "H_CURRENT_SUBZONE", function(obj)
        local name = ns.api.GetSubZoneName()
        if not name then ns.api.Print(L["ERR_NO_SUBZONE"]) return end
        obj.name, obj.mapID = name, ns.api.GetPlayerMapID()
    end, 120 },
    location = { "H_MY_POSITION", function(obj)
        local mapID = ns.api.GetPlayerMapID()
        local x, y = ns.api.GetPlayerPosition(mapID)
        if not x then ns.api.Print(L["ERR_NO_POSITION"]) return end
        obj.mapID, obj.x, obj.y = mapID, x, y
        obj.radius = obj.radius or 0.02
    end },
}

-- Hover help for fields whose value is an ID looked up elsewhere.
local FIELD_HINTS = { itemID = "HINT_ITEM", npcID = "HINT_NPC", encounterID = "HINT_ENCOUNTER", mapID = "HINT_MAP" }

local function typeLabel(t) return L["TYPE_" .. t:upper()] end
local TYPE_ITEMS = UI.EnumItems(Model.OBJECTIVE_TYPES, typeLabel)

-- Tabs ---------------------------------------------------------------------------

local function showTab(name)
    for _, tab in ipairs(TABS) do
        panels[tab]:SetShown(tab == name)
        if tab == name then tabButtons[tab]:LockHighlight() else tabButtons[tab]:UnlockHighlight() end
    end
    fields.addObjective:SetShown(name == "objectives")
    fields.help:SetShown(name == "objectives")
end

-- Objectives tab -------------------------------------------------------------------

local renderObjectives

local function createObjectiveRow(i)
    local panel = panels.objectives
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(innerWidth, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -40 - (i - 1) * ROW_HEIGHT)

    row.type = UI.CreateDropdown(row, 100, function() return TYPE_ITEMS end,
        function() local obj = currentStage().objectives[row.index] return obj and obj.type end,
        function(value)
            local stage = currentStage()
            local old = stage.objectives[row.index]
            if old.type == value then return end
            stage.objectives[row.index] = { type = value, count = old.count }
            renderObjectives()
        end)
    row.type:SetPoint("BOTTOMLEFT", 0, 2)

    row.edits, row.labels = {}, {}
    for f = 1, MAX_FIELDS do
        local e = UI.CreateEditBox(row, 60)
        e:SetScript("OnTextChanged", function(self, userInput)
            if not userInput or not self.spec then return end
            local obj = currentStage().objectives[row.index]
            obj[self.spec[1]] = parseValue(self:GetText(), self.spec[4], self.spec[5])
        end)
        -- Shift-clicking an item while the box has focus inserts its link.
        e:SetScript("OnEditFocusGained", function(self) row.focused = self end)
        e:SetScript("OnEnter", function(self)
            local hint = self.spec and FIELD_HINTS[self.spec[1]]
            if not hint then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L[self.spec[2]])
            GameTooltip:AddLine(L[hint], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        e:SetScript("OnLeave", GameTooltip_Hide)
        row.edits[f] = e
        row.labels[f] = UI.CreateLabel(row, "", "GameFontDisableSmall")
        row.labels[f]:SetPoint("BOTTOMLEFT", e, "TOPLEFT", -4, 0)
    end

    row.fallback = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.fallback:SetSize(22, 22)
    row.fallback:SetScript("OnClick", function(self)
        currentStage().objectives[row.index].fallbackAny = self:GetChecked() and true or nil
    end)
    row.fallback:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["FALLBACK_TITLE"])
        GameTooltip:AddLine(L["FALLBACK_HELP"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.fallback:SetScript("OnLeave", GameTooltip_Hide)

    row.helper = UI.CreateButton(row, "", 80)
    row.remove = UI.CreateButton(row, "X", 24, function()
        local stage = currentStage()
        if #stage.objectives <= 1 then return end
        table.remove(stage.objectives, row.index)
        renderObjectives()
    end)
    row.remove:SetPoint("BOTTOMRIGHT", 0, 2)
    objectiveRows[i] = row
    return row
end

function renderObjectives()
    local stage = currentStage()
    stageLabel:SetText(L["STAGE_N"]:format(stageIndex, #draft.stages))
    stageText:SetText(stage.text or "")
    for _, row in ipairs(objectiveRows) do row:Hide() end

    for i, obj in ipairs(stage.objectives) do
        local row = objectiveRows[i] or createObjectiveRow(i)
        row.index = i
        row:Show()
        row.type:Refresh()

        local prev = row.type
        local specs = FIELD_SPECS[obj.type]
        for f = 1, MAX_FIELDS do
            local e, spec = row.edits[f], specs[f]
            e.spec = spec
            e:SetShown(spec ~= nil)
            row.labels[f]:SetShown(spec ~= nil)
            if spec then
                e:SetWidth(spec[3])
                e:ClearAllPoints()
                e:SetPoint("LEFT", prev, "RIGHT", 10, 0)
                e:SetText(formatValue(obj[spec[1]], spec[5]))
                e:SetCursorPosition(0)
                row.labels[f]:SetText(L[spec[2]])
                prev = e
            end
        end

        row.fallback:SetShown(obj.type == "kill")
        if obj.type == "kill" then
            row.fallback:ClearAllPoints()
            row.fallback:SetPoint("LEFT", prev, "RIGHT", 4, 0)
            row.fallback:SetChecked(obj.fallbackAny)
            prev = row.fallback
        end

        local helper = HELPERS[obj.type]
        row.helper:SetShown(helper ~= nil)
        if helper then
            row.helper:SetText(L[helper[1]])
            row.helper:SetWidth(helper[3] or 80)
            row.helper:ClearAllPoints()
            row.helper:SetPoint("LEFT", prev, "RIGHT", 6, 0)
            row.helper:SetScript("OnClick", function()
                helper[2](currentStage().objectives[row.index])
                renderObjectives()
            end)
        end
    end
    fields.addObjective:SetEnabled(#stage.objectives < Model.MAX_OBJECTIVES)
end

local function createObjectivesPanel(panel)
    stageLabel = UI.CreateLabel(panel, "", "GameFontNormal")
    stageLabel:SetPoint("TOPLEFT", 0, -6)
    stageText = UI.CreateEditBox(panel, 280)
    stageText:SetPoint("LEFT", stageLabel, "RIGHT", 12, 0)
    stageText:SetMaxLetters(Model.MAX_TEXT)
    stageText:SetScript("OnTextChanged", function(self, userInput)
        if userInput then currentStage().text = self:GetText() end
    end)

    local nextStage = UI.CreateButton(panel, ">", 26, function()
        if stageIndex < #draft.stages then stageIndex = stageIndex + 1 renderObjectives() end
    end)
    nextStage:SetPoint("TOPRIGHT", 0, 0)
    local prevStage = UI.CreateButton(panel, "<", 26, function()
        if stageIndex > 1 then stageIndex = stageIndex - 1 renderObjectives() end
    end)
    prevStage:SetPoint("RIGHT", nextStage, "LEFT", -2, 0)
    local removeStage = UI.CreateButton(panel, "-", 26, function()
        if #draft.stages <= 1 then return end
        table.remove(draft.stages, stageIndex)
        stageIndex = math.min(stageIndex, #draft.stages)
        renderObjectives()
    end)
    removeStage:SetPoint("RIGHT", prevStage, "LEFT", -6, 0)
    local addStage = UI.CreateButton(panel, "+", 26, function()
        if #draft.stages >= Model.MAX_STAGES then return end
        stageIndex = stageIndex + 1
        table.insert(draft.stages, stageIndex, { text = "", objectives = { { type = "manual", text = "", count = 1 } } })
        renderObjectives()
    end)
    addStage:SetPoint("RIGHT", removeStage, "LEFT", -2, 0)
end

-- General tab ---------------------------------------------------------------------

local function labeled(parent, text, widget, x, y)
    local label = UI.CreateLabel(parent, text)
    label:SetPoint("TOPLEFT", x, y)
    widget:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -2)
    widget.label = label
    return widget
end

-- Templates this one may follow, laid out like the Templates tree: each
-- follow-up indented under the quest it follows. Leaves out this quest and
-- everything after it, since those would loop.
local function chainItems()
    local items = { { value = false, text = L["CHAIN_NONE"] } }
    for _, node in ipairs(Model.TemplateTree()) do
        if node.id ~= draftID and not (draftID and Model.WouldCycle(draftID, node.id)) then
            local t = Model.GetTemplate(node.id)
            local indent = node.depth > 0 and (("    "):rep(node.depth - 1) .. "  » ") or ""
            items[#items + 1] = { value = node.id, text = indent
                .. UI.QuestIconMarkup(UI.QuestKind(t, node.id), "available", 14) .. " " .. UI.QuestText(t.title) }
        end
    end
    return items
end

-- Where the quest sits: "A » B » This quest", then the quests that follow it.
local function chainSummary()
    local names = {}
    local current = draft.requires
    for _ = 1, 30 do
        local t = current and Model.GetTemplate(current)
        if not t then break end
        table.insert(names, 1, UI.QuestText(t.title))
        current = t.requires
    end
    local nexts = {}
    for _, id in ipairs(draftID and Model.GetFollowUps(draftID) or {}) do
        nexts[#nexts + 1] = UI.QuestText(Model.GetTemplate(id).title)
    end
    if #names == 0 and #nexts == 0 then return L["CHAIN_SOLO"] end
    local this = draft.title ~= "" and UI.QuestText(draft.title) or L["CHAIN_THIS"]
    names[#names + 1] = "|cffffd200" .. this .. "|r"
    local text = L["CHAIN_PATH"]:format(table.concat(names, " » "))
    if #nexts > 0 then text = text .. "\n" .. L["CHAIN_NEXT_LIST"]:format(table.concat(nexts, ", ")) end
    return text
end

local function refreshChain()
    if not draft or not fields.chainPath then return end
    fields.chainPath:SetText(chainSummary())
end

local function createGeneralPanel(panel)
    fields.title = labeled(panel, L["F_TITLE"], UI.CreateEditBox(panel, 270), 0, -4)
    fields.title:SetMaxLetters(Model.MAX_TITLE)
    fields.title:SetScript("OnTextChanged", function(self)
        draft.title = self:GetText()
        refreshChain()
    end)

    fields.giver = labeled(panel, L["F_GIVER"], UI.CreateEditBox(panel, 160), 290, -4)
    fields.giver:SetMaxLetters(Model.MAX_TITLE)
    fields.giver:SetScript("OnTextChanged", function(self) draft.giver = self:GetText() end)

    fields.kind = labeled(panel, L["F_KIND"], UI.CreateDropdown(panel, 110,
        function() return UI.EnumItems(Model.KINDS, function(v) return L["KIND_" .. v:upper()] end) end,
        function() return draft.kind end,
        function(v) draft.kind = v end), 470, -4)

    fields.repeatMode = labeled(panel, L["F_REPEAT"], UI.CreateDropdown(panel, 130,
        function() return UI.EnumItems(Model.REPEAT_MODES, function(v) return L["REPEAT_" .. v:upper()] end) end,
        function() return draft.repeatMode end,
        function(v) draft.repeatMode = v end), 0, -56)

    -- Level range: empty means no limit.
    local function levelField(key, label, x)
        local e = labeled(panel, label, UI.CreateEditBox(panel, 40, true), x, -56)
        e:SetMaxLetters(3)
        e:SetScript("OnTextChanged", function(self, userInput)
            if userInput then draft[key] = tonumber(self:GetText()) end
        end)
        return e
    end
    fields.minLevel = levelField("minLevel", L["F_MIN_LEVEL"], 160)
    fields.maxLevel = levelField("maxLevel", L["F_MAX_LEVEL"], 230)

    -- Chain: the quest that must be completed before this one.
    fields.requires = labeled(panel, L["F_REQUIRES"], UI.CreateDropdown(panel, 360, chainItems,
        function() return draft.requires end,
        function(value)
            draft.requires = value or nil
            refreshChain()
        end), 0, -108)
    fields.chainPath = UI.CreateLabel(panel, "", "GameFontHighlight")
    fields.chainPath:SetPoint("TOPLEFT", fields.requires, "BOTTOMLEFT", 0, -8)
    fields.chainPath:SetSpacing(3)
    fields.chainHint = UI.CreateLabel(panel, L["CHAIN_HINT"], "GameFontDisableSmall")
    fields.chainHint:SetPoint("TOPLEFT", fields.chainPath, "BOTTOMLEFT", 0, -8)
end

-- Texts tab ------------------------------------------------------------------------

local TEXT_COLORS = { "ffd200", "ff4040", "20ff20", "40a0ff", "ff80ff", "ffffff" }
local lastTextField, preview

-- Shows description and reward as the journal will render them.
local function refreshPreview()
    if not preview then return end
    local parts = {}
    if draft.description and draft.description ~= "" then parts[#parts + 1] = UI.QuestText(draft.description) end
    if draft.rewardText and draft.rewardText ~= "" then
        parts[#parts + 1] = L["REWARD"]:format(UI.QuestText(draft.rewardText))
    end
    if draft.completionText and draft.completionText ~= "" then
        parts[#parts + 1] = "|cffffd200" .. L["F_COMPLETION"] .. ":|r " .. UI.QuestText(draft.completionText)
    end
    preview:SetText(table.concat(parts, "\n\n"))
end

-- Inserts text at the cursor of the field last edited.
local function insertInto(text)
    local target = lastTextField or fields.description
    target:SetFocus()
    target:Insert(text)
    refreshPreview()
end

local function createToolbar(panel)
    local x = 0
    for _, hex in ipairs(TEXT_COLORS) do
        local b = CreateFrame("Button", nil, panel, "BackdropTemplate")
        b:SetSize(20, 20)
        b:SetPoint("TOPLEFT", x, 0)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        b:SetBackdropColor(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
            tonumber(hex:sub(5, 6), 16) / 255, 1)
        b:SetBackdropBorderColor(0, 0, 0, 1)
        b:SetScript("OnClick", function() insertInto("[color=" .. hex .. "]") end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["TB_COLOR"])
            GameTooltip:AddLine(L["TB_COLOR_HELP"], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        x = x + 24
    end
    local close = UI.CreateButton(panel, L["TB_END_COLOR"], 90, function() insertInto("[/color]") end)
    close:SetPoint("TOPLEFT", x + 6, 1)
    local token = UI.CreateButton(panel, "{name}", 70, function() insertInto("{name}") end)
    token:SetPoint("LEFT", close, "RIGHT", 4, 0)
    local class = UI.CreateButton(panel, "{class}", 70, function() insertInto("{class}") end)
    class:SetPoint("LEFT", token, "RIGHT", 2, 0)
    local race = UI.CreateButton(panel, "{race}", 70, function() insertInto("{race}") end)
    race:SetPoint("LEFT", class, "RIGHT", 2, 0)
end

local function createTextsPanel(panel)
    createToolbar(panel)

    local descArea
    descArea, fields.description = UI.CreateTextArea(panel, innerWidth, 100)
    textAreas.description = descArea
    labeled(panel, L["F_DESCRIPTION"], descArea, 0, -28)
    fields.description:SetMaxLetters(Model.MAX_TEXT)
    fields.description:SetScript("OnEditFocusGained", function(self) lastTextField = self end)
    fields.description:SetScript("OnTextChanged", function(self)
        draft.description = self:GetText()
        refreshPreview()
    end)

    local rewardArea
    rewardArea, fields.reward = UI.CreateTextArea(panel, innerWidth, 60)
    textAreas.reward = rewardArea
    labeled(panel, L["F_REWARD"], rewardArea, 0, -152)
    fields.reward:SetMaxLetters(Model.MAX_TEXT)
    fields.reward:SetScript("OnEditFocusGained", function(self) lastTextField = self end)
    fields.reward:SetScript("OnTextChanged", function(self)
        draft.rewardText = self:GetText()
        refreshPreview()
    end)

    local completionArea
    completionArea, fields.completion = UI.CreateTextArea(panel, innerWidth, 60)
    textAreas.completion = completionArea
    labeled(panel, L["F_COMPLETION"], completionArea, 0, -232)
    fields.completion:SetMaxLetters(Model.MAX_TEXT)
    fields.completion:SetScript("OnEditFocusGained", function(self) lastTextField = self end)
    fields.completion:SetScript("OnTextChanged", function(self)
        draft.completionText = self:GetText()
        refreshPreview()
    end)

    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetSize(innerWidth, 80)
    textAreas.preview = box
    box:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0.1, 0.08, 0.02, 0.8)
    labeled(panel, L["TB_PREVIEW"], box, 0, -312)
    preview = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    preview:SetPoint("TOPLEFT", 8, -8)
    preview:SetSize(innerWidth - 20, 64)
    preview:SetJustifyH("LEFT")
    preview:SetJustifyV("TOP")
end

-- Window ---------------------------------------------------------------------------

-- Fits the tabs to the window: boxes get the extra width, and the extra height
-- goes half to the description and half to the preview.
local function layout(w, h)
    innerWidth = w - 40
    for _, row in ipairs(objectiveRows) do row:SetWidth(innerWidth) end
    fields.chainPath:SetWidth(innerWidth - 20)
    fields.chainHint:SetWidth(innerWidth - 20)

    local extra = math.max(0, h - HEIGHT)
    local toDescription = math.floor(extra / 2)
    local heights = { description = 100 + toDescription, reward = 60, completion = 60,
                      preview = 80 + extra - toDescription }
    local tops = { description = -28, reward = -152 - toDescription, completion = -232 - toDescription,
                   preview = -312 - toDescription }
    for name, area in pairs(textAreas) do
        area:SetSize(innerWidth, heights[name])
        area.label:ClearAllPoints()
        area.label:SetPoint("TOPLEFT", 0, tops[name])
    end
    preview:SetSize(innerWidth - 20, heights.preview - 16)
end

local function loadDraft()
    fields.title:SetText(draft.title or "")
    fields.giver:SetText(draft.giver or "")
    fields.kind:Refresh()
    fields.repeatMode:Refresh()
    fields.requires:Refresh()
    refreshChain()
    fields.minLevel:SetText(draft.minLevel and tostring(draft.minLevel) or "")
    fields.maxLevel:SetText(draft.maxLevel and tostring(draft.maxLevel) or "")
    fields.description:SetText(draft.description or "")
    fields.reward:SetText(draft.rewardText or "")
    fields.completion:SetText(draft.completionText or "")
    refreshPreview()
    errorText:SetText("")
    renderObjectives()
end

-- Errors that point at a field switch to the tab that holds it.
local ERROR_TABS = { ERR_NEED_TITLE = "general", ERR_LEVEL_RANGE = "general", ERR_CHAIN_CYCLE = "general" }

local function save()
    local id, err, stage, objective = Model.SaveTemplate(draft, draftID, ns.api.Now())
    if not id then
        local where = stage and L["ERR_WHERE"]:format(stage, objective or 0) or ""
        errorText:SetText("|cffff4040" .. (L[err] or err) .. where .. "|r")
        if stage then
            stageIndex = stage
            renderObjectives()
        end
        showTab(ERROR_TABS[err] or "objectives")
        return
    end
    window:Hide()
    if ns.Journal then ns.Journal.ShowTemplate(id) end
end

-- Insert shift-clicked item links into the focused item field.
local function onInsertLink(link)
    if not window or not window:IsShown() or type(link) ~= "string" then return end
    for _, row in ipairs(objectiveRows) do
        local e = row.focused
        if row:IsShown() and e and e:HasFocus() and e.spec and e.spec[4] == "item" then
            local itemID = Util.ParseItemID(link)
            if itemID then
                e:SetText(tostring(itemID))
                currentStage().objectives[row.index].itemID = itemID
            end
        end
    end
end
-- Retail 12 moved link insertion to ChatFrameUtil; older clients still use the global.
if ChatFrameUtil and ChatFrameUtil.InsertLink then
    hooksecurefunc(ChatFrameUtil, "InsertLink", onInsertLink)
elseif ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", onInsertLink)
end

local helpWindow

-- Explains where IDs come from and which buttons fill them in.
local function showHelp()
    if not helpWindow then
        helpWindow = UI.CreateWindow("CustomQuestsEditorHelp", 480, 420, L["HELP_TITLE"])
        helpWindow:SetFrameStrata("FULLSCREEN_DIALOG")
        local scroll = CreateFrame("ScrollFrame", nil, helpWindow, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -34)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(430, 1)
        scroll:SetScrollChild(content)
        local text = UI.CreateLabel(content, L["HELP_TEXT"], "GameFontHighlight")
        text:SetPoint("TOPLEFT")
        text:SetWidth(430)
        text:SetSpacing(3)
        content:SetHeight(text:GetStringHeight() + 10)
    end
    helpWindow:SetShown(not helpWindow:IsShown())
end

local function create()
    window = UI.CreateWindow("CustomQuestsEditor", WIDTH, HEIGHT, L["EDITOR_TITLE"])
    fields = {}

    local prev
    for _, tab in ipairs(TABS) do
        local b = UI.CreateButton(window, L["EDITOR_TAB_" .. tab:upper()], 150, function() showTab(tab) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 16, -30) end
        tabButtons[tab] = b
        prev = b

        local panel = CreateFrame("Frame", nil, window)
        panel:SetPoint("TOPLEFT", 20, -64)
        panel:SetPoint("BOTTOMRIGHT", -20, 46)
        panels[tab] = panel
    end
    createGeneralPanel(panels.general)
    createTextsPanel(panels.texts)
    createObjectivesPanel(panels.objectives)

    fields.addObjective = UI.CreateButton(window, L["ADD_OBJECTIVE"], 130, function()
        local stage = currentStage()
        if #stage.objectives >= Model.MAX_OBJECTIVES then return end
        stage.objectives[#stage.objectives + 1] = { type = "item", count = 1 }
        renderObjectives()
    end)
    fields.addObjective:SetPoint("BOTTOMLEFT", 20, 14)

    fields.help = UI.CreateButton(window, L["HELP_BUTTON"], 80, showHelp)
    fields.help:SetPoint("LEFT", fields.addObjective, "RIGHT", 6, 0)

    errorText = UI.CreateLabel(window, "", "GameFontHighlightSmall")
    errorText:SetPoint("BOTTOMLEFT", 250, 18)
    errorText:SetWidth(170)

    local saveButton = UI.CreateButton(window, SAVE, 90, save)
    saveButton:SetPoint("BOTTOMRIGHT", -20, 14)
    UI.CreateButton(window, CANCEL, 90, function() window:Hide() end)
        :SetPoint("RIGHT", saveButton, "LEFT", -6, 0)

    window:SetScript("OnHide", function()
        if helpWindow then helpWindow:Hide() end
    end)
    UI.MakeResizable(window, WIDTH, HEIGHT, MAX_SIZE[1], MAX_SIZE[2], layout)
end

-- Opens a working copy; nothing is saved until "Save" passes validation.
-- prerequisiteID: a new quest that comes next in that quest's chain.
function Editor.Open(templateID, prerequisiteID)
    if not window then create() end
    local template = templateID and Model.GetTemplate(templateID)
    draft = template and Util.DeepCopy(template) or Model.NewEmptyTemplate()
    draftID = template and templateID or nil
    local prerequisite = not template and prerequisiteID and Model.GetTemplate(prerequisiteID)
    if prerequisite then
        draft.requires = prerequisiteID
        draft.kind = prerequisite.kind
    end
    stageIndex = 1
    loadDraft()
    showTab("general")
    window:Show()
end
