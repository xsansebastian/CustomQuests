local _, ns = ...

-- Template export/import. The payload is a small typed format wrapped in
-- base64 so it survives chat and edit boxes. Decoding never runs code.
local Serializer = {}
ns.Serializer = Serializer

Serializer.PREFIX = "CQ1:"
Serializer.MAX_LENGTH = 16384
Serializer.MAX_DEPTH = 8

-- Encoding -------------------------------------------------------------------
-- t<count>:<key><value>...   table with count pairs
-- s<len>:<bytes>             string
-- n<digits>;                 number (%.17g)
-- T / F                      booleans

local function encodeValue(value, out, depth)
    local kind = type(value)
    if kind == "string" then
        out[#out + 1] = "s" .. #value .. ":" .. value
    elseif kind == "number" then
        out[#out + 1] = "n" .. string.format("%.17g", value) .. ";"
    elseif kind == "boolean" then
        out[#out + 1] = value and "T" or "F"
    elseif kind == "table" then
        if depth >= Serializer.MAX_DEPTH then error("too deep") end
        local keys = {}
        for k in pairs(value) do
            local kt = type(k)
            if kt == "string" or kt == "number" then keys[#keys + 1] = k end
        end
        -- Deterministic output: numbers first in order, then strings.
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        out[#out + 1] = "t" .. #keys .. ":"
        for _, k in ipairs(keys) do
            encodeValue(k, out, depth + 1)
            encodeValue(value[k], out, depth + 1)
        end
    else
        error("unsupported type " .. kind)
    end
end

-- Decoding -------------------------------------------------------------------

local function decodeValue(s, pos, depth)
    local tag = s:sub(pos, pos)
    if tag == "s" then
        local len, colon = s:match("^(%d+)():", pos + 1)
        len = tonumber(len)
        if not len then return nil, pos, "bad string" end
        local startPos = colon + 1
        local endPos = startPos + len - 1
        if endPos > #s then return nil, pos, "truncated" end
        return s:sub(startPos, endPos), endPos + 1
    elseif tag == "n" then
        local digits, nextPos = s:match("^([%-%+%deE%.]+);()", pos + 1)
        local n = tonumber(digits)
        if not n or n ~= n or n == math.huge or n == -math.huge then return nil, pos, "bad number" end
        return n, nextPos
    elseif tag == "T" then
        return true, pos + 1
    elseif tag == "F" then
        return false, pos + 1
    elseif tag == "t" then
        if depth >= Serializer.MAX_DEPTH then return nil, pos, "too deep" end
        local count, nextPos = s:match("^(%d+):()", pos + 1)
        count = tonumber(count)
        if not count or count > 1000 then return nil, pos, "bad table" end
        local result = {}
        pos = nextPos
        for _ = 1, count do
            local k, v, err
            k, pos, err = decodeValue(s, pos, depth + 1)
            if err then return nil, pos, err end
            if type(k) ~= "string" and type(k) ~= "number" then return nil, pos, "bad key" end
            v, pos, err = decodeValue(s, pos, depth + 1)
            if err then return nil, pos, err end
            result[k] = v
        end
        return result, pos
    end
    return nil, pos, "unknown tag"
end

-- Base64 (arithmetic only: Lua 5.1 has no bit operators) ----------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for i = 1, 64 do DECODE[ALPHABET:sub(i, i)] = i - 1 end

local function toBase64(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = ALPHABET:sub(c1 + 1, c1 + 1) .. ALPHABET:sub(c2 + 1, c2 + 1)
            .. (b and ALPHABET:sub(c3 + 1, c3 + 1) or "=")
            .. (c and ALPHABET:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function fromBase64(text)
    text = text:gsub("%s", "")
    if #text % 4 ~= 0 or text:find("[^%w%+/=]") then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local chunk = text:sub(i, i + 3)
        local pad = select(2, chunk:gsub("=", ""))
        if pad > 2 or (pad > 0 and i + 3 < #text) then return nil end
        local n = 0
        for j = 1, 4 do
            local ch = chunk:sub(j, j)
            local v = ch == "=" and 0 or DECODE[ch]
            if not v then return nil end
            n = n * 64 + v
        end
        local b1 = math.floor(n / 65536) % 256
        local b2 = math.floor(n / 256) % 256
        local b3 = n % 256
        out[#out + 1] = string.char(b1)
        if pad < 2 then out[#out + 1] = string.char(b2) end
        if pad < 1 then out[#out + 1] = string.char(b3) end
    end
    return table.concat(out)
end

-- Public API -----------------------------------------------------------------

function Serializer.Encode(value)
    local out = {}
    encodeValue(value, out, 0)
    return Serializer.PREFIX .. toBase64(table.concat(out))
end

-- Returns the decoded table, or nil and an error key from ns.L.
function Serializer.Decode(text)
    if type(text) ~= "string" then return nil, "ERR_IMPORT_FORMAT" end
    text = text:match("^%s*(.-)%s*$")
    if #text > Serializer.MAX_LENGTH then return nil, "ERR_IMPORT_TOO_LONG" end
    if text:sub(1, #Serializer.PREFIX) ~= Serializer.PREFIX then return nil, "ERR_IMPORT_FORMAT" end
    local raw = fromBase64(text:sub(#Serializer.PREFIX + 1))
    if not raw then return nil, "ERR_IMPORT_FORMAT" end
    local value, pos, err = decodeValue(raw, 1, 0)
    if err or pos ~= #raw + 1 or type(value) ~= "table" then return nil, "ERR_IMPORT_CORRUPT" end
    return value
end

-- Sections travel by name: their ids mean nothing on another account. On
-- import the name is matched with a section of the same name or creates one.
local function sectionNameOf(tpl)
    local section = ns.Model.SectionByID(tpl.section)
    return section and section.name or nil
end

-- A name read from untrusted data, or nil.
local function readSectionName(value)
    return ns.Model.CleanSectionName(value)
end

-- Export only what a template needs; drops local fields like createdAt and
-- the prerequisite id, which means nothing on another account.
function Serializer.ExportTemplate(tpl)
    local clean = ns.Model.ValidateTemplate(tpl)
    if not clean then return nil end
    clean.requires = nil
    clean.sectionName = sectionNameOf(tpl)
    clean.section = nil
    return Serializer.Encode(clean)
end

local function chainEntries(ids)
    local Model = ns.Model
    local index, entries = {}, {}
    for i, templateID in ipairs(ids) do index[templateID] = i end
    for i, templateID in ipairs(ids) do
        local tpl = Model.GetTemplate(templateID)
        local clean = Model.ValidateTemplate(tpl)
        clean.requires = nil
        clean.section = nil
        entries[i] = { template = clean, requires = tpl.requires and index[tpl.requires], section = sectionNameOf(tpl) }
    end
    return entries
end

-- Exports the whole chain id belongs to. A lone template uses the plain
-- format; a chain is { chain = { { template, requires = index, section = name } ... } }.
function Serializer.ExportChain(id)
    local Model = ns.Model
    local ids = Model.GetChain(id)
    if #ids <= 1 then return Serializer.ExportTemplate(Model.GetTemplate(id)) end
    return Serializer.Encode({ chain = chainEntries(ids) })
end

-- Exports every quest of a section (nil when it has none). Links between them
-- are kept; a link to a quest outside the section is dropped. At most 50.
function Serializer.ExportSection(sectionID)
    local Model = ns.Model
    local members = {}
    for _, entry in ipairs(Model.ListTemplates()) do
        if Model.SectionOf(entry.template) == sectionID then members[entry.id] = true end
    end
    -- Prerequisites first, so every link points at an earlier entry.
    local ids, placed = {}, {}
    local progress = true
    while progress and #ids < 50 do
        progress = false
        for _, entry in ipairs(Model.ListTemplates()) do
            local id, requires = entry.id, entry.template.requires
            if members[id] and not placed[id] and (not (requires and members[requires]) or placed[requires]) then
                placed[id] = true
                ids[#ids + 1] = id
                progress = true
                if #ids >= 50 then break end
            end
        end
    end
    if #ids == 0 then return nil end
    return Serializer.Encode({ chain = chainEntries(ids) })
end

-- Returns a validated template, or nil and an error key.
function Serializer.ImportTemplate(text)
    local decoded, err = Serializer.Decode(text)
    if not decoded then return nil, err end
    local clean, validateErr = ns.Model.ValidateTemplate(decoded)
    if clean then clean.requires = nil clean.section = nil end
    return clean, validateErr
end

-- Accepts a single template or a chain. Returns a list of
-- { template, requires = earlier index, section = name } ready for Model.SaveImported.
function Serializer.Import(text)
    local decoded, err = Serializer.Decode(text)
    if not decoded then return nil, err end
    if type(decoded.chain) ~= "table" then
        local clean, validateErr = ns.Model.ValidateTemplate(decoded)
        if not clean then return nil, validateErr end
        clean.requires = nil
        clean.section = nil
        return { { template = clean, section = readSectionName(decoded.sectionName) } }
    end
    if #decoded.chain == 0 or #decoded.chain > 50 then return nil, "ERR_IMPORT_CORRUPT" end
    local entries = {}
    for i, entry in ipairs(decoded.chain) do
        local clean, validateErr = ns.Model.ValidateTemplate(type(entry) == "table" and entry.template)
        if not clean then return nil, validateErr end
        clean.requires = nil
        clean.section = nil
        -- Only links to an earlier entry are allowed, so imports can't form loops.
        local req = type(entry.requires) == "number" and entry.requires
        entries[i] = {
            template = clean,
            requires = req and req >= 1 and req < i and math.floor(req) == req and req or nil,
            section = readSectionName(entry.section),
        }
    end
    return entries
end
