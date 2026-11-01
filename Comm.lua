local _, ns = ...

-- Addon-message transport, in plain Lua so tests/run.lua can drive it with a
-- fake clock: framing, fragmentation, reassembly with size caps and timeouts,
-- and an outgoing queue behind our own token-bucket throttle (no
-- ChatThrottleLib, see ADR-001). Sending itself is Comm.transport, which Core
-- points at ns.api.SendComm; it answers "ok", "throttle", "lockdown" or a
-- failure ("offline", "nogroup", "noguild", "error").
local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "CustomQuests" -- at most 16 characters
Comm.MAX_MESSAGE = 255       -- bytes in one addon message
Comm.MAX_CHUNK = 240         -- payload bytes in one fragment, at most
Comm.MAX_FRAGMENTS = 100     -- 16 KB / ~234 bytes is 71; anything above is junk
Comm.SEP = "~"               -- field separator: not in base64, stripped from titles

-- Framing -----------------------------------------------------------------------

function Comm.Pack(...)
    return table.concat({ ... }, Comm.SEP)
end

-- Splits a frame into at most maxFields fields; the last one keeps any "~".
function Comm.Unpack(msg, maxFields)
    local fields, pos = {}, 1
    while #fields < maxFields - 1 do
        local at = msg:find(Comm.SEP, pos, true)
        if not at then break end
        fields[#fields + 1] = msg:sub(pos, at - 1)
        pos = at + 1
    end
    fields[#fields + 1] = msg:sub(pos)
    return fields
end

-- Fragmentation --------------------------------------------------------------------

-- The payload cut in chunks of at most size bytes (at least one chunk).
function Comm.Fragment(payload, size)
    local chunks = {}
    for i = 1, math.max(#payload, 1), size do chunks[#chunks + 1] = payload:sub(i, i + size - 1) end
    return chunks
end

-- Room left for payload once header is in front of it, never above MAX_CHUNK.
function Comm.ChunkSize(header)
    return math.min(Comm.MAX_CHUNK, Comm.MAX_MESSAGE - #header)
end

-- Reassembly -------------------------------------------------------------------------
-- Fragments may come in any order and more than once. The assembly refuses
-- an index out of range and stops at maxBytes; the owner drops it once
-- Expired says nothing arrived for a while.

local Assembly = {}
Assembly.__index = Assembly

-- nil when total is not a sane fragment count.
function Comm.NewAssembly(total, maxBytes, now)
    if type(total) ~= "number" or total < 1 or total > Comm.MAX_FRAGMENTS or total ~= math.floor(total) then
        return nil
    end
    return setmetatable({ total = total, maxBytes = maxBytes, parts = {}, have = 0, bytes = 0, last = now }, Assembly)
end

-- Returns "added", "duplicate" (ignored: the first copy wins), or nil and
-- "bad_index" / "too_big" / "empty".
function Assembly:Add(index, chunk, now)
    if type(index) ~= "number" or index < 1 or index > self.total or index ~= math.floor(index) then
        return nil, "bad_index"
    end
    if type(chunk) ~= "string" or chunk == "" then return nil, "empty" end
    if self.parts[index] then return "duplicate" end
    if self.bytes + #chunk > self.maxBytes then return nil, "too_big" end
    self.parts[index] = chunk
    self.have = self.have + 1
    self.bytes = self.bytes + #chunk
    self.last = now
    return "added"
end

function Assembly:IsComplete()
    return self.have == self.total
end

function Assembly:Result()
    if not self:IsComplete() then return nil end
    return table.concat(self.parts)
end

function Assembly:Missing()
    local list = {}
    for i = 1, self.total do if not self.parts[i] then list[#list + 1] = i end end
    return list
end

function Assembly:Expired(now, timeout)
    return now - self.last > timeout
end

-- Throttle ------------------------------------------------------------------------------
-- A token bucket: capacity tokens, refilled at rate per second.

local Bucket = {}
Bucket.__index = Bucket

function Comm.NewBucket(capacity, rate, now)
    return setmetatable({ capacity = capacity, rate = rate, tokens = capacity, at = now }, Bucket)
end

function Bucket:Refill(now)
    if now > self.at then
        self.tokens = math.min(self.capacity, self.tokens + (now - self.at) * self.rate)
    end
    self.at = now
end

function Bucket:Take(now)
    self:Refill(now)
    if self.tokens >= 1 then
        self.tokens = self.tokens - 1
        return true
    end
    return false
end

-- Empties the bucket: the server said we went too fast.
function Bucket:Drain(now)
    self:Refill(now)
    self.tokens = 0
end

-- Outgoing queue ----------------------------------------------------------------------------
-- The game shares 10 messages per prefix, refilled at 1 per second, between
-- every chat type except WHISPER outside instances (warcraft.wiki.gg). Our
-- whispers stay at 5 per second out of courtesy; a "throttle" answer backs off.

Comm.GROUP_BUCKET = { 10, 1 }
Comm.WHISPER_BUCKET = { 10, 5 }
Comm.BACKOFF = 2 -- seconds of silence after a "throttle" answer

-- Hooks, set by Core (and by the tests).
Comm.transport = function() return "error" end -- (prefix, text, channel, target) -> result
Comm.onFail = function() end                     -- (tag, result) once per failed tag
Comm.onLockdown = function() end                 -- () when sending stops for a chat lockdown
Comm.inLockdown = function() return false end    -- () -> bool, checked before sending

local LANES = { "group", "whisper" } -- fixed order, so a pump is predictable
local queues, buckets, backoffUntil = {}, {}, {}
Comm.paused = false

local function laneOf(channel)
    return channel == "WHISPER" and "whisper" or "group"
end

local function bucketFor(lane, now)
    if not buckets[lane] then
        local spec = lane == "whisper" and Comm.WHISPER_BUCKET or Comm.GROUP_BUCKET
        buckets[lane] = Comm.NewBucket(spec[1], spec[2], now)
    end
    return buckets[lane]
end

-- Forgets every queue and bucket (tests, and a fresh session).
function Comm.Reset()
    queues, buckets, backoffUntil = { whisper = {}, group = {} }, {}, {}
    Comm.paused = false
end
Comm.Reset()

-- Queues one message. tag groups the messages of one transfer, so a failure
-- or a cancel drops them all.
function Comm.Enqueue(text, channel, target, tag)
    local q = queues[laneOf(channel)]
    q[#q + 1] = { text = text, channel = channel, target = target, tag = tag }
end

-- Drops every queued message with this tag; returns how many.
function Comm.Cancel(tag)
    local n = 0
    for _, q in pairs(queues) do
        for i = #q, 1, -1 do
            if q[i].tag == tag then table.remove(q, i) n = n + 1 end
        end
    end
    return n
end

function Comm.Pending(tag)
    local n = 0
    for _, q in pairs(queues) do
        for _, item in ipairs(q) do if tag == nil or item.tag == tag then n = n + 1 end end
    end
    return n
end

function Comm.IsIdle()
    return Comm.Pending() == 0
end

function Comm.Resume()
    Comm.paused = false
end

-- Sends what the buckets allow. Call it often (Core runs a ticker while there
-- is work). Returns the number of messages sent.
function Comm.Pump(now)
    if Comm.paused then
        if Comm.inLockdown() then return 0 end
        Comm.paused = false
    end
    local sent = 0
    for _, lane in ipairs(LANES) do
        local q = queues[lane]
        while q[1] and not Comm.paused and now >= (backoffUntil[lane] or 0) do
            if Comm.inLockdown() then
                Comm.paused = true
                Comm.onLockdown()
                break
            end
            local bucket = bucketFor(lane, now)
            if not bucket:Take(now) then break end
            local item = q[1]
            local result = Comm.transport(Comm.PREFIX, item.text, item.channel, item.target)
            if result == "ok" then
                table.remove(q, 1)
                sent = sent + 1
            elseif result == "throttle" then
                bucket:Drain(now)
                backoffUntil[lane] = now + Comm.BACKOFF
            elseif result == "lockdown" then
                Comm.paused = true
                Comm.onLockdown()
            else
                if item.tag then Comm.Cancel(item.tag) else table.remove(q, 1) end
                Comm.onFail(item.tag, result)
            end
        end
    end
    return sent
end
