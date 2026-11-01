-- Builds import texts (CQ1:...) that cover every kind of quest, for testing in game.
--   luajit tools/make_test_imports.lua      (run from the addon folder)
-- Writes tests/imports/<name>.txt: open one, copy its whole line, then in game
-- /cq > Templates > Import. Each file also round-trips through the importer here.

local ns = {}
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.api = { Now = function() return 1000 end, IsSecret = function() return false end }
for _, file in ipairs({ "Util.lua", "Model.lua", "Serializer.lua" }) do
    assert(loadfile(file))("CustomQuests", ns)
end
local Model, Serializer = ns.Model, ns.Serializer

local function newDB() Model.InitDB({}, {}) end

local function save(tpl)
    return assert(Model.SaveTemplate(tpl, nil, 1000))
end

-- A one-stage quest with the given objectives.
local function quest(title, objectives, extra)
    local tpl = { title = title, kind = "rp", repeatMode = "none", giver = "Mensajero de pruebas",
        description = "Misión de prueba para {name}, {class} de {race}.",
        rewardText = "Un [color=20ff20]premio de prueba[/color].",
        completionText = "Gracias, {name}. [color=ffd200]¡Prueba superada![/color]",
        stages = { { text = "", objectives = objectives } } }
    for k, v in pairs(extra or {}) do tpl[k] = v end
    return tpl
end

local manual = function(text, count) return { type = "manual", text = text, count = count or 1 } end

local sets = {}
local function add(name, description, build)
    newDB()
    local id = build()
    local text = assert(Serializer.ExportChain(id))
    -- It must import back, with every template of the chain.
    local entries = assert(Serializer.Import(text))
    sets[#sets + 1] = { name = name, description = description, text = text, count = #entries }
end

-- 1. Every objective type, in two stages -------------------------------------------------------------
add("01-todos-los-objetivos", "Una sola misión suelta con dos etapas: objeto, matar, matar cualquiera, manual / zona, subzona, ubicación, nivel y jefe.", function()
    return save({
        title = "[Test] Todos los objetivos", kind = "rp", repeatMode = "none", giver = "Mensajero de pruebas",
        description = "Cubre todos los tipos de objetivo. {name}, completa las dos etapas.",
        rewardText = "Un [color=ff4040]trofeo[/color] de pruebas.",
        completionText = "Lo has probado todo, {name}.",
        stages = {
            { text = "Etapa 1: cosas del mundo", objectives = {
                { type = "item", itemID = 2589, count = 2 }, -- Linen Cloth
                { type = "kill", npcID = 448, name = "Hogger", mapID = 37, count = 1 },
                { type = "kill", mapID = 1, count = 3 }, -- any enemy in Durotar
                manual("Habla con tres personas", 3),
            } },
            { text = "Etapa 2: lugares y logros", objectives = {
                { type = "zone", mapID = 37 }, -- Elwynn Forest
                { type = "subzone", name = "Granja Rocamuela", mapID = 1 },
                { type = "location", mapID = 37, x = 0.42, y = 0.65, radius = 0.03 },
                { type = "level", level = 10 },
                { type = "boss", encounterID = 1064, name = "Edwin VanCleef", count = 1 },
            } },
        },
    })
end)

-- 2. Repeatable: daily and weekly ----------------------------------------------------------------------
add("02-diaria", "Misión repetible diaria (icono de repetible).", function()
    return save(quest("[Test] Diaria: saludar", { manual("Saluda a alguien", 1) }, { repeatMode = "daily" }))
end)
add("03-semanal", "Misión repetible semanal.", function()
    return save(quest("[Test] Semanal: tres recados", { manual("Haz un recado", 3) }, { repeatMode = "weekly" }))
end)

-- 3. Campaign chain with a branch ------------------------------------------------------------------------
add("04-cadena-con-rama", "Cadena de 5 misiones: A > B, y B tiene dos siguientes (C > E y D). Prueba el árbol de Plantillas y que cada una se oculta hasta entregar la anterior.", function()
    local a = save(quest("[Test] Cadena A: el comienzo", { manual("Empieza la historia", 1) }))
    local b = save(quest("[Test] Cadena B: el cruce", { manual("Llega al cruce", 2) }, { requires = a }))
    local c = save(quest("[Test] Cadena C: camino del norte", { manual("Recorre el norte", 1) }, { requires = b }))
    save(quest("[Test] Cadena D: camino del sur", { manual("Recorre el sur", 1) }, { requires = b }))
    save(quest("[Test] Cadena E: final del norte", { manual("Termina el norte", 1) }, { requires = c }))
    return a
end)

-- 4. Chain that mixes one-time and daily ---------------------------------------------------------------------
add("05-cadena-con-repetible", "Dos misiones: una suelta y su siguiente diaria. Ambas deben verse como de campaña.", function()
    local a = save(quest("[Test] Mixta A: puntual", { manual("Un solo paso", 1) }))
    save(quest("[Test] Mixta B: diaria", { manual("Repite cada día", 1) }, { requires = a, repeatMode = "daily" }))
    return a
end)

-- 5. Level limits and texts ------------------------------------------------------------------------------------
add("06-solo-novatos", "Suelta solo para niveles 1-5: debe salir 'bloqueada' si tu personaje es de más nivel.", function()
    return save(quest("[Test] Solo novatos (nivel 1-5)", { manual("Cosa de novatos", 1) }, { minLevel = 1, maxLevel = 5 }))
end)
add("07-solo-veteranos-y-textos", "Suelta de nivel 100+ (bloqueada por debajo). Mezcla colores y {name}/{class}/{race} en la descripción.", function()
    return save(quest("[Test] Solo veteranos (nivel 100+)", { manual("Cosa de veteranos", 1) }, {
        minLevel = 100,
        description = "[color=ff4040]Rojo[/color], [color=20ff20]verde[/color], [color=40a0ff]azul[/color]. {name} el {class} ({race}).",
    }))
end)

-- Output -----------------------------------------------------------------------------------------------------------
local function mkdir(path)
    os.execute(('mkdir "%s" 2>nul'):format((path:gsub("/", "\\"))))
end
mkdir("tests/imports")
local index = { "# Imports de prueba", "", "En el juego: `/cq` > Plantillas > Importar, pegar el contenido de un archivo.", "" }
for _, set in ipairs(sets) do
    local f = assert(io.open("tests/imports/" .. set.name .. ".txt", "w"))
    f:write(set.text, "\n")
    f:close()
    index[#index + 1] = ("- `%s.txt` (%d misi%s, %d caracteres): %s"):format(
        set.name, set.count, set.count == 1 and "ón" or "ones", #set.text, set.description)
    print(("%s  %d quests  %d chars"):format(set.name, set.count, #set.text))
end
local f = assert(io.open("tests/imports/README.md", "w"))
f:write(table.concat(index, "\n"), "\n")
f:close()
