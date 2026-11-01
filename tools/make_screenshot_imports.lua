-- Builds polished import texts (CQ1:...) for the CurseForge screenshot gallery.
--   luajit tools/make_screenshot_imports.lua      (run from the addon folder)
-- Writes screenshots/imports/<nn-name>.txt and a README with the import order
-- and the shot each file is for. Every text round-trips through the importer
-- here, and no text may be cut by the model's length limits.
--
-- IDs: uiMapIDs are the ones Samples.lua checked against warcraft.wiki.gg/wiki/UiMapID;
-- item and NPC IDs are long-standing Wowhead ids. Encounter IDs are the
-- DungeonEncounterIDs of classic raids: if one doesn't count in game, use the
-- editor's Last boss button and re-export.

local ns = {}
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.api = { Now = function() return 1000 end, IsSecret = function() return false end }
for _, file in ipairs({ "Util.lua", "Model.lua", "Serializer.lua" }) do
    assert(loadfile(file))("CustomQuests", ns)
end
local Model, Serializer = ns.Model, ns.Serializer

-- IDs ---------------------------------------------------------------------------------------------------
local MAP = {
    ELWYNN = 37, DUROTAR = 1, N_STRANGLETHORN = 50, TANARIS = 71, UNGORO = 78,
    WINTERSPRING = 83, E_PLAGUELANDS = 23, NAGRAND = 107, ICECROWN = 118, JADE_FOREST = 371,
}
local ITEM = {
    LINEN = 2589, WOOL = 2592, SILK = 4306, MAGEWEAVE = 4338, RUNECLOTH = 14047,
    PEACEBLOOM = 2447, SILVERLEAF = 765, COPPER_ORE = 2770, TIN_ORE = 2771, IRON_ORE = 2772,
}
local NPC = { HOGGER = 448 }
local ENCOUNTER = { RAGNAROS = 672, ONYXIA = 1084, LICH_KING = 856 }

-- Builders ----------------------------------------------------------------------------------------------
local function item(id, count) return { type = "item", itemID = id, count = count } end
local function kill(npcID, name, mapID, count) return { type = "kill", npcID = npcID, name = name, mapID = mapID, count = count } end
local function killAny(mapID, count) return { type = "kill", mapID = mapID, count = count } end
local function boss(id, name) return { type = "boss", encounterID = id, name = name, count = 1 } end
local function zone(mapID) return { type = "zone", mapID = mapID } end
local function subzone(name, mapID) return { type = "subzone", name = name, mapID = mapID } end
local function location(mapID, x, y, radius) return { type = "location", mapID = mapID, x = x, y = y, radius = radius } end
local function level(n) return { type = "level", level = n } end
local function manual(text, count) return { type = "manual", text = text, count = count or 1 } end
local function stage(text, objectives) return { text = text, objectives = objectives } end

-- Fails if validation would cut or drop any text: what is written here is what shows in game.
local function checkTexts(tpl)
    local clean = assert(Model.ValidateTemplate(tpl))
    for _, key in ipairs({ "title", "giver", "description", "rewardText", "completionText" }) do
        assert(clean[key] == tpl[key], ("%s: %s is too long (%d)"):format(tpl.title, key, #(tpl[key] or "")))
    end
    for i, s in ipairs(tpl.stages) do
        assert(clean.stages[i].text == s.text, ("%s: stage %d text is too long"):format(tpl.title, i))
        assert(#clean.stages[i].objectives == #s.objectives)
    end
end

local function save(tpl)
    checkTexts(tpl)
    return assert(Model.SaveTemplate(tpl, nil, 1000))
end

local function section(name) return assert(Model.CreateSection(name, 1000)) end

local sets = {}
-- build() returns a template id (its whole chain is exported) or { section = id }.
local function add(name, shots, description, build)
    Model.InitDB({}, {})
    local result = build()
    local text = assert(type(result) == "table" and Serializer.ExportSection(result.section)
        or Serializer.ExportChain(result))
    assert(#text <= Serializer.MAX_LENGTH, name .. " is too long to import")
    -- It must import back whole: same number of quests, same titles, same links.
    local entries = assert(Serializer.Import(text))
    Model.InitDB({}, {})
    local ids = Model.SaveImported(entries, 1000)
    assert(#ids == #entries)
    for i, id in ipairs(ids) do
        assert(id and Model.GetTemplate(id).title == entries[i].template.title)
        if entries[i].requires then assert(Model.GetTemplate(id).requires == ids[entries[i].requires]) end
    end
    sets[#sets + 1] = { name = name, shots = shots, description = description, text = text, entries = entries }
end

-- 1. Campaign chain with a branch ----------------------------------------------------------------------
add("01-the-ember-oath", "Templates tree, Journal detail, campaign icons",
    "Section \"The Ember Oath\": a five-quest roleplay campaign. The second quest branches into two roads, "
    .. "and the scholar's road leads on to the finale, so Templates shows a nested tree.", function()
    local giver = "A hooded courier"
    local a = save({
        title = "A Letter Sealed in Ash", kind = "rp", repeatMode = "none", giver = giver,
        description = "A courier in a soot-stained cloak presses a letter into your hands and vanishes into the crowd. "
            .. "The wax seal is still warm, stamped with a burning eye.\n\n[color=ffd200]\"{name}, the Ember Oath "
            .. "remembers the debt your kin owe. Come to Goldshire. Come alone.\"[/color]",
        rewardText = "A [color=ff4040]cinder-black seal[/color] and a name you did not expect to read.",
        completionText = "The ink shifts as you read, rearranging into a map of Elwynn. Whoever wrote this knew you would come.",
        stages = { stage("Answer the summons", {
            manual("Break the ember seal and read the letter"),
            subzone("Goldshire", MAP.ELWYNN),
        }) },
    })
    local b = save({
        title = "Whispers at the Lion's Pride", kind = "rp", repeatMode = "none", giver = giver, requires = a,
        description = "The Lion's Pride Inn is loud with laughter, but one table by the hearth stays empty, a single "
            .. "candle burning beside a cup of untouched wine.\n\nSit where the letter told you to. Listen. Someone "
            .. "here knows more about the Ember Oath than they will admit to a stranger.",
        rewardText = "Two names, whispered over the candle: a scholar in the north, a sellsword in the south.",
        completionText = "\"You're braver than the last {class} they sent,\" the stranger murmurs. \"Choose your road.\"",
        stages = { stage("Find the empty table", {
            location(MAP.ELWYNN, 0.43, 0.66, 0.03),
            manual("Ask the innkeeper about the hooded courier"),
            manual("Overhear the travellers by the hearth", 3),
        }) },
    })
    local c = save({
        title = "The Scholar's Road", kind = "rp", repeatMode = "none", giver = "Brother Aldous Venn", requires = b,
        description = "Brother Aldous once kept the archives of Light's Hope Chapel, before the Oath burned his name "
            .. "from every ledger. He believes the burning eye is older than the Scourge.\n\nTravel to the chapel and "
            .. "copy the sigil carved beneath the eastern window, before someone else erases it for good.",
        rewardText = "A rubbing of the [color=40a0ff]ember sigil[/color], and the scholar's trust.",
        completionText = "Aldous traces the sigil with a trembling finger. \"Everlook,\" he breathes. \"They gather at Everlook.\"",
        stages = { stage("Search the chapel archives", {
            subzone("Light's Hope Chapel", MAP.E_PLAGUELANDS),
            manual("Copy the sigil beneath the eastern window"),
        }) },
    })
    save({
        title = "The Blade's Road", kind = "rp", repeatMode = "none", giver = "Kessa Ironvein", requires = b,
        description = "Kessa Ironvein sold her sword to the Oath once, and still carries the brand on her wrist. She "
            .. "will tell you everything, after you prove you can survive the jungle that nearly killed her.\n\n"
            .. "Thin out the raiders in Northern Stranglethorn and come back in one piece.",
        rewardText = "Kessa's brand-scarred dagger and a [color=ff4040]map of the Oath's hideouts[/color].",
        completionText = "\"Not bad, {race}.\" Kessa spits into the fire. \"Maybe you'll live long enough to regret this.\"",
        stages = { stage("Survive the jungle", {
            zone(MAP.N_STRANGLETHORN),
            killAny(MAP.N_STRANGLETHORN, 12),
        }) },
    })
    save({
        title = "The Ember Oath", kind = "rp", repeatMode = "none", giver = "Brother Aldous Venn", requires = c,
        description = "Everlook sleeps under the northern lights, but tonight a ring of torches burns in the snow beyond "
            .. "its gates. The Ember Oath is gathering.\n\nStand before them, {name}. Decide whether you break the "
            .. "Oath, or swear yourself to it.",
        rewardText = "[color=ffd200]The Ember Oath[/color] knows your name now, and so does everyone who fears it.",
        completionText = "The torches gutter out one by one. When the last flame dies, only your footprints remain in "
            .. "the snow. [color=ff80ff]The story of the Ember Oath is yours to write.[/color]",
        stages = {
            stage("Reach the frozen north", { zone(MAP.WINTERSPRING), subzone("Everlook", MAP.WINTERSPRING) }),
            stage("Face the circle of torches", { manual("Speak your answer to the Oath") }),
        },
    })
    Model.SetSection({ a }, section("The Ember Oath"))
    return a
end)

-- 2. Daily and weekly routine, exported as a whole section -----------------------------------------------
add("02-dailies-and-weeklies", "Recurring icons, section headers in Templates, Active and the tracker",
    "Section \"Dailies and Weeklies\": two daily and two weekly quests (herbs, a road patrol, guild bank cloth "
    .. "and an old-raid transmog night). Exported as a whole section.", function()
    local herbs = save({
        title = "Herbs for the Morning Kettle", kind = "personal", repeatMode = "daily",
        description = "A good day starts with a good brew. Gather fresh [color=20ff20]Peacebloom[/color] and "
            .. "[color=20ff20]Silverleaf[/color] for tomorrow's tea, potions and the odd poultice.",
        rewardText = "A steaming pot of herbal tea and a full herb pouch.",
        completionText = "The kettle sings. Another quiet morning in Azeroth, well earned.",
        stages = { stage("Fill the herb pouch", { item(ITEM.PEACEBLOOM, 10), item(ITEM.SILVERLEAF, 10) }) },
    })
    local patrol = save({
        title = "Patrol the Goldshire Road", kind = "rp", repeatMode = "daily", giver = "Stormwind Watch",
        description = "Bandits and wolves keep testing the road between Goldshire and the Stormwind gates. The Watch "
            .. "is stretched thin, so {name} the {class} has volunteered for the morning patrol.",
        rewardText = "A few silver from the Watch and a nod from the guards at the gate.",
        completionText = "The road is quiet again, for today. The Watch thanks you, {name}.",
        stages = { stage("Walk the patrol route", {
            subzone("Goldshire", MAP.ELWYNN),
            killAny(MAP.ELWYNN, 15),
        }) },
    })
    local cloth = save({
        title = "Supplies for the Guild Bank", kind = "personal", repeatMode = "weekly",
        description = "The guild tailors are running low again. Set aside a stack of each cloth this week, bring it "
            .. "to the guild bank and [color=ffd200]log it in the guild notes[/color].",
        rewardText = "Bandages and bags for the whole guild, and bragging rights on Discord.",
        completionText = "The officer of the week signs your entry with a flourish. Same time next week?",
        stages = { stage("Gather the weekly cloth", {
            item(ITEM.LINEN, 20), item(ITEM.WOOL, 20), item(ITEM.SILK, 20),
            manual("Deposit it in the guild bank"),
        }) },
    })
    local raids = save({
        title = "Old Raid Night", kind = "personal", repeatMode = "weekly",
        description = "Every week, the same ritual: clear the old raids, hope for that one [color=ff80ff]mount[/color] "
            .. "or the last piece of a [color=40a0ff]transmog set[/color]. One week the drop will come.",
        rewardText = "A few more pieces for the collection. Maybe.",
        completionText = "No mount again. There is always next week, {name}.",
        stages = { stage("Clear the classics", {
            boss(ENCOUNTER.RAGNAROS, "Ragnaros"),
            boss(ENCOUNTER.ONYXIA, "Onyxia"),
            boss(ENCOUNTER.LICH_KING, "The Lich King"),
        }) },
    })
    local id = section("Dailies and Weeklies")
    Model.SetSection({ herbs, patrol, cloth, raids }, id)
    return { section = id }
end)

-- 3. Personal goals: exploring, levelling, collecting --------------------------------------------------
add("03-personal-goals", "Personal goals, a chain inside a section, zone and level objectives",
    "Section \"Personal Goals\": a two-part world tour (a short chain), a levelling goal in three stages, "
    .. "a cloth collection and a mining goal. Exported as a whole section.", function()
    local tour = save({
        title = "Grand Tour: Old Roads", kind = "personal", repeatMode = "none",
        description = "Before the new expansions, before the portals, there were the old roads. Walk them again: "
            .. "from the fields of [color=20ff20]Elwynn[/color] to the deserts of Tanaris and the snows of Winterspring.",
        rewardText = "Sore feet and a map full of memories.",
        completionText = "Every road leads somewhere. Yours led all the way around the world.",
        stages = { stage("Visit the old lands", {
            zone(MAP.ELWYNN), zone(MAP.DUROTAR), zone(MAP.N_STRANGLETHORN), zone(MAP.TANARIS),
            zone(MAP.UNGORO), zone(MAP.WINTERSPRING), subzone("Gadgetzan", MAP.TANARIS),
            subzone("Marshal's Refuge", MAP.UNGORO),
        }) },
    })
    save({
        title = "Grand Tour: Beyond the Horizon", kind = "personal", repeatMode = "none", requires = tour,
        description = "The old continents are behind you. Now cross the Dark Portal, sail to the frozen north and "
            .. "find the mists of Pandaria.",
        rewardText = "A traveller's tale for every tavern in Azeroth.",
        completionText = "Outland, Northrend, Pandaria. The world is bigger than it looks from Goldshire.",
        stages = { stage("Visit the far lands", {
            zone(MAP.NAGRAND), zone(MAP.ICECROWN), zone(MAP.JADE_FOREST),
        }) },
    })
    local hero = save({
        title = "A Hero in the Making", kind = "personal", repeatMode = "none",
        description = "Every legend starts small. This new {race} {class} has a long way to go, so set the milestones "
            .. "now and tick them off one by one.\n\n[color=ffd200]Tip:[/color] each milestone is a stage, so the "
            .. "tracker only shows the next one.",
        rewardText = "The first chapter of {name}'s legend.",
        completionText = "Level 30 already? {name} the {class} is no longer a beginner.",
        stages = {
            stage("Learn the basics", { level(10) }),
            stage("Find your feet", { level(20) }),
            stage("Earn your name", { level(30) }),
        },
    })
    local hoard = save({
        title = "The Cloth Hoarder", kind = "personal", repeatMode = "none",
        description = "A stack of every classic cloth, kept in the bags at the same time. Is it practical? No. "
            .. "Is it satisfying? [color=ff80ff]Absolutely.[/color]",
        rewardText = "One very full bag.",
        completionText = "Five stacks, five colours. Perfection.",
        stages = { stage("Hoard the cloth", {
            item(ITEM.LINEN, 20), item(ITEM.WOOL, 20), item(ITEM.SILK, 20),
            item(ITEM.MAGEWEAVE, 20), item(ITEM.RUNECLOTH, 20),
        }) },
    })
    local ore = save({
        title = "Ore for the Forge", kind = "personal", repeatMode = "none",
        description = "The forge is cold and the anvil is waiting. Mine enough copper, tin and iron to start "
            .. "levelling blacksmithing properly.",
        rewardText = "Enough bars to make the anvil ring for an evening.",
        completionText = "The forge roars back to life.",
        stages = { stage("Mine the ore", {
            item(ITEM.COPPER_ORE, 20), item(ITEM.TIN_ORE, 10), item(ITEM.IRON_ORE, 10),
        }) },
    })
    local id = section("Personal Goals")
    Model.SetSection({ tour, hero, hoard, ore }, id)
    return { section = id }
end)

-- 4. Every objective type, across three stages -------------------------------------------------------------
add("04-trials-of-the-wanderer", "Tracker with many objective types, editor Objectives tab",
    "One roleplay quest in three stages using every objective type: item, kill (NPC and any enemy), "
    .. "subzone, location and manual in stage 1; zone, subzone, kill and level in stage 2; boss and manual in "
    .. "stage 3. No section, so it shows under \"Other quests\".", function()
    return save({
        title = "Trials of the Wanderer", kind = "rp", repeatMode = "none", giver = "Archivist Elowen Brightquill",
        description = "\"Every wanderer in my archive began the same way, {name}: with a pack, a road and a reason.\" "
            .. "Elowen opens a fresh page.\n\n\"Complete the [color=ffd200]three trials[/color] and your name joins "
            .. "theirs. Fail, and I will write that down too.\"",
        rewardText = "A page in the [color=40a0ff]Wanderers' Archive[/color] and the title of [color=ffd200]Wanderer[/color].",
        completionText = "Elowen dips her quill and writes: [color=ffd200]{name}, {race} {class}. Wanderer.[/color] "
            .. "\"Welcome to the archive. Now go and give me something worth writing.\"",
        stages = {
            stage("The trial of the hearth", {
                item(ITEM.LINEN, 10),
                kill(NPC.HOGGER, "Hogger", MAP.ELWYNN, 1),
                killAny(MAP.ELWYNN, 8),
                subzone("Goldshire", MAP.ELWYNN),
                location(MAP.ELWYNN, 0.43, 0.66, 0.03),
                manual("Share a drink with a stranger at the inn"),
            }),
            stage("The trial of the road", {
                zone(MAP.TANARIS),
                subzone("Gadgetzan", MAP.TANARIS),
                killAny(MAP.TANARIS, 10),
                level(20),
            }),
            stage("The trial of legend", {
                boss(ENCOUNTER.RAGNAROS, "Ragnaros"),
                manual("Tell the tale to Elowen"),
            }),
        },
    })
end)

-- 5. A quick quest for the turn-in window -------------------------------------------------------------------
add("05-the-innkeepers-favour", "Turn-in window with coloured text and {name}/{class}/{race}",
    "One roleplay quest with a single manual objective: press + once and it is ready to turn in. Rich "
    .. "completion and reward texts with colours and tokens, for the turn-in window shot.", function()
    return save({
        title = "The Innkeeper's Favour", kind = "rp", repeatMode = "none", giver = "Innkeeper Marla Thistledown",
        description = "Marla's best cask of [color=ff80ff]Thistledown Cider[/color] went missing the night the bard "
            .. "left town. She doesn't want the bard; she wants the cider back before the harvest festival.\n\n"
            .. "\"Ask around, {name}. A {race} with a friendly face hears more than a guard ever will.\"",
        rewardText = "[color=ffd200]Free lodging[/color] at the Thistledown Inn for life, and a mug of the good stuff.",
        completionText = "Marla gasps as you roll the cask through the door.\n\n\"By the Light, {name}! You found it!\" "
            .. "She pours two mugs and pushes one toward you. \"To the finest [color=ffd200]{class}[/color] this inn "
            .. "has ever seen. Your room is always ready.\"\n\n[color=20ff20]The common room cheers.[/color]",
        stages = { stage("Track down the missing cask", { manual("Return the cask of Thistledown Cider") }) },
    })
end)

-- Output -----------------------------------------------------------------------------------------------------
local function mkdir(path)
    if package.config:sub(1, 1) == "\\" then
        os.execute(('mkdir "%s" 2>nul'):format((path:gsub("/", "\\"))))
    else
        os.execute(('mkdir -p "%s"'):format(path))
    end
end
mkdir("screenshots/imports")

local index = {
    "# Screenshot imports",
    "",
    "Quest sets for the CurseForge gallery, generated by `luajit tools/make_screenshot_imports.lua`",
    "(do not edit the `.txt` files by hand; change the script and run it again).",
    "",
    "## How to import",
    "",
    "1. In game: `/cq` > **Templates** > **Import**.",
    "2. Open a file, copy its whole single line (it starts with `CQ1:`), paste it and click **Import**.",
    "3. Import them **in number order**: sections are listed in the order they are created, so the",
    "   Templates list reads The Ember Oath, Dailies and Weeklies, Personal Goals, then Other quests.",
    "4. Each file creates its quests once; importing a file twice makes duplicates.",
    "",
    "## Files",
    "",
    "| File | Quests | For the shot | Contents |",
    "|---|---|---|---|",
}
for _, set in ipairs(sets) do
    local f = assert(io.open("screenshots/imports/" .. set.name .. ".txt", "w"))
    f:write(set.text, "\n")
    f:close()
    index[#index + 1] = ("| `%s.txt` | %d | %s | %s |"):format(set.name, #set.entries, set.shots, set.description)
    print(("%s  %d quests  %d chars"):format(set.name, #set.entries, #set.text))
end
local tail = {
    "",
    "## Suggested shots",
    "",
    "1. **Templates tree**: Templates with all three sections open and The Ember Oath unfolded",
    "   (A Letter Sealed in Ash > Whispers at the Lion's Pride > two roads, the scholar's one going on).",
    "2. **Journal detail**: Templates > Trials of the Wanderer selected, showing its three stages.",
    "3. **Tracker**: accept Trials of the Wanderer, Patrol the Goldshire Road, Herbs for the Morning Kettle",
    "   and A Hero in the Making; stand in Elwynn so some objectives are already ticked. Section headers show.",
    "4. **Turn-in window**: accept The Innkeeper's Favour, press + once, click the yellow ? (or Complete).",
    "5. **Editor**: Edit Trials of the Wanderer, Description tab (colour toolbar and live preview) and",
    "   Objectives tab.",
    "6. **History**: turn in a daily, then `/cq reset` and turn it in again so the count reads 2 times.",
    "7. **Export**: right-click the Dailies and Weeklies header > Export section.",
    "",
    "## IDs",
    "",
    "- uiMapIDs: 37 Elwynn Forest, 1 Durotar, 50 Northern Stranglethorn, 71 Tanaris, 78 Un'Goro Crater,",
    "  83 Winterspring, 23 Eastern Plaguelands, 107 Nagrand, 118 Icecrown, 371 The Jade Forest",
    "  (the same ones `Samples.lua` uses, checked against warcraft.wiki.gg).",
    "- Items: 2589 Linen Cloth, 2592 Wool Cloth, 4306 Silk Cloth, 4338 Mageweave Cloth, 14047 Runecloth,",
    "  2447 Peacebloom, 765 Silverleaf, 2770 Copper Ore, 2771 Tin Ore, 2772 Iron Ore. NPC: 448 Hogger.",
    "- Encounters (DungeonEncounterID): 672 Ragnaros, 1084 Onyxia, 856 The Lich King. Not verified in game:",
    "  if one doesn't count, kill the boss, use **Last boss** in the editor and regenerate.",
    "- Subzone names are the English client's (Goldshire, Light's Hope Chapel, Everlook, Gadgetzan,",
    "  Marshal's Refuge); on other game languages they need editing.",
}
for _, line in ipairs(tail) do index[#index + 1] = line end
local f = assert(io.open("screenshots/imports/README.md", "w"))
f:write(table.concat(index, "\n"), "\n")
f:close()
