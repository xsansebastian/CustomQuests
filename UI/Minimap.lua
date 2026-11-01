local _, ns = ...

local L, Model = ns.L, ns.Model

-- Minimap button: left-click opens the journal, right-click shows/hides the
-- tracker, Shift+drag moves it around the minimap. Position is account-wide.
local MinimapButton = {}
ns.Minimap = MinimapButton

local RADIUS = 80
local button

local function setPosition(angle)
    local rad = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * RADIUS, math.sin(rad) * RADIUS)
end

-- While dragging: the angle from the minimap centre to the cursor.
local function followCursor()
    local cx, cy = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local angle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
    Model.account.minimap.angle = angle
    setPosition(angle)
end

local function create()
    button = CreateFrame("Button", "CustomQuestsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture("Interface\\AddOns\\CustomQuests\\Media\\Icon")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if ns.Tracker then ns.Tracker.Toggle() end
        elseif ns.Journal then
            ns.Journal.Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:SetScript("OnUpdate", followCursor) end
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("CustomQuests")
        GameTooltip:AddLine(L["MM_JOURNAL"], 1, 1, 1)
        GameTooltip:AddLine(L["MM_TRACKER"], 1, 1, 1)
        GameTooltip:AddLine(L["MM_MOVE"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
end

function MinimapButton.Refresh()
    if not button then return end
    local settings = Model.account.minimap
    button:SetShown(not settings.hidden)
    setPosition(settings.angle)
end

function MinimapButton.Init()
    if button or not Minimap then return end
    create()
    MinimapButton.Refresh()
end

-- /cq minimap
function MinimapButton.Toggle()
    local settings = Model.account.minimap
    settings.hidden = not settings.hidden
    MinimapButton.Refresh()
    ns.api.Print(settings.hidden and L["MM_HIDDEN"] or L["MM_SHOWN"])
end
