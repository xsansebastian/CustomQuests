# Architecture Decision Records

Registro de las decisiones de arquitectura de CustomQuests: el porqué, las alternativas y sus consecuencias. No se borran: si una decisión cambia, se escribe un ADR nuevo que la sustituye.

| ADR | Decisión | Estado |
|---|---|---|
| [001](ADR-001-lua-puro-y-paquete-por-cliente.md) | Lua puro, capa `ns.api` y un paquete por cliente | Accepted |
| [002](ADR-002-muertes-sin-combat-log.md) | Muertes con `PARTY_KILL` y `ENCOUNTER_END`, sin combat log | Accepted (falta validar en instancias) |
| [003](ADR-003-formato-cq1-sin-ejecutar-codigo.md) | Formato `CQ1:` propio que nunca ejecuta código | Accepted |
| [004](ADR-004-cadenas-frente-a-etapas.md) | Cadenas como plantillas enlazadas, distintas de las etapas | Accepted |
| [005](ADR-005-componentes-nativos-de-blizzard.md) | Dropdowns e iconos con los componentes nativos de Blizzard | Accepted |

Nuevos ADR: `ADR-NNN-titulo-en-kebab-case.md` con las secciones Status, Date, Context, Decision, Alternatives Considered y Consequences.
