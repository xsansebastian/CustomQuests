# ADR-007: Interacción con NPCs solo por eventos y unidades cercanas

## Status
Accepted (falta validar en el juego)

## Date
2026-11-02

## Context
Se quiere que una misión se complete, o muestre un texto, al acercarse a un NPC concreto. En Retail 12.x:
- La posición de un NPC no se puede leer: `UnitPosition` solo sirve para el jugador y el grupo.
- Interactuar con un NPC o seleccionarlo por código está protegido (`C_PlayerInteractionManager.InteractUnit`, `TargetUnit`), y no hay API para añadir opciones al diálogo (gossip) de Blizzard.
- El identificador de un NPC (`UnitGUID`) puede ser un valor secreto dentro de instancias (`SecretWhenUnitIdentityRestricted`); ver ADR-002.
- El cursor sobre una unidad del mundo lo redibuja el motor en cada fotograma: cambiarlo con `SetCursor` parpadea (probado en el juego).

## Decision
- Nuevo tipo de objetivo `near`, con `npcID`, `name`, `label` (texto mostrado) y `dialog` (texto del popup). Se completa al detectar al NPC cerca y se queda completado.
- «Cerca» se decide con las unidades que el juego ya da al addon: `npc` (se está hablando con él), `softinteract`, y `target`, `mouseover` y placas de nombre dentro del alcance de `CheckInteractDistance(unit, 3)`. Un ticker de 0,5 s existe solo mientras haya objetivos de ubicación o `near` pendientes; `PLAYER_SOFT_INTERACT_CHANGED` y `GOSSIP_SHOW` comprueban al instante.
- Identidad secreta: el NPC se descarta, nunca se inspecciona.
- Al completarse, un objetivo con `dialog` abre un popup propio (retrato `PlayerModel:SetCreature`, nombre y texto con scroll). No se toca el gossip de Blizzard.
- El tooltip del NPC (`TooltipDataProcessor`, tipo Unit) muestra la misión y el texto del objetivo mientras está pendiente.
- Se descarta cambiar el cursor del ratón.
- Máximo de 5 objetivos por etapa.

## Alternatives Considered

### Coordenadas del NPC con `location`
- Pros: ya existía y no depende de la identidad.
- Cons: no detecta al NPC, solo un punto del mapa; falla si el NPC se mueve.

### Waypoint y `C_Navigation`
- Pros: aviso nativo al llegar.
- Cons: ocupa el único waypoint y super-track del jugador.

### Añadir una opción al gossip de Blizzard
- Cons: no hay API; tocar el marco produce taint y se rompe con cada parche.

## Consequences
- No funciona dentro de instancias con restricciones, ni con NPCs que el jugador no tenga a la vista (sin placa, target, ratón o soft-target) y sin hablarles.
- El popup y el tooltip leen el texto de la copia de la plantilla guardada al aceptar la misión; editar la plantilla no cambia una misión ya aceptada.
- `CheckInteractDistance` en combate y el valor por defecto de `SoftTargetInteract` no están verificados en 12.x.
