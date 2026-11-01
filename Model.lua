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

-- Icons are an Interface/Icons file name ("INV_Misc_Book_09") or a file ID.
function Model.ValidIcon(icon)
    if type(icon) == "number" and icon == math.floor(icon) and icon > 0 and icon < 1e9 then return icon end
    if type(icon) == "string" and #icon <= 80 and icon:match("^[%w_%-]+$") then return icon end
end

-- Converts what the icon provider returns (file ID or full texture path)
-- into the stored form: a file ID or a bare file name.
function Model.NormalizeIcon(texture)
    if type(texture) == "number" then return Model.ValidIcon(texture) end
    if type(texture) ~= "string" then return nil end
    return Model.ValidIcon(tonumber(texture) or texture:match("([^/\\]+)$"))
end

Model.MAX_RECENT_ICONS = 10

-- Most recent first, no duplicates.
function Model.PushRecentIcon(icon)
    icon = Model.ValidIcon(icon)
    if not icon then return end
    local list = Model.account.recentIcons
    for i = #list, 1, -1 do
        if list[i] == icon then table.remove(list, i) end
    end
    table.insert(list, 1, icon)
    while #list > Model.MAX_RECENT_ICONS do table.remove(list) end
end

function Model.IconTexture(icon)
    if type(icon) == "number" then return icon end
    if type(icon) == "string" then return "Interface\\Icons\\" .. icon end
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
        icon = Model.ValidIcon(tpl.icon),
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
    accountDB.recentIcons = accountDB.recentIcons or {}
    accountDB.minimap = accountDB.minimap or { angle = 225, hidden = false }
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

-- Sorted by title for stable lists.
function Model.ListTemplates()
    local list = {}
    for id, tpl in pairs(Model.account.templates) do list[#list + 1] = { id = id, template = tpl } end
    table.sort(list, function(a, b) return a.template.title:lower() < b.template.title:lower() end)
    return list
end

function Model.NewEmptyTemplate()
    return {
        title = "", kind = "personal", repeatMode = "none",
        stages = { { text = "", objectives = { { type = "manual", text = "", count = 1 } } } },
    }
end

Model.DeepCopy = Util.DeepCopy
