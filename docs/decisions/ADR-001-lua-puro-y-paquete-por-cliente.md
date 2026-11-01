# ADR-001: Lua puro con una capa de compatibilidad y un paquete por cliente

## Status
Accepted

## Date
2026-11-01

## Context
CustomQuests debe funcionar en **Retail** (12.1.x, interfaz 120105) y, más adelante, en **Forever** (1.60.x, interfaz 16001). Los dos clientes comparten buena parte de la API, pero no toda: Forever se identifica con `WOW_PROJECT_CAMELOT`, no con `WOW_PROJECT_MAINLINE`, y las restricciones de valores secretos pueden comportarse distinto. Además:
- Queremos poder probar la lógica sin el juego (tests offline con LuaJIT).
- No queremos depender de librerías de terceros que haya que mantener en dos clientes.
- La guía multi-versión del plugin `wow-addon-dev` recomienda código compartido con un adaptador por cliente y un artefacto por cliente.

## Decision
- **Lua puro, sin librerías** (ni Ace3 ni LibStub).
- **Una sola capa de acceso al cliente, `ns.api`**, implementada en `Compat/Retail.lua` (y en el futuro `Compat/Forever.lua`). Ningún otro módulo de lógica llama a la API del juego directamente.
- **Lógica pura y testeable** en `Util`, `Model`, `Serializer`, `Objectives`, `Lifecycle` y `Samples`; los tests sustituyen `ns.api` por un falso.
- **Un zip por cliente**, cada uno con su TOC, su número de interfaz y solo su adaptador. Se empieza por Retail.

## Alternatives Considered

### Un solo paquete con TOC multi-interfaz y ramas `if isRetail`
- Pros: un solo zip; más simple de distribuir.
- Cons: el código de ambos clientes se mezcla en todos los módulos; un fallo de detección hace que se use la API equivocada.
- Rejected: el usuario eligió un zip por cliente y la guía lo desaconseja.

### Ace3 (AceAddon, AceDB, AceConfig)
- Pros: base de datos con perfiles, opciones y eventos ya resueltos.
- Cons: dependencia externa en dos clientes; más difícil de testear offline; añade peso para un addon pequeño.
- Rejected: lo que necesitamos de Ace (SavedVariables con valores por defecto, un bus de eventos) son unas pocas líneas en `Model` y `Util`.

## Consequences
- Portar a Forever consiste en escribir `Compat/Forever.lua` y un TOC; el resto del código no se toca.
- Los tests (`luajit tests/run.lua`) cubren la lógica sin cliente; la UI y los eventos reales solo se validan en juego (`tests/INGAME.md`).
- La UI (`UI/`) sí usa la API de frames directamente; si Forever difiere en widgets, habrá que aislarlo también (ver ADR-005).
- Cada adaptador comprueba al arrancar que el cliente es el esperado y avisa si se instaló el zip equivocado.
