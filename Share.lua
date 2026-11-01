local _, ns = ...

local Util, Model, Serializer, Comm = ns.Util, ns.Model, ns.Serializer, ns.Comm

-- In-game quest sharing (ADR-006). One player offers a quest, a chain or a
-- section; each receiver sees a popup and, only if they accept, the sender
-- whispers them the CQ1 text in fragments. The text then takes exactly the
-- path of a pasted import (Serializer.Import > Model.ValidateTemplate >
-- Model.SaveImported), so nothing received is ever run (ADR-003).
--
-- Frames (fields joined by "~", version first):
--   1~O~tid~kind~count~bytes~z~title   offer (whisper or group/guild channel)
--   1~A~tid~z                          accept (whisper to the sender)
--   1~N~tid~reason                     decline / refuse (whisper)
--   1~D~tid~i~n~e~chunk                data fragment i of n, e = encoding
--   1~K~tid~result                     received: "ok", "dup" or an error key
--   1~X~tid                            abort, either side
--   1~R~label                          chat link click: "send me that quest"
-- z is "1" when that side can use compressed data; e is "p" (plain CQ1 text)
-- or "z" (Deflate + base64, only when both sides said z=1). A frame with
-- another version is ignored, so a later protocol can coexist.
--
-- Everything that touches the game goes through ns.api and Comm; the popup
-- and the chat lines through the hooks below, so tests/run.lua drives it all.
local Share = {}
ns.Share = Share

Share.VERSION = "1"
Share.OFFER_TTL = 90          -- seconds an offer stays valid (the popup times out at 60)
Share.TRANSFER_TIMEOUT = 30   -- seconds without a fragment before a transfer is dropped
Share.SENDER_COOLDOWN = 30    -- seconds between two offers from the same player
Share.REQUEST_COOLDOWN = 10   -- seconds between two link requests to / from the same player
Share.REQUEST_TTL = 60        -- seconds a link request lets that player's offer through
Share.LINK_TTL = 600          -- seconds the sender honours a chat link
Share.MAX_PENDING = 3         -- offers waiting for an answer (one popup at a time)
Share.MAX_INCOMING = 2        -- accepted transfers arriving at once
Share.MAX_OUTGOING = 3        -- our offers alive at once
Share.MAX_RECIPIENTS = 10     -- players who may accept one group offer
Share.MAX_TITLE = 80          -- bytes of the title in an offer
Share.MAX_LABEL = 40          -- bytes of a chat link label
Share.MAX_LINKS = 20
Share.KINDS = { quest = true, chain = true, section = true }
Share.GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true }

-- Hooks (Core and the UI set them; the tests replace them).
Share.notify = function() end      -- (key, ...) a chat line: L[key]:format(...)
Share.showOffer = function() end   -- (offer) open the popup for this offer
Share.hideOffer = function() end   -- (offer) the offer expired or went away
Share.imported = function() end    -- (entries, ids, skipped, sender) after a successful import
Share.onWork = function() end      -- () there is something to pump or time out

-- State --------------------------------------------------------------------------------

local outgoing, pending, incoming = {}, {}, {}
local lastOffer, lastRequest, requested, links, blockedSession = {}, {}, {}, {}, {}
local shown -- the offer whose popup is open
Share.dropped = 0 -- offers dropped silently (blocked, rate limited, policy)

function Share.Reset()
    outgoing, pending, incoming = {}, {}, {}
    lastOffer, lastRequest, requested, links, blockedSession = {}, {}, {}, {}, {}
    shown = nil
    Share.dropped = 0
end

-- Names compare without case; a bare name is on our realm.
local function key(name)
    local full = ns.api.FullName(name)
    return full and full:lower()
end

local function newID()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local out = {}
    for i = 1, 6 do
        local n = math.random(1, #chars)
        out[i] = chars:sub(n, n)
    end
    return table.concat(out)
end

local function options()
    return Model.SharingOptions()
end

local function send(channel, target, tag, ...)
    Comm.Enqueue(Comm.Pack(Share.VERSION, ...), channel, target, tag)
    Share.onWork()
end

local function whisper(target, tag, ...)
    send("WHISPER", target, tag, ...)
end

-- True when this client can take compressed data (Share.Decompress is set
-- by the compression code and needs the native codec).
local function canDecompress()
    return Share.Decompress ~= nil and ns.api.GetCodec() ~= nil
end

-- What is shared -------------------------------------------------------------------------

-- The text, kind, quest count and title for a quest (with its chain) or a
-- section; nil and an error key when there is nothing to share.
function Share.Describe(kind, id)
    if kind == "section" then
        local section = Model.SectionByID(id)
        local text = section and Serializer.ExportSection(id)
        if not text then return nil, "ERR_SECTION_EMPTY" end
        return { text = text, kind = "section", count = math.min(#Model.SectionMembers(id), 50), title = section.name }
    end
    local tpl = Model.GetTemplate(id)
    if not tpl then return nil, "ERR_NO_TEMPLATE" end
    local text = Serializer.ExportChain(id)
    if not text then return nil, "ERR_BAD_TEMPLATE" end
    local chain = Model.GetChain(id)
    local first = #chain > 1 and Model.GetTemplate(chain[1]) or tpl
    return { text = text, kind = #chain > 1 and "chain" or "quest", count = #chain, title = first.title }
end

-- Offering ----------------------------------------------------------------------------------

-- Offers a quest ("quest", templateID) or a section ("section", sectionID) on
-- channel: "WHISPER" with target, "GROUP" (party, raid or instance group) or
-- "GUILD". Returns the transfer id, or nil and an error key.
function Share.Offer(kind, id, channel, target, now)
    local ok, err = ns.api.CanSendComm()
    if not ok then return nil, err end
    if channel == "GROUP" then
        channel = ns.api.GroupChannel()
        if not channel then return nil, "ERR_SHARE_NO_GROUP" end
    elseif channel == "GUILD" then
        if not ns.api.IsInGuild() then return nil, "ERR_SHARE_NO_GUILD" end
    elseif channel == "WHISPER" then
        target = ns.api.FullName(target and target:match("^%s*(.-)%s*$"))
        if not target or not target:match("^[^%s%-]+%-[^%s]+$") then return nil, "ERR_SHARE_NO_TARGET" end
        if key(target) == key(ns.api.PlayerFullName()) then return nil, "ERR_SHARE_SELF" end
    else
        return nil, "ERR_SHARE_NO_TARGET"
    end
    local info, describeErr = Share.Describe(kind, id)
    if not info then return nil, describeErr end
    if #info.text > Serializer.MAX_LENGTH then return nil, "ERR_IMPORT_TOO_LONG" end
    local live = 0
    for _ in pairs(outgoing) do live = live + 1 end
    if live >= Share.MAX_OUTGOING then return nil, "ERR_SHARE_BUSY" end

    local tid = newID()
    local title = Util.SafeLabel(info.title, Share.MAX_TITLE)
    outgoing[tid] = {
        tid = tid, text = info.text, kind = info.kind, count = info.count, title = title,
        channel = channel, target = channel == "WHISPER" and key(target) or nil,
        expires = now + Share.OFFER_TTL, recipients = {}, nRecipients = 0,
    }
    send(channel, target, tid, "O", tid, info.kind, info.count, #info.text, canDecompress() and "1" or "0", title)
    if ns.api.InChatLockdown() then Share.notify("SHARE_QUEUED_LOCKDOWN") end
    return tid
end

-- The payload for one recipient, and its encoding.
local function payloadFor(offer, compressed)
    if compressed and Share.Compress then
        local z = Share.Compress(offer.text)
        if z and #z < #offer.text then return z, "z" end
    end
    return offer.text, "p"
end

local function startSending(offer, who, sender, compressed)
    local payload, encoding = payloadFor(offer, compressed)
    local header = Comm.Pack(Share.VERSION, "D", offer.tid, "000", "000", encoding, "")
    local chunks = Comm.Fragment(payload, Comm.ChunkSize(header))
    local tag = offer.tid .. "/" .. who
    for i, chunk in ipairs(chunks) do
        whisper(sender, tag, "D", offer.tid, i, #chunks, encoding, chunk)
    end
    offer.recipients[who] = { state = "sending", name = sender, tag = tag }
end

local function onAccept(sender, who, tid, z, now)
    local offer = outgoing[tid]
    if not offer or now > offer.expires then
        whisper(sender, nil, "X", tid)
        return
    end
    if offer.target and offer.target ~= who then return end -- not the one we asked
    if offer.recipients[who] then return end                -- already sending to them
    if offer.nRecipients >= Share.MAX_RECIPIENTS then
        whisper(sender, nil, "X", tid)
        return
    end
    offer.nRecipients = offer.nRecipients + 1
    startSending(offer, who, sender, z == "1" and canDecompress())
end

local function onDecline(sender, who, tid, reason)
    if tid == "-" then
        -- The answer to a chat link request: the sender no longer offers it.
        if requested[who] then
            requested[who] = nil
            Share.notify("SHARE_LINK_GONE", Util.SafeLabel(ns.api.ShortName(sender), 64))
        end
        return
    end
    local offer = outgoing[tid]
    if not offer or (offer.target and offer.target ~= who) then return end
    local name = Util.SafeLabel(ns.api.ShortName(sender), 64)
    if reason == "full" then
        Share.notify("SHARE_REMOTE_FULL", name)
    elseif reason == "busy" then
        Share.notify("SHARE_REMOTE_BUSY", name)
    else
        Share.notify("SHARE_DECLINED", name, offer.title)
    end
    if offer.target then outgoing[tid] = nil end
end

local function onReceived(sender, who, tid, result)
    local offer = outgoing[tid]
    local r = offer and offer.recipients[who]
    if not r or r.state ~= "sending" then return end
    r.state = "done"
    local name = Util.SafeLabel(ns.api.ShortName(sender), 64)
    if result == "ok" or result == "dup" then
        Share.notify(result == "ok" and "SHARE_DELIVERED" or "SHARE_DELIVERED_DUP", name, offer.title)
    else
        Share.notify("SHARE_REMOTE_FAILED", name, offer.title)
    end
    if offer.target then outgoing[tid] = nil end
end

-- Receiving ------------------------------------------------------------------------------------

-- Why an offer from sender on channel is not shown, or nil when it may be.
-- Silent reasons (nothing is answered): off, blocked, scope, rate.
function Share.CheckOffer(sender, channel, now)
    local who = key(sender)
    local opts = options()
    if not who then return "blocked" end
    if Model.IsShareBlocked(who) or blockedSession[who] or ns.api.IsIgnored(sender) then return "blocked" end
    -- A player we asked through a chat link may answer whatever the setting.
    local asked = requested[who] and now - requested[who] <= Share.REQUEST_TTL
    if not asked then
        if opts.incoming == "off" then return "off" end
        if opts.incoming == "trusted" and not (Share.GROUP_CHANNELS[channel] or ns.api.IsTrusted(sender)) then
            return "scope"
        end
    end
    if lastOffer[who] and now - lastOffer[who] < Share.SENDER_COOLDOWN then return "rate" end
    if #pending >= Share.MAX_PENDING then return "busy" end
    return nil
end

local function removePending(offer)
    for i, p in ipairs(pending) do
        if p == offer then table.remove(pending, i) break end
    end
    if shown == offer then shown = nil end
end

-- Opens the next popup unless one is open or we are in combat.
function Share.ShowNext()
    if shown or not pending[1] or ns.api.InCombat() then return end
    shown = pending[1]
    Share.showOffer(shown)
end

local function onOffer(sender, who, channel, f, now)
    local tid, kind, count, bytes, z = f[3], f[4], tonumber(f[5]), tonumber(f[6]), f[7]
    if not (tid and Share.KINDS[kind] and count and bytes) then return end
    if count < 1 or count > 50 or bytes < 1 or bytes > Serializer.MAX_LENGTH then return end
    for _, p in ipairs(pending) do
        if p.who == who and p.tid == tid then return end -- the same offer twice
    end
    local reason = Share.CheckOffer(sender, channel, now)
    if reason then
        Share.dropped = Share.dropped + 1
        -- Only a direct offer learns that we are busy; refusals stay silent.
        if reason == "busy" and channel == "WHISPER" then whisper(sender, nil, "N", tid, "busy") end
        return
    end
    lastOffer[who] = now
    requested[who] = nil
    if Model.CountTemplates() + count > Model.MAX_TEMPLATES then
        whisper(sender, nil, "N", tid, "full")
        Share.notify("SHARE_FULL", Util.SafeLabel(ns.api.ShortName(sender), 64))
        return
    end
    local title = Util.SafeLabel(f[8], Share.MAX_TITLE)
    pending[#pending + 1] = {
        sender = sender, who = who, tid = tid, kind = kind, count = count, bytes = bytes, z = z == "1",
        channel = channel, expires = now + Share.OFFER_TTL,
        senderLabel = Util.SafeLabel(ns.api.ShortName(sender), 64),
        title = title ~= "" and title or "?",
    }
    Share.ShowNext()
end

-- The popup's answers. offer is what showOffer received.
function Share.Accept(offer, now)
    removePending(offer)
    local active = 0
    for _, t in pairs(incoming) do
        active = active + 1
        if t.who == offer.who then active = math.huge end -- one at a time per sender
    end
    if now > offer.expires then
        Share.notify("SHARE_EXPIRED", offer.senderLabel)
    elseif active >= Share.MAX_INCOMING then
        whisper(offer.sender, nil, "N", offer.tid, "busy")
        Share.notify("SHARE_TOO_MANY")
    else
        local z = offer.z and canDecompress()
        incoming[offer.who .. "/" .. offer.tid] = {
            sender = offer.sender, who = offer.who, tid = offer.tid, title = offer.title,
            senderLabel = offer.senderLabel, bytes = offer.bytes, z = z, last = now,
        }
        whisper(offer.sender, nil, "A", offer.tid, z and "1" or "0")
        Share.notify("SHARE_RECEIVING", offer.title, offer.senderLabel)
    end
    Share.ShowNext()
end

function Share.Decline(offer)
    removePending(offer)
    whisper(offer.sender, nil, "N", offer.tid, "declined")
    Share.ShowNext()
end

-- Declines and never shows this player's offers again (Options can clear it).
function Share.Block(offer)
    removePending(offer)
    Model.SetShareBlocked(offer.who, true)
    blockedSession[offer.who] = true
    -- Dropping the rest of their offers too.
    for i = #pending, 1, -1 do
        if pending[i].who == offer.who then table.remove(pending, i) end
    end
    Share.notify("SHARE_BLOCKED", offer.senderLabel)
    Share.ShowNext()
end

-- Turns a received payload into CQ1 text, or nil.
local function payloadText(transfer, payload)
    if transfer.encoding == "z" then
        return Share.Decompress and Share.Decompress(payload) or nil
    end
    return payload
end

local function finish(transfer, payload, now)
    incoming[transfer.who .. "/" .. transfer.tid] = nil
    local text = payloadText(transfer, payload)
    local entries, err
    if text then entries, err = Serializer.Import(text) else err = "ERR_IMPORT_CORRUPT" end
    local ids, skipped
    if entries then
        ids, skipped = Model.SaveImported(entries, ns.api.Now())
        if not ids then err = skipped end
    end
    if not ids then
        whisper(transfer.sender, nil, "K", transfer.tid, err)
        Share.notify("SHARE_IMPORT_FAILED", transfer.title, transfer.senderLabel, ns.L[err])
        return
    end
    local allDup = true
    for i = 1, #entries do if not skipped[i] then allDup = false end end
    whisper(transfer.sender, nil, "K", transfer.tid, allDup and "dup" or "ok")
    Share.imported(entries, ids, skipped, transfer.senderLabel)
end

local function failTransfer(transfer, reasonKey)
    incoming[transfer.who .. "/" .. transfer.tid] = nil
    whisper(transfer.sender, nil, "X", transfer.tid)
    Share.notify(reasonKey, transfer.title, transfer.senderLabel)
end

-- Bytes a payload may have: the plain text announced in the offer, or for
-- compressed data the base64 of at most that much (deflate never needs more).
local function payloadCap(transfer, encoding)
    if encoding == "z" then return math.ceil(transfer.bytes / 3) * 4 + 4 end
    return transfer.bytes
end

local function onData(who, f, now)
    local transfer = incoming[who .. "/" .. (f[3] or "")]
    if not transfer then return end -- unsolicited, or from someone else: dropped
    local i, n, encoding, chunk = tonumber(f[4]), tonumber(f[5]), f[6], f[7]
    if not (i and n and (encoding == "p" or encoding == "z")) then return failTransfer(transfer, "SHARE_CORRUPT") end
    if encoding == "z" and not transfer.z then return failTransfer(transfer, "SHARE_CORRUPT") end
    if not transfer.assembly then
        transfer.assembly = Comm.NewAssembly(n, payloadCap(transfer, encoding), now)
        transfer.encoding = encoding
        if not transfer.assembly then return failTransfer(transfer, "SHARE_CORRUPT") end
    elseif transfer.assembly.total ~= n or transfer.encoding ~= encoding then
        return failTransfer(transfer, "SHARE_CORRUPT") -- changed mid-way
    end
    local result, err = transfer.assembly:Add(i, chunk, now)
    if not result then
        return failTransfer(transfer, err == "too_big" and "SHARE_TOO_BIG" or "SHARE_CORRUPT")
    end
    transfer.last = now
    if transfer.assembly:IsComplete() then finish(transfer, transfer.assembly:Result(), now) end
end

local function onAbort(who, tid)
    local transfer = incoming[who .. "/" .. (tid or "")]
    if transfer then
        incoming[who .. "/" .. tid] = nil
        Share.notify("SHARE_ABORTED", transfer.title, transfer.senderLabel)
    end
    -- A receiver gave up: stop sending to them.
    local offer = outgoing[tid or ""]
    local r = offer and offer.recipients[who]
    if r and r.state == "sending" then
        Comm.Cancel(r.tag)
        r.state = "aborted"
        if offer.target then outgoing[tid] = nil end
    end
    for _, p in ipairs(pending) do
        if p.who == who and p.tid == tid then
            removePending(p)
            Share.hideOffer(p)
            Share.ShowNext()
            break
        end
    end
end

-- Chat links ------------------------------------------------------------------------------

-- The text to put in chat for a quest or section, remembered for LINK_TTL so
-- a click from another player can ask for it. nil and an error key if none.
function Share.MakeLink(kind, id, now)
    local info, err = Share.Describe(kind, id)
    if not info then return nil, err end
    local label = Util.SafeLabel(info.title, Share.MAX_LABEL)
    if label == "" then label = "?" end
    links[label:lower()] = { kind = kind, id = id, at = now }
    -- Only the newest few.
    local list = {}
    for k, v in pairs(links) do list[#list + 1] = { k = k, at = v.at } end
    table.sort(list, function(a, b) return a.at > b.at end)
    for i = Share.MAX_LINKS + 1, #list do links[list[i].k] = nil end
    return "[CustomQuests: " .. label .. "]"
end

local MARKER = "%[CustomQuests: ([^%[%]|:~\r\n]+)%]"

-- Chat text with every [CustomQuests: label] turned into a clickable link that
-- asks author for it, or nil when there is none. Done locally by the chat
-- filter: |Haddon links never travel.
function Share.LinkifyMarkers(msg, author)
    if type(msg) ~= "string" or type(author) ~= "string" or not msg:find("[CustomQuests: ", 1, true) then
        return nil
    end
    -- Real character names never hold these; anything that does gets no link.
    if author == "" or author:find("[|:%[%]%s%c~]") then return nil end
    local safeAuthor = author
    local count
    msg, count = msg:gsub(MARKER, function(label)
        label = Util.SafeLabel(label, Share.MAX_LABEL)
        if label == "" then return nil end
        return ("|cff71d5ff|Haddon:CustomQuests:%s:%s|h[CustomQuests: %s]|h|r"):format(safeAuthor, label, label)
    end)
    return count > 0 and msg or nil
end

-- The author and label of one of our links, or nil.
function Share.ParseLink(link)
    if type(link) ~= "string" then return nil end
    local author, label = link:match("^addon:CustomQuests:([^:|]+):([^:|]+)$")
    return author, label
end

-- A click on a link: asks its author, by whisper, to offer the quest.
-- Returns true, or nil and an error key.
function Share.RequestLink(author, label, now)
    local who = key(author)
    if not who then return nil, "ERR_SHARE_NO_TARGET" end
    if who == key(ns.api.PlayerFullName()) then return nil, "ERR_SHARE_SELF" end
    if lastRequest[who] and now - lastRequest[who] < Share.REQUEST_COOLDOWN then return nil, "ERR_SHARE_WAIT" end
    local ok, err = ns.api.CanSendComm()
    if not ok then return nil, err end
    lastRequest[who] = now
    requested[who] = now
    whisper(author, nil, "R", Util.SafeLabel(label, Share.MAX_LABEL))
    return true
end

local function onRequest(sender, who, label, now)
    if Model.IsShareBlocked(who) or blockedSession[who] or ns.api.IsIgnored(sender) then return end
    if lastRequest["from:" .. who] and now - lastRequest["from:" .. who] < Share.REQUEST_COOLDOWN then return end
    lastRequest["from:" .. who] = now
    local link = links[Util.SafeLabel(label, Share.MAX_LABEL):lower()]
    if not link or now - link.at > Share.LINK_TTL or not Share.Describe(link.kind, link.id) then
        whisper(sender, nil, "N", "-", "gone")
        return
    end
    Share.Offer(link.kind, link.id, "WHISPER", sender, now)
end

-- Entry points --------------------------------------------------------------------------------

-- One addon message with our prefix. sender comes from the event (the server
-- fills it in), never from the message.
function Share.OnMessage(text, channel, sender, now)
    if type(text) ~= "string" or type(sender) ~= "string" or #text > Comm.MAX_MESSAGE then return end
    local who = key(sender)
    if not who or who == key(ns.api.PlayerFullName()) then return end -- our own group echo
    local f = Comm.Unpack(text, 8)
    if f[1] ~= Share.VERSION then return end
    local t = f[2]
    if t == "O" then
        onOffer(sender, who, channel, f, now)
    elseif channel ~= "WHISPER" then
        return -- everything but an offer comes by whisper
    elseif t == "D" then
        onData(who, Comm.Unpack(text, 7), now)
    elseif t == "A" then
        onAccept(sender, who, f[3], f[4], now)
    elseif t == "N" then
        onDecline(sender, who, f[3], f[4])
    elseif t == "K" then
        onReceived(sender, who, f[3], f[4])
    elseif t == "X" then
        onAbort(who, f[3])
    elseif t == "R" then
        onRequest(sender, who, Comm.Unpack(text, 3)[3], now)
    end
end

-- A transfer of ours failed at the transport (offline, not in group...).
function Share.OnSendFailed(tag, result)
    local tid, who = (tag or ""):match("^([^/]+)/?(.*)$")
    local offer = outgoing[tid or ""]
    if not offer then return end
    local reason = result == "offline" and "SHARE_FAIL_OFFLINE" or result == "nogroup" and "SHARE_FAIL_NOGROUP"
        or result == "noguild" and "SHARE_FAIL_NOGUILD" or "SHARE_FAIL_SEND"
    local r = who ~= "" and offer.recipients[who]
    Share.notify(reason, r and Util.SafeLabel(ns.api.ShortName(r.name), 64) or "", offer.title)
    if r then r.state = "failed" end
    if who == "" or offer.target then outgoing[tid] = nil end
end

-- Timeouts. Call about once a second while Share.IsIdle() is false.
function Share.Tick(now)
    for k, transfer in pairs(incoming) do
        if now - transfer.last > Share.TRANSFER_TIMEOUT then
            incoming[k] = nil
            whisper(transfer.sender, nil, "X", transfer.tid)
            Share.notify("SHARE_TIMEOUT", transfer.title, transfer.senderLabel)
        end
    end
    for i = #pending, 1, -1 do
        local offer = pending[i]
        if now > offer.expires then
            removePending(offer)
            Share.hideOffer(offer)
        end
    end
    for tid, offer in pairs(outgoing) do
        local busy = false
        for _, r in pairs(offer.recipients) do
            if r.state == "sending" and Comm.Pending(r.tag) > 0 then busy = true end
        end
        if now > offer.expires and not busy and Comm.Pending(tid) == 0 then outgoing[tid] = nil end
    end
    Share.ShowNext()
end

function Share.IsIdle()
    return next(outgoing) == nil and next(incoming) == nil and pending[1] == nil and Comm.IsIdle()
end

-- For the UI and tests.
function Share.PendingOffers() return pending end
function Share.Outgoing() return outgoing end
function Share.Incoming() return incoming end
function Share.Shown() return shown end
