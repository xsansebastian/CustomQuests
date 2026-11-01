# ADR-002: Contar muertes con PARTY_KILL y ENCOUNTER_END, sin combat log

## Status
Accepted (pendiente de validar en juego dentro de instancias)

## Date
2026-11-01

## Context
Los objetivos de tipo «matar» necesitan saber qué NPC ha muerto. En Retail 12.x:
- `COMBAT_LOG_EVENT_UNFILTERED` **ya no está disponible para addons**, y `CombatLogGetCurrentEventInfo()` no se puede usar desde código de addon.
- `PARTY_KILL(attackerGUID, targetGUID)` existe en Retail y en Forever, pero su payload está anotado `SecretWhenUnitIdentityRestricted`: en instancias, durante el combate, los GUID de unidades que no son jugadores son **valores secretos**. No se pueden comparar ni descomponer, y está prohibido intentar revelarlos.
- `ENCOUNTER_END(encounterID, ..., success)` no tiene anotación de secreto.

El usuario pidió explícitamente que las muertes **cuenten también en instancias**.

## Decision
- **NPC identificable** (mundo abierto, o fuera de la restricción): `PARTY_KILL` + el npcID extraído del GUID → conteo exacto.
- **Identidad secreta** (`issecretvalue(targetGUID)`): nunca se inspecciona el GUID. La muerte cuenta como «no identificada» y solo suma a:
  - objetivos «matar en este mapa» sin NPC concreto, y
  - objetivos de NPC marcados como **aproximados** (`fallbackAny`) en ese mismo mapa.
  El rastreador muestra un icono de aviso en esos objetivos.
- **Jefes:** un tipo de objetivo propio, `boss`, con `ENCOUNTER_END` y `success == 1`. Es exacto.
- El editor explica el modo aproximado y pide un ID de mapa para usarlo.

## Alternatives Considered

### Combat log (`COMBAT_LOG_EVENT_UNFILTERED`)
- Pros: era la forma estándar; da el NPC exacto.
- Cons: no se entrega a addons en 12.x.
- Rejected: no funciona.

### Contar por botín (`LOOT_READY` + origen del botín)
- Pros: no depende de `PARTY_KILL`.
- Cons: solo cuenta los cadáveres que se saquean; `GetLootSourceInfo` no aparece en el inventario de APIs generado; los datos de botín también pueden ser secretos en instancias.
- Rejected: menos fiable que `PARTY_KILL` y con las mismas restricciones.

### No soportar muertes en instancias
- Pros: honesto y simple.
- Cons: el usuario lo pidió expresamente.
- Rejected; se mantiene como plan B si `PARTY_KILL` no llegara a los addons dentro de instancias.

## Consequences
- En instancias, «10 bandidos Defias» se convierte en «10 muertes en las Minas»: puede contar otros enemigos. Es una limitación del juego, no del addon, y se comunica en la UI.
- **Riesgo abierto:** está verificado que `PARTY_KILL` existe en el código fuente, pero no que se entregue a addons dentro de instancias. Es el punto 6 de `tests/INGAME.md`. Si no se entrega, el trash de instancia pasa a «no soportado» y solo quedan los jefes.
- Forever puede aplicar los secretos en situaciones distintas; hay que volver a validarlo al portar.
