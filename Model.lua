local _, ns = ...

local Util = ns.Util
local Model = {}
ns.Model = Model

Model.SCHEMA = 1
Model.MAX_STAGES = 20
Model.MAX_OBJECTIVES = 10
Model.MAX_TEXT = 500
Model.MAX_TITLE = 80

Model.OBJECTIVE_TYPES = { "item", "kill", "boss", "zone", "subzone", "location", "level", "manual" }
Model.KINDS = { "personal", "rp" }
Model.REPEAT_MODES = { "none", "daily", "weekly" }

local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

-- Per-type allowed fields: name -> "number" | "string" | "boolean".
local OBJECTIVE_FIELDS = {
    item     = { itemID = "number", count = "number" },
    kill     = { npcID = "number", name = "string", mapID = "number", count = "number", fallbackAny = "boolean" },
    boss     = { encounterID = "number", name = "string", count = "number" },
    zone     = { mapID = "number" },
    subzone  = { name = "string", mapID = "number" }, -- name as shown on the minimap
    location = { mapID = "number", x = "number", y = "number", radius = "number" },
    level    = { level = "number" },
    manual   = { text = "string", count = "number" },
}
Model.OBJECTIVE_FIELDS = OBJECTIVE_FIELDS

local function cleanString(value, maxLen)
    if type(value) ~= "string" then return nil end
    -- Stored raw; UI escapes "|" with Util.SafeText when rendering.
    if #value > maxLen then value = value:sub(1, maxLen) end
    return value
end

local function clamp(n, lo, hi)
    if n < lo then return lo elseif n > hi then return hi end
    return n
end

-- Returns a sanitized copy containing only known fields, or nil and an error key.
function Model.ValidateObjective(obj)
    -- Zone objectives saved with a name were subzones before the two were split.
    if type(obj) == "table" and obj.type == "zone" and type(obj.name) == "string" and not obj.name:match("^%s*$") then
        local copy = {}
        for k, v in pairs(obj) do copy[k] = v end
        copy.type = "subzone"
        obj = copy
    end
    if type(obj) ~= "table" or not OBJECTIVE_FIELDS[obj.type] then return nil, "ERR_BAD_OBJECTIVE" end
    local clean = { type = obj.type }
    for field, kind in pairs(OBJECTIVE_FIELDS[obj.type]) do
        local v = obj[field]
        if kind == "number" and type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
            clean[field] = v
        elseif kind == "string" then
            clean[field] = cleanString(v, Model.MAX_TEXT)
        elseif kind == "boolean" and type(v) == "boolean" then
            clean[field] = v
        end
    end

    local t = clean.type
    if t == "item" and not clean.itemID then return nil, "ERR_NEED_ITEM" end
    if t == "kill" and not clean.npcID and not clean.mapID then return nil, "ERR_NEED_NPC_OR_MAP" end
    if t == "boss" and not clean.encounterID then return nil, "ERR_NEED_ENCOUNTER" end
    if t == "subzone" and clean.name and clean.name:match("^%s*$") then clean.name = nil end
    if t == "subzone" and not clean.name then return nil, "ERR_NEED_SUBZONE" end
    if (t == "zone" or t == "location") and not clean.mapID then return nil, "ERR_NEED_MAP" end
    if t == "location" and not (clean.x and clean.y) then return nil, "ERR_NEED_COORDS" end
    if t == "manual" and (not clean.text or clean.text == "") then return nil, "ERR_NEED_TEXT" end
    if t == "level" and not clean.level then return nil, "ERR_NEED_LEVEL" end

    if clean.count then clean.count = clamp(math.floor(clean.count), 1, 100000) end
    if t == "item" or t == "kill" or t == "boss" or t == "manual" then clean.count = clean.count or 1 end
    if t == "level" then clean.level = clamp(math.floor(clean.level), 1, 200) end
    if t == "location" then
        clean.x = clamp(clean.x, 0, 1)
        clean.y = clamp(clean.y, 0, 1)
        clean.radius = clamp(clean.radius or 0.02, 0.001, 0.5)
    end
    return clean
end

function Model.ValidateTemplate(tpl)
    if type(tpl) ~= "table" then return nil, "ERR_BAD_TEMPLATE" end
    local title = cleanString(tpl.title, Model.MAX_TITLE)
    if not title or title:match("^%s*$") then return nil, "ERR_NEED_TITLE" end

    local clean = {
        title = title,
        kind = contains(Model.KINDS, tpl.kind) and tpl.kind or "personal",
        repeatMode = contains(Model.REPEAT_MODES, tpl.repeatMode) and tpl.repeatMode or "none",
        giver = cleanString(tpl.giver, Model.MAX_TITLE),
        description = cleanString(tpl.description, Model.MAX_TEXT),
        rewardText = cleanString(tpl.rewardText, Model.MAX_TEXT),
        completionText = cleanString(tpl.completionText, Model.MAX_TEXT),
        requires = type(tpl.requires) == "string" and #tpl.requires <= 64
            and tpl.requires:match("^[%w%-]+$") and tpl.requires or nil,
        stages = {},
    }

    -- Optional level range; 0 or empty means no limit.
    for _, key in ipairs({ "minLevel", "maxLevel" }) do
        local v = tpl[key]
        if type(v) == "number" and v == v and v >= 1 and v ~= math.huge then
            clean[key] = clamp(math.floor(v), 1, 200)
        end
    end
    if clean.minLevel and clean.maxLevel and clean.minLevel > clean.maxLevel then
        return nil, "ERR_LEVEL_RANGE"
    end

    if type(tpl.stages) ~= "table" or #tpl.stages == 0 then return nil, "ERR_NEED_STAGE" end
    if #tpl.stages > Model.MAX_STAGES then return nil, "ERR_TOO_MANY_STAGES" end
    for i, stage in ipairs(tpl.stages) do
        if type(stage) ~= "table" or type(stage.objectives) ~= "table" or #stage.objectives == 0 then
            return nil, "ERR_NEED_OBJECTIVE"
        end
        if #stage.objectives > Model.MAX_OBJECTIVES then return nil, "ERR_TOO_MANY_OBJECTIVES" end
        local cleanStage = { text = cleanString(stage.text, Model.MAX_TEXT), objectives = {} }
        for j, obj in ipairs(stage.objectives) do
            local cleanObj, err = Model.ValidateObjective(obj)
            if not cleanObj then return nil, err, i, j end
            cleanStage.objectives[j] = cleanObj
        end
        clean.stages[i] = cleanStage
    end
    return clean
end

-- Appearance options (tracker only) --------------------------------------------

-- Fonts the game ships; SharedMedia fonts are also accepted (any name up to 128 letters).
Model.FONT_KEYS = { "default", "ARIALN", "SKURRI", "MORPHEUS" }
Model.BORDER_STYLES = { "none", "thin", "tooltip" }
Model.SCALE_MIN, Model.SCALE_MAX = 70, 160

-- Defaults reproduce the look the tracker had before the options existed.
local OPTION_DEFAULTS = {
    font = "default",
    scale = 100,
    tracker = { bg = { 0, 0, 0 }, bgAlpha = 0, border = "none", borderColor = { 1, 0.82, 0 } },
}

local function validNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function cleanColor(color, default)
    local out = {}
    for i = 1, 3 do
        local v = type(color) == "table" and color[i]
        out[i] = validNumber(v) and clamp(v, 0, 1) or default[i]
    end
    return out
end

function Model.DefaultOptions()
    return Util.DeepCopy(OPTION_DEFAULTS)
end

-- Returns a complete, valid options table from whatever was saved (missing
-- parts filled in, anything unknown or out of range replaced by the default).
function Model.CleanOptions(saved)
    saved = type(saved) == "table" and saved or {}
    local d = OPTION_DEFAULTS.tracker
    local t = type(saved.tracker) == "table" and saved.tracker or {}
    local font = type(saved.font) == "string" and #saved.font > 0 and #saved.font <= 128 and saved.font
    return {
        font = font or OPTION_DEFAULTS.font,
        scale = validNumber(saved.scale) and clamp(math.floor(saved.scale + 0.5), Model.SCALE_MIN, Model.SCALE_MAX)
            or OPTION_DEFAULTS.scale,
        tracker = {
            bg = cleanColor(t.bg, d.bg),
            bgAlpha = validNumber(t.bgAlpha) and clamp(t.bgAlpha, 0, 1) or d.bgAlpha,
            border = contains(Model.BORDER_STYLES, t.border) and t.border or d.border,
            borderColor = cleanColor(t.borderColor, d.borderColor),
        },
    }
end

-- SavedVariables ------------------------------------------------------------

local idCounter = 0
function Model.NewID(prefix, now)
    idCounter = idCounter + 1
    -- Random suffix: the counter restarts after /reload within the same second.
    return string.format("%s-%d-%d-%d", prefix, now or 0, idCounter, math.random(1000, 9999))
end

function Model.InitDB(accountDB, charDB)
    accountDB = type(accountDB) == "table" and accountDB or {}
    charDB = type(charDB) == "table" and charDB or {}
    accountDB.schema = accountDB.schema or Model.SCHEMA
    accountDB.templates = accountDB.templates or {}
    accountDB.history = accountDB.history or {}
    accountDB.recentIcons = nil -- the icon picker is gone
    accountDB.chainCollapsed = type(accountDB.chainCollapsed) == "table" and accountDB.chainCollapsed or {}
    accountDB.minimap = accountDB.minimap or { angle = 225, hidden = false }
    accountDB.windowSizes = type(accountDB.windowSizes) == "table" and accountDB.windowSizes or {}
    accountDB.options = Model.CleanOptions(accountDB.options)
    charDB.schema = charDB.schema or Model.SCHEMA
    charDB.active = charDB.active or {}
    charDB.tracked = charDB.tracked or {}
    charDB.trackerShown = charDB.trackerShown ~= false
    Model.account = accountDB
    Model.char = charDB
    return accountDB, charDB
end

function Model.GetTemplate(id)
    return Model.account.templates[id]
end

-- Saves a validated copy; returns the id or nil and an error key.
function Model.SaveTemplate(tpl, id, now)
    local clean, err, stage, objective = Model.ValidateTemplate(tpl)
    if not clean then return nil, err, stage, objective end
    id = id or Model.NewID("t", now)
    if clean.requires then
        if not Model.account.templates[clean.requires] then
            clean.requires = nil
        elseif Model.WouldCycle(id, clean.requires) then
            return nil, "ERR_CHAIN_CYCLE"
        end
    end
    clean.createdAt = (Model.account.templates[id] and Model.account.templates[id].createdAt) or now
    Model.account.templates[id] = clean
    return id
end

-- True if making id require prerequisite would close a loop.
function Model.WouldCycle(id, prerequisite)
    local current = prerequisite
    for _ = 1, 100 do
        if not current then return false end
        if current == id then return true end
        local tpl = Model.account.templates[current]
        current = tpl and tpl.requires
    end
    return true
end

-- Templates whose prerequisite is id (the next links of a chain).
function Model.GetFollowUps(id)
    local list = {}
    for otherID, tpl in pairs(Model.account.templates) do
        if tpl.requires == id then list[#list + 1] = otherID end
    end
    table.sort(list)
    return list
end

-- Every template linked to id through prerequisites, prerequisites first.
function Model.GetChain(id)
    local root = id
    for _ = 1, 100 do
        local tpl = Model.account.templates[root]
        if not (tpl and tpl.requires and Model.account.templates[tpl.requires]) then break end
        root = tpl.requires
    end
    local ordered, queue, seen = {}, { root }, {}
    while #queue > 0 do
        local current = table.remove(queue, 1)
        if not seen[current] then
            seen[current] = true
            ordered[#ordered + 1] = current
            for _, nextID in ipairs(Model.GetFollowUps(current)) do queue[#queue + 1] = nextID end
        end
    end
    return ordered
end

-- Saves imported templates; entry.requires is an index into entries.
-- Returns the new ids in the same order.
function Model.SaveImported(entries, now)
    local ids = {}
    for i, entry in ipairs(entries) do
        local tpl = Util.DeepCopy(entry.template)
        tpl.requires = entry.requires and ids[entry.requires] or nil
        ids[i] = Model.SaveTemplate(tpl, nil, now)
    end
    return ids
end

-- Deleting a link keeps the chain whole: follow-ups inherit its prerequisite.
function Model.DeleteTemplate(id)
    local removed = Model.account.templates[id]
    for _, nextID in ipairs(Model.GetFollowUps(id)) do
        Model.account.templates[nextID].requires = removed and removed.requires
    end
    Model.account.templates[id] = nil
end

-- Every template that comes after id in its chain (follow-ups of follow-ups
-- included), not id itself. Sorted for a stable order.
function Model.GetDescendants(id)
    local found, queue, seen = {}, { id }, { [id] = true }
    local steps = 0
    while #queue > 0 and steps < 1000 do
        steps = steps + 1
        local current = table.remove(queue, 1)
        for _, nextID in ipairs(Model.GetFollowUps(current)) do
            if not seen[nextID] then
                seen[nextID] = true
                found[#found + 1] = nextID
                queue[#queue + 1] = nextID
            end
        end
    end
    table.sort(found)
    return found
end

-- True if one of ids has a direct follow-up that isn't in ids: deleting it then
-- needs a choice between the whole branch and just those templates.
function Model.NeedsBranchChoice(ids)
    local picked = {}
    for _, id in ipairs(ids) do picked[id] = true end
    for _, id in ipairs(ids) do
        for _, nextID in ipairs(Model.GetFollowUps(id)) do
            if not picked[nextID] then return true end
        end
    end
    return false
end

-- Deletes several templates at once. With withBranch everything after each one
-- goes too; without it their follow-ups are relinked, one deletion at a time.
function Model.DeleteTemplates(ids, withBranch)
    local doomed, order = {}, {}
    local function add(id)
        if not doomed[id] then
            doomed[id] = true
            order[#order + 1] = id
        end
    end
    for _, id in ipairs(ids) do
        add(id)
        if withBranch then
            for _, descendant in ipairs(Model.GetDescendants(id)) do add(descendant) end
        end
    end
    for _, id in ipairs(order) do Model.DeleteTemplate(id) end
end

-- Sorted by title for stable lists.
function Model.ListTemplates()
    local list = {}
    for id, tpl in pairs(Model.account.templates) do list[#list + 1] = { id = id, template = tpl } end
    table.sort(list, function(a, b) return a.template.title:lower() < b.template.title:lower() end)
    return list
end

-- The templates as a tree for the Templates list: standalone quests and chain
-- roots at depth 0, each follow-up one level below the quest it follows.
-- collapsed[id] hides the follow-ups of that quest. Rows: { id, depth,
-- hasChildren, collapsed, count } where count is the size of the whole subtree.
function Model.TemplateTree(collapsed)
    collapsed = collapsed or {}
    local entries = Model.ListTemplates()
    local order = {}
    for i, entry in ipairs(entries) do order[entry.id] = i end

    local function children(id)
        local list = Model.GetFollowUps(id)
        table.sort(list, function(a, b) return (order[a] or 0) < (order[b] or 0) end)
        return list
    end

    local reached = {}
    local function size(id, depth)
        if reached[id] or depth > 30 then return 0 end
        reached[id] = true
        local total = 1
        for _, child in ipairs(children(id)) do total = total + size(child, depth + 1) end
        return total
    end

    local rows, shown = {}, {}
    local function walk(id, depth)
        if shown[id] or depth > 30 then return end
        shown[id] = true
        local kids = children(id)
        local row = { id = id, depth = depth, hasChildren = #kids > 0, collapsed = collapsed[id] and #kids > 0 or false }
        rows[#rows + 1] = row
        if row.collapsed then return end
        for _, child in ipairs(kids) do walk(child, depth + 1) end
    end

    local roots = {}
    for _, entry in ipairs(entries) do
        local requires = entry.template.requires
        if not (requires and Model.account.templates[requires]) then roots[#roots + 1] = entry.id end
    end
    -- A broken loop has no root: its members still show up, as roots.
    for _, id in ipairs(roots) do size(id, 0) end
    for _, entry in ipairs(entries) do
        if not reached[entry.id] then roots[#roots + 1] = entry.id size(entry.id, 0) end
    end
    for _, id in ipairs(roots) do walk(id, 0) end
    for _, row in ipairs(rows) do
        reached = {}
        row.count = size(row.id, 0)
    end
    return rows
end

function Model.NewEmptyTemplate()
    return {
        title = "", kind = "personal", repeatMode = "none",
        stages = { { text = "", objectives = { { type = "manual", text = "", count = 1 } } } },
    }
end

Model.DeepCopy = Util.DeepCopy
