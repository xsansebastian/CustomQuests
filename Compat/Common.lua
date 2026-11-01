local ADDON_NAME, ns = ...

-- One adapter and one package for Retail and Forever. Every client-specific API
-- call goes through ns.api so the shared modules stay testable offline. The
-- client is told apart by build number (as EllesmereUI does), not project ID.
local build = select(4, GetBuildInfo()) or 0
if build >= 16000 and build < 20000 then
    ns.target = "forever"
elseif build >= 120000 then
    ns.target = "retail"
end

local api = {}
ns.api = api

-- False on any client this package isn't made for (e.g. Classic Era).
function api.IsExpectedClient()
    return ns.target ~= nil
end

function api.GetMetadata(field)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return get and get(ADDON_NAME, field)
end

function api.Now()
    return time()
end

-- Secret values (12.x) must never be compared, indexed or concatenated.
function api.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

-- Bank included (bank, reagent bank, account bank), so moving items between
-- bags and bank doesn't make the progress drop and count again.
function api.GetItemCount(itemID)
    return (C_Item and C_Item.GetItemCount or GetItemCount)(itemID, true, false, true, true) or 0
end

function api.GetItemName(itemID)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(itemID) end
    return (GetItemInfo(itemID))
end

function api.GetPlayerMapID()
    return C_Map.GetBestMapForUnit("player")
end

-- Name of the subzone as the minimap shows it (falls back to the zone name).
function api.GetSubZoneName()
    local name = GetMinimapZoneText and GetMinimapZoneText()
    if not name or name == "" or api.IsSecret(name) then name = GetSubZoneText and GetSubZoneText() end
    if not name or name == "" or api.IsSecret(name) then return nil end
    return name
end

-- Set of lowercase names that count as "where the player is now".
function api.GetSubZoneNames()
    local names = {}
    for _, name in ipairs({ GetMinimapZoneText and GetMinimapZoneText() or "",
                            GetSubZoneText and GetSubZoneText() or "" }) do
        if name ~= "" and not api.IsSecret(name) then names[name:lower()] = true end
    end
    return names
end

function api.GetMapName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name
end

-- True when mapID is ancestor or the map itself (a city counts inside its zone).
function api.IsMapInside(mapID, ancestorID)
    for _ = 1, 10 do
        if not mapID or mapID == 0 then return false end
        if mapID == ancestorID then return true end
        local info = C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
    end
    return false
end

-- Returns x, y in 0..1 on the given map, or nil when the player is not on it.
function api.GetPlayerPosition(mapID)
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if api.IsSecret(x) or not x or x <= 0 or y <= 0 or x >= 1 or y >= 1 then return nil end
    return x, y
end

function api.GetSecondsUntilReset(mode)
    if not C_DateAndTime then return nil end -- callers fall back to 24 h
    if mode == "daily" then
        return C_DateAndTime.GetSecondsUntilDailyReset()
    elseif mode == "weekly" then
        return C_DateAndTime.GetSecondsUntilWeeklyReset()
    end
end

-- Target identity for the editor. Returns npcID, name or nil when restricted.
function api.GetTargetNPC()
    if not UnitExists("target") or UnitIsPlayer("target") then return nil end
    local guid = UnitGUID("target")
    if not guid or api.IsSecret(guid) then return nil end
    local name = UnitName("target")
    if api.IsSecret(name) then name = nil end
    return ns.Util.NPCIDFromGUID(guid), name
end

function api.GetPlayerLevel()
    return UnitLevel("player")
end

-- Values for {name}, {class} (class-coloured) and {race} in quest texts.
function api.GetPlayerTokens()
    local className, classFile = UnitClass("player")
    local color = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    return {
        name = UnitName("player"),
        class = color and color:WrapTextInColorCode(className) or className,
        race = (UnitRace("player")),
    }
end

function api.GetCharacterKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

function api.Print(msg)
    print("|cff33ccffCustomQuests|r " .. msg)
end

-- Yellow messages at the top centre of the screen, like standard quest
-- updates. Own frame instead of UIErrorsFrame so they stay up longer.
local SPLASH_HOLD, SPLASH_FADE, SPLASH_MAX, SPLASH_LINE = 5, 1.5, 5, 24
local splash, splashLines, splashEntries = nil, {}, {}

local function updateSplash(self, elapsed)
    local now = GetTime()
    for i = #splashEntries, 1, -1 do
        if now - splashEntries[i].time > SPLASH_HOLD + SPLASH_FADE then table.remove(splashEntries, i) end
    end
    -- Newest at the bottom, older ones pushed up.
    for i, fs in ipairs(splashLines) do
        local entry = splashEntries[#splashEntries - i + 1]
        if entry then
            local age = now - entry.time
            fs:SetText(entry.text)
            fs:SetAlpha(age <= SPLASH_HOLD and 1 or math.max(0, 1 - (age - SPLASH_HOLD) / SPLASH_FADE))
            fs:Show()
        else
            fs:Hide()
        end
    end
    if #splashEntries == 0 then self:Hide() end
end

function api.Splash(msg)
    if not splash then
        splash = CreateFrame("Frame", nil, UIParent)
        splash:SetSize(700, SPLASH_LINE * SPLASH_MAX)
        splash:SetPoint("TOP", UIParent, "TOP", 0, -190)
        splash:SetFrameStrata("HIGH")
        for i = 1, SPLASH_MAX do
            local fs = splash:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            fs:SetTextColor(1, 0.82, 0)
            fs:SetShadowOffset(1, -1)
            fs:SetPoint("BOTTOM", splash, "BOTTOM", 0, (i - 1) * SPLASH_LINE)
            splashLines[i] = fs
        end
        splash:SetScript("OnUpdate", updateSplash)
    end
    splashEntries[#splashEntries + 1] = { text = msg, time = GetTime() }
    while #splashEntries > SPLASH_MAX do table.remove(splashEntries, 1) end
    splash:Show()
    updateSplash(splash)
end

function api.PlayObjectiveSound()
    local sound = SOUNDKIT and (SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or SOUNDKIT.IG_QUEST_LIST_COMPLETE)
    if sound then PlaySound(sound) end
end

-- Sharing: addon messages, players, chat links -----------------------------------
-- C_ChatInfo, C_FriendList and C_EncodingUtil are declared alike in Retail
-- 12.1.5 and Forever 1.60.1 (wow-addon-dev snapshot 2.1.0); everything is
-- feature-detected and wrapped so a missing or throwing call degrades instead
-- of erroring.

-- Seconds with sub-second precision, for throttles and timeouts.
function api.Clock()
    return GetTime()
end

function api.InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

function api.RegisterCommPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
    end
end

-- 12.x: addon messages and chat stop during raid encounters, Mythic+ and the
-- like. False where the client doesn't have the query.
function api.InChatLockdown()
    local query = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not query then return false end
    local ok, locked = pcall(query)
    return ok and locked == true
end

-- Enum.SendAddonMessageResult (same 13 values in both clients) by number, so
-- it also works if the Enum table is missing.
local SEND_RESULTS = {
    [0] = "ok", [3] = "throttle", [8] = "throttle", [5] = "nogroup", [10] = "noguild",
    [11] = "lockdown", [12] = "offline",
}

-- Sends one addon message. Logged, because the content is written by players
-- and the logged variant is the one that can be reported (warcraft.wiki.gg).
-- Returns "ok", "throttle", "lockdown", "offline", "nogroup", "noguild" or "error".
function api.SendComm(prefix, text, channel, target)
    local send = C_ChatInfo and (C_ChatInfo.SendAddonMessageLogged or C_ChatInfo.SendAddonMessage)
    if not send then return "error" end
    local ok, code = pcall(send, prefix, text, channel, target)
    if not ok then return api.InChatLockdown() and "lockdown" or "error" end
    if code == nil or code == true then return "ok" end -- nothing or a boolean on older builds
    if code == false then return "error" end
    return SEND_RESULTS[code] or "error"
end

-- Trial and Veteran accounts can't send addon messages (Forever 1.60.1, and
-- Retail from 12.1.7 per warcraft.wiki.gg). Returns true, or false and an error key.
function api.CanSendComm()
    if not (C_ChatInfo and (C_ChatInfo.SendAddonMessageLogged or C_ChatInfo.SendAddonMessage)) then
        return false, "ERR_SHARE_UNAVAILABLE"
    end
    if (IsTrialAccount and IsTrialAccount()) or (IsVeteranTrialAccount and IsVeteranTrialAccount()) then
        return false, "ERR_SHARE_TRIAL"
    end
    return true
end

local function realm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if not r or r == "" then r = (GetRealmName() or ""):gsub("[%s%-]", "") end
    return r
end

-- "Name-Realm" for any name; a bare name is on our realm.
function api.FullName(name)
    if type(name) ~= "string" or name == "" or api.IsSecret(name) then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. realm()
end

function api.PlayerFullName()
    local name, r = UnitFullName("player")
    return (name or "?") .. "-" .. ((r and r ~= "") and r or realm())
end

-- The current target's full name when it is another player, else nil.
function api.TargetPlayerName()
    if not (UnitExists("target") and UnitIsPlayer("target")) or UnitIsUnit("target", "player") then return nil end
    local name, r = UnitName("target")
    if not name or api.IsSecret(name) or api.IsSecret(r) then return nil end
    return (r and r ~= "") and (name .. "-" .. r) or api.FullName(name)
end

-- A name without our own realm, as the game shows it.
function api.ShortName(name)
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "none")
        if ok and type(short) == "string" then return short end
    end
    return name
end

function api.IsIgnored(name)
    local check = C_FriendList and C_FriendList.IsIgnored
    if not check then return false end
    for _, n in ipairs({ name, api.ShortName(name) }) do
        local ok, ignored = pcall(check, n)
        if ok and ignored then return true end
    end
    return false
end

-- The chat type for "my group": instance group, raid or party; nil when alone.
function api.GroupChannel()
    if not IsInGroup then return nil end
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

function api.IsInGuild()
    return IsInGuild and IsInGuild() or false
end

local function isGuildMember(full)
    if not (api.IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return false end
    local wanted = full:lower()
    for i = 1, math.min(GetNumGuildMembers() or 0, 1000) do
        local member = GetGuildRosterInfo(i)
        if type(member) == "string" and not api.IsSecret(member) and member:lower() == wanted then return true end
    end
    return false
end

-- Someone on the friends list, in the group or in the guild.
function api.IsTrusted(name)
    local full = api.FullName(name)
    if not full then return false end
    local short = api.ShortName(full)
    if C_FriendList and C_FriendList.GetFriendInfo then
        for _, n in ipairs({ full, short }) do
            local ok, info = pcall(C_FriendList.GetFriendInfo, n)
            if ok and info then return true end
        end
    end
    if UnitInParty then
        local ok, inParty = pcall(UnitInParty, short)
        if ok and inParty == true then return true end
        local ok2, inRaid = pcall(UnitInRaid, short)
        if ok2 and type(inRaid) == "number" then return true end
    end
    local ok, member = pcall(isGuildMember, full)
    return ok and member
end

-- Native Deflate + base64 (C_EncodingUtil), or nil when the client lacks it.
-- Every call is protected: nil means "couldn't".
local codec
function api.GetCodec()
    if codec ~= nil then return codec or nil end
    local E = C_EncodingUtil
    if not (E and E.CompressString and E.DecompressString and E.EncodeBase64 and E.DecodeBase64) then
        codec = false
        return nil
    end
    local deflate = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
    local function safe(fn, ...)
        local ok, out = pcall(fn, ...)
        return ok and type(out) == "string" and out or nil
    end
    codec = {
        Compress = function(s) return safe(E.CompressString, s, deflate) end,
        Decompress = function(s) return safe(E.DecompressString, s, deflate) end,
        Encode64 = function(s) return safe(E.EncodeBase64, s) end,
        Decode64 = function(s) return safe(E.DecodeBase64, s) end,
    }
    return codec
end

-- Chat filter on a CHAT_MSG_* event. False when neither the 12.x
-- ChatFrameUtil nor the older global exists.
function api.AddChatFilter(event, fn)
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not add then return false end
    return (pcall(add, event, fn))
end

-- Clicks on |Haddon:...|h links reach EventRegistry's "SetItemRef" (local
-- links only, both clients). fn(link, button). False when that is missing.
function api.OnAddonLinkClick(fn)
    if not (EventRegistry and EventRegistry.RegisterCallback) then return false end
    local ok = pcall(EventRegistry.RegisterCallback, EventRegistry, "SetItemRef", function(_, link, _, button)
        if type(link) == "string" and not api.IsSecret(link) then fn(link, button) end
    end, api)
    return ok
end

-- Puts text in the open chat box, opening one when none is. False if it can't.
function api.InsertChatText(text)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if insert then
        local ok, done = pcall(insert, text)
        if ok and done then return true end
    end
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if open then return (pcall(open, text)) end
    return false
end
