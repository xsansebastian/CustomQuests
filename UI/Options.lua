local _, ns = ...

local L, UI, Model = ns.L, ns.UI, ns.Model
local Style = UI.Style

-- Appearance settings for the tracker, shown in the game's Options > AddOns >
-- CustomQuests: font and size, background and border. Values live in
-- Model.account.options; every change goes through Style.Set, which restyles
-- the tracker at once.
local Options = {}
ns.Options = Options

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CONTENT_WIDTH, CONTENT_HEIGHT = 560, 560

local panel, category
local controls = {} -- everything that must re-read its value (after Reset, on show)

-- The panel's own labels use plain font strings, so a big text size can't break its layout.
local function text(parent, str, x, y, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(str)
    return fs
end

local function header(parent, str, y)
    text(parent, str, 0, y, "GameFontNormalLarge")
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetPoint("TOPLEFT", 0, y - 22)
    line:SetSize(CONTENT_WIDTH, 1)
end

-- Plain horizontal slider with its value written to the right.
local function slider(parent, x, y, width, min, max, step, get, set, format)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", x, y)
    s:SetSize(width, 14)
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:GetThumbTexture():SetSize(24, 24)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.value = text(parent, "", x + width + 8, y - 1, "GameFontHighlightSmall")

    local syncing = false
    s:SetScript("OnValueChanged", function(_, value)
        s.value:SetText(format(value))
        if not syncing then set(value) end
    end)
    function s:Refresh()
        syncing = true
        self:SetValue(get())
        s.value:SetText(format(get()))
        syncing = false
    end
    controls[#controls + 1] = s
    return s
end

-- Colour swatch; opens the game's colour picker.
local function swatch(parent, x, y, get, set)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(24, 24)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropBorderColor(1, 1, 1, 1)
    function b:Refresh()
        local c = get()
        self:SetBackdropColor(c[1], c[2], c[3], 1)
    end
    b:SetScript("OnClick", function()
        local c = get()
        local r, g, bl = c[1], c[2], c[3]
        local function picked()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            set({ nr, ng, nb })
            b:Refresh()
        end
        local function cancelled()
            set({ r, g, bl })
            b:Refresh()
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = bl, hasOpacity = false, swatchFunc = picked, cancelFunc = cancelled,
            })
        else -- clients before the 10.2.5 colour picker
            ColorPickerFrame.func, ColorPickerFrame.cancelFunc, ColorPickerFrame.hasOpacity = picked, cancelled, false
            ColorPickerFrame:SetColorRGB(r, g, bl)
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end)
    controls[#controls + 1] = b
    return b
end

local function dropdown(parent, x, y, width, getItems, get, set)
    local dd = UI.CreateDropdown(parent, width, getItems, get, set)
    dd:SetPoint("TOPLEFT", x, y)
    controls[#controls + 1] = dd
    return dd
end

-- Panel ------------------------------------------------------------------------------------

local function fontItems()
    local items = {}
    for _, choice in ipairs(Style.FontChoices(L["OPT_FONT_DEFAULT"])) do
        items[#items + 1] = { value = choice.value, text = choice.name }
    end
    return items
end

local function borderItems()
    local items = {}
    for _, style in ipairs(Model.BORDER_STYLES) do
        items[#items + 1] = { value = style, text = L["OPT_BORDER_" .. style:upper()] }
    end
    return items
end

local function percent(value) return ("%d%%"):format(value) end

local function refreshAll()
    for _, control in ipairs(controls) do control:Refresh() end
end

local function build(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, CONTENT_HEIGHT)
    scroll:SetScrollChild(content)

    -- Live sample: a box and text styled exactly like the tracker.
    local box = CreateFrame("Frame", nil, content, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 0, 0)
    box:SetSize(CONTENT_WIDTH, 64)
    Style.Box(box)
    local title = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    title:SetText("|cffffd200" .. L["OPT_SAMPLE_QUEST"] .. "|r")
    Style.Text(title)
    local objective = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    objective:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 8, -3)
    objective:SetText("- " .. L["OPT_SAMPLE_OBJECTIVE"])
    Style.Text(objective)

    header(content, L["OPT_TRACKER"], -84)
    local function cfg() return Style.Options().tracker end

    text(content, L["OPT_FONT"], 0, -122)
    dropdown(content, 150, -118, 190, fontItems,
        function() return Style.Options().font end,
        function(value) Style.Set(nil, "font", value) end)

    text(content, L["OPT_SCALE"], 0, -154)
    slider(content, 154, -152, 160, Model.SCALE_MIN, Model.SCALE_MAX, 5,
        function() return Style.Options().scale end,
        function(value) Style.Set(nil, "scale", value) end, percent)

    text(content, L["OPT_BG"], 0, -190)
    swatch(content, 150, -186,
        function() return cfg().bg end,
        function(color) Style.Set("tracker", "bg", color) end)
    text(content, L["OPT_OPACITY"], 290, -190)
    slider(content, 410, -188, 100, 0, 100, 5,
        function() return math.floor(cfg().bgAlpha * 100 + 0.5) end,
        function(value) Style.Set("tracker", "bgAlpha", value / 100) end, percent)

    text(content, L["OPT_BORDER"], 0, -226)
    dropdown(content, 150, -222, 130, borderItems,
        function() return cfg().border end,
        function(value) Style.Set("tracker", "border", value) end)
    text(content, L["OPT_BORDER_COLOR"], 290, -226)
    swatch(content, 410, -222,
        function() return cfg().borderColor end,
        function(color) Style.Set("tracker", "borderColor", color) end)

    -- The name written on the tracker's banner; empty goes back to the default.
    text(content, L["OPT_TITLE"], 0, -262)
    local titleBox = UI.CreateEditBox(content, 190)
    titleBox:SetPoint("TOPLEFT", 156, -258)
    titleBox:SetMaxLetters(Model.MAX_TRACKER_TITLE)
    titleBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then Style.Set(nil, "title", self:GetText()) end
    end)
    function titleBox:Refresh() self:SetText(Model.CleanTrackerTitle(Style.Options().title)) end
    titleBox:SetScript("OnEditFocusLost", titleBox.Refresh)
    controls[#controls + 1] = titleBox

    local reset = UI.CreateButton(content, L["OPT_RESET"], 160, function()
        Style.Reset()
        refreshAll()
    end)
    reset:SetPoint("TOPLEFT", 0, -314)

    -- Sharing: whose offers pop up, chat links, and the blocked players.
    header(content, L["OPT_SHARING"], -360)
    local function sharing() return Model.SharingOptions() end
    text(content, L["OPT_SHARE_INCOMING"], 0, -398)
    dropdown(content, 230, -394, 210, function()
        local items = {}
        for _, value in ipairs(Model.SHARE_INCOMING) do
            items[#items + 1] = { value = value, text = L["OPT_SHARE_" .. value:upper()] }
        end
        return items
    end, function() return sharing().incoming end, function(value) sharing().incoming = value end)

    local links = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    links:SetPoint("TOPLEFT", -4, -428)
    links:SetSize(24, 24)
    text(content, L["OPT_SHARE_LINKS"], 24, -433)
    links:SetScript("OnClick", function(self) sharing().chatLinks = self:GetChecked() and true or false end)
    function links:Refresh() self:SetChecked(sharing().chatLinks) end
    controls[#controls + 1] = links

    local unblock = UI.CreateButton(content, "", 200, function(self)
        Model.ClearShareBlocked()
        ns.api.Print(L["OPT_SHARE_CLEARED"])
        self:Refresh()
    end)
    unblock:SetPoint("TOPLEFT", 0, -464)
    function unblock:Refresh()
        local n = Model.account and Model.CountShareBlocked() or 0
        self:SetText(L["OPT_SHARE_CLEAR_BLOCKED"]:format(n))
        self:SetEnabled(n > 0)
    end
    controls[#controls + 1] = unblock

    local help = text(content, L["OPT_SHARE_HELP"], 0, -500, "GameFontHighlightSmall")
    help:SetWidth(CONTENT_WIDTH)

    parent:SetScript("OnShow", refreshAll)
    refreshAll()
end

-- Registers the panel in the game's settings, under Options > AddOns.
function Options.Init()
    if panel or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    panel = CreateFrame("Frame")
    panel.name = "CustomQuests"
    build(panel)
    category = Settings.RegisterCanvasLayoutCategory(panel, "CustomQuests")
    Settings.RegisterAddOnCategory(category)
end

function Options.Open()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        ns.api.Print(L["OPT_UNAVAILABLE"])
    end
end
