local _, ns = ...

local L, UI = ns.L, ns.UI

-- Popup shown when the player gets close to an NPC of a "near" objective that
-- has a popup text: the NPC's portrait, its name and what it says (scrolls
-- when it doesn't fit).
local NPCTalk = {}
ns.NPCTalk = NPCTalk

local WIDTH, HEIGHT = 338, 496 -- the size of the game's quest window
local PORTRAIT = 120 -- a quarter of the window's width, about
local window

local function create()
    window = UI.CreateWindow("CustomQuestsNPCTalk", WIDTH, HEIGHT, "")

    -- The portrait frame: a dark box in the top left corner with the NPC on it.
    local frame = CreateFrame("Frame", nil, window, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", 16, -34)
    frame:SetSize(PORTRAIT, PORTRAIT)
    frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8", edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(0, 0, 0, 0.6)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    window.model = CreateFrame("PlayerModel", nil, frame)
    window.model:SetPoint("TOPLEFT", 2, -2)
    window.model:SetPoint("BOTTOMRIGHT", -2, 2)

    window.name = UI.CreateLabel(window, "", "GameFontNormalLarge")
    window.name:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -8)
    window.name:SetPoint("RIGHT", window, "RIGHT", -16, 0)
    window.name:SetJustifyH("LEFT")

    window.scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    window.scroll:SetPoint("TOPLEFT", window.name, "BOTTOMLEFT", 0, -8)
    window.scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -34, 50)
    window.content = CreateFrame("Frame", nil, window.scroll)
    window.content:SetSize(1, 1)
    window.scroll:SetScrollChild(window.content)
    window.text = UI.CreateLabel(window.content, "", "GameFontHighlight")
    window.text:SetPoint("TOPLEFT")
    window.text:SetJustifyH("LEFT")
    window.text:SetJustifyV("TOP")
    window.text:SetSpacing(2)

    UI.CreateButton(window, CLOSE, 100, function() window:Hide() end):SetPoint("BOTTOMRIGHT", -16, 14)
end

-- obj: a near objective (npcID, name, dialog); questTitle goes on the window's title bar.
function NPCTalk.Show(obj, questTitle)
    if not window then create() end
    window.TitleText:SetText(UI.QuestText(questTitle or ""))
    window.name:SetText(UI.QuestText(obj.name and obj.name ~= "" and obj.name or L["NPC_N"]:format(obj.npcID)))
    window:Show()
    -- The scroll area has its size once the window is shown.
    local width = math.max(1, window.scroll:GetWidth())
    window.content:SetWidth(width)
    window.text:SetWidth(width)
    window.text:SetText(UI.QuestText(obj.dialog or ""))
    window.content:SetHeight(math.max(1, window.text:GetStringHeight() + 4))
    window.scroll:SetVerticalScroll(0)
    -- A creature id with no model leaves the box empty instead of failing.
    pcall(function()
        window.model:ClearModel()
        window.model:SetCreature(obj.npcID)
        window.model:SetPortraitZoom(1)
    end)
end
