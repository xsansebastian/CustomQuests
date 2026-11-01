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

-- One chat line per imported quest; the ones already saved say so instead.
function Dialogs.ReportImported(entries, skipped)
    for i, entry in ipairs(entries) do
        local key = skipped and skipped[i] and "IMPORT_DUPLICATE" or "IMPORTED"
        ns.api.Print(L[key]:format(UI.QuestText(entry.template.title)))
    end
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
        local ids, skippedOrErr = Model.SaveImported(entries, ns.api.Now())
        if not ids then
            status:SetText("|cffff4040" .. UI.ErrorText(skippedOrErr) .. "|r")
            return
        end
        window:Hide()
        Dialogs.ReportImported(entries, skippedOrErr)
        if onImported then onImported(ids[1]) end
    end)
    window:Show()
    edit:SetFocus()
end

-- Sharing ----------------------------------------------------------------------
-- Everything shown here about an offer (sender, title) was already passed
-- through Util.SafeLabel by Share: no escape codes, brackets or colons.

local function offerText(offer)
    return L["SHARE_OFFER_TEXT"]:format(offer.senderLabel, L["SHARE_KIND_" .. offer.kind:upper()], offer.title,
        L["SHARE_COUNT"]:format(offer.count), offer.bytes / 1024)
end

-- Accept / Decline / Block. A popup that times out is dropped without an answer.
StaticPopupDialogs["CUSTOMQUESTS_SHARE_OFFER"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = DECLINE,
    button3 = L["SHARE_BLOCK"],
    OnAccept = function(_, offer) ns.Share.Accept(offer, ns.api.Clock()) end,
    OnCancel = function(_, offer, reason)
        if reason == "clicked" then ns.Share.Decline(offer) else ns.Share.Dismiss(offer) end
    end,
    OnAlt = function(_, offer) ns.Share.Block(offer) end,
    timeout = 60,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Dialogs.ShowShareOffer(offer)
    StaticPopup_Show("CUSTOMQUESTS_SHARE_OFFER", offerText(offer), nil, offer)
end

function Dialogs.HideShareOffer(offer)
    StaticPopup_Hide("CUSTOMQUESTS_SHARE_OFFER", offer)
end

-- data = { onAccept = function(name) }.
StaticPopupDialogs["CUSTOMQUESTS_SHARE_NAME"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 64,
    OnShow = function(dialog)
        local box = popupEditBox(dialog)
        box:SetText(ns.api.TargetPlayerName() or "")
        box:HighlightText()
        box:SetFocus()
    end,
    OnAccept = function(dialog, data) data.onAccept(popupEditBox(dialog):GetText()) end,
    EditBoxOnEnterPressed = function(box, data)
        local dialog = box:GetParent()
        data = data or dialog.data
        local text = box:GetText()
        dialog:Hide()
        if data then data.onAccept(text) end
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Offers a quest ("quest", templateID) or a section ("section", sectionID).
-- channel: "WHISPER" (with target), "GROUP" or "GUILD".
function Dialogs.Share(kind, id, channel, target)
    local tid, err = ns.Share.Offer(kind, id, channel, target, ns.api.Clock())
    if not tid then ns.api.Print(UI.ErrorText(err)) return end
    local offer = ns.Share.Outgoing()[tid]
    local where = channel == "GUILD" and L["SHARE_WHERE_GUILD"] or channel == "GROUP" and L["SHARE_WHERE_GROUP"]
        or ns.Util.SafeLabel(ns.api.ShortName(offer.targetName or target or "?"), 64)
    ns.api.Print(L["SHARE_OFFERED"]:format(offer.title, where))
end

-- Puts [CustomQuests: Title] in the chat box; a click on it asks us for the quest.
function Dialogs.LinkInChat(kind, id)
    local marker, err = ns.Share.MakeLink(kind, id, ns.api.Clock())
    if not marker then ns.api.Print(UI.ErrorText(err)) return end
    if not ns.api.InsertChatText(marker) then ns.api.Print(L["SHARE_LINK_NO_CHAT"]) end
end

-- The "Share with..." submenu, added to a context menu built with MenuUtil.
function Dialogs.AddShareMenu(root, kind, id)
    local sub = root:CreateButton(L["SHARE_WITH"])
    local function enable(element, on)
        if element and element.SetEnabled then element:SetEnabled(on and true or false) end
    end
    local target = ns.api.TargetPlayerName()
    enable(sub:CreateButton(target and L["SHARE_TARGET"]:format(ns.Util.SafeLabel(ns.api.ShortName(target), 64))
        or L["SHARE_TARGET_NONE"], function() Dialogs.Share(kind, id, "WHISPER", target) end), target)
    enable(sub:CreateButton(L["SHARE_GROUP"], function() Dialogs.Share(kind, id, "GROUP") end),
        ns.api.GroupChannel())
    enable(sub:CreateButton(L["SHARE_GUILD"], function() Dialogs.Share(kind, id, "GUILD") end), ns.api.IsInGuild())
    sub:CreateButton(L["SHARE_PLAYER"], function()
        StaticPopup_Show("CUSTOMQUESTS_SHARE_NAME", L["SHARE_NAME_PROMPT"], nil, {
            onAccept = function(name) Dialogs.Share(kind, id, "WHISPER", name) end,
        })
    end)
    sub:CreateDivider()
    sub:CreateButton(L["SHARE_LINK"], function() Dialogs.LinkInChat(kind, id) end)
end
