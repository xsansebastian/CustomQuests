local _, ns = ...

local L, Util = ns.L, ns.Util
local UI = {}
ns.UI = UI

UI.TYPE_ICONS = {
    item = "Interface\\Icons\\INV_Misc_Bag_10",
    kill = "Interface\\Icons\\Ability_DualWield",
    boss = "Interface\\Icons\\Achievement_Boss_Ragnaros",
    zone = "Interface\\Icons\\INV_Misc_Map_01",
    subzone = "Interface\\Icons\\INV_Misc_Map_01",
    location = "Interface\\Icons\\Ability_Tracking",
    level = "Interface\\Icons\\Achievement_Level_10",
    manual = "Interface\\Icons\\INV_Misc_Note_01",
}
UI.APPROX_ICON = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:12|t"
UI.QUEST_COLOR = "ffd200"

local function mapName(mapID)
    return ns.api.GetMapName(mapID) or ("#" .. tostring(mapID))
end

-- Quest text for display: escaped, then {name}/{class}/{race} filled in.
function UI.QuestText(text)
    return Util.ExpandTokens(Util.SafeText(text), ns.api.GetPlayerTokens())
end

-- Quest icons: the game's own quest-giver icons, by kind of quest and its state.
-- campaign = part of a chain, recurring = daily or weekly, plain = the rest.
-- States: available (not accepted), progress (in the log), ready (to turn in).
-- A name with a backslash is a texture file, otherwise an atlas.
local QUEST_ICONS = {
    campaign = { available = "CampaignAvailableQuestIcon", progress = "CampaignInProgressQuestIcon",
                 ready = "CampaignActiveQuestIcon" },
    recurring = { available = "Recurringavailablequesticon", progress = "RepeatableInProgressquesticon",
                  ready = "Recurringactivequesticon" },
    plain = { available = "Interface\\GossipFrame\\AvailableQuestIcon", progress = "SideInProgressquesticon",
              ready = "QuestTurnin" },
}
-- Shown when an atlas doesn't exist on the client.
local ICON_FILES = {
    available = "Interface\\GossipFrame\\AvailableQuestIcon",
    progress = "Interface\\GossipFrame\\ActiveQuestIcon",
    ready = "Interface\\GossipFrame\\ActiveQuestIcon",
}

local function atlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- "campaign" for quests in a chain, "recurring" for daily/weekly ones, else "plain".
function UI.QuestKind(template, templateID)
    if template.requires or (templateID and #ns.Model.GetFollowUps(templateID) > 0) then return "campaign" end
    if template.repeatMode and template.repeatMode ~= "none" then return "recurring" end
    return "plain"
end

function UI.SetQuestIcon(texture, kind, iconState)
    local name = QUEST_ICONS[kind][iconState]
    if not name:find("\\", 1, true) and atlasExists(name) then
        texture:SetAtlas(name)
        return
    end
    texture:SetTexture(name:find("\\", 1, true) and name or ICON_FILES[iconState])
    texture:SetTexCoord(0, 1, 0, 1)
end

-- The same icon as text, to put in front of a title.
function UI.QuestIconMarkup(kind, iconState, size)
    local name = QUEST_ICONS[kind][iconState]
    if not name:find("\\", 1, true) and atlasExists(name) then return CreateAtlasMarkup(name, size, size) end
    return "|T" .. (name:find("\\", 1, true) and name or ICON_FILES[iconState]) .. ":" .. size .. "|t"
end

-- The template's own icon, else one for its first objective type.
function UI.TemplateIcon(template)
    local icon = ns.Model.IconTexture(template.icon)
    if icon then return icon end
    local obj = template.stages[1] and template.stages[1].objectives[1]
    return UI.TYPE_ICONS[obj and obj.type or "manual"]
end

function UI.InlineIcon(template, size)
    return "|T" .. UI.TemplateIcon(template) .. ":" .. (size or 16) .. "|t "
end

-- Lines describing level range and chain links of a template.
function UI.TemplateRequirements(template, templateID)
    local Model, lines = ns.Model, {}
    if template.minLevel and template.maxLevel then
        lines[#lines + 1] = L["LEVELS_RANGE"]:format(template.minLevel, template.maxLevel)
    elseif template.minLevel then
        lines[#lines + 1] = L["LEVELS_MIN"]:format(template.minLevel)
    elseif template.maxLevel then
        lines[#lines + 1] = L["LEVELS_MAX"]:format(template.maxLevel)
    end
    local prerequisite = template.requires and Model.GetTemplate(template.requires)
    if prerequisite then lines[#lines + 1] = L["REQUIRES"]:format(UI.QuestText(prerequisite.title)) end
    if templateID then
        for _, nextID in ipairs(Model.GetFollowUps(templateID)) do
            lines[#lines + 1] = L["FOLLOWED_BY"]:format(UI.QuestText(Model.GetTemplate(nextID).title))
        end
    end
    return table.concat(lines, "\n")
end

-- Error text for an error key that may carry an argument.
function UI.ErrorText(err, arg)
    if arg ~= nil then
        return L[err]:format(type(arg) == "string" and UI.QuestText(arg) or arg)
    end
    return L[err]
end

-- Human-readable objective text (already escaped).
function UI.ObjectiveLabel(obj)
    local t = obj.type
    if t == "item" then
        return Util.SafeText(ns.api.GetItemName(obj.itemID) or L["ITEM_N"]:format(obj.itemID))
    elseif t == "kill" then
        if obj.npcID then
            local name = obj.name and obj.name ~= "" and obj.name or L["NPC_N"]:format(obj.npcID)
            if obj.mapID then return L["KILL_IN"]:format(Util.SafeText(name), mapName(obj.mapID)) end
            return Util.SafeText(name)
        end
        return L["KILL_ANY_IN"]:format(mapName(obj.mapID))
    elseif t == "boss" then
        return Util.SafeText(obj.name and obj.name ~= "" and obj.name or L["ENCOUNTER_N"]:format(obj.encounterID))
    elseif t == "zone" or t == "subzone" then
        if obj.name and obj.name ~= "" then return L["GO_TO"]:format(Util.SafeText(obj.name)) end
        return L["GO_TO"]:format(mapName(obj.mapID))
    elseif t == "location" then
        return L["REACH"]:format(mapName(obj.mapID), obj.x * 100, obj.y * 100)
    elseif t == "level" then
        return L["REACH_LEVEL"]:format(obj.level)
    elseif t == "manual" then
        return UI.QuestText(obj.text)
    end
    return "?"
end

-- "Label: 3/10", or just the label with a check mark for 0/1 objectives.
function UI.ObjectiveLine(quest, i, obj)
    local value = quest.progress[i] or 0
    local goal = ns.Objectives.Goal(obj)
    local done = value >= goal
    local text = UI.ObjectiveLabel(obj)
    if obj.type ~= "zone" and obj.type ~= "subzone" and obj.type ~= "location" and obj.type ~= "level" then
        text = ("%s: %d/%d"):format(text, value, goal)
    end
    if quest.approx and quest.approx[i] then text = text .. " " .. UI.APPROX_ICON end
    if done then text = "|cff20ff20" .. text .. "|r" end
    return text, done
end

-- Widgets ------------------------------------------------------------------

function UI.CreateWindow(name, width, height, title)
    local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    if not f.TitleText then
        f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.TitleText:SetPoint("TOP", 0, -5)
    end
    f.TitleText:SetText(title)
    if name then tinsert(UISpecialFrames, name) end
    return f
end

function UI.CreateButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function UI.CreateEditBox(parent, width, numeric)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    if numeric then e:SetMaxLetters(10) end
    return e
end

function UI.CreateLabel(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

-- Multi-line edit box inside a scroll frame. Returns container, editBox.
function UI.CreateTextArea(parent, width, height)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(width, height)
    holder:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    holder:SetBackdropColor(0, 0, 0, 0.6)
    local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(width - 36)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    scroll:SetScrollChild(edit)
    holder:SetScript("OnMouseDown", function() edit:SetFocus() end)
    return holder, edit
end

-- Blizzard menu dropdown (Blizzard_Menu, Retail 11+).
-- getItems() returns { { value = any, text = string, icon = texture? } };
-- the selected item is the one whose value equals getValue(). Use false, not
-- nil, as the value of a "none" entry.
function UI.CreateDropdown(parent, width, getItems, getValue, onSelect)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetWidth(width)
    dd:SetupMenu(function(_, root)
        local items = getItems()
        if #items > 15 then root:SetScrollMode(15 * 20) end
        for _, item in ipairs(items) do
            local text = item.icon and ("|T" .. item.icon .. ":14|t " .. item.text) or item.text
            root:CreateRadio(text,
                function(value) return (getValue() or false) == value end,
                function(value) onSelect(value) end,
                item.value)
        end
    end)
    -- Re-reads getValue() to update the shown text after outside changes.
    function dd:Refresh() self:GenerateMenu() end
    return dd
end

-- Items for a fixed list of values with translated labels.
function UI.EnumItems(values, labelFn)
    local items = {}
    for _, v in ipairs(values) do items[#items + 1] = { value = v, text = labelFn(v) } end
    return items
end

function UI.FormatDate(timestamp)
    return timestamp and date("%Y-%m-%d %H:%M", timestamp) or "-"
end

function UI.FormatDuration(seconds)
    seconds = math.max(0, seconds or 0)
    local d = math.floor(seconds / 86400)
    local h = math.floor(seconds % 86400 / 3600)
    local m = math.floor(seconds % 3600 / 60)
    if d > 0 then return L["DURATION_DH"]:format(d, h) end
    if h > 0 then return L["DURATION_HM"]:format(h, m) end
    return L["DURATION_M"]:format(m)
end
