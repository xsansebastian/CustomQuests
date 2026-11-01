# Viabilidad: interactuar con NPCs (proximidad, diálogo, tooltip)

Fecha: 2026-11-01 · Rama: `feature/interact-npcs` · Solo investigación, sin cambios de código.

**Evidencia usada.** Gethe/wow-ui-source, rama `live`, commit `d07eb00237d8891f153215db98a5df880a26cfe5` (`version.txt` = 12.1.5.70688). Firmas de `Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua`. Para `UnitPosition` y 12.0, además warcraft.wiki.gg.

**Grados de evidencia:** todo es comprobación estática; nada se ha probado en el juego. El cliente instalado puede ir por delante o por detrás del espejo: confirmar con `select(4, GetBuildInfo())`. El TOC también declara 120001 y 16001; este documento solo cubre Retail. Forever y Classic necesitan su propia comprobación.

## TL;DR

Sí se puede, pero solo de forma **pasiva**. El addon puede detectar qué NPC tiene delante y reaccionar (completar un objetivo, mostrar un aviso, abrir una ventana propia, añadir una línea al tooltip) siempre que el jugador ya esté interactuando con él, lo tenga en target, ratón o soft-target, o vea su placa de nombre.

No puede:
- medir la distancia real a un NPC concreto (`UnitPosition` solo vale para jugador y grupo);
- interactuar con el NPC ni seleccionarlo por código (APIs protegidas);
- añadir opciones al gossip de Blizzard (no hay API; tocar su frame produce taint).

Fuera de grupo y en mundo abierto la identidad del NPC es legible. En instancias o con restricciones activas puede llegar como valor secreto.

## Cómo está el addon hoy (lo relevante)

- Tipos de objetivo en `Model.lua:26-35` (`OBJECTIVE_FIELDS`): item, kill, boss, zone, subzone, location, level y manual. Ya existe un campo `giver`, pero es texto libre (`Model.lua:103`, `UI/Editor.lua:330`).
- `Objectives.lua`: `eachObjective` recorre las quests activas y su etapa actual. Los objetivos de zona y localización se quedan fijados en 1 al cumplirse. `OnKill` ya tiene modo aproximado cuando el GUID es secreto.
- `Core.lua`: `RefreshAll`, `ApplyChange` y una tabla `handlers` donde cada evento se registra con pcall. Solo hay un ticker de 1 s para `location`, y solo existe mientras hace falta (`UpdateLocationTicker`).
- `Compat/Common.lua` (`ns.api`): `IsSecret`, `GetTargetNPC()`, `GetPlayerPosition`, `HookItemTooltip`.
- `Util.NPCIDFromGUID` (`Util.lua:15`) acepta Creature y Vehicle.
- `docs/decisions/ADR-002-muertes-sin-combat-log.md` documenta qué hacer con valores secretos.

## 1. Detectar proximidad

| Mecanismo | Firma | ¿Sirve? | Caveats |
|---|---|---|---|
| Coordenadas del jugador vs. coordenadas fijas del NPC | `C_Map.GetPlayerMapPosition(uiMapID, "player")` | **Sí, ya se usa** (objetivo `location`) | La posición del NPC se escribe en la plantilla. No sirve para NPCs que se mueven. |
| `UnitPosition(unit)` | solo `SecretArguments` en el doc | Solo jugador | Según la wiki, solo player/party/raid; nil en instancias. **No da la posición de un NPC.** |
| `CheckInteractDistance(unit, distIndex)` | `PlayerScriptDocumentation.lua` | Solo con unit token | Necesita target, mouseover, softinteract, npc o nameplateN. Restricciones en combate: **no verificado** en 12.x. Usar fuera de combate. |
| `C_Item.IsItemInRange` / LibRangeCheck | `ItemDocumentation.lua` | Desaconsejado | Necesita token e ítem de referencia; restringido en combate (**no verificado**). |
| `C_Navigation.GetDistance()` + `NAVIGATION_DESTINATION_REACHED` | `InGameNavigationDocumentation.lua` | Interesante | Poner un waypoint con `C_Map.SetUserWaypoint` y `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`. Coste: pisa el waypoint y el super-track del jugador (solo hay uno). |
| Placas de nombre | `NAME_PLATE_UNIT_ADDED` / `_REMOVED`; `FORBIDDEN_NAME_PLATE_UNIT_ADDED` | Proximidad aproximada | ~40-60 m según CVars. NPCs amistosos solo si el jugador tiene placas activadas. En instancias son "forbidden". Frecuente en ciudades: filtrar con tabla de npcIDs. |
| Soft-target de interacción | `PLAYER_SOFT_INTERACT_CHANGED(oldTarget, newTarget)` (`SecretWhenUnitIdentityRestricted`); token `"softinteract"` | **Mejor señal de "estoy al lado"** | El payload trae los GUID: sin polling. Depende del CVar `SoftTargetInteract` (valor por defecto **no verificado**). Alcance de interacción, pocos metros. |
| Target y mouseover | `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT` | Sí | Exigen acción del jugador. Para distancia, `CheckInteractDistance("target", 3)`. |
| Interacción iniciada | `GOSSIP_SHOW`, `PLAYER_INTERACTION_MANAGER_FRAME_SHOW(type)`, `QUEST_DETAIL`, `QUEST_GREETING` | **Señal más fiable** | La cercanía está garantizada. Token `"npc"` válido mientras dura. Un NPC sin diálogo no dispara nada. |

## 2. Identificar el NPC

- `UnitCreatureID(unit)` es **nuevo en 12.0**, con `SecretWhenUnitIdentityRestricted` y `RequiresUnitIdentityAccess`. Más limpio que trocear el GUID.
- Alternativa: `UnitGUID(unit)` + `Util.NPCIDFromGUID`.
- `SecretWhenUnitIdentityRestricted` produce secretos cuando la unidad no es del jugador ni del grupo/banda, y solo mientras la restricción está activa. Tipos de restricción (`Enum.AddOnRestrictionType`): Combat, Encounter, ChallengeMode, PvPMatch, Map, Chat.
- Consulta previa: `C_Secrets.ShouldUnitIdentityBeSecret(unit)`. Cambios: `ADDON_RESTRICTION_STATE_CHANGED(type, state)` y `C_RestrictedActions.IsAddOnRestrictionActive(type)`.
- En mundo abierto y fuera de restricción el GUID y el npcID son legibles. En mazmorras, bandas, M+, PvP o encuentros pueden ser secretos.
- Con un secreto **no se puede comparar ni trocear**: se comprueba con `issecretvalue` y se descarta (ADR-002). `UnitName` tiene su propia variante (`SecretWhenUnitNameIdentityRestricted`).

## 3. Interacción directa

- **Leer el gossip: sí.** `C_GossipInfo.GetOptions()`, `GetText()`, `GetAvailableQuests()`, `GetActiveQuests()`, `SelectOption(id)`, `CloseGossip()`; eventos `GOSSIP_SHOW`, `GOSSIP_CLOSED`, `GOSSIP_OPTIONS_REFRESHED`.
- **Añadir opciones al gossip de Blizzard: no.** Alternativas:
  1. Ventana o tarjeta **propia** abierta con `GOSSIP_SHOW` o `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`, anclada a `GossipFrame` si está visible y centrada si no (convivencia con Immersion, DialogueUI). Reutilizar el estilo de `UI/TurnIn.lua` y `UI/Dialogs.lua`.
  2. Aviso con `api.Splash`/`Print` y sonido.
  3. Línea en el tooltip del NPC.
- **Interactuar o seleccionar por código: no.** `C_PlayerInteractionManager.InteractUnit` y `ReopenInteraction` llevan `HasRestrictions = true`; `TargetUnit` también está protegido. Pedir al jugador su tecla de interacción, o un macro `/target Nombre` que pulse él.
- **Tooltip:** `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, fn)`. `data.guid` puede ser secreto: filtrar como en `api.HookItemTooltip`.
- **Mapa:** `C_Map.CanSetUserWaypointOnMap`, `SetUserWaypoint(UiMapPoint)`, `ClearUserWaypoint`, `C_SuperTrack.SetSuperTrackedUserWaypoint(bool)`. Pins propios (data providers de MapCanvas) son posibles pero fuera del MVP.

## 4. Límites y cambios de 12.0

- **Protegido o imposible:** interactuar, seleccionar objetivo, moverse hacia el NPC, añadir opciones al gossip, leer la posición de un NPC.
- **Nuevo en 12.0 y relevante:** valores secretos (`issecretvalue`, `canaccessvalue`, `C_Secrets.*`), `UnitCreatureID`, `C_RestrictedActions` con `ADDON_RESTRICTION_STATE_CHANGED`, error al registrar `COMBAT_LOG_EVENT_UNFILTERED` (ver ADR-002).
- **No verificado en 12.x:** si `CheckInteractDistance` o `IsItemInRange` siguen restringidos en combate; valor por defecto de `SoftTargetInteract`.

## Rendimiento

- Los eventos (gossip, interacción, soft-interact, target, mouseover, tooltip) cuestan prácticamente nada. Comparar contra un `set[npcID]` que se reconstruye con `QUESTS_CHANGED`; no recorrer plantillas en cada evento.
- `NAME_PLATE_UNIT_ADDED` es frecuente en ciudades: consulta O(1) y salir.
- Si hace falta polling, `C_Timer.NewTicker` de 0,5-1 s que **solo exista** mientras haya objetivos pendientes (como `UpdateLocationTicker`). Nunca `OnUpdate` por frame.

## Recomendación de diseño (MVP)

1. **Objetivo `talk`** ("habla con X"). En `Model.lua` `OBJECTIVE_FIELDS`: `talk = { npcID = "number", name = "string", mapID = "number" }`. Como `zone` y `location`: meta 1, se fija al cumplirse, sin entrar en `COUNTED`.
   - Disparadores en `Core.lua` `handlers`: `GOSSIP_SHOW`, `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`, `QUEST_DETAIL`/`QUEST_GREETING`, cada uno con `ns.api.GetUnitNPC("npc")`.
   - `Objectives.OnTalk(quests, npcID, mapID)` → `ns.ApplyChange(...)`.
   - Exacto y sin polling. Con identidad secreta no se cuenta (sin `fallbackAny` para hablar).
2. **`api.GetUnitNPC(unit)` en `Compat/Common.lua`**: devuelve npcID y nombre, o nil. Prueba `UnitCreatureID` y si no `UnitGUID` + `Util.NPCIDFromGUID`; `api.IsSecret` en cada valor. `api.GetTargetNPC()` pasa a ser `GetUnitNPC("target")`.
3. **Variante opcional "acércate a X"**: opción `proximity = true` dentro de `talk`, con `PLAYER_SOFT_INTERACT_CHANGED` y, de respaldo, `UPDATE_MOUSEOVER_UNIT` / `PLAYER_TARGET_CHANGED` + `CheckInteractDistance(unit, 3)`. Para un NPC estático, `location` con radio pequeño sigue siendo lo más robusto.
4. **Ofrecer o entregar quests al hablar (fase 2):** campo `giverNPC = "number"` junto a `giver`. Con `GOSSIP_SHOW` y ese npcID, tarjeta propia ("CustomQuests: <título> — Aceptar") anclada a `GossipFrame`, reutilizando `UI/Dialogs.lua` y el flujo de aceptar de `Lifecycle`. Mismo enganche para entregar con `ns.TurnIn`.
5. **Tooltip:** `api.HookUnitTooltip(fn)` siguiendo `HookItemTooltip`, y `UI/UnitTooltip.lua` análogo a `UI/ItemTooltip.lua`.
6. **Editor** (`UI/Editor.lua:60`): el botón "desde target" ya rellena npcID y nombre; vale para `talk` y `giverNPC`.
7. **Tests y docs:** casos en `tests/run.lua` para `OnTalk` (identidad secreta → no cuenta); un ADR-007 ("Interacción con NPCs solo por eventos de interacción; sin posición de NPC ni interacción programática"); filas en `tests/INGAME.md`: gossip en mundo abierto, NPC sin gossip (no dispara), NPC dentro de instancia (identidad secreta), convivencia con addons que sustituyen el gossip.
8. **Fuera del MVP:** waypoint/super-track automáticos (solo como botón "Marcar en el mapa"), placas de nombre, LibRangeCheck.
