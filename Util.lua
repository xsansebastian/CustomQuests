local _, ns = ...

-- Pure helpers with no WoW API dependencies (covered by tests/run.lua).
local Util = {}
ns.Util = Util

function Util.DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = Util.DeepCopy(v) end
    return copy
end

-- Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID (also Vehicle).
function Util.NPCIDFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local unitType, npcID = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if unitType == "Creature" or unitType == "Vehicle" then
        return tonumber(npcID)
    end
end

-- Accepts a plain number or an item link pasted with shift-click.
function Util.ParseItemID(text)
    if type(text) == "number" then return text end
    if type(text) ~= "string" then return nil end
    return tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
end

-- User and imported text is shown literally: no raw colour codes, links or
-- textures. The only formatting is [color=rrggbb]...[/color], which is turned
-- into a real colour code here and always closed.
function Util.SafeText(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|", "||")
    local open = 0
    text = text:gsub("%[(/?)color=?(%x*)%]", function(slash, hex)
        if slash == "" and #hex == 6 then
            open = open + 1
            return "|cff" .. hex
        elseif slash == "/" and hex == "" and open > 0 then
            open = open - 1
            return "|r"
        end
    end)
    return text .. ("|r"):rep(open)
end

-- Cuts text to at most maxBytes without splitting a UTF-8 character.
function Util.TruncateUTF8(text, maxBytes)
    if #text <= maxBytes then return text end
    local cut = maxBytes
    -- Byte cut + 1 must start a character; step back while it continues one.
    while cut > 0 do
        local b = text:byte(cut + 1)
        if b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return text:sub(1, cut)
end

-- Text another player controls (a shared quest's title, a chat link label, a
-- name) made harmless for a popup, a chat line or a link: no escape codes,
-- no brackets or colons that could close a link and fake another, no control
-- characters or line breaks, at most maxBytes. Shown as is, never formatted.
function Util.SafeLabel(text, maxBytes)
    if type(text) ~= "string" then return "" end
    text = text:gsub("[%c|%[%]:~]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    return (Util.TruncateUTF8(text, maxBytes or 40):match("^(.-)%s*$"))
end

-- Replaces {name}, {class}, {race} with values from vars; unknown tokens stay.
-- Run after SafeText so substituted values may carry colour codes.
function Util.ExpandTokens(text, vars)
    if type(text) ~= "string" then return "" end
    return (text:gsub("{(%a+)}", function(key) return vars[key] end))
end

-- Simple event bus for UI refreshes.
local listeners = {}

function Util.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function Util.Fire(event, ...)
    for _, fn in ipairs(listeners[event] or {}) do fn(...) end
end
