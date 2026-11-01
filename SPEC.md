# Spec: CustomQuests

Estado: **borrador pendiente de aprobación** · 2026-11-01

## Objective

Addon de WoW para crear **misiones propias** y seguirlas en pantalla. Dos usos:

- **Roleplay**: misiones con narrativa (NPC, descripción, texto de recompensa, etapas encadenadas) que se pueden compartir con otros jugadores como texto.
- **Tareas personales**: objetivos que el addon sigue solo (farmear N objetos, matar N de un NPC, llegar a un sitio), repetibles con **plantillas** y con reinicio diario/semanal opcional.

Usuario: un jugador individual (sin servidor ni coordinación de grupo). Éxito = puedo crear una plantilla "Farmear 20 Hierro" una vez, aceptarla cuando quiera, verla avanzar sola mientras farmeo y ver en el historial cuántas veces la he completado.

### Supuestos (corrígeme)
1. Existe también un objetivo **manual** (marcar / +1) aunque no lo elegiste: lo necesitan las misiones RP ("habla con Juan en Ventormenta").
2. Objetos: cuenta **lo que llevas en las bolsas** en este momento (no el banco, no "desde que aceptaste"). Si gastas los objetos, el progreso baja.
3. Muertes: cuenta las de tu grupo (`PARTY_KILL`), no solo las tuyas. **Deben contar también en instancias** (decisión del usuario), ver "Muertes en instancias".
4. Ubicación: radio en porcentaje del mapa (simple y fiable en ambos clientes), no en yardas.
5. Plantillas e historial son **de cuenta**; las misiones activas son **por personaje**.

## Capability Map

| Module id | Responsibility | Depends on |
|---|---|---|
| `model` | Esquema de plantillas, instancias y SavedVariables, migraciones, validación | — |
| `serializer` | Exportar/importar plantillas como texto (`CQ1:...`), sin `loadstring` | `model` |
| `objectives` | Motor de progreso: item, kill, location/zone, near, manual. Eventos y adaptadores | `model` |
| `lifecycle` | Aceptar/abandonar/completar, etapas, reinicio diario/semanal, historial | `model`, `objectives` |
| `ui-journal` | Ventana: lista de plantillas, editor, activas, historial, importar/exportar | `lifecycle`, `serializer` |
| `ui-tracker` | Rastreador flotante con progreso en vivo | `lifecycle` |
| `share` | Compartir en el juego: transporte por addon messages y protocolo de oferta | `serializer`, `model` |

Orden: `model` → `serializer`, `objectives` → `lifecycle` → `ui-tracker` → `ui-journal`.
El tracker va antes que el diario porque permite probar el motor en juego con misiones creadas por `/cq` mientras el editor no existe.

## Tech Stack

- Lua 5.1 (entorno WoW), sin librerías externas.
- Targets: **retail** (live, 12.1.5, interfaz 120105) y **forever** (1.60.1, interfaz 16001). Evidencia: snapshot de `wow-addon-dev` 2.1.0, commits Gethe `d07eb002` (retail) y `ca8368f2` (forever). Las interfaces se confirman con `select(4, GetBuildInfo())`.

## Technical Design

### Datos

```lua
-- Cuenta (SavedVariables: CustomQuestsDB)
CustomQuestsDB = {
  schema = 1,
  templates = {
    ["t-1700000000-1"] = {
      title = "Farmear hierro", kind = "personal",   -- "personal" | "rp"
      giver = nil, description = "", rewardText = "",
      repeatMode = "none",                            -- "none" | "daily" | "weekly"
      stages = {
        { text = "Consigue el mineral", objectives = {
          { type = "item", itemID = 2772, count = 20 },
          { type = "kill", npcID = 1234, name = "Kobold", count = 10, mapID = nil, fallbackAny = false },
          { type = "kill", npcID = nil, mapID = 2651, count = 30 },          -- any
          { type = "boss", encounterID = 3108, name = "Jefe", count = 1 },
          { type = "zone", mapID = 37 },
          { type = "location", mapID = 37, x = 0.42, y = 0.65, radius = 0.02 },
          { type = "manual", text = "Habla con Juan", count = 1 },
        } },
      },
    },
  },
  history = { { templateID = "...", title = "...", completedAt = 1700000000, char = "Name-Realm" } },
  sections = { { id = "s-...", name = "Lost Isles" } },   -- orden = orden en pantalla; plantilla.section = id
  sectionCollapsed = { ["s-..."] = true },                -- plegado en Plantillas (cuenta)
}

-- Personaje (SavedVariablesPerCharacter: CustomQuestsCharDB)
CustomQuestsCharDB = {
  schema = 1,
  active = {
    ["q-..."] = { templateID = "...", stage = 1, progress = { [1] = 7, [2] = 3 },
                  acceptedAt = 0, resetAt = nil },
  },
  tracked = { ["q-..."] = true },
  trackerPos = nil,
  sectionCollapsed = { log = {}, tracker = {} },          -- plegado por vista, por personaje
}
```

Cada misión activa guarda una **copia** de la plantilla al aceptarla, así editar la plantilla no rompe misiones en curso.

### Objetivos: fuentes y eventos

| Tipo | API / evento (ambos clientes, declarado en fuente) | Notas |
|---|---|---|
| item | `C_Item.GetItemCount(itemID)` en `BAG_UPDATE_DELAYED` | Recalcula solo los objetivos item activos. |
| kill (npc) | `PARTY_KILL(attackerGUID, targetGUID)`; npcID desde el GUID | Identifica el NPC concreto cuando el GUID es legible. |
| kill (any) | `PARTY_KILL` en un `mapID` dado | Cuenta cualquier muerte del grupo en esa zona/instancia sin leer el GUID. |
| boss | `ENCOUNTER_END(encounterID, ..., success)` | Sin anotación de secreto. Fiable en mazmorras y bandas. |
| zone | `C_Map.GetBestMapForUnit("player")` en `ZONE_CHANGED_NEW_AREA` y `PLAYER_ENTERING_WORLD` | |
| location | `C_Map.GetPlayerMapPosition(mapID, "player")` con `C_Timer.NewTicker(0.5)` | El ticker solo existe mientras haya objetivos location o near pendientes. Puede devolver nil en instancias. |
| near | Unidades `npc`, `softinteract`, `target`, `mouseover` y placas de nombre con `CheckInteractDistance(unit, 3)`; `PLAYER_SOFT_INTERACT_CHANGED` y `GOSSIP_SHOW` comprueban al instante | npcID desde el GUID; con identidad secreta no cuenta. Al completarse abre el popup con retrato si tiene `dialog`; el tooltip del NPC lista la misión. Ver ADR-007. |
| manual | Botones +/− en tracker y diario | |

### Muertes en instancias

El payload de `PARTY_KILL` está anotado `SecretWhenUnitIdentityRestricted`: en instancias, durante el combate, los GUIDs de unidades no-jugador son secretos y el addon no puede saber **qué** NPC murió (no se puede comparar ni descomponer un valor secreto, y está prohibido intentar revelarlo). Diseño:

- Si el GUID es legible (`not issecretvalue(targetGUID)`): se cuenta por npcID como siempre.
- Si es secreto: se cuenta para los objetivos **kill (any)** del mapa actual y para objetivos **kill (npc)** marcados con `fallbackAny = true` en ese mapa ("10 kobolds en las Minas" cuenta cualquier muerte dentro de las Minas). El tracker muestra el objetivo como "aproximado" (icono).
- Jefes: tipo **boss** con `ENCOUNTER_END`, exacto.
- El editor avisa al crear un objetivo kill (npc) en un mapa de instancia y propone activar `fallbackAny` o usar boss.

Pendiente de verificar en juego: que `PARTY_KILL` se entregue al addon en instancias aunque el payload sea secreto, y cuándo deja de ser secreto (¿fuera de combate?). Si no se entrega, el trash de instancia se marca como **no soportado** en el editor (los jefes siguen funcionando con boss) y se vuelve a preguntar al usuario.

Reinicio: al **completar** una misión diaria/semanal queda en estado `done` con `resetAt = time() + GetSecondsUntilDailyReset()` (o `...WeeklyReset`). En `PLAYER_LOGIN` y cada 60 s, si `time() >= resetAt`, vuelve a `active` desde la etapa 1 con la versión actual de la plantilla. Una misión sin completar conserva su progreso a través del reset.

`COMBAT_LOG_EVENT_UNFILTERED` **no se usa**: no está disponible para addons en Retail 12.x.

### Compatibilidad y empaquetado

**Un solo paquete para los dos clientes** (modelo de EllesmereUI: un TOC con ambas interfaces y detección por número de build). Un solo repo y una sola carpeta; `tools/build.py` genera `dist/CustomQuests-<versión>.zip`. El cliente se detecta en `Compat/Common.lua` por número de build (16000-19999 = Forever, ≥120000 = Retail) y avisa en cualquier otro. Forever **sin probar aún en juego**. Las APIs anteriores aparecen declaradas en ambos snapshots; su disponibilidad real y el comportamiento de los secretos en Forever **solo se confirman en juego**.

### Export / import

- Formato `CQ1:` + serialización propia de tablas (solo string/number/boolean/table) + escape seguro. Se puede pegar en chat o Discord.
- El import **nunca ejecuta código** (`loadstring` prohibido): parser propio, valida contra el esquema de `model`, descarta campos desconocidos y limita tamaño (≤ 16 KB, ≤ 20 etapas, ≤ 10 objetivos por etapa).

## Commands

```
Recargar en juego:   /reload
Abrir diario:        /cq
Comandos debug:      /cq debug | /cq reset-char | /cq dump <questID>
Tests offline:       luajit tests/run.lua (desde la carpeta del addon; LuaJIT = semántica Lua 5.1, winget DEVCOM.LuaJIT)
Lint:                luacheck . --std lua51 --globals CustomQuestsDB CustomQuestsCharDB
```

## Project Structure

```
CustomQuests/
  CustomQuests.toc   un TOC para Retail (120105) y Forever (16001)
  Locales/           enUS.lua (base, con fallback a la clave), esES.lua
  Util.lua           helpers puros, bus de eventos
  Compat/Common.lua  ns.api + detección de cliente: único sitio con llamadas a la API del cliente
  Model.lua          esquema, defaults, validación                  [model]
  Serializer.lua     CQ1 encode/decode                              [serializer]
  Comm.lua           addon messages: tramas, fragmentos, throttle   [share]
  Share.lua          protocolo oferta/aceptación/datos, enlaces     [share]
  Objectives.lua     motor de progreso                              [objectives]
  Lifecycle.lua      aceptar/completar/etapas/resets/historial      [lifecycle]
  Core.lua           eventos, refresco y comandos /cq
  UI/Common.lua      widgets y textos de objetivos
  UI/Tracker.lua                                                    [ui-tracker]
  UI/Journal.lua, UI/Editor.lua, UI/Dialogs.lua                     [ui-journal]
  tests/run.lua      tests offline (Lua 5.1, sin dependencias)
  tests/INGAME.md    checklist en juego
```

## Code Style

```lua
local _, ns = ...

local Lifecycle = {}
ns.Lifecycle = Lifecycle

-- Returns the new quest id, or nil and an error key from ns.L.
function Lifecycle.Accept(templateID)
    local template = ns.Model.GetTemplate(templateID)
    if not template then return nil, "ERR_NO_TEMPLATE" end
    ...
end
```

- Un módulo = una tabla en `ns` (`ns.Model`, `ns.Objectives`...). Ningún global salvo los SavedVariables, `SLASH_*` y frames con nombre que lo necesiten (`UISpecialFrames`).
- Funciones públicas en PascalCase; locales en camelCase. 4 espacios.
- Textos visibles solo vía `ns.L`. Lógica pura sin llamadas a APIs WoW directas (inyectadas por `Compat`), para poder testearla offline.

## Testing Strategy

- **Offline (busted, Lua 5.1)**: `model`, `serializer`, `lifecycle` y la lógica de `objectives` (con stubs de `C_Item`, `C_Map`, `time`). Prioridad: el serializador con entradas maliciosas o truncadas, migraciones y resets.
- **En juego (manual, ambos clientes)**: checklist por módulo en `tests/INGAME.md` — aceptar plantilla, farmear objeto y ver subir/bajar contador, matar NPC en mundo abierto, kill dentro de mazmorra (esperado: no cuenta, sin errores), entrar en zona, reset diario (cambiando `resetAt` con `/cq debug`), `/reload` y reinicio completo conservan datos.
- Sin errores Lua con `/console scriptErrors 1`.

## Boundaries

- **Always**: inicializar datos en `ADDON_LOADED`; comprobar `issecretvalue` antes de usar datos de unidades; validar cualquier import; mantener `Compat.lua` como único sitio con ramas por cliente; actualizar esta spec si cambia el modelo.
- **Ask first**: cambiar el esquema de SavedVariables (requiere migración); añadir librerías (Ace3, LibDataBroker...); integración con el ObjectiveTracker de Blizzard; nuevos usos de `SendAddonMessage` fuera del protocolo de compartir (ADR-006); empaquetado separado por cliente.
- **Never**: `loadstring` sobre datos importados; `COMBAT_LOG_EVENT_UNFILTERED`; acciones protegidas en combate; intentar revelar valores secretos; editar los archivos del plugin `wow-addon-dev` instalado.

## Success Criteria

1. Crear una plantilla con al menos un objetivo de cada tipo desde el diario, sin `/cq` de texto.
2. Aceptarla: aparece en el tracker; los objetivos item/kill/zone/location avanzan solos en mundo abierto en **Retail y Forever**.
3. Una plantilla `daily` completada vuelve a estar disponible tras el reset diario.
4. Exportar → importar en otro personaje produce una plantilla idéntica; un texto manipulado se rechaza con mensaje, sin error Lua.
5. El historial muestra fecha y número de veces completada por plantilla.
6. `/reload` y reinicio completo conservan plantillas, activas e historial en ambos clientes.
7. Tests offline en verde.

## Decisiones

- Muertes en instancias: deben contar (diseño en "Muertes en instancias").
- Empaquetado: un solo zip para ambos clientes.
- UI: **mock-up primero** (aceptado 2026-11-01); la UI de producción espera a su aprobación.

## Open Questions

1. ¿Confirmas los supuestos 1, 2, 4 y 5 (sobre todo objeto = "en bolsas ahora")?
2. ¿Te vale el modo "aproximado" para trash de instancia cuando el NPC no se puede identificar?

## v0.4 — iconos, niveles y cadenas

- **Icono por plantilla** (`icon`): nombre de archivo de `Interface/Icons` o fileID. Sin icono se usa el del primer objetivo. Se ve en la lista, el detalle y el rastreador. **Retirado después:** ahora el icono sale del tipo de misión (campaña, repetible o suelta) y de su estado, con los iconos del juego.
- **Nivel mínimo/máximo** (`minLevel`, `maxLevel`): solo se comprueban al aceptar (como en WoW). Una misión ya aceptada no se cancela por subir de nivel.
- **Etapas vs. cadenas**: las etapas son pasos dentro de una misma misión (una entrada, una recompensa, una línea de historial). Una cadena son misiones distintas enlazadas con `requires` (la plantilla previa): la siguiente queda bloqueada hasta que **este personaje** completa la anterior, y entonces se acepta sola si cumple el nivel.
- Sin bucles (`ERR_CHAIN_CYCLE`). Borrar un eslabón reconecta el siguiente con el anterior.
- **Exportar** una plantilla que forma parte de una cadena exporta la cadena entera (`{ chain = { { template, requires = índice } } }`); al importar, los enlaces solo pueden apuntar a entradas anteriores.

## Secciones de misiones

- Una **sección** (`CustomQuestsDB.sections`, máx. 50, nombre ≤ 40) agrupa plantillas que el jugador decide que están relacionadas. Cada plantilla lleva `section = id` (o nada), pero **una cadena se mueve entera**: `Model.SetSection` arrastra todas las misiones enlazadas (y el editor, al cambiar la sección de una misión, mueve su cadena). Datos antiguos con una cadena repartida se siguen mostrando: la parte que queda sin su anterior abre su propio árbol.
- Sin secciones todo se ve como antes. Con alguna, van en el orden de la lista y las misiones sin sección al final bajo «Otras misiones». En Plantillas las secciones vacías conservan su cabecera; en Activas y en el rastreador se ocultan.
- Borrar una sección no borra misiones: quedan sin sección. Un `section` que no existe se lee como «sin sección».
- **Exportar/importar**: la sección viaja por **nombre** (`sectionName` en una plantilla suelta, `section` en cada entrada de `chain`); al importar se reutiliza la sección del mismo nombre o se crea. Se puede exportar una sección entera (`Serializer.ExportSection`, ≤ 50 misiones).
- Las misiones activas se agrupan según la plantilla *viva* (no la copia), así que mover una plantilla mueve también su misión en curso. El plegado de Activas y del rastreador es por personaje y separado.
- Esquema: solo se añaden campos (sin subir `schema`). Una versión anterior del addon perdería `section` al guardar la plantilla.

## Compartir en el juego (ADR-006)

- **Qué:** una misión (con su cadena entera) o una sección. **A quién:** el objetivo, un jugador por nombre (`Nombre` o `Nombre-Reino`), el grupo (PARTY, RAID o INSTANCE_CHAT) o la hermandad. Menú contextual de Plantillas («Compartir con…»), menú de la cabecera de sección y `/cq share <jugador|group|guild>` sobre la plantilla seleccionada.
- **Protocolo** (prefijo `CustomQuests`, `SendAddonMessageLogged`, campos separados por `~`, versión `1`):

| Trama | Canal | Campos |
|---|---|---|
| `O` oferta | WHISPER o grupo/hermandad | `tid`, tipo (`quest`/`chain`/`section`), nº de misiones, bytes del CQ1, `z`, título saneado |
| `A` aceptar | WHISPER | `tid`, `z` |
| `N` rechazar | WHISPER | `tid` (o `-` para un enlace caducado), motivo (`declined`, `busy`, `full`, `gone`) |
| `D` datos | WHISPER | `tid`, `i`, `n`, codificación `p`/`z`, trozo (≤ 240 bytes) |
| `K` recibido | WHISPER | `tid`, `ok` / `dup` / clave de error |
| `X` abortar | WHISPER | `tid` |
| `R` pedir (enlace) | WHISPER | etiqueta del enlace |

- **Recepción:** popup con remitente, título, tipo, nº de misiones y tamaño; Aceptar / Rechazar / Bloquear; expira a los 60 s sin respuesta. Solo tras Aceptar llegan los `DATA`, que pasan por `Serializer.Import` → `Model.ValidateTemplate` → `Model.SaveImported` como un import pegado.
- **Límites:** 1 oferta por remitente cada 30 s; 3 ofertas esperando; 1 popup; 2 transferencias entrando; 3 ofertas propias vivas; 10 receptores por oferta de grupo; oferta válida 90 s; 30 s sin fragmentos = timeout; 16 KB de texto, 100 fragmentos, nunca más bytes que los anunciados; 1000 plantillas por cuenta.
- **Opciones** (`CustomQuestsDB.options.sharing`): `incoming` = `trusted` (amigos, hermandad y grupo; por defecto) / `anyone` / `off`; `chatLinks` (por defecto sí); `autoStart` (por defecto sí): al aceptar una oferta se inician las misiones que puedan empezar (de una cadena, solo el primer eslabón; las que ya están activas o fuera de nivel se quedan solo como plantilla). Bloqueados en `CustomQuestsDB.shareBlocked` (`["nombre-reino"] = true`, máx. 200). Solo se añaden campos, sin subir `schema`.
- **Duplicados:** `Model.SaveImported` omite una plantilla con la misma huella (`Model.Fingerprint`: contenido validado sin sección, enlace ni fecha) y devuelve `ids, skipped`; el chat dice «ya estaba».
- **Enlace de chat:** `[CustomQuests: Título]` en texto plano (≤ 40 bytes saneados); el filtro local lo convierte en `|Haddon:CustomQuests:<autor>:<título>|h`; el clic pide la misión por `R`; el autor la ofrece si la enlazó hace ≤ 10 min. No se filtran SAY, YELL ni canales numerados; los susurros de desconocidos solo con `incoming = anyone`.
- **Compresión:** Deflate + base64 de `C_EncodingUtil` si ambos lo tienen (detectado en ejecución); entrada comprimida ≤ 4 KB, salida descartada si no cabe en un CQ1.
- **Restricciones 12.x:** con `InChatMessagingLockdown()` la cola se pausa y avisa; sigue sola. Payloads secretos de `CHAT_MSG_ADDON(_LOGGED)` y del chat se ignoran. Cuentas de prueba/veterano: no envían, se avisa.
