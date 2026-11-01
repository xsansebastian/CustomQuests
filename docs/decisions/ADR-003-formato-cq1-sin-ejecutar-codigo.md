# ADR-003: Formato de import/export «CQ1:» propio, que nunca ejecuta código

## Status
Accepted

## Date
2026-11-01

## Context
Las plantillas (sobre todo las de rol) se comparten entre jugadores pegando texto en chat, Discord o foros. Ese texto es **contenido no confiable**: cualquiera puede escribirlo o manipularlo. Además:
- Tiene que sobrevivir a cajas de texto y chat del juego, donde `|` inicia secuencias de escape (colores, enlaces, texturas).
- El addon no usa librerías (ADR-001), así que no hay AceSerializer ni LibDeflate.
- Una cadena de misiones (ADR-004) tiene que poder compartirse entera.

## Decision
- Formato propio: prefijo `CQ1:` + base64 de una serialización tipada mínima (`t` tabla, `s<len>:` cadena, `n…;` número, `T`/`F` booleanos).
- **El import nunca ejecuta código:** parser propio, sin `loadstring`. Límites duros: 16 KB de texto, profundidad 8, 1000 claves por tabla, números finitos.
- Lo decodificado **siempre pasa por `Model.ValidateTemplate`**: se descartan campos desconocidos, se recortan textos y se rechaza lo inválido con un mensaje, nunca con un error de Lua.
- Los textos se guardan tal cual y se escapan al mostrarlos (`Util.SafeText`): los `|c`, `|H` o `|T` importados se ven como texto, no se interpretan.
- Una plantilla que pertenece a una cadena se exporta con la cadena completa: `{ chain = { { template, requires = índice } } }`. Al importar, los enlaces solo pueden apuntar a entradas anteriores, así que no se pueden crear bucles.

## Alternatives Considered

### Serializar como código Lua y cargarlo con `loadstring`
- Pros: trivial de implementar.
- Cons: ejecutar texto pegado por terceros es ejecución de código arbitrario.
- Rejected: inaceptable por seguridad.

### AceSerializer + LibDeflate (formato tipo WeakAuras)
- Pros: estándar de facto, compacto.
- Cons: dos dependencias externas, contra ADR-001.
- Rejected.

### JSON
- Pros: legible.
- Cons: no hay parser JSON en el entorno de WoW; contiene caracteres que el chat transforma.
- Rejected.

## Consequences
- El base64 añade ~33 % al tamaño de la serialización y no hay compresión; aceptable para plantillas de pocos KB (la del explorador ocupa ~1,3 KB).
- Si cambia el formato habrá que crear `CQ2:` y mantener la lectura de `CQ1:`.
- Las variables `{name}`, `{class}` y `{race}` viajan sin sustituir, así que cada jugador que importa ve su propio nombre.
- Los tests offline cubren ida y vuelta, textos truncados o manipulados, anidamiento excesivo y enlaces de cadena hacia delante.
