# Plan: borrado múltiple en el árbol de Plantillas

## Objetivo
- **Casillas:** cada fila de la vista Plantillas tiene una casilla. Con ella se marcan varias plantillas y se borran de una vez.
- **Borrado dentro de una cadena:** si alguna de las plantillas que se van a borrar tiene siguientes en la cadena que no están marcadas, se pregunta:
  - **Toda la rama:** borra la plantilla y todo lo que va después de ella.
  - **Solo esta:** borra solo la plantilla. Sus siguientes pasan a depender del padre de la borrada (lo que hace hoy `Model.DeleteTemplate`).
  - **Cancelar.**

Las misiones activas creadas a partir de esas plantillas se mantienen, como ahora.

## Grafo de dependencias
```
Model.GetDescendants / Model.DeleteTemplates  (lógica pura, con tests)
        │
        ├── Diálogo de 3 botones (UI/Dialogs.lua)
        │
        └── Casillas + botón «Borrar (N)» (UI/Journal.lua)
                 └── El botón Borrar del detalle usa el mismo flujo
Locales (4) ── las usan los dos anteriores
```

## Decisiones
- **Modelo:**
  - `Model.GetDescendants(id)` devuelve todos los ids que van después de `id` en la cadena, sin incluir `id`.
  - `Model.DeleteTemplates(ids, withBranch)` borra en bloque. Si `withBranch` es verdadero, añade los descendientes de cada id. Después borra cada uno con `Model.DeleteTemplate`, que vuelve a enlazar los siguientes. Borrar en secuencia es correcto incluso si padre e hijo están los dos marcados: el nieto acaba colgando del abuelo.
  - `Model.NeedsBranchChoice(ids)` es verdadero si alguno de los ids tiene un siguiente directo que no está en `ids`. Si todos los descendientes ya están marcados, no hace falta preguntar.
- **Diálogo:** `StaticPopupDialogs` con `button1 = «Toda la rama»`, `button3 = «Solo esta(s)»` y `button2 = CANCEL`. Antes hay que comprobar en el FrameXML de Retail que `button3` llama a `OnAlt`. Si no es fiable, usar dos diálogos encadenados.
- **UI:**
  - La casilla es de 18 px (`UICheckButtonTemplate`), va antes del botón de plegar y desplaza un poco la sangría.
  - La selección se guarda en `state.checked[id] = true`. Se limpia al salir de Plantillas y después de borrar, y se descartan los ids que ya no existen.
  - El botón «Borrar (N)» va en la cabecera de Plantillas, a la izquierda de Importar. Se desactiva si N = 0.
  - Al hacer clic en la casilla solo se marca; al hacer clic en la fila se sigue mostrando el detalle.
  - El botón Borrar del detalle usa el mismo flujo con `{ id }`.
- **Rama:** esta funcionalidad se añade en `feature/ux-improve-chainQuest-Creation` (PR #3 abierto), porque toca el mismo `Journal.lua`.

## Tareas

### Fase 1: modelo
**T1. Borrado en bloque en el modelo**
- **Archivos:** `Model.lua` y `tests/run.lua`.
- **Aceptación:**
  - `GetDescendants` en la cadena A > B > (C > E, D): para B devuelve {C, D, E}; para E devuelve {}.
  - `DeleteTemplates({B}, true)` deja solo A.
  - `DeleteTemplates({B}, false)` deja C y D colgando de A.
  - `DeleteTemplates({A, B}, false)`: C y D quedan como raíz y E sigue colgando de C.
  - `NeedsBranchChoice({B, C, D, E})` es falso y `NeedsBranchChoice({B})` es verdadero.
- **Verificación:** `luajit tests/run.lua` pasa sin fallos.

**Checkpoint 1:** tests en verde antes de tocar la UI.

### Fase 2: UI
**T2. Diálogo de borrado**
- **Archivos:** `UI/Dialogs.lua` y las cuatro locales.
- **Aceptación:**
  - `Dialogs.ConfirmDelete(ids, onDone)` usa el diálogo de 3 botones si `NeedsBranchChoice` es verdadero, y si no, el `Confirm` simple.
  - El texto menciona el título si es una sola plantilla, o «N plantillas» si son varias.
  - Llama a `Model.DeleteTemplates` y después a `onDone`.

**T3. Casillas y botón «Borrar (N)» en Plantillas**
- **Archivo:** `UI/Journal.lua`.
- **Aceptación:**
  - La casilla solo aparece en la vista Plantillas y conserva su estado al plegar y desplegar.
  - El botón muestra el número de marcadas y se desactiva si no hay ninguna.
  - El botón Borrar del detalle usa `ConfirmDelete({ id })`.
  - Después de borrar, se refrescan la lista, la selección y el rastreador (`ns.RefreshAll` si corresponde).

**T4. Documentación**
- Añadir una línea al `CHANGELOG.md` y una nota en la «Actualización» de ADR-004 sobre el borrado de toda la rama.

**Checkpoint 2:** tests en verde, comprobación de sintaxis con `luajit` de todos los archivos tocados y revisión del diff.

## Comprobaciones en el juego
- Marcar 3 plantillas sueltas → Borrar (3) → confirmar.
- Marcar Cadena B → aparece la pregunta → «Solo esta» → C y D cuelgan de A.
- Lo mismo con «Toda la rama» → desaparecen B, C, D y E.
- Que las casillas no se monten con el botón de plegar ni con el icono.
