local _, ns = ...

local UI = ns.UI

-- Chat links for shared quests (ADR-006, phase 2). The sender types plain text
-- "[CustomQuests: Title]" (Link in chat); on each receiver with the addon a
-- chat filter turns it into a local |Haddon:CustomQuests:...|h link, and a click
-- asks the sender by whisper to offer it, which shows the usual popup. Players
-- without the addon just see the text. If the client lacks the filter or the
-- link callback, nothing is hooked and the text stays text.
local ChatLink = {}
ns.ChatLink = ChatLink

-- Group, guild and whisper chat only: no say, yell or numbered channels.
local EVENTS = {
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER",
}

local function filter(_, event, msg, author, ...)
    if not ns.Model.SharingOptions().chatLinks then return false end
    -- During a chat lockdown text and author may be secret: never touch them.
    if ns.api.IsSecret(msg) or ns.api.IsSecret(author) or type(msg) ~= "string" or type(author) ~= "string" then
        return false
    end
    if not msg:find("[CustomQuests: ", 1, true) then return false end
    local full = ns.api.FullName(author)
    if not full or full:lower() == ns.api.PlayerFullName():lower() then return false end
    -- Whispers from strangers stay text unless offers from anyone are allowed.
    if event == "CHAT_MSG_WHISPER" and ns.Model.SharingOptions().incoming ~= "anyone"
        and not ns.api.IsTrusted(full) then
        return false
    end
    local linked = ns.Share.LinkifyMarkers(msg, full)
    if linked then return false, linked, author, ... end
    return false
end

local function onClick(link)
    local author, label = ns.Share.ParseLink(link)
    if not author then return end
    local ok, err = ns.Share.RequestLink(author, label, ns.api.Clock())
    if not ok then ns.api.Print(UI.ErrorText(err)) end
end

function ChatLink.Init()
    if ChatLink.ready then return end
    ChatLink.ready = true
    if not ns.api.OnAddonLinkClick(onClick) then return end
    for _, event in ipairs(EVENTS) do ns.api.AddChatFilter(event, filter) end
end
