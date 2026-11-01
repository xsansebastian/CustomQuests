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
