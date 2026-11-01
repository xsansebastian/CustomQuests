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

for _, file in ipairs({ "Util.lua", "Model.lua", "Serializer.lua", "Objectives.lua", "Lifecycle.lua", "Samples.lua" }) do
    assert(loadfile(file))("CustomQuests", ns)
end
local Util, Model, Serializer, Objectives, Lifecycle = ns.Util, ns.Model, ns.Serializer, ns.Objectives, ns.Lifecycle
local Samples = ns.Samples

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

test("Icons accept file names and IDs only", function()
    eq(Model.ValidIcon("INV_Misc_Book_09"), "INV_Misc_Book_09")
    eq(Model.ValidIcon(134400), 134400)
    eq(Model.ValidIcon("..\\evil"), nil)
    eq(Model.ValidIcon(1.5), nil)
    eq(Model.IconTexture("INV_Misc_Book_09"), "Interface\\Icons\\INV_Misc_Book_09")
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

test("NormalizeIcon converts provider textures to the stored form", function()
    eq(Model.NormalizeIcon(136243), 136243)
    eq(Model.NormalizeIcon("136243"), 136243)
    eq(Model.NormalizeIcon("INTERFACE\\ICONS\\INV_MISC_QUESTIONMARK"), "INV_MISC_QUESTIONMARK")
    eq(Model.NormalizeIcon("Interface/Icons/INV_Misc_Book_09"), "INV_Misc_Book_09")
    eq(Model.NormalizeIcon("bad name!"), nil)
end)

test("Recent icons keep the newest first, without duplicates, up to the limit", function()
    for i = 1, 12 do Model.PushRecentIcon(1000 + i) end
    Model.PushRecentIcon(1005)
    local recent = Model.account.recentIcons
    eq(#recent, Model.MAX_RECENT_ICONS)
    eq(recent[1], 1005)
    eq(recent[2], 1012)
    local seen = {}
    for _, icon in ipairs(recent) do
        assert(not seen[icon], "duplicate " .. icon)
        seen[icon] = true
    end
end)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
