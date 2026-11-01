-- Offline tests for the pure modules. Run from the addon folder:
--   lua5.1 tests/run.lua
-- No WoW client needed: ns.api is replaced by a fake.

local ns = {}
ns.L = setmetatable({}, { __index = function(_, k) return k end })

local fake = { now = 1000, items = {}, map = 1, maps = {}, position = nil, secondsUntilReset = 3600 }
ns.api = {
    Now = function() return fake.now end,
    IsSecret = function(v) return v == "SECRET" end,
    GetItemCount = function(id) return fake.items[id] or 0 end,
    GetPlayerMapID = function() return fake.map end,
    IsMapInside = function(mapID, ancestor)
        while mapID do
            if mapID == ancestor then return true end
            mapID = fake.maps[mapID]
        end
        return false
    end,
    GetPlayerPosition = function() if fake.position then return fake.position[1], fake.position[2] end end,
    GetSecondsUntilReset = function() return fake.secondsUntilReset end,
    GetCharacterKey = function() return "Tester-Realm" end,
    GetPlayerLevel = function() return fake.level end,
}

for _, file in ipairs({ "Util.lua", "Model.lua", "Serializer.lua", "Comm.lua", "Share.lua", "Objectives.lua", "Lifecycle.lua", "Samples.lua" }) do
    assert(loadfile(file))("CustomQuests", ns)
end
local Util, Model, Serializer, Objectives, Lifecycle = ns.Util, ns.Model, ns.Serializer, ns.Objectives, ns.Lifecycle
local Samples, Comm, Share = ns.Samples, ns.Comm, ns.Share

local passed, failed = 0, 0
local function test(name, fn)
    Model.InitDB({}, {})
    fake.items, fake.map, fake.maps, fake.position, fake.now, fake.level = {}, 1, {}, nil, 1000, 1
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1 print("FAIL " .. name .. ": " .. tostring(err)) end
end

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function template(objectives, extra)
    local t = { title = "Test", stages = { { objectives = objectives } } }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

local function settle()
    local q = Model.char.active
    for _ = 1, 25 do
        Objectives.UpdateItems(q)
        Objectives.UpdateZone(q, fake.map)
        Objectives.UpdateLocation(q)
        Objectives.UpdateLevel(q, fake.level)
        if not Lifecycle.Advance() then break end
    end
end

-- Util ----------------------------------------------------------------------

test("NPCIDFromGUID parses creatures and ignores players", function()
    eq(Util.NPCIDFromGUID("Creature-0-1465-0-2105-448-000043F59F"), 448)
    eq(Util.NPCIDFromGUID("Vehicle-0-1465-0-2105-32913-000043F59F"), 32913)
    eq(Util.NPCIDFromGUID("Player-1465-0A1B2C3D"), nil)
    eq(Util.NPCIDFromGUID(nil), nil)
end)

test("ParseItemID accepts numbers and links", function()
    eq(Util.ParseItemID("2772"), 2772)
    eq(Util.ParseItemID("|cffffffff|Hitem:2772::::::::70:::::|h[Iron Ore]|h|r"), 2772)
    eq(Util.ParseItemID("abc"), nil)
end)

-- Model -----------------------------------------------------------------------

test("ValidateTemplate drops unknown fields and fills defaults", function()
    local clean = Model.ValidateTemplate(template({ { type = "item", itemID = 1, evil = "x" } }, { hack = true }))
    eq(clean.hack, nil)
    eq(clean.stages[1].objectives[1].evil, nil)
    eq(clean.stages[1].objectives[1].count, 1)
    eq(clean.repeatMode, "none")
end)

test("ValidateTemplate rejects missing data with an error key", function()
    eq(select(2, Model.ValidateTemplate(template({}))), "ERR_NEED_OBJECTIVE")
    eq(select(2, Model.ValidateTemplate({ title = " ", stages = {} })), "ERR_NEED_TITLE")
    eq(select(2, Model.ValidateTemplate(template({ { type = "kill" } }))), "ERR_NEED_NPC_OR_MAP")
    eq(select(2, Model.ValidateTemplate(template({ { type = "nope" } }))), "ERR_BAD_OBJECTIVE")
    eq(select(2, Model.ValidateTemplate(template({ { type = "item", itemID = 1 / 0 } }))), "ERR_NEED_ITEM")
end)

-- Serializer --------------------------------------------------------------------

test("Export then import round-trips a template", function()
    local tpl = Model.ValidateTemplate(template({
        { type = "location", mapID = 37, x = 0.42, y = 0.65, radius = 0.02 },
        { type = "manual", text = "Habla con Juan | ñ", count = 2 },
        { type = "kill", npcID = 1234, name = "Kobold", mapID = 37, count = 10, fallbackAny = true },
    }, { giver = "Elisa", repeatMode = "daily", kind = "rp" }))
    local text = Serializer.ExportTemplate(tpl)
    eq(text:sub(1, 4), "CQ1:")
    assert(not text:find("|", 1, true), "export must not contain pipes")
    local back = assert(Serializer.ImportTemplate(text))
    eq(back.giver, "Elisa")
    eq(back.repeatMode, "daily")
    eq(back.stages[1].objectives[1].x, 0.42)
    eq(back.stages[1].objectives[2].text, "Habla con Juan | ñ")
    eq(back.stages[1].objectives[3].fallbackAny, true)
end)

test("Import rejects tampered, truncated and foreign text", function()
    local text = Serializer.ExportTemplate(Model.ValidateTemplate(template({ { type = "item", itemID = 5, count = 3 } })))
    eq(select(2, Serializer.ImportTemplate(text:sub(1, #text - 8))), "ERR_IMPORT_CORRUPT")
    eq(select(2, Serializer.ImportTemplate("hello")), "ERR_IMPORT_FORMAT")
    eq(select(2, Serializer.ImportTemplate("CQ1:!!!!")), "ERR_IMPORT_FORMAT")
    eq(select(2, Serializer.ImportTemplate("CQ1:" .. string.rep("A", 20000))), "ERR_IMPORT_TOO_LONG")
    -- Valid encoding of a non-template table must fail validation, not crash.
    eq(select(2, Serializer.ImportTemplate(Serializer.Encode({ title = 5 }))), "ERR_NEED_TITLE")
end)

test("Decode refuses deeply nested payloads", function()
    local deep = {}
    local cur = deep
    for _ = 1, 10 do cur.x = {} cur = cur.x end
    local ok = pcall(Serializer.Encode, deep)
    eq(ok, false)
end)

-- Objectives and lifecycle ---------------------------------------------------------

-- A finished quest waits as "ready" until the player turns it in.
local function turnIn(qid)
    assert(Lifecycle.Get(qid).ready, "quest should be ready")
    assert(Lifecycle.TurnIn(qid))
end

local function accept(objectives, extra)
    local id = assert(Model.SaveTemplate(template(objectives, extra), nil, fake.now))
    return assert(Lifecycle.Accept(id)), id
end

test("Item objectives follow the bag count and complete the quest", function()
    local qid = accept({ { type = "item", itemID = 2772, count = 20 } })
    fake.items[2772] = 12
    settle()
    eq(Lifecycle.Get(qid).progress[1], 12)
    fake.items[2772] = 20
    settle()
    eq(Lifecycle.Get(qid).ready, true, "finished quest waits for turn-in")
    eq(#Model.account.history, 0)
    turnIn(qid)
    eq(Lifecycle.Get(qid), nil, "one-time quest removed when turned in")
    eq(#Model.account.history, 1)
end)

test("Kills count by NPC, and secret kills only count on approximate objectives", function()
    local qid = accept({
        { type = "kill", npcID = 448, count = 5 },
        { type = "kill", npcID = 999, mapID = 50, fallbackAny = true, count = 5 },
        { type = "kill", mapID = 50, count = 5 },
    })
    local quest = Lifecycle.Get(qid)
    Objectives.OnKill(Model.char.active, 448, 1)
    eq(quest.progress[1], 1)
    eq(quest.progress[3], nil, "other map")
    Objectives.OnKill(Model.char.active, nil, 50) -- secret identity inside map 50
    eq(quest.progress[1], 1, "exact objective ignores unidentified kills")
    eq(quest.progress[2], 1)
    eq(quest.progress[3], 1)
    eq(quest.approx[2], true)
end)

test("Boss, zone and location objectives", function()
    fake.maps[200] = 100 -- map 200 is inside zone 100
    local qid = accept({
        { type = "boss", encounterID = 3108, count = 1 },
        { type = "zone", mapID = 100 },
        { type = "location", mapID = 100, x = 0.5, y = 0.5, radius = 0.02 },
    })
    local quest = Lifecycle.Get(qid)
    Objectives.OnBoss(Model.char.active, 1)
    eq(quest.progress[1], nil)
    Objectives.OnBoss(Model.char.active, 3108)
    eq(quest.progress[1], 1)
    fake.map = 200
    settle()
    eq(quest.progress[2], 1)
    fake.position = { 0.6, 0.6 }
    settle()
    eq(quest.progress[3], nil)
    fake.position = { 0.51, 0.5 }
    settle()
    turnIn(qid)
    eq(Lifecycle.Get(qid), nil, "completed")
end)

test("Stages advance and a satisfied next stage completes at once", function()
    local id = assert(Model.SaveTemplate({ title = "Chain", stages = {
        { objectives = { { type = "manual", text = "a", count = 1 } } },
        { objectives = { { type = "item", itemID = 7, count = 1 } } },
    } }, nil, fake.now))
    local qid = Lifecycle.Accept(id)
    fake.items[7] = 3
    local quest = Lifecycle.Get(qid)
    Objectives.AdjustManual(quest, 1, 1)
    settle()
    turnIn(qid)
    eq(Lifecycle.Get(qid), nil)
end)

test("Subzone objectives match the minimap name, optionally inside a map", function()
    fake.maps[300] = 100
    local qid = accept({
        { type = "subzone", name = "Granja Rocamuela" },
        { type = "subzone", name = "Rocamuela", mapID = 555 },
    })
    local quest = Lifecycle.Get(qid)
    eq(select(2, Model.ValidateTemplate(template({ { type = "subzone", name = "  " } }))), "ERR_NEED_SUBZONE")
    eq(Model.ValidateObjective({ type = "zone", name = "Granja", mapID = 1 }).type, "subzone", "old named zones migrate")
    Objectives.UpdateZone(Model.char.active, 300, { ["durotar"] = true })
    eq(quest.progress[1], nil, "zone name is not the subzone")
    Objectives.UpdateZone(Model.char.active, 300, { ["granja rocamuela"] = true })
    eq(quest.progress[1], 1)
    eq(quest.progress[2], nil, "same name on another map doesn't count")
end)

test("Daily quests wait for the reset and then restart", function()
    local qid, tid = accept({ { type = "manual", text = "a", count = 1 } }, { repeatMode = "daily" })
    Objectives.AdjustManual(Lifecycle.Get(qid), 1, 1)
    settle()
    turnIn(qid)
    local quest = Lifecycle.Get(qid)
    eq(quest.state, "done")
    eq(select(2, Lifecycle.Accept(tid)), "ERR_WAIT_RESET")
    eq(Lifecycle.CheckResets(fake.now + 100), false)
    eq(Lifecycle.CheckResets(fake.now + 3600), true)
    eq(quest.state, "active")
    eq(quest.progress[1], nil)
    eq(Lifecycle.GetStats(tid), 1)
end)

test("Manual objectives clamp between 0 and the goal", function()
    local qid = accept({ { type = "manual", text = "a", count = 2 } })
    local quest = Lifecycle.Get(qid)
    eq(Objectives.AdjustManual(quest, 1, -1), false)
    Objectives.AdjustManual(quest, 1, 1)
    Objectives.AdjustManual(quest, 1, 5)
    eq(quest.progress[1], 2)
end)

test("Editing a template doesn't change a quest in progress", function()
    local qid, tid = accept({ { type = "manual", text = "old", count = 1 } })
    Model.SaveTemplate(template({ { type = "manual", text = "new", count = 1 } }), tid, fake.now)
    eq(Lifecycle.Get(qid).template.stages[1].objectives[1].text, "old")
end)

test("SafeText turns [color] tags into codes, always closed, and escapes raw pipes", function()
    eq(Util.SafeText("a [color=ff0000]b[/color] c"), "a |cffff0000b|r c")
    eq(Util.SafeText("[color=ff0000]open"), "|cffff0000open|r")
    eq(Util.SafeText("[/color] [color=zz] |cffff0000x"), "[/color] [color=zz] ||cffff0000x")
end)

test("SafeLabel strips escapes, brackets, colons and control characters", function()
    eq(Util.SafeLabel("|cffff0000Red|r [Link]: x"), "cffff0000Red r Link x")
    eq(Util.SafeLabel("a\nb\tc\0d\127e"), "a b c d e")
    eq(Util.SafeLabel("|Hitem:1|h[Fake]|h"), "Hitem 1 h Fake h")
    eq(Util.SafeLabel("  spaced   out  "), "spaced out")
    eq(Util.SafeLabel("a~b"), "a b", "the protocol separator too")
    eq(Util.SafeLabel(nil), "")
    eq(Util.SafeLabel(42), "")
    eq(#Util.SafeLabel(("x"):rep(100), 40), 40)
    eq(Util.SafeLabel("abc def", 4), "abc", "no trailing space after the cut")
end)

test("TruncateUTF8 never splits a character", function()
    local s = "ñandú" -- n-tilde (2 bytes) a n d u-acute (2 bytes)
    eq(Util.TruncateUTF8(s, 1), "")
    eq(Util.TruncateUTF8(s, 2), "ñ")
    eq(Util.TruncateUTF8(s, 6), "ñand")
    eq(Util.TruncateUTF8(s, 7), s)
    eq(Util.TruncateUTF8("€", 2), "", "3-byte character")
    eq(#Util.SafeLabel(("é"):rep(30), 40), 40)
end)

test("ExpandTokens fills known tokens and keeps unknown ones", function()
    eq(Util.ExpandTokens("Hola {name}, {class} {x}", { name = "Arthas", class = "Paladín" }), "Hola Arthas, Paladín {x}")
end)

test("Level objectives show progress and complete at the target", function()
    local qid = accept({ { type = "level", level = 5 } })
    fake.level = 3
    settle()
    eq(Lifecycle.Get(qid).progress[1], 3)
    eq(Objectives.Goal(Lifecycle.Get(qid).template.stages[1].objectives[1]), 5)
    fake.level = 5
    settle()
    turnIn(qid)
    eq(Lifecycle.Get(qid), nil)
end)

test("Welcome sample is a valid template that keeps its tokens after export", function()
    local id = assert(Samples.InstallWelcome())
    eq(id, Samples.WELCOME_ID)
    local back = assert(Serializer.ImportTemplate(Serializer.ExportTemplate(Model.GetTemplate(id))))
    assert(back.description:find("{name}", 1, true) and back.description:find("{class}", 1, true))
    eq(back.stages[1].objectives[1].level, 5)
end)

test("Explorer sample visits ten zones and completes from sub-maps", function()
    Samples.InstallAll()
    local qid = assert(Lifecycle.Accept(Samples.EXPLORER_ID))
    eq(#Lifecycle.Get(qid).template.stages[1].objectives, 10)
    local zones = { 37, 1, 50, 71, 78, 83, 23, 107, 118, 371 }
    fake.maps[9999] = 371 -- a sub-map inside the Jade Forest
    for i = 1, 9 do fake.map = zones[i] settle() end
    eq(Lifecycle.Get(qid).progress[9], 1)
    fake.map = 9999
    settle()
    turnIn(qid)
    eq(Lifecycle.Get(qid), nil, "completed")
end)

-- One TOC serves both clients: it must list Retail and Forever and every file must exist.
test("TOC covers both clients and all its files exist", function()
    local f = assert(io.open("CustomQuests.toc", "r"))
    local text = f:read("*a")
    f:close()
    local interfaces = text:match("## Interface:%s*([^\r\n]+)")
    assert(interfaces:find("120105", 1, true) and interfaces:find("16001", 1, true), "Retail and Forever interfaces")
    for line in text:gmatch("[^\r\n]+") do
        if not line:match("^#") then
            local file = assert(io.open((line:gsub("\\", "/")), "r"), "missing " .. line)
            file:close()
        end
    end
end)

-- Every translation must define every key the English file does (missing ones show the raw key).
test("All locales define the same keys as enUS", function()
    local function keys(file)
        local set, f = {}, assert(io.open(file, "r"))
        for key in f:read("*a"):gmatch('L%["([%w_]+)"%]%s*=') do set[key] = true end
        f:close()
        return set
    end
    local en = keys("Locales/enUS.lua")
    for _, locale in ipairs({ "esES", "deDE", "frFR" }) do
        local other = keys("Locales/" .. locale .. ".lua")
        for key in pairs(en) do assert(other[key], locale .. " is missing " .. key) end
        for key in pairs(other) do assert(en[key], locale .. " has unknown key " .. key) end
    end
end)

test("Appearance options fill defaults and reject bad values", function()
    local defaults = Model.CleanOptions(nil)
    eq(defaults.font, "default")
    eq(defaults.scale, 100)
    eq(defaults.tracker.bgAlpha, 0)
    eq(defaults.tracker.border, "none")
    local clean = Model.CleanOptions({
        font = 42, scale = 9999,
        tracker = { bgAlpha = 5, border = "default", bg = { 2, "x", -1 }, borderColor = { 0.5, 0.25, 0.75 } },
    })
    eq(clean.font, "default", "non-string font")
    eq(clean.scale, Model.SCALE_MAX, "scale clamped")
    eq(clean.tracker.bgAlpha, 1, "alpha clamped")
    eq(clean.tracker.border, "none", "unknown border")
    eq(clean.tracker.bg[1], 1)
    eq(clean.tracker.bg[2], 0, "bad channel falls back")
    eq(clean.tracker.bg[3], 0)
    eq(clean.tracker.borderColor[3], 0.75)
    eq(Model.CleanOptions({ font = "Fira Sans" }).font, "Fira Sans", "SharedMedia names are kept")
    eq(Model.CleanOptions("junk").scale, 100, "non-table")
    eq(defaults.title, "CustomQuests", "banner name defaults to the addon name")
    eq(Model.CleanOptions({ title = "  Mi |cffff0000diario  " }).title, "Mi cffff0000diario", "trimmed, no pipes")
    eq(Model.CleanOptions({ title = "   " }).title, "CustomQuests", "empty goes back to the default")
    eq(Model.CleanOptions({ title = 5 }).title, "CustomQuests", "non-string")
    eq(#Model.CleanOptions({ title = ("x"):rep(100) }).title, Model.MAX_TRACKER_TITLE, "length capped")
    eq(Model.account.options.scale, 100, "InitDB stores clean options")
end)

test("Level range blocks accepting outside it", function()
    local tid = assert(Model.SaveTemplate(template({ { type = "manual", text = "a" } }, { minLevel = 10, maxLevel = 20 }), nil, fake.now))
    fake.level = 5
    local _, err, arg = Lifecycle.Accept(tid)
    eq(err, "ERR_LEVEL_LOW") eq(arg, 10)
    fake.level = 25
    eq(select(2, Lifecycle.Accept(tid)), "ERR_LEVEL_HIGH")
    fake.level = 15
    assert(Lifecycle.Accept(tid))
    eq(select(2, Model.ValidateTemplate(template({ { type = "manual", text = "a" } }, { minLevel = 30, maxLevel = 20 }))), "ERR_LEVEL_RANGE")
end)

local function chainOf(n)
    local ids = {}
    for i = 1, n do
        ids[i] = assert(Model.SaveTemplate(template({ { type = "manual", text = "step" .. i } },
            { title = "Part " .. i, requires = ids[i - 1] }), nil, fake.now))
    end
    return ids
end

test("Chains are locked until the previous quest is done, then start on their own", function()
    local ids = chainOf(3)
    eq(select(2, Lifecycle.Accept(ids[2])), "ERR_LOCKED")
    local q1 = assert(Lifecycle.Accept(ids[1]))
    Objectives.AdjustManual(Lifecycle.Get(q1), 1, 1)
    settle()
    eq(Lifecycle.FindByTemplate(ids[2]), nil, "next link waits for the turn-in")
    turnIn(q1)
    local q2 = Lifecycle.FindByTemplate(ids[2])
    assert(q2, "second link accepted automatically")
    eq(Lifecycle.FindByTemplate(ids[3]), nil)
end)

test("Chains can't loop", function()
    local ids = chainOf(3)
    local first = Model.GetTemplate(ids[1])
    first.requires = ids[3]
    eq(select(2, Model.SaveTemplate(first, ids[1], fake.now)), "ERR_CHAIN_CYCLE")
end)

test("Only the first quest of a chain can be accepted by hand", function()
    local ids = chainOf(3)
    eq(select(2, Lifecycle.CanAccept(ids[1])), nil, "the first one is free")
    local q1 = assert(Lifecycle.Accept(ids[1]))
    Objectives.AdjustManual(Lifecycle.Get(q1), 1, 1)
    settle()
    turnIn(q1)
    local q2 = Lifecycle.FindByTemplate(ids[2])
    assert(q2, "the second one started by itself")
    -- Even with its predecessor completed, nobody accepts the third (or a repeat of the second) by hand.
    eq(select(2, Lifecycle.CanAccept(ids[3])), "ERR_LOCKED", "still locked")
    Lifecycle.Abandon(q2)
    eq(select(2, Lifecycle.Accept(ids[2])), "ERR_CHAIN_AUTO", "unlocked but automatic")
    eq(select(3, Lifecycle.Accept(ids[2])), "Part 1", "names the quest it follows")
end)

test("A chained quest stays hidden until its predecessor is turned in", function()
    local ids = chainOf(2)
    -- Accepted while free, then made part of a chain nobody has completed.
    local free = assert(Model.SaveTemplate(template({ { type = "manual", text = "x" } }, { title = "Free" }), nil, fake.now))
    local qid = assert(Lifecycle.Accept(free))
    eq(Lifecycle.IsUnlocked(Lifecycle.Get(qid)), true, "no predecessor")
    Model.account.templates[free].requires = ids[1]
    eq(Lifecycle.IsUnlocked(Lifecycle.Get(qid)), false, "predecessor never completed")
    -- Completing the predecessor unlocks it ...
    local q1 = assert(Lifecycle.Accept(ids[1]))
    Objectives.AdjustManual(Lifecycle.Get(q1), 1, 1)
    settle()
    turnIn(q1)
    eq(Lifecycle.IsUnlocked(Lifecycle.Get(qid)), true, "predecessor turned in")
    -- ... and doing the predecessor again locks it until that run is turned in.
    local again = assert(Lifecycle.Accept(ids[1]))
    eq(Lifecycle.IsUnlocked(Lifecycle.Get(qid)), false, "predecessor active again")
    Objectives.AdjustManual(Lifecycle.Get(again), 1, 1)
    settle()
    turnIn(again)
    eq(Lifecycle.IsUnlocked(Lifecycle.Get(qid)), true, "turned in again")
end)

test("The template tree nests chains under their first quest and honours folds", function()
    local ids = chainOf(3) -- Part 1 > Part 2 > Part 3
    local solo = assert(Model.SaveTemplate(template({ { type = "manual", text = "x" } }, { title = "Alone" }), nil, fake.now))
    local function shape(rows)
        local out = {}
        for _, r in ipairs(rows) do out[#out + 1] = r.depth .. (r.hasChildren and "+" or "") end
        return table.concat(out, ",")
    end
    local rows = Model.TemplateTree({})
    eq(shape(rows), "0,0+,1+,2", "Alone, then the chain")
    eq(rows[1].id, solo)
    eq(rows[2].count, 3, "the chain root counts the whole chain")
    eq(rows[3].count, 2)
    eq(shape(Model.TemplateTree({ [ids[1]] = true })), "0,0+", "folded root hides the rest")
    eq(Model.TemplateTree({ [ids[1]] = true })[2].collapsed, true)
    eq(shape(Model.TemplateTree({ [ids[2]] = true })), "0,0+,1+", "folding a middle quest hides what follows it")
    eq(shape(Model.TemplateTree({ [solo] = true })), "0,0+,1+,2", "folding a leaf does nothing")
end)

test("Exporting a chain carries every link and import rebuilds them", function()
    local ids = chainOf(3)
    local text = Serializer.ExportChain(ids[2])
    Model.InitDB({}, {})
    local entries = assert(Serializer.Import(text))
    eq(#entries, 3)
    local newIDs = Model.SaveImported(entries, fake.now)
    eq(Model.GetTemplate(newIDs[1]).requires, nil)
    eq(Model.GetTemplate(newIDs[2]).requires, newIDs[1])
    eq(Model.GetTemplate(newIDs[3]).requires, newIDs[2])
    eq(Model.GetTemplate(newIDs[3]).title, "Part 3")
end)

test("Imported chain links can only point backwards", function()
    local bad = Serializer.Encode({ chain = {
        { template = template({ { type = "manual", text = "a" } }), requires = 2 },
        { template = template({ { type = "manual", text = "b" } }), requires = 1 },
    } })
    local entries = assert(Serializer.Import(bad))
    eq(entries[1].requires, nil)
    eq(entries[2].requires, 1)
end)

test("Deleting a middle link reconnects the chain", function()
    local ids = chainOf(3)
    Model.DeleteTemplate(ids[2])
    eq(Model.GetTemplate(ids[3]).requires, ids[1])
end)

-- Chain A > B > (C > E, D); returns the ids by letter.
local function branchedChain()
    local function save(title, requires)
        return assert(Model.SaveTemplate(template({ { type = "manual", text = title } },
            { title = title, requires = requires }), nil, fake.now))
    end
    local a = save("A")
    local b = save("B", a)
    local c = save("C", b)
    local d = save("D", b)
    local e = save("E", c)
    return { A = a, B = b, C = c, D = d, E = e }
end

local function sortedSet(ids)
    local copy = { unpack(ids) }
    table.sort(copy)
    return table.concat(copy, ",")
end

test("GetDescendants lists everything after a quest in its chain", function()
    local t = branchedChain()
    eq(sortedSet(Model.GetDescendants(t.B)), sortedSet({ t.C, t.D, t.E }))
    eq(#Model.GetDescendants(t.E), 0)
end)

test("GetDescendants stops on a loop", function()
    local t = branchedChain()
    Model.account.templates[t.A].requires = t.E -- forced loop A > B > C > E > A
    eq(#Model.GetDescendants(t.B), 4, "every other member once, and it ends")
end)

test("NeedsBranchChoice is only true when a follow-up stays behind", function()
    local t = branchedChain()
    eq(Model.NeedsBranchChoice({ t.B, t.C, t.D, t.E }), false)
    eq(Model.NeedsBranchChoice({ t.B }), true)
    eq(Model.NeedsBranchChoice({ t.E }), false)
end)

test("DeleteTemplates with the branch removes everything after", function()
    local t = branchedChain()
    Model.DeleteTemplates({ t.B }, true)
    eq(#Model.ListTemplates(), 1)
    eq(Model.GetTemplate(t.A) ~= nil, true)
end)

test("DeleteTemplates without the branch relinks the follow-ups", function()
    local t = branchedChain()
    Model.DeleteTemplates({ t.B }, false)
    eq(#Model.ListTemplates(), 4)
    eq(Model.GetTemplate(t.C).requires, t.A)
    eq(Model.GetTemplate(t.D).requires, t.A)
    eq(Model.GetTemplate(t.E).requires, t.C)
end)

test("DeleteTemplates of parent and child together leaves the rest hanging in place", function()
    local t = branchedChain()
    Model.DeleteTemplates({ t.A, t.B }, false)
    eq(Model.GetTemplate(t.C).requires, nil)
    eq(Model.GetTemplate(t.D).requires, nil)
    eq(Model.GetTemplate(t.E).requires, t.C)
end)

-- Sections -----------------------------------------------------------------------

local function quest(title, extra)
    local tpl = template({ { type = "manual", text = "x" } }, { title = title })
    for k, v in pairs(extra or {}) do tpl[k] = v end
    return assert(Model.SaveTemplate(tpl, nil, fake.now))
end

local function headerShape(list, label)
    local out = {}
    for _, e in ipairs(list) do
        if e.header then
            out[#out + 1] = "[" .. (e.header.name or "none") .. ":" .. e.count .. (e.collapsed and "-" or "") .. "]"
        else
            out[#out + 1] = label(e)
        end
    end
    return table.concat(out, ",")
end

test("Sections: create, rename and reject bad or repeated names", function()
    local a = assert(Model.CreateSection("  Lost Isles ", fake.now))
    eq(Model.SectionByID(a).name, "Lost Isles", "name is trimmed")
    eq(select(2, Model.CreateSection("lost isles", fake.now)), "ERR_SECTION_EXISTS", "case-insensitive")
    eq(select(2, Model.CreateSection("   ", fake.now)), "ERR_SECTION_NAME")
    local b = assert(Model.CreateSection("A|cffff0000B", fake.now))
    eq(Model.SectionByID(b).name, "Acffff0000B", "pipes are stripped")
    assert(Model.RenameSection(a, "Isles"))
    eq(Model.SectionByID(a).name, "Isles")
    eq(select(2, Model.RenameSection(a, "acffff0000b")), "ERR_SECTION_EXISTS")
    assert(Model.RenameSection(a, "ISLES"), "renaming to itself is fine")
end)

test("Sections: a template keeps its section and an unknown id reads as none", function()
    local s = assert(Model.CreateSection("S", fake.now))
    local id = quest("Q", { section = s })
    eq(Model.GetTemplate(id).section, s)
    local stray = quest("Stray", { section = "s-does-not-exist" })
    eq(Model.GetTemplate(stray).section, nil)
end)

test("Sections: deleting one keeps its quests, now without section", function()
    local s = assert(Model.CreateSection("S", fake.now))
    local id = quest("Q", { section = s })
    Model.account.sectionCollapsed[s] = true
    Model.char.sectionCollapsed.tracker[s] = true
    Model.DeleteSection(s)
    eq(#Model.ListSections(), 0)
    eq(Model.GetTemplate(id).section, nil)
    eq(Model.account.sectionCollapsed[s], nil)
    eq(Model.char.sectionCollapsed.tracker[s], nil)
end)

test("Sections: move up/down and SetSection", function()
    local a, b = Model.CreateSection("A", fake.now), Model.CreateSection("B", fake.now)
    eq(Model.MoveSection(a, -1), false)
    eq(Model.MoveSection(a, 1), true)
    eq(Model.ListSections()[1].id, b)
    local q1, q2 = quest("Q1"), quest("Q2")
    eq(Model.SetSection({ q1, q2 }, a), 2)
    eq(Model.SetSection({ q1, q2 }, a), 0, "nothing changes the second time")
    eq(Model.SetSection({ q1 }, "nope"), 0)
    eq(Model.SetSection({ q1 }, nil), 1)
end)

test("Sections: InitDB cleans broken saved data", function()
    local db = { sections = { { id = "a", name = "Ok" }, { id = "a", name = "Dup" }, { id = "b c", name = "X" },
        { id = "d", name = 5 }, "junk" } }
    Model.InitDB(db, {})
    eq(#db.sections, 1)
    eq(db.sections[1].name, "Ok")
    Model.InitDB({ sections = "bad" }, {})
    eq(#Model.account.sections, 0)
end)

test("Sections: moving a quest moves its whole chain", function()
    local s = assert(Model.CreateSection("S", fake.now))
    local ids = chainOf(3)
    local other = quest("Other")
    eq(Model.SetSection({ ids[2] }, s), 3, "the middle quest brings the whole chain")
    for _, id in ipairs(ids) do eq(Model.GetTemplate(id).section, s) end
    eq(Model.GetTemplate(other).section, nil)
    eq(Model.SetSection({ ids[3] }, nil), 3, "and back out again")
    eq(Model.GetTemplate(ids[1]).section, nil)
end)

test("Sections: a chain split by older data still shows up in the tree", function()
    local s = assert(Model.CreateSection("S", fake.now))
    local ids = chainOf(3)
    quest("Loose")
    Model.GetTemplate(ids[1]).section = s
    Model.GetTemplate(ids[3]).section = s
    local function label(e) return Model.GetTemplate(e.row.id).title .. "@" .. e.row.depth end
    eq(headerShape(Model.SectionedTree({}, {}), label), "[S:2],Part 1@0,Part 3@0,[none:2],Loose@0,Part 2@0",
        "Part 3 starts its own tree in S because Part 2 isn't there")
    eq(headerShape(Model.SectionedTree({ [s] = true }, {}), label), "[S:2-],[none:2],Loose@0,Part 2@0")
    Model.DeleteSection(s)
    local plain = Model.SectionedTree({}, {})
    eq(#plain, 4)
    eq(plain[1].header, nil, "no sections: plain tree, no headers")
end)

test("Sections: an empty section keeps its header in the Templates tree", function()
    local s = assert(Model.CreateSection("Empty", fake.now))
    quest("Loose")
    local tree = Model.SectionedTree({}, {})
    eq(tree[1].header.id, s)
    eq(tree[1].count, 0)
end)

test("Sections: GroupBySection orders by section, loose last, hides folded and empty ones", function()
    local a, b = Model.CreateSection("A", fake.now), Model.CreateSection("B", fake.now)
    local items = { { n = 1, s = b }, { n = 2 }, { n = 3, s = a }, { n = 4, s = b } }
    local function label(e) return tostring(e.item.n) end
    local get = function(item) return item.s end
    eq(headerShape(Model.GroupBySection(items, get, {}), label), "[A:1],3,[B:2],1,4,[none:1],2")
    eq(headerShape(Model.GroupBySection(items, get, { [b] = true }), label), "[A:1],3,[B:2-],[none:1],2")
    eq(headerShape(Model.GroupBySection({ { n = 3, s = a } }, get, {}), label), "[A:1],3", "empty groups are hidden")
    eq(headerShape(Model.GroupBySection({ { n = 3, s = a } }, get, {}, true), label), "[A:1],3,[B:0]", "unless asked for")
    Model.DeleteSection(a)
    Model.DeleteSection(b)
    eq(headerShape(Model.GroupBySection(items, get, {}), label), "1,2,3,4", "no sections, no headers")
end)

test("Sections: export carries the section by name and import matches or creates it", function()
    local s = assert(Model.CreateSection("Lost Isles", fake.now))
    local ids = chainOf(2)
    Model.SetSection({ ids[1] }, s)
    local text = Serializer.ExportChain(ids[1])
    local single = Serializer.ExportTemplate(Model.GetTemplate(ids[1]))
    Model.InitDB({}, {})
    local entries = assert(Serializer.Import(text))
    eq(entries[1].section, "Lost Isles")
    eq(entries[2].section, "Lost Isles", "the whole chain moved with it")
    eq(entries[1].template.section, nil, "ids never travel")
    local newIDs = Model.SaveImported(entries, fake.now)
    eq(#Model.ListSections(), 1)
    local sid = Model.GetTemplate(newIDs[1]).section
    eq(Model.SectionByID(sid).name, "Lost Isles")
    eq(Model.GetTemplate(newIDs[2]).section, sid)
    -- A second import reuses the section instead of duplicating it.
    local again = assert(Serializer.Import(single))
    eq(again[1].section, "Lost Isles")
    local id2 = Model.SaveImported(again, fake.now)[1]
    eq(#Model.ListSections(), 1)
    eq(Model.GetTemplate(id2).section, sid)
end)

test("Sections: exporting a section carries its quests and the links among them", function()
    local s = assert(Model.CreateSection("Pack", fake.now))
    local ids = chainOf(3)
    local other = quest("Other")
    Model.SetSection({ ids[1], ids[2], other }, s)
    local entries = assert(Serializer.Import(assert(Serializer.ExportSection(s))))
    eq(#entries, 4)
    local titles = {}
    for i, e in ipairs(entries) do
        titles[#titles + 1] = e.template.title
        eq(e.section, "Pack")
        if e.requires then eq(e.requires < i, true) end
    end
    eq(table.concat(titles, ","), "Other,Part 1,Part 2,Part 3")
    eq(Serializer.ExportSection("nothing"), nil)
end)

test("Sections: a hostile section name in an import is cleaned", function()
    local payload = Serializer.Encode({ title = "T", stages = { { objectives = { { type = "manual", text = "x" } } } },
        sectionName = "|cffff0000Evil|r" })
    local entries = assert(Serializer.Import(payload))
    eq(entries[1].section, "cffff0000Evilr")
end)

-- Imports and duplicates -----------------------------------------------------------

test("Importing the same template twice keeps one copy and says so", function()
    local id = quest("Twice")
    local text = Serializer.ExportChain(id)
    local ids, skipped = Model.SaveImported(assert(Serializer.Import(text)), fake.now)
    eq(ids[1], id, "the existing template stands in")
    eq(skipped[1], true)
    eq(#Model.ListTemplates(), 1)
    -- Edited a little: it is a different quest now, so it is saved.
    local tpl = Model.GetTemplate(id)
    tpl.description = "changed"
    local ids2, skipped2 = Model.SaveImported(assert(Serializer.Import(text)), fake.now)
    eq(skipped2[1], nil)
    assert(ids2[1] ~= id)
    eq(#Model.ListTemplates(), 2)
end)

test("A chain whose first quest exists links the new ones to it", function()
    local ids = chainOf(3)
    local text = Serializer.ExportChain(ids[1])
    Model.DeleteTemplate(ids[3])
    Model.DeleteTemplate(ids[2])
    local newIDs, skipped = Model.SaveImported(assert(Serializer.Import(text)), fake.now)
    eq(skipped[1], true)
    eq(newIDs[1], ids[1])
    eq(Model.GetTemplate(newIDs[2]).requires, ids[1])
    eq(Model.GetTemplate(newIDs[3]).requires, newIDs[2])
    eq(#Model.ListTemplates(), 3)
end)

test("Fingerprint ignores where a template lives, not what it says", function()
    local a = Model.ValidateTemplate(template({ { type = "manual", text = "x" } }))
    local b = Util.DeepCopy(a)
    b.section, b.requires, b.createdAt = "s-1", "t-1", 5
    eq(Model.Fingerprint(a), Model.Fingerprint(b))
    b.title = "Other"
    assert(Model.Fingerprint(a) ~= Model.Fingerprint(b))
    eq(Model.Fingerprint({}), nil)
end)

test("Imports stop at the template cap", function()
    local old = Model.MAX_TEMPLATES
    Model.MAX_TEMPLATES = 2
    quest("One")
    local text = Serializer.ExportChain(quest("Two"))
    local fresh = Serializer.Encode(Model.ValidateTemplate(template({ { type = "manual", text = "x" } }, { title = "Three" })))
    local ok, err = pcall(function()
        eq(select(2, Model.SaveImported(assert(Serializer.Import(fresh)), fake.now)), "ERR_TOO_MANY_TEMPLATES")
        eq(Model.SaveImported(assert(Serializer.Import(text)), fake.now)[1] ~= nil, true, "a duplicate costs nothing")
    end)
    Model.MAX_TEMPLATES = old
    assert(ok, err)
    eq(#Model.ListTemplates(), 2)
end)

-- Comm: framing, fragments, throttle ---------------------------------------------------

test("Comm frames split on ~ and keep the rest in the last field", function()
    local f = Comm.Unpack(Comm.Pack("1", "D", "abc", "rest~with~tildes"), 4)
    eq(#f, 4)
    eq(f[3], "abc")
    eq(f[4], "rest~with~tildes")
    eq(#Comm.Unpack("only", 5), 1)
end)

test("Comm fragments reassemble out of order, ignoring duplicates", function()
    local payload = ("0123456789"):rep(50) -- 500 bytes
    local chunks = Comm.Fragment(payload, 240)
    eq(#chunks, 3)
    eq(#chunks[3], 20)
    local a = assert(Comm.NewAssembly(3, 16384, 0))
    eq(a:Add(3, chunks[3], 1), "added")
    eq(a:Add(1, chunks[1], 2), "added")
    eq(a:Add(1, "other", 3), "duplicate", "the first copy wins")
    eq(a:IsComplete(), false)
    eq(a:Result(), nil)
    eq(table.concat(a:Missing(), ","), "2")
    eq(a:Add(2, chunks[2], 4), "added")
    eq(a:Result(), payload)
    eq(#Comm.Fragment("", 240), 1, "an empty payload is still one fragment")
end)

test("Comm assembly refuses bad indexes, empty chunks and oversize payloads", function()
    local a = assert(Comm.NewAssembly(3, 10, 0))
    eq(select(2, a:Add(0, "x", 0)), "bad_index")
    eq(select(2, a:Add(4, "x", 0)), "bad_index")
    eq(select(2, a:Add(1.5, "x", 0)), "bad_index")
    eq(select(2, a:Add("1", "x", 0)), "bad_index")
    eq(select(2, a:Add(1, "", 0)), "empty")
    eq(a:Add(1, "123456", 0), "added")
    eq(select(2, a:Add(2, "12345", 0)), "too_big")
    eq(Comm.NewAssembly(0, 10, 0), nil)
    eq(Comm.NewAssembly(Comm.MAX_FRAGMENTS + 1, 10, 0), nil)
    eq(Comm.NewAssembly(2.5, 10, 0), nil)
end)

test("Comm assembly times out from the last fragment", function()
    local a = assert(Comm.NewAssembly(2, 100, 0))
    a:Add(1, "x", 20)
    eq(a:Expired(45, 30), false)
    eq(a:Expired(51, 30), true)
end)

test("Comm chunk size leaves room for the header", function()
    eq(Comm.ChunkSize("1~D~abcdef~1~2~p~"), 238)
    eq(Comm.ChunkSize("x"), Comm.MAX_CHUNK)
end)

test("Token bucket: a burst of its capacity, then its rate", function()
    local b = Comm.NewBucket(10, 1, 0)
    local n = 0
    for _ = 1, 20 do if b:Take(0) then n = n + 1 end end
    eq(n, 10)
    eq(b:Take(0.5), false)
    eq(b:Take(1.01), true)
    eq(b:Take(1.02), false)
    b:Refill(100)
    eq(b.tokens, 10, "never above capacity")
    b:Drain(100)
    eq(b:Take(100), false)
end)

-- A fake transport for the queue: records what it sends, answers from a script.
local function fakeTransport(answers)
    local log = {}
    Comm.Reset()
    Comm.transport = function(prefix, text, channel, target)
        eq(prefix, Comm.PREFIX)
        local answer = table.remove(answers, 1) or "ok"
        if answer == "ok" then log[#log + 1] = { text = text, channel = channel, target = target } end
        return answer
    end
    return log
end

test("Comm queue: group messages burst 10 then go 1 per second; whispers 5 per second", function()
    local log = fakeTransport({})
    Comm.inLockdown = function() return false end
    for i = 1, 15 do Comm.Enqueue("g" .. i, "PARTY", nil, "t") end
    for i = 1, 15 do Comm.Enqueue("w" .. i, "WHISPER", "Bob", "u") end
    Comm.Pump(0)
    eq(#log, 20, "10 of each lane at once")
    eq(Comm.Pending("t"), 5)
    Comm.Pump(1)
    eq(Comm.Pending("t"), 4, "one more group message a second later")
    eq(Comm.Pending("u"), 0, "five more whispers a second later")
    eq(log[1].text, "g1")
    eq(log[11].channel, "WHISPER")
    eq(log[11].target, "Bob")
end)

test("Comm queue backs off on throttle and pauses on lockdown", function()
    local log = fakeTransport({ "ok", "throttle" })
    local locked, lockdowns = false, 0
    Comm.inLockdown = function() return locked end
    Comm.onLockdown = function() lockdowns = lockdowns + 1 end
    for i = 1, 3 do Comm.Enqueue("m" .. i, "WHISPER", "Bob", "t") end
    Comm.Pump(0)
    eq(#log, 1)
    Comm.Pump(1)
    eq(#log, 1, "still backing off")
    Comm.Pump(0 + Comm.BACKOFF + 1)
    eq(#log, 3, "the throttled message is retried, nothing is lost")
    -- Lockdown: nothing goes out until it lifts, then everything does.
    locked = true
    Comm.Enqueue("late", "WHISPER", "Bob", "t")
    Comm.Pump(10)
    eq(Comm.paused, true)
    eq(lockdowns, 1)
    Comm.Pump(11)
    eq(lockdowns, 1, "told once")
    eq(#log, 3)
    locked = false
    Comm.Pump(12)
    eq(#log, 4)
    eq(Comm.paused, false)
    -- A lockdown answer from the server pauses the same way.
    fakeTransport({ "lockdown" })
    Comm.inLockdown = function() return false end
    Comm.Enqueue("x", "PARTY", nil, "t")
    Comm.Pump(20)
    eq(Comm.paused, true)
    eq(Comm.Pending(), 1, "kept for later")
    Comm.Pump(21)
    eq(Comm.Pending(), 0, "sent once the lockdown is over")
end)

test("Comm queue drops a whole transfer when a message fails", function()
    fakeTransport({ "offline" })
    Comm.inLockdown = function() return false end
    local failed
    Comm.onFail = function(tag, result) failed = tag .. ":" .. result end
    for i = 1, 3 do Comm.Enqueue("m" .. i, "WHISPER", "Gone", "t1") end
    Comm.Enqueue("other", "WHISPER", "Bob", "t2")
    Comm.Pump(0)
    eq(failed, "t1:offline")
    eq(Comm.Pending("t1"), 0)
    eq(Comm.Pending("t2"), 0, "the other transfer still went out")
    eq(Comm.Cancel("t2"), 0)
    Comm.onFail = function() end
end)

-- Share: the offer / accept / data protocol between fake players ---------------------------
-- Each client loads its own copy of the modules (its own SavedVariables, Comm
-- queue and Share state); net carries the addon messages between them.

local net = { now = 0, clients = {}, wire = {} }

local function fullName(n)
    if type(n) ~= "string" or n == "" then return nil end
    return n:find("-", 1, true) and n or (n .. "-Realm")
end

function net.reset()
    net.now, net.clients, net.wire = 0, {}, {}
    net.filter = nil
end

local function newClient(name)
    local c = { name = name, full = name .. "-Realm", printed = {}, shown = {}, hidden = {}, imported = {},
        trusted = {}, ignored = {}, canSend = true, lockdown = false, combat = false }
    local cns = { L = ns.L }
    cns.api = {
        Now = function() return 1000 + math.floor(net.now) end,
        IsSecret = function() return false end,
        GetPlayerTokens = function() return {} end,
        FullName = fullName,
        PlayerFullName = function() return c.full end,
        ShortName = function(n) return (n:gsub("%-Realm$", "")) end,
        CanSendComm = function() if c.canSend then return true end return false, "ERR_SHARE_TRIAL" end,
        GroupChannel = function() return c.group and "PARTY" or nil end,
        IsInGuild = function() return c.guild ~= nil end,
        InChatLockdown = function() return c.lockdown end,
        InCombat = function() return c.combat end,
        IsIgnored = function(n) return c.ignored[fullName(n)] or false end,
        IsTrusted = function(n) return c.trusted[fullName(n)] or false end,
        GetCodec = function() return c.codec end,
    }
    for _, file in ipairs({ "Util.lua", "Model.lua", "Serializer.lua", "Comm.lua", "Share.lua" }) do
        assert(loadfile(file))("CustomQuests", cns)
    end
    cns.Model.InitDB({}, {})
    -- Tests opt into the default "trusted" setting where they check it.
    cns.Model.account.options.sharing.incoming = "anyone"
    local S = cns.Share
    cns.Comm.transport = function(_, text, channel, target)
        if c.sendResult then return c.sendResult end
        net.wire[#net.wire + 1] = { from = c, text = text, channel = channel, target = target }
        return "ok"
    end
    cns.Comm.inLockdown = function() return c.lockdown end
    cns.Comm.onFail = function(tag, result) S.OnSendFailed(tag, result) end
    S.notify = function(key) c.printed[#c.printed + 1] = key end
    S.showOffer = function(offer) c.shown[#c.shown + 1] = offer end
    S.hideOffer = function(offer) c.hidden[#c.hidden + 1] = offer end
    S.imported = function(entries, ids, skipped) c.imported[#c.imported + 1] = { entries = entries, ids = ids, skipped = skipped } end
    c.ns, c.Share, c.Model, c.Comm = cns, S, cns.Model, cns.Comm
    net.clients[c.full] = c
    return c
end

local function printed(c, key)
    for _, k in ipairs(c.printed) do if k == key then return true end end
    return false
end

-- Pumps every queue and delivers until nothing moves. net.filter(msg) may drop
-- (false) messages; net.shuffle reverses each batch to deliver out of order.
function net.flush(seconds)
    for _ = 1, 200 do
        for _, c in pairs(net.clients) do c.Comm.Pump(net.now) end
        local batch = net.wire
        net.wire = {}
        if #batch == 0 then
            if (seconds or 0) <= 0 then return end
            net.now = net.now + 1
            seconds = seconds - 1
        end
        if net.shuffle then
            for i = 1, math.floor(#batch / 2) do batch[i], batch[#batch - i + 1] = batch[#batch - i + 1], batch[i] end
        end
        for _, msg in ipairs(batch) do
            if not net.filter or net.filter(msg) ~= false then
                if msg.channel == "WHISPER" then
                    local to = net.clients[fullName(msg.target)]
                    if to then to.Share.OnMessage(msg.text, "WHISPER", msg.from.full, net.now) end
                else
                    for _, to in pairs(net.clients) do
                        local same = (msg.channel == "GUILD" and to.guild == msg.from.guild)
                            or (msg.channel ~= "GUILD" and to.group == msg.from.group)
                        if same and to.group ~= nil or same and msg.channel == "GUILD" then
                            to.Share.OnMessage(msg.text, msg.channel, msg.from.full, net.now)
                        end
                    end
                end
            end
        end
    end
end

local function tick(seconds)
    for _ = 1, seconds do
        net.now = net.now + 1
        for _, c in pairs(net.clients) do c.Share.Tick(net.now) end
        net.flush()
    end
end

-- A chain of n quests in c's templates, each with a long description so the
-- transfer needs several fragments. Returns the first id.
local function chainIn(c, n, prefix)
    local ids = {}
    for i = 1, n do
        ids[i] = assert(c.Model.SaveTemplate({ title = (prefix or "Part ") .. i,
            description = ("Lorem ipsum dolor sit amet %d. "):format(i):rep(14),
            stages = { { objectives = { { type = "manual", text = "step " .. i } } } },
            requires = ids[i - 1] }, nil, 1000))
    end
    return ids[1]
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local function shareTest(name, fn)
    test(name, function()
        net.reset()
        net.shuffle = false
        Comm.Reset()
        fn()
    end)
end

shareTest("Share: a whispered chain arrives in several fragments and is imported", function()
    local a, b = newClient("Alice"), newClient("Bob")
    local first = chainIn(a, 3)
    eq(a.Share.Describe("quest", first).kind, "chain")
    assert(a.Share.Offer("quest", first, "WHISPER", "Bob", net.now))
    net.flush()
    eq(#b.shown, 1)
    local offer = b.shown[1]
    eq(offer.title, "Part 1")
    eq(offer.count, 3)
    eq(offer.kind, "chain")
    eq(offer.senderLabel, "Alice")
    assert(offer.bytes > 3 * Comm.MAX_CHUNK, "big enough for several fragments")
    b.Share.Accept(offer, net.now)
    net.shuffle = true -- fragments arrive in reverse order
    net.flush(5)
    eq(#b.imported, 1)
    eq(#b.Model.ListTemplates(), 3)
    local imported = b.imported[1]
    eq(b.Model.GetTemplate(imported.ids[3]).requires, imported.ids[2], "links rebuilt")
    assert(printed(a, "SHARE_DELIVERED"))
    eq(count(a.Share.Outgoing()), 0, "a whisper offer is done once delivered")
    eq(count(b.Share.Incoming()), 0)
    assert(a.Share.IsIdle() and b.Share.IsIdle())
end)

shareTest("Share: sending the same quest again reports a duplicate, not a copy", function()
    local a, b = newClient("Alice"), newClient("Bob")
    local id = chainIn(a, 1)
    for round = 1, 2 do
        assert(a.Share.Offer("quest", id, "WHISPER", "Bob", net.now))
        net.flush()
        b.Share.Accept(b.shown[round], net.now)
        net.flush(5)
        net.now = net.now + Share.SENDER_COOLDOWN + 1
    end
    eq(#b.Model.ListTemplates(), 1)
    eq(b.imported[2].skipped[1], true)
    assert(printed(a, "SHARE_DELIVERED_DUP"))
end)

shareTest("Share: declining tells the sender and imports nothing", function()
    local a, b = newClient("Alice"), newClient("Bob")
    assert(a.Share.Offer("quest", chainIn(a, 1), "WHISPER", "Bob", net.now))
    net.flush()
    b.Share.Decline(b.shown[1])
    net.flush()
    assert(printed(a, "SHARE_DECLINED"))
    eq(#b.Model.ListTemplates(), 0)
    eq(count(a.Share.Outgoing()), 0)
end)

shareTest("Share: blocking a sender hides their later offers, and persists", function()
    local a, b = newClient("Alice"), newClient("Bob")
    local id = chainIn(a, 1)
    a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)
    net.flush()
    b.Share.Block(b.shown[1])
    assert(b.Model.IsShareBlocked("alice-realm"))
    net.now = net.now + 100
    a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)
    net.flush()
    eq(#b.shown, 1, "no second popup")
    eq(b.Share.dropped, 1)
    eq(#a.printed, 0, "the sender learns nothing")
    -- Survives a reload: InitDB keeps the cleaned list.
    b.Model.InitDB(b.Model.account, b.Model.char)
    assert(b.Model.IsShareBlocked("alice-realm"))
    b.Model.ClearShareBlocked()
    eq(b.Model.IsShareBlocked("alice-realm"), false)
end)

shareTest("Share: the game's ignore list and the incoming setting are honoured", function()
    local a, b = newClient("Alice"), newClient("Bob")
    local id = chainIn(a, 1)
    b.ignored["Alice-Realm"] = true
    a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)
    net.flush()
    eq(#b.shown, 0, "ignored")
    b.ignored = {}
    -- Default: whispers only from friends, guild and group.
    b.Model.account.options.sharing.incoming = "trusted"
    net.now = net.now + 100
    a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)
    net.flush()
    eq(#b.shown, 0, "a stranger's whisper")
    b.trusted["Alice-Realm"] = true
    net.now = net.now + 100
    a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)
    net.flush()
    eq(#b.shown, 1, "a friend's whisper")
    b.Share.Decline(b.shown[1])
    b.Model.account.options.sharing.incoming = "off"
    net.now = net.now + 100
    a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)
    net.flush()
    eq(#b.shown, 1, "off means off")
    b.trusted = {}
    b.Model.account.options.sharing.incoming = "anyone"
    net.now = net.now + 100
    a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)
    net.flush()
    eq(#b.shown, 2, "anyone")
    eq(Model.CleanOptions({ sharing = { incoming = "everyone" } }).sharing.incoming, "trusted", "bad value")
    eq(Model.CleanOptions({ sharing = { chatLinks = false } }).sharing.chatLinks, false)
end)

shareTest("Share: offers from one sender are rate limited, and pending offers capped", function()
    local a, b = newClient("Alice"), newClient("Bob")
    b.Model.account.options.sharing.incoming = "anyone"
    local id = chainIn(a, 1)
    a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)
    net.flush()
    net.now = net.now + 5
    a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)
    net.flush()
    eq(#b.Share.PendingOffers(), 1, "second offer within the cooldown dropped")
    eq(b.Share.dropped, 1)
    -- Three more senders: only MAX_PENDING wait, the last one hears "busy".
    for _, n in ipairs({ "Cara", "Dan", "Eve" }) do
        local c = newClient(n)
        c.Share.Offer("quest", chainIn(c, 1, n), "WHISPER", "Bob", net.now)
        net.flush()
    end
    eq(#b.Share.PendingOffers(), Share.MAX_PENDING)
    eq(#b.shown, 1, "one popup at a time")
    assert(printed(net.clients["Eve-Realm"], "SHARE_REMOTE_BUSY"))
    -- Answering the popup shows the next one.
    b.Share.Decline(b.shown[1])
    eq(#b.shown, 2)
    eq(b.shown[2].senderLabel, "Cara")
end)

shareTest("Share: unsolicited or foreign data is dropped", function()
    local a, b, c = newClient("Alice"), newClient("Bob"), newClient("Cara")
    b.Model.account.options.sharing.incoming = "anyone"
    local id = chainIn(a, 1)
    local tid = a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)
    net.flush()
    -- Data before accepting, from the sender and from a third player.
    local forged = Serializer.Encode(Model.ValidateTemplate(template({ { type = "manual", text = "x" } }, { title = "Evil" })))
    local frame = Comm.Pack("1", "D", tid, 1, 1, "p", forged)
    b.Share.OnMessage(frame, "WHISPER", "Alice-Realm", net.now)
    b.Share.OnMessage(frame, "WHISPER", "Cara-Realm", net.now)
    b.Share.Accept(b.shown[1], net.now)
    -- Accepted from Alice: Cara still can't slip data in.
    b.Share.OnMessage(frame, "WHISPER", "Cara-Realm", net.now)
    -- Nor can anyone over a group channel.
    b.Share.OnMessage(frame, "PARTY", "Alice-Realm", net.now)
    eq(#b.Model.ListTemplates(), 0)
    net.flush(5)
    eq(#b.Model.ListTemplates(), 1)
    eq(b.Model.ListTemplates()[1].template.title, "Part 1", "the real quest, not the forged one")
    eq(#c.shown, 0)
end)

shareTest("Share: a transfer that stalls times out on both sides", function()
    local a, b = newClient("Alice"), newClient("Bob")
    local tid = a.Share.Offer("quest", chainIn(a, 3), "WHISPER", "Bob", net.now)
    net.flush()
    b.Share.Accept(b.shown[1], net.now)
    -- Lose every second fragment.
    local n = 0
    net.filter = function(msg)
        if msg.text:find("~D~", 1, true) then
            n = n + 1
            return n % 2 == 0
        end
    end
    net.flush(3)
    eq(count(b.Share.Incoming()), 1, "still waiting")
    net.filter = nil
    tick(Share.TRANSFER_TIMEOUT + 2)
    assert(printed(b, "SHARE_TIMEOUT"))
    eq(count(b.Share.Incoming()), 0)
    eq(#b.Model.ListTemplates(), 0)
    -- The sender got the abort; late fragments are dropped by the receiver.
    b.Share.OnMessage(Comm.Pack("1", "D", tid, 1, 9, "p", "x"), "WHISPER", "Alice-Realm", net.now)
    eq(count(b.Share.Incoming()), 0)
    tick(Share.OFFER_TTL)
    eq(count(a.Share.Outgoing()), 0)
end)

shareTest("Share: the sender can be told to stop, and a receiver abort cancels the queue", function()
    local a, b = newClient("Alice"), newClient("Bob")
    a.group, b.group = 1, 1
    local tid = a.Share.Offer("quest", chainIn(a, 3), "GROUP", nil, net.now)
    net.flush()
    b.Share.Accept(b.shown[1], net.now)
    -- Hold the data back, then Bob aborts.
    net.filter = function(msg) return not msg.text:find("~D~", 1, true) end
    a.lockdown = true
    net.flush()
    assert(a.Comm.Pending() > 0)
    b.Share.OnMessage(Comm.Pack("1", "X", tid), "WHISPER", "Alice-Realm", net.now) -- harmless on the receiver: Alice isn't sending to herself
    a.Share.OnMessage(Comm.Pack("1", "X", tid), "WHISPER", "Bob-Realm", net.now)
    eq(a.Comm.Pending(), 0, "nothing more queued for Bob")
end)

shareTest("Share: a group offer reaches everyone but the sender, each accepts on their own", function()
    local a, b, c = newClient("Alice"), newClient("Bob"), newClient("Cara")
    a.group, b.group, c.group = 1, 1, 1
    local tid = assert(a.Share.Offer("quest", chainIn(a, 2), "GROUP", nil, net.now))
    net.flush()
    eq(#a.shown, 0, "our own echo is ignored")
    eq(#b.shown, 1, "group offers pass the trusted setting")
    eq(#c.shown, 1)
    b.Share.Accept(b.shown[1], net.now)
    c.Share.Accept(c.shown[1], net.now)
    net.flush(10)
    eq(#b.Model.ListTemplates(), 2)
    eq(#c.Model.ListTemplates(), 2)
    eq(count(a.Share.Outgoing()[tid].recipients), 2)
    tick(Share.OFFER_TTL + 1)
    eq(count(a.Share.Outgoing()), 0, "a group offer ends when it expires")
    -- Accepting after that is refused.
    local d = newClient("Dan")
    d.Share.OnMessage(Comm.Pack("1", "O", tid, "quest", 1, 10, "0", "T"), "PARTY", "Alice-Realm", net.now)
    d.Share.Accept(d.shown[1], net.now)
    net.flush()
    assert(printed(d, "SHARE_ABORTED"))
end)

shareTest("Share: offers check the sender can send, the channel and the size", function()
    local a = newClient("Alice")
    local id = chainIn(a, 1)
    a.canSend = false
    eq(select(2, a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)), "ERR_SHARE_TRIAL")
    a.canSend = true
    eq(select(2, a.Share.Offer("quest", id, "GROUP", nil, net.now)), "ERR_SHARE_NO_GROUP")
    eq(select(2, a.Share.Offer("quest", id, "GUILD", nil, net.now)), "ERR_SHARE_NO_GUILD")
    eq(select(2, a.Share.Offer("quest", id, "WHISPER", "  ", net.now)), "ERR_SHARE_NO_TARGET")
    eq(select(2, a.Share.Offer("quest", id, "WHISPER", "alice", net.now)), "ERR_SHARE_SELF")
    eq(select(2, a.Share.Offer("quest", "nope", "WHISPER", "Bob", net.now)), "ERR_NO_TEMPLATE")
    eq(select(2, a.Share.Offer("section", "nope", "WHISPER", "Bob", net.now)), "ERR_SECTION_EMPTY")
    for i = 1, Share.MAX_OUTGOING do assert(a.Share.Offer("quest", id, "WHISPER", "P" .. i, net.now)) end
    eq(select(2, a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)), "ERR_SHARE_BUSY")
end)

shareTest("Share: a whole section can be offered", function()
    local a, b = newClient("Alice"), newClient("Bob")
    local s = assert(a.Model.CreateSection("Pack", 1000))
    a.Model.SetSection({ chainIn(a, 2), chainIn(a, 1, "Solo ") }, s)
    assert(a.Share.Offer("section", s, "WHISPER", "Bob", net.now))
    net.flush()
    eq(b.shown[1].kind, "section")
    eq(b.shown[1].title, "Pack")
    eq(b.shown[1].count, 3)
    b.Share.Accept(b.shown[1], net.now)
    net.flush(5)
    eq(#b.Model.ListTemplates(), 3)
    eq(b.Model.ListSections()[1].name, "Pack")
end)

shareTest("Share: oversize, changed or malformed data fails the transfer", function()
    local b = newClient("Bob")
    b.Model.account.options.sharing.incoming = "anyone"
    local function offerFrom(sender, tid, bytes)
        b.Share.OnMessage(Comm.Pack("1", "O", tid, "quest", 1, bytes, "0", "T"), "WHISPER", sender, net.now)
        b.Share.Accept(b.shown[#b.shown], net.now)
    end
    offerFrom("Alice-Realm", "t1", 10)
    b.Share.OnMessage(Comm.Pack("1", "D", "t1", 1, 2, "p", ("x"):rep(11)), "WHISPER", "Alice-Realm", net.now)
    assert(printed(b, "SHARE_TOO_BIG"), "more bytes than announced")
    net.now = net.now + 100
    offerFrom("Alice-Realm", "t2", 100)
    b.Share.OnMessage(Comm.Pack("1", "D", "t2", 1, 2, "p", "abc"), "WHISPER", "Alice-Realm", net.now)
    b.Share.OnMessage(Comm.Pack("1", "D", "t2", 2, 3, "p", "abc"), "WHISPER", "Alice-Realm", net.now)
    eq(count(b.Share.Incoming()), 0, "the fragment count changed mid-way")
    net.now = net.now + 100
    offerFrom("Alice-Realm", "t3", 100)
    b.Share.OnMessage(Comm.Pack("1", "D", "t3", 1, 1, "p", "CQ1:garbage"), "WHISPER", "Alice-Realm", net.now)
    assert(printed(b, "SHARE_IMPORT_FAILED"), "bad text goes through the normal import errors")
    -- Offers that make no sense never pop up.
    local before = #b.shown
    for _, f in ipairs({
        Comm.Pack("1", "O", "t4", "virus", 1, 10, "0", "T"),
        Comm.Pack("1", "O", "t5", "quest", 0, 10, "0", "T"),
        Comm.Pack("1", "O", "t6", "quest", 1, Serializer.MAX_LENGTH + 1, "0", "T"),
        Comm.Pack("2", "O", "t7", "quest", 1, 10, "0", "T"),
    }) do b.Share.OnMessage(f, "WHISPER", "Zed-Realm", net.now) end
    eq(#b.shown, before)
end)

shareTest("Share: offer titles and sender names are sanitised", function()
    local b = newClient("Bob")
    b.Model.account.options.sharing.incoming = "anyone"
    b.Share.OnMessage(Comm.Pack("1", "O", "t1", "quest", 1, 10, "0", "|cffff0000[Free]|r |Hitem:1|h:" .. ("x"):rep(200)),
        "WHISPER", "Mal|r-Realm", net.now)
    local offer = b.shown[1]
    assert(not offer.title:find("[|%[%]:]"), offer.title)
    assert(#offer.title <= Share.MAX_TITLE)
    assert(not offer.senderLabel:find("|", 1, true))
end)

shareTest("Share: the template cap refuses an offer before any data moves", function()
    local a, b = newClient("Alice"), newClient("Bob")
    b.Model.MAX_TEMPLATES = 1
    chainIn(b, 1, "Mine ")
    a.Share.Offer("quest", chainIn(a, 2), "WHISPER", "Bob", net.now)
    net.flush()
    eq(#b.shown, 0)
    assert(printed(b, "SHARE_FULL"))
    assert(printed(a, "SHARE_REMOTE_FULL"))
end)

shareTest("Share: chat lockdown queues the offer until it lifts", function()
    local a, b = newClient("Alice"), newClient("Bob")
    a.lockdown = true
    assert(a.Share.Offer("quest", chainIn(a, 1), "WHISPER", "Bob", net.now))
    assert(printed(a, "SHARE_QUEUED_LOCKDOWN"))
    net.flush()
    eq(#b.shown, 0)
    eq(a.Comm.paused, true)
    a.lockdown = false
    net.flush()
    eq(#b.shown, 1)
end)

shareTest("Share: popups wait for the end of combat", function()
    local a, b = newClient("Alice"), newClient("Bob")
    b.combat = true
    a.Share.Offer("quest", chainIn(a, 1), "WHISPER", "Bob", net.now)
    net.flush()
    eq(#b.shown, 0)
    eq(#b.Share.PendingOffers(), 1)
    b.combat = false
    b.Share.ShowNext()
    eq(#b.shown, 1)
end)

shareTest("Share: an offer nobody answers expires and its popup closes", function()
    local a, b = newClient("Alice"), newClient("Bob")
    a.Share.Offer("quest", chainIn(a, 1), "WHISPER", "Bob", net.now)
    net.flush()
    tick(Share.OFFER_TTL + 1)
    eq(#b.hidden, 1)
    eq(#b.Share.PendingOffers(), 0)
    eq(b.Share.Shown(), nil)
end)

shareTest("Share: a failed send tells the sender", function()
    local a = newClient("Alice")
    a.sendResult = "offline"
    a.Share.Offer("quest", chainIn(a, 1), "WHISPER", "Gone", net.now)
    net.flush()
    assert(printed(a, "SHARE_FAIL_OFFLINE"))
    eq(count(a.Share.Outgoing()), 0)
end)

-- Compression (mock codec: the real one is C_EncodingUtil, in game only) ---------------------
-- "Compresses" by swapping a phrase the test quests repeat for a control byte.

local PHRASE = "Lorem ipsum dolor sit amet"
local function mockCodec(log)
    return {
        Compress = function(s) log.compress = (log.compress or 0) + 1 return "Z" .. s:gsub(PHRASE, "\1") end,
        Decompress = function(s)
            log.decompress = (log.decompress or 0) + 1
            if s:sub(1, 1) ~= "Z" then return nil end
            if log.bomb then return ("x"):rep(log.bomb) end
            return (s:sub(2):gsub("\1", PHRASE))
        end,
        Encode64 = Serializer.ToBase64,
        Decode64 = Serializer.FromBase64,
    }
end

-- Which encoding the DATA frames used ("p" / "z"), from the wire.
local function watchEncoding()
    local seen = {}
    net.filter = function(msg)
        local e = msg.text:match("^1~D~[^~]+~%d+~%d+~(%a)~")
        if e then seen[e] = true end
    end
    return seen
end

shareTest("Compression: used only when both sides can, and the result is identical", function()
    local cases = {
        { sender = true, receiver = true, expect = "z" },
        { sender = true, receiver = false, expect = "p" },
        { sender = false, receiver = true, expect = "p" },
        { sender = false, receiver = false, expect = "p" },
    }
    for i, case in ipairs(cases) do
        net.reset()
        Comm.Reset()
        local a, b = newClient("Alice"), newClient("Bob")
        local logA, logB = {}, {}
        a.codec = case.sender and mockCodec(logA) or nil
        b.codec = case.receiver and mockCodec(logB) or nil
        local id = chainIn(a, 3)
        local text = a.ns.Serializer.ExportChain(id)
        a.Share.Offer("quest", id, "WHISPER", "Bob", net.now)
        net.flush()
        local seen = watchEncoding()
        b.Share.Accept(b.shown[1], net.now)
        net.flush(5)
        eq(seen[case.expect], true, "case " .. i)
        eq(seen[case.expect == "z" and "p" or "z"], nil, "case " .. i .. " mixed encodings")
        eq(#b.Model.ListTemplates(), 3, "case " .. i)
        eq(b.ns.Serializer.ExportChain(b.imported[1].ids[1]), text, "case " .. i .. " same quests")
    end
end)

shareTest("Compression: Compress and Decompress round-trip and refuse junk", function()
    local a = newClient("Alice")
    a.codec = mockCodec({})
    local text = a.ns.Serializer.ExportChain(chainIn(a, 2))
    local z = assert(a.Share.Compress(text))
    assert(#z < #text, "smaller")
    assert(not z:find("[~|]"), "printable and frame-safe")
    eq(a.Share.Decompress(z), text)
    eq(a.Share.Decompress("not base64!"), nil)
    eq(a.Share.Decompress(Serializer.ToBase64("plain")), nil, "codec refuses")
    eq(a.Share.Decompress(("A"):rep(math.ceil(Share.MAX_COMPRESSED / 3) * 4 + 4)), nil, "too much compressed data")
    a.codec = nil
    eq(a.Share.Compress(text), nil, "no codec, no compression")
    eq(Serializer.FromRaw(("x"):rep(Serializer.MAX_RAW + 1)), nil)
    eq(Serializer.ToRaw("nope"), nil)
end)

shareTest("Compression: a decompression bomb is refused before the import", function()
    local a, b = newClient("Alice"), newClient("Bob")
    local logB = { bomb = Serializer.MAX_RAW + 1 }
    a.codec, b.codec = mockCodec({}), mockCodec(logB)
    a.Share.Offer("quest", chainIn(a, 3), "WHISPER", "Bob", net.now)
    net.flush()
    b.Share.Accept(b.shown[1], net.now)
    net.flush(5)
    eq(logB.decompress, 1)
    eq(#b.Model.ListTemplates(), 0)
    assert(printed(b, "SHARE_IMPORT_FAILED"))
end)

shareTest("Compression: compressed data nobody asked for is refused", function()
    local b = newClient("Bob") -- no codec: it accepts with z=0
    b.Share.OnMessage(Comm.Pack("1", "O", "t1", "quest", 1, 100, "1", "T"), "WHISPER", "Alice-Realm", net.now)
    b.Share.Accept(b.shown[1], net.now)
    b.Share.OnMessage(Comm.Pack("1", "D", "t1", 1, 1, "z", "WkFB"), "WHISPER", "Alice-Realm", net.now)
    assert(printed(b, "SHARE_CORRUPT"))
    eq(count(b.Share.Incoming()), 0)
end)

-- Chat links ---------------------------------------------------------------------------------

shareTest("Chat link: the marker becomes a local link and a click asks the sender", function()
    local a, b = newClient("Alice"), newClient("Bob")
    b.Model.account.options.sharing.incoming = "off" -- a requested offer still gets through
    local id = chainIn(a, 1, "The |cffff0000Ember: [Oath] ")
    local marker = assert(a.Share.MakeLink("quest", id, net.now))
    eq(marker, "[CustomQuests: The cffff0000Ember Oath 1]")
    local msg = b.Share.LinkifyMarkers("look " .. marker .. "!", "Alice-Realm")
    eq(msg, "look |cff71d5ff|Haddon:CustomQuests:Alice-Realm:The cffff0000Ember Oath 1|h[CustomQuests: The cffff0000Ember Oath 1]|h|r!")
    local author, label = b.Share.ParseLink("addon:CustomQuests:Alice-Realm:The cffff0000Ember Oath 1")
    eq(author, "Alice-Realm")
    assert(b.Share.RequestLink(author, label, net.now))
    eq(select(2, b.Share.RequestLink(author, label, net.now)), "ERR_SHARE_WAIT", "one request at a time")
    net.flush()
    eq(#b.shown, 1)
    b.Share.Accept(b.shown[1], net.now)
    net.flush(5)
    eq(#b.Model.ListTemplates(), 1)
end)

shareTest("Chat link: unknown or expired links answer 'gone'; hostile markers stay text", function()
    local a, b = newClient("Alice"), newClient("Bob")
    local id = chainIn(a, 1)
    local marker = a.Share.MakeLink("quest", id, net.now)
    net.now = net.now + Share.LINK_TTL + 1
    assert(b.Share.RequestLink("Alice-Realm", marker:match(": (.-)%]$"), net.now))
    net.flush()
    assert(printed(b, "SHARE_LINK_GONE"))
    eq(#b.shown, 0)
    eq(b.Share.LinkifyMarkers("no marker here", "Alice-Realm"), nil)
    eq(b.Share.LinkifyMarkers("[CustomQuests: a|Hitem:1|h]", "Alice-Realm"), nil, "pipes never match")
    eq(b.Share.LinkifyMarkers("[CustomQuests: a:b]", "Alice-Realm"), nil, "colons never match")
    eq(b.Share.LinkifyMarkers("[CustomQuests: x]", "|Hx:|h"), nil, "a weird author gives no link")
    eq(b.Share.ParseLink("addon:Other:Alice-Realm:x"), nil)
    eq(b.Share.ParseLink("addon:CustomQuests:Alice-Realm:x|h"), nil)
    eq(select(2, b.Share.RequestLink("Bob", "x", net.now)), "ERR_SHARE_SELF")
end)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
