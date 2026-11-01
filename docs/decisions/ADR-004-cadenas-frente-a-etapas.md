# ADR-004: Cadenas de misiones como plantillas enlazadas, distintas de las etapas

## Status
Accepted

## Date
2026-11-01

## Context
El modelo ya tenía **etapas**: pasos secuenciales dentro de una misma misión, con una entrada en el diario, una recompensa y una línea de historial. El usuario pidió también **cadenas de misiones** y preguntó si eran lo mismo.

Para rol, una campaña por capítulos necesita que cada capítulo tenga su propio título, texto, icono, recompensa, rango de niveles e historial. Eso no cabe en las etapas.

## Decision
- Una cadena se modela con un campo opcional `requires` en la plantilla: el ID de la plantilla que hay que completar antes.
- **Bloqueo por personaje:** una plantilla con `requires` solo se puede aceptar si **este personaje** ha completado la anterior (según el historial de cuenta, que guarda el personaje).
- **Avance automático:** al completar una misión, sus continuaciones se aceptan solas si el personaje cumple los requisitos (por ejemplo, el nivel). El chat avisa en cualquier caso.
- **Sin bucles:** `Model.WouldCycle` impide guardar un `requires` que cierre un ciclo, y el editor no ofrece esas opciones.
- **Borrar un eslabón** reconecta la cadena: sus continuaciones pasan a requerir el eslabón anterior.
- Se permite que una misión tenga varias continuaciones (ramas).
- Las etapas no cambian.

## Alternatives Considered

### Ampliar las etapas (texto y recompensa por etapa)
- Pros: sin conceptos nuevos.
- Cons: sigue siendo una sola entrada de historial y de diario; no hay niveles por capítulo; no se puede reutilizar un capítulo en otra cadena.
- Rejected: no cubre lo que pidió el usuario.

### Una entidad «cadena» aparte que contenga una lista ordenada de plantillas
- Pros: orden explícito; fácil de mostrar como lista.
- Cons: otra entidad que guardar, editar, exportar y validar; complica las ramas.
- Rejected: un único campo `requires` cubre la necesidad con menos superficie.

### Desbloqueo por cuenta en lugar de por personaje
- Pros: los alters no repiten capítulos.
- Cons: rompe la idea de progreso de rol de cada personaje.
- Rejected; se podría ofrecer como opción en el futuro.

## Consequences
- Los IDs de plantilla son locales a cada cuenta, así que el export reescribe los enlaces como índices (ver ADR-003).
- Una plantilla editada después de aceptada no afecta a la misión en curso (se guarda una copia al aceptar); el cambio sí aplica al siguiente eslabón que se acepte.
- La lista de plantillas marca en gris las bloqueadas, y el detalle muestra «Requiere…» y «Siguiente en la cadena…».

## Actualización
- Las cadenas se crean ahora hacia delante desde el detalle de la plantilla: el botón «Añadir siguiente misión» abre el editor con una misión nueva ya enlazada (hereda el tipo de la anterior).
- El campo del editor se lee «Se desbloquea al completar», el desplegable lista las plantillas como un árbol (los seguimientos sangrados) y bajo él se muestra el camino de la cadena («Cadena: A » B » Esta misión») con las misiones que vienen después.
- Plantillas permite marcar varias con una casilla y borrarlas de una vez. Si alguna tiene misiones detrás en su cadena que no están marcadas, se elige entre borrar toda la rama o solo las marcadas (las demás se enlazan con la anterior, como al borrar una sola). El botón Borrar del detalle sigue el mismo camino.
- Se consideró y se descartó un selector «Suelta / En cadena»: añade un estado más que mantener sincronizado con `requires`. También un editor de cadenas dedicado: es la entidad «cadena» ya rechazada arriba.
