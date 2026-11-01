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

-- Import / export ------------------------------------------------------------

local window, edit, actionButton, status

local function create()
    window = UI.CreateWindow("CustomQuestsTransfer", 440, 280, "")
    local area
    area, edit = UI.CreateTextArea(window, 410, 180)
    area:SetPoint("TOP", 0, -32)
    edit:SetMaxLetters(Serializer.MAX_LENGTH)

    status = UI.CreateLabel(window, "", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 16, 16)
    status:SetWidth(240)

    actionButton = UI.CreateButton(window, L["IMPORT"], 100)
    actionButton:SetPoint("BOTTOMRIGHT", -16, 12)
    UI.CreateButton(window, CLOSE, 80, function() window:Hide() end)
        :SetPoint("RIGHT", actionButton, "LEFT", -6, 0)
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
