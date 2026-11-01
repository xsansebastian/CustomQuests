local _, ns = ...

local L, UI = ns.L, ns.UI
local Model, Serializer = ns.Model, ns.Serializer

local Dialogs = {}
ns.Dialogs = Dialogs

StaticPopupDialogs["CUSTOMQUESTS_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) data() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Dialogs.Confirm(text, onAccept)
    StaticPopup_Show("CUSTOMQUESTS_CONFIRM", text, nil, onAccept)
end

-- Three ways out when a deleted template has quests after it in its chain:
-- the whole branch (button1), only the chosen ones (button3, OnAlt) or nothing.
-- data = { ids = {...}, onDone = function }.
StaticPopupDialogs["CUSTOMQUESTS_DELETE_BRANCH"] = {
    text = "%s",
    button1 = L["DELETE_BRANCH_ALL"],
    button2 = CANCEL,
    button3 = L["DELETE_BRANCH_ONLY"],
    OnAccept = function(_, data)
        Model.DeleteTemplates(data.ids, true)
        if data.onDone then data.onDone() end
    end,
    OnAlt = function(_, data)
        Model.DeleteTemplates(data.ids, false)
        if data.onDone then data.onDone() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Deletes the templates after asking; onDone runs once they are gone.
function Dialogs.ConfirmDelete(ids, onDone)
    local many = #ids > 1
    if Model.NeedsBranchChoice(ids) then
        local text = many and L["CONFIRM_DELETE_BRANCH_MANY"]:format(#ids)
            or L["CONFIRM_DELETE_BRANCH"]:format(UI.QuestText(Model.GetTemplate(ids[1]).title))
        StaticPopup_Show("CUSTOMQUESTS_DELETE_BRANCH", text, nil, { ids = ids, onDone = onDone })
        return
    end
    local text = many and L["CONFIRM_DELETE_MANY"]:format(#ids)
        or L["CONFIRM_DELETE"]:format(UI.QuestText(Model.GetTemplate(ids[1]).title))
    Dialogs.Confirm(text, function()
        Model.DeleteTemplates(ids, false)
        if onDone then onDone() end
    end)
end

-- Sections -------------------------------------------------------------------

-- The edit box of a popup: a method in recent clients, a field in older ones.
local function popupEditBox(dialog)
    return dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
end

-- data = { initial = string, onAccept = function(name) }.
StaticPopupDialogs["CUSTOMQUESTS_SECTION_NAME"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = Model.MAX_SECTION_NAME,
    OnShow = function(dialog, data)
        local edit = popupEditBox(dialog)
        edit:SetText(data and data.initial or "")
        edit:HighlightText()
        edit:SetFocus()
    end,
    OnAccept = function(dialog, data)
        data.onAccept(popupEditBox(dialog):GetText())
    end,
    EditBoxOnEnterPressed = function(edit, data)
        local dialog = edit:GetParent()
        data = data or dialog.data
        -- Read the text first: hiding the popup clears the edit box.
        local text = edit:GetText()
        dialog:Hide()
        if data then data.onAccept(text) end
    end,
    EditBoxOnEscapePressed = function(edit) edit:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Dialogs.PromptSectionName(initial, onAccept)
    StaticPopup_Show("CUSTOMQUESTS_SECTION_NAME", L["SECTION_NAME_PROMPT"], nil, { initial = initial, onAccept = onAccept })
end

-- Asks for a name and makes the section; onCreated(id) runs when it exists.
function Dialogs.NewSection(onCreated)
    Dialogs.PromptSectionName("", function(name)
        local id, err = Model.CreateSection(name, ns.api.Now())
        if not id then ns.api.Print(UI.ErrorText(err)) return end
        if onCreated then onCreated(id) end
    end)
end

function Dialogs.RenameSection(sectionID, onDone)
    local section = Model.SectionByID(sectionID)
    if not section then return end
    Dialogs.PromptSectionName(section.name, function(name)
        local ok, err = Model.RenameSection(sectionID, name)
        if not ok then ns.api.Print(UI.ErrorText(err)) return end
        if onDone then onDone() end
    end)
end

function Dialogs.ConfirmDeleteSection(sectionID, onDone)
    local section = Model.SectionByID(sectionID)
    if not section then return end
    Dialogs.Confirm(L["CONFIRM_DELETE_SECTION"]:format(UI.QuestText(section.name)), function()
        Model.DeleteSection(sectionID)
        if onDone then onDone() end
    end)
end

-- Import / export ------------------------------------------------------------

local window, edit, actionButton, status

local function create()
    window = UI.CreateWindow("CustomQuestsTransfer", 440, 280, "")
    local area
    area, edit = UI.CreateTextArea(window, 410, 180)
    area:SetPoint("TOPLEFT", 15, -32)
    area:SetPoint("BOTTOMRIGHT", -15, 44)
    edit:SetMaxLetters(Serializer.MAX_LENGTH)

    status = UI.CreateLabel(window, "", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 16, 16)
    status:SetWidth(240)

    actionButton = UI.CreateButton(window, L["IMPORT"], 100)
    actionButton:SetPoint("BOTTOMRIGHT", -16, 12)
    UI.CreateButton(window, CLOSE, 80, function() window:Hide() end)
        :SetPoint("RIGHT", actionButton, "LEFT", -6, 0)
    UI.MakeResizable(window, 360, 220, 900, 700)
end

-- Exports the template, or its whole chain when it belongs to one.
function Dialogs.ShowExport(templateID)
    if not window then create() end
    local text = Serializer.ExportChain(templateID)
    local count = #Model.GetChain(templateID)
    window.TitleText:SetText(L["EXPORT_TITLE"])
    status:SetText(count > 1 and L["EXPORT_CHAIN_HINT"]:format(count) or L["EXPORT_HINT"])
    actionButton:Hide()
    edit:SetText(text or "")
    window:Show()
    edit:SetFocus()
    edit:HighlightText()
end

-- Exports every quest of a section.
function Dialogs.ShowSectionExport(sectionID)
    local section = Model.SectionByID(sectionID)
    local text = section and Serializer.ExportSection(sectionID)
    if not text then ns.api.Print(UI.ErrorText("ERR_SECTION_EMPTY")) return end
    if not window then create() end
    window.TitleText:SetText(L["EXPORT_TITLE"])
    status:SetText(L["SECTION_EXPORT_HINT"]:format(UI.QuestText(section.name), #Model.SectionMembers(sectionID)))
    actionButton:Hide()
    edit:SetText(text)
    window:Show()
    edit:SetFocus()
    edit:HighlightText()
end

function Dialogs.ShowImport(onImported)
    if not window then create() end
    window.TitleText:SetText(L["IMPORT_TITLE"])
    status:SetText(L["IMPORT_HINT"])
    edit:SetText("")
    actionButton:Show()
    actionButton:SetScript("OnClick", function()
        local entries, err = Serializer.Import(edit:GetText())
        if not entries then
            status:SetText("|cffff4040" .. (L[err] or err) .. "|r")
            return
        end
        local ids = Model.SaveImported(entries, ns.api.Now())
        window:Hide()
        for _, entry in ipairs(entries) do
            ns.api.Print(L["IMPORTED"]:format(UI.QuestText(entry.template.title)))
        end
        if onImported then onImported(ids[1]) end
    end)
    window:Show()
    edit:SetFocus()
end
