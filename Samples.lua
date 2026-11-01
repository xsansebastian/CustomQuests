local _, ns = ...

-- Built-in example templates. Texts keep {name}/{class}/{race} tokens so each
-- character sees its own name and class.
local Samples = {}
ns.Samples = Samples

Samples.WELCOME_ID = "t-sample-welcome"

Samples.WELCOME = {
    title = "Bienvenido a Azeroth",
    kind = "rp",
    repeatMode = "none",
    giver = "Cronista de Azeroth",
    description = "Saludos, {name}. Los vientos de Azeroth anunciaban la llegada de un nuevo {class}, "
        .. "y aquí estás por fin. Este mundo está lleno de peligros, leyendas y gloria esperando a quien "
        .. "se atreva a reclamarla.\n\nPero todo héroe empieza por algo: demuestra que la sangre de {race} "
        .. "que corre por tus venas está a la altura de tu vocación.",
    rewardText = "El Cronista anota tu nombre en sus anales: {name}, {class} prometedor. "
        .. "Tu verdadera aventura acaba de empezar.",
    stages = {
        {
            text = "Da tus primeros pasos como {class}",
            objectives = { { type = "level", level = 5 } },
        },
    },
}

Samples.EXPLORER_ID = "t-sample-explorer"

-- uiMapIDs checked against warcraft.wiki.gg/wiki/UiMapID (zone objectives also
-- count from any sub-map inside the zone).
Samples.EXPLORER = {
    title = "El gran viaje del explorador",
    kind = "rp",
    repeatMode = "none",
    giver = "Liga de Expedicionarios",
    description = "{name}, la Liga de Expedicionarios busca a alguien con espíritu aventurero, y no "
        .. "hay muchos {class} dispuestos a cruzar el mundo de punta a punta.\n\nTu encargo: recorrer "
        .. "diez de los lugares más emblemáticos de Azeroth, desde los bosques de Elwynn hasta las "
        .. "cumbres heladas de Corona de Hielo, y volver con historias que contar.",
    rewardText = "Tu nombre queda grabado en el mapa de la Liga: {name}, explorador de Azeroth.",
    completionText = "Has regresado con el polvo de diez caminos en las botas, {name}. La Liga de "
        .. "Expedicionarios te recibe con honores: tus historias se contarán durante años.",
    stages = {
        {
            text = "Visita los diez lugares emblemáticos",
            objectives = {
                { type = "zone", mapID = 37 },  -- Elwynn Forest
                { type = "zone", mapID = 1 },   -- Durotar
                { type = "zone", mapID = 50 },  -- Northern Stranglethorn
                { type = "zone", mapID = 71 },  -- Tanaris
                { type = "zone", mapID = 78 },  -- Un'Goro Crater
                { type = "zone", mapID = 83 },  -- Winterspring
                { type = "zone", mapID = 23 },  -- Eastern Plaguelands
                { type = "zone", mapID = 107 }, -- Nagrand (Outland)
                { type = "zone", mapID = 118 }, -- Icecrown
                { type = "zone", mapID = 371 }, -- The Jade Forest
            },
        },
    },
}

-- Creates or refreshes the welcome template; returns its id.
function Samples.InstallWelcome()
    return ns.Model.SaveTemplate(Samples.WELCOME, Samples.WELCOME_ID, ns.api.Now())
end

-- Installs every sample; returns the id of the first one.
function Samples.InstallAll()
    local first = Samples.InstallWelcome()
    ns.Model.SaveTemplate(Samples.EXPLORER, Samples.EXPLORER_ID, ns.api.Now())
    return first
end
