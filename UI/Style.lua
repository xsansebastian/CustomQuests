local _, ns = ...

local Model, Util, UI = ns.Model, ns.Util, ns.UI

-- Applies the appearance options (Model.account.options) to the tracker: the
-- font and size of its text, and its background and border. Nothing is stored
-- here: registered text and boxes are re-styled from the options each time
-- Style.Refresh() runs.
local Style = {}
UI.Style = Style

-- Fonts the game always ships. "default" (the game's own font, Friz Quadrata in
-- most languages) is not repeated here.
local FONT_PATHS = {
    ARIALN = "Fonts\\ARIALN.TTF",
    SKURRI = "Fonts\\SKURRI.TTF",
    MORPHEUS = "Fonts\\MORPHEUS.TTF",
}
local FONT_NAMES = { ARIALN = "Arial Narrow", SKURRI = "Skurri", MORPHEUS = "Morpheus" }

local WHITE = "Interface\\Buttons\\WHITE8X8"
local EDGES = {
    thin = { file = WHITE, size = 1, inset = 1 },
    tooltip = { file = "Interface\\Tooltips\\UI-Tooltip-Border", size = 12, inset = 3 },
}

local texts, boxes = {}, {}

function Style.Options()
    return Model.account and Model.account.options or Model.DefaultOptions()
end

-- Fonts from SharedMedia, when that library is installed (many addons add fonts to it).
local function sharedMedia()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function fontPath(key)
    if FONT_PATHS[key] then return FONT_PATHS[key] end
    local lsm = sharedMedia()
    return lsm and key ~= "default" and lsm:Fetch("font", key, true) or nil
end

-- Whether the game can load this font file. SetFont fails quietly on a bad file
-- (and the text would keep its old font), so every font is checked first.
local probe
local usable = {}

local function canLoad(path)
    if usable[path] == nil then
        probe = probe or UIParent:CreateFontString(nil, "OVERLAY")
        usable[path] = probe:SetFont(path, 12, "") and true or false
    end
    return usable[path]
end

-- Items for a font dropdown: { value = key, name = shown name }.
function Style.FontChoices(defaultName)
    local items = { { value = "default", name = defaultName } }
    for _, key in ipairs(Model.FONT_KEYS) do
        if key ~= "default" and canLoad(FONT_PATHS[key]) then items[#items + 1] = { value = key, name = FONT_NAMES[key] } end
    end
    local lsm = sharedMedia()
    if lsm then
        local names = {}
        for name, path in pairs(lsm:HashTable("font")) do
            if not FONT_PATHS[name] and canLoad(path) then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do items[#items + 1] = { value = name, name = name } end
    end
    return items
end

-- Text -------------------------------------------------------------------------------

local function applyText(fs)
    local base, o = fs.cqBase, Style.Options()
    local path = fontPath(o.font) or base.path
    -- Untouched while the options are at their defaults, so the stock look is exact.
    if path == base.path and o.scale == 100 then
        if fs.cqChanged then fs:SetFont(base.path, base.size, base.flags) fs.cqChanged = nil end
        return
    end
    if fs:SetFont(path, base.size * o.scale / 100, base.flags) then
        fs.cqChanged = true
    else -- the font couldn't be loaded: show the default rather than a stale font
        fs:SetFont(base.path, base.size * o.scale / 100, base.flags)
        fs.cqChanged = o.scale ~= 100 or nil
    end
end

-- Registers a FontString; its current font becomes the "default" it returns to.
function Style.Text(fs)
    local path, size, flags = fs:GetFont()
    if not path then return fs end
    fs.cqBase = { path = path, size = size, flags = flags }
    texts[#texts + 1] = fs
    applyText(fs)
    return fs
end

-- Box (a frame with BackdropTemplate) ----------------------------------------------

local function applyBox(frame)
    local cfg = Style.Options().tracker
    local edge = EDGES[cfg.border]
    local backdrop = { bgFile = WHITE, insets = { left = 0, right = 0, top = 0, bottom = 0 } }
    if edge then
        backdrop.edgeFile, backdrop.edgeSize = edge.file, edge.size
        backdrop.insets = { left = edge.inset, right = edge.inset, top = edge.inset, bottom = edge.inset }
    end
    frame:SetBackdrop(backdrop)
    frame:SetBackdropColor(cfg.bg[1], cfg.bg[2], cfg.bg[3], cfg.bgAlpha)
    if edge then frame:SetBackdropBorderColor(cfg.borderColor[1], cfg.borderColor[2], cfg.borderColor[3], 1) end
end

function Style.Box(frame)
    boxes[#boxes + 1] = frame
    applyBox(frame)
    return frame
end

-- Changes -------------------------------------------------------------------------------

function Style.Refresh()
    for _, fs in ipairs(texts) do applyText(fs) end
    for _, frame in ipairs(boxes) do applyBox(frame) end
    Util.Fire("STYLE_CHANGED")
end

-- Sets one option (key under "tracker", or a top-level one when section is nil).
function Style.Set(section, key, value)
    local o = Style.Options()
    if section then o[section][key] = value else o[key] = value end
    Style.Refresh()
end

function Style.Reset()
    -- The sharing settings aren't appearance: Reset leaves them alone.
    local sharing = Model.account.options.sharing
    Model.account.options = Model.DefaultOptions()
    Model.account.options.sharing = sharing
    Style.Refresh()
end
