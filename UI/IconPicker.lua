local _, ns = ...

local L, UI, Model = ns.L, ns.UI, ns.Model

-- Icon picker with the same catalogue as the macro window: Blizzard's
-- IconDataProviderMixin with the Spellbook extra type (your spells first,
-- then every spell and item icon). A "recent" row sits on top.
local IconPicker = {}
ns.IconPicker = IconPicker

local COLUMNS, VISIBLE_ROWS, SIZE, GAP = 10, 7, 36, 4
local CELL = SIZE + GAP

local frame, provider, onPick
local recentButtons, gridButtons = {}, {}
local offset = 0

local function createIconButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIZE, SIZE)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b:SetScript("OnClick", function(self)
        local icon = Model.NormalizeIcon(self.texture)
        if not icon then return end
        Model.PushRecentIcon(icon)
        frame:Hide()
        if onPick then onPick(icon) end
    end)
    return b
end

local function numRows()
    return math.ceil(provider:GetNumIcons() / COLUMNS)
end

local function refreshGrid()
    local total = provider:GetNumIcons()
    for i, b in ipairs(gridButtons) do
        local index = offset * COLUMNS + i
        local texture = index <= total and provider:GetIconByIndex(index)
        b.texture = texture or nil
        b.tex:SetTexture(texture or nil)
        b:SetShown(texture ~= nil and texture ~= false)
    end
end

local function refreshRecent()
    local recent = Model.account.recentIcons
    for i, b in ipairs(recentButtons) do
        local icon = recent[i]
        b.texture = icon
        b.tex:SetTexture(icon and Model.IconTexture(icon))
        b:SetShown(icon ~= nil)
    end
    frame.noRecent:SetShown(#recent == 0)
end

local function setOffset(value)
    local maxOffset = math.max(0, numRows() - VISIBLE_ROWS)
    offset = math.max(0, math.min(maxOffset, math.floor(value + 0.5)))
    if frame.slider:GetValue() ~= offset then frame.slider:SetValue(offset) end
    refreshGrid()
end

local function create()
    frame = CreateFrame("Frame", "CustomQuestsIconPicker", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetSize(COLUMNS * CELL + 44, VISIBLE_ROWS * CELL + CELL + 104)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    tinsert(UISpecialFrames, "CustomQuestsIconPicker")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local recentLabel = UI.CreateLabel(frame, L["ICONS_RECENT"], "GameFontNormal")
    recentLabel:SetPoint("TOPLEFT", 12, -10)
    for i = 1, Model.MAX_RECENT_ICONS do
        local b = createIconButton(frame)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * CELL, -28)
        recentButtons[i] = b
    end
    frame.noRecent = UI.CreateLabel(frame, L["ICONS_NO_RECENT"], "GameFontDisableSmall")
    frame.noRecent:SetPoint("TOPLEFT", 14, -40)

    local allLabel = UI.CreateLabel(frame, L["ICONS_ALL"], "GameFontNormal")
    allLabel:SetPoint("TOPLEFT", 12, -30 - CELL)
    local gridTop = -48 - CELL
    for row = 1, VISIBLE_ROWS do
        for col = 1, COLUMNS do
            local b = createIconButton(frame)
            b:SetPoint("TOPLEFT", 12 + (col - 1) * CELL, gridTop - (row - 1) * CELL)
            gridButtons[#gridButtons + 1] = b
        end
    end

    -- Plain vertical slider: works without Blizzard scroll templates.
    local slider = CreateFrame("Slider", nil, frame, "BackdropTemplate")
    slider:SetOrientation("VERTICAL")
    slider:SetPoint("TOPLEFT", 16 + COLUMNS * CELL, gridTop)
    slider:SetSize(14, VISIBLE_ROWS * CELL - GAP)
    slider:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", tile = true, tileSize = 8 })
    slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetScript("OnValueChanged", function(_, value) setOffset(value) end)
    frame.slider = slider

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) setOffset(offset - delta * 2) end)

    -- Any other icon by file name or file ID.
    local customLabel = UI.CreateLabel(frame, L["ICON_CUSTOM"], "GameFontDisableSmall")
    customLabel:SetPoint("BOTTOMLEFT", 12, 34)
    local edit = UI.CreateEditBox(frame, 220)
    edit:SetPoint("BOTTOMLEFT", 16, 10)
    local ok = UI.CreateButton(frame, OKAY, 70, function()
        local text = edit:GetText():match("^%s*(.-)%s*$")
        local icon = Model.NormalizeIcon(tonumber(text) or text)
        if not icon then return end
        Model.PushRecentIcon(icon)
        frame:Hide()
        if onPick then onPick(icon) end
    end)
    ok:SetPoint("LEFT", edit, "RIGHT", 8, 0)
    edit:SetScript("OnEnterPressed", function() ok:Click() end)
    frame.edit = edit

    -- The provider holds the whole icon list in memory; free it when closed.
    frame:SetScript("OnHide", function()
        if provider then provider:Release() provider = nil end
    end)
end

function IconPicker.Open(anchor, callback)
    if not frame then create() end
    onPick = callback
    if not provider then
        provider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.Spellbook)
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    frame.slider:SetMinMaxValues(0, math.max(0, numRows() - VISIBLE_ROWS))
    frame.edit:SetText("")
    offset = 0
    frame.slider:SetValue(0)
    refreshRecent()
    refreshGrid()
    frame:Show()
end
