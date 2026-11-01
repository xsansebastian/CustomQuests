# ADR-006: Compartir misiones en el juego por addon messages, con oferta y aceptación

## Status
Accepted (falta validar en el juego; ver `tests/INGAME.md`)

## Date
2026-11-01

## Context
Hasta ahora una misión solo se compartía copiando y pegando el texto `CQ1:` (ADR-003). Los jugadores de rol quieren pasarse misiones dentro del juego: a su objetivo, al grupo o a la hermandad. El informe `docs/research/quest-sharing-feasibility.md` estudió las opciones. Restricciones:
- Sin librerías (ADR-001): ni AceComm, ni ChatThrottleLib, ni LibDeflate.
- El import nunca ejecuta código (ADR-003).
- Un addon message tiene como mucho 255 bytes; el prefijo comparte un cupo de 10 mensajes que se recupera a 1 por segundo en todos los canales menos WHISPER fuera de instancias (warcraft.wiki.gg).
- En 12.x el chat y los addon messages se bloquean en encuentros de banda, Mítica+ y JcJ puntuado (`C_ChatInfo.InChatMessagingLockdown`, `ADDON_RESTRICTION_STATE_CHANGED`); el texto del chat puede llegar como valor secreto.
- Las cuentas de prueba y de veterano no pueden enviar addon messages (Forever; Retail desde 12.1.7 según la wiki).
- Recibir datos de desconocidos abre una superficie de **disponibilidad**: spam de popups, memoria, SavedVariables llenos, bombas de descompresión.

## Decision
- **Transporte propio** en `Comm.lua` (Lua puro, testeable offline): tramas con campos separados por `~`, fragmentos de ≤ 240 bytes en mensajes de ≤ 255, reensamblado por índice en cualquier orden con duplicados ignorados, índices y tamaño comprobados y timeout por inactividad. Cola de salida con un token bucket propio (10 y luego 1/s en grupo y hermandad; 10 y 5/s en susurros), backoff ante `AddonMessageThrottle`/`ChannelThrottle`, pausa ante bloqueo de chat y abandono de toda la transferencia ante `TargetOffline`, `NotInGroup` o `NotInGuild`.
- **Protocolo** en `Share.lua`, versión `1`: `OFFER` → `ACCEPT`/`DECLINE` → `DATA` → `K` (recibido), más `X` (abortar) y `R` (petición desde un enlace de chat). La oferta puede ir por WHISPER, PARTY/RAID/INSTANCE_CHAT o GUILD, pero los datos **solo** van por WHISPER y **solo** a quien aceptó; el receptor descarta cualquier `DATA` que no pertenezca a una transferencia que él aceptó de ese mismo remitente. Una trama con otra versión se ignora.
- **Envío con `SendAddonMessageLogged`**, la vía para contenido escrito por jugadores (denunciable). El texto CQ1 y el base64 ya son imprimibles.
- Al completar, el texto pasa por **el mismo camino que un import pegado**: `Serializer.Import` → `Model.ValidateTemplate` → `Model.SaveImported`.
- **Controles anti-abuso desde el MVP:** popup con Aceptar / Rechazar / Bloquear (lista de bloqueados persistente, se vacía en Opciones); lista de ignorados del juego; por defecto solo ofertas de amigos, hermandad y grupo (opciones: cualquiera, nadie); 1 oferta por remitente cada 30 s; como mucho 3 ofertas esperando y 1 popup a la vez; nada de popups en combate; como mucho 2 transferencias entrando; tope de `bytes` anunciado en la oferta, 16 KB de texto y 100 fragmentos; tope global de 1000 plantillas; los rechazos por política son **silenciosos** (el remitente no sabe si le has bloqueado).
- **Saneado:** el título de la oferta y el nombre del remitente pasan por `Util.SafeLabel` (sin `|`, `[`, `]`, `:`, `~` ni caracteres de control; recortados sin partir UTF-8). El remitente sale siempre del evento, nunca del mensaje.
- **Duplicados:** `Model.SaveImported` ya no guarda una plantilla idéntica a una existente (misma huella, sin contar sección, enlace de cadena ni fecha): reutiliza la existente y lo dice. Vale para el import pegado y para el compartido.
- **Enlace de chat (fase 2):** se escribe texto plano `[CustomQuests: Título]` (≤ 40 bytes saneados). El filtro de chat del receptor (`ChatFrameUtil.AddMessageEventFilter`, o el global antiguo) lo cambia por un enlace local `|Haddon:CustomQuests:<autor>:<título>|h`, que nunca viaja. El clic (`EventRegistry` `"SetItemRef"`) envía `R` por susurro y el autor, si lo enlazó hace menos de 10 minutos, manda una oferta normal. Sin esos ganchos el marcador se queda como texto.
- **Compresión (fase 3):** si los dos clientes tienen `C_EncodingUtil`, la serialización dentro del CQ1 viaja con Deflate + base64. `OFFER` y `ACCEPT` llevan `z`, y cada `DATA` su codificación (`p`/`z`), así que clientes con y sin compresión se entienden. Contra bombas: solo se descomprime lo aceptado, la entrada comprimida está limitada a 4 KB, y la salida se descarta si no cabe en un CQ1 de 16 KB.
- **Bloqueo de chat 12.x:** antes de cada envío se consulta `InChatMessagingLockdown`; la cola se pausa y avisa una vez, y sigue sola al terminar. Los payloads secretos de `CHAT_MSG_ADDON` se ignoran antes de compararlos.

## Alternatives Considered

### AceComm + ChatThrottleLib + LibDeflate
- Pros: probadas, con reintentos y compresión portable.
- Cons: tres dependencias, contra ADR-001.
- Rejected.

### Enviar los datos por el canal de grupo o hermandad
- Pros: un solo envío para todos.
- Cons: todos reciben datos que no han aceptado, y el cupo de 1 mensaje por segundo lo hace lento (≈ 60 s en el peor caso).
- Rejected: solo la oferta va al canal; los datos, por susurro a cada uno que acepta.

### Enviar la misión entera en el enlace de chat
- Pros: sin protocolo.
- Cons: un mensaje de chat tiene 255 caracteres y la misión más pequeña ocupa ~560.
- Rejected.

### Sustituir la plantilla duplicada en vez de omitirla
- Pros: se actualizaría a la versión recibida.
- Cons: con la misma huella el contenido es idéntico; sustituir solo cambiaría ids y rompería enlaces de cadenas y misiones activas.
- Rejected: se omite y se informa.

## Consequences
- Nadie recibe nada sin pulsar Aceptar; lo peor que puede hacer un desconocido es enviar ofertas que se descartan sin avisar.
- El protocolo es versionado; un cambio incompatible será `2` y los clientes `1` lo ignorarán.
- Todo lo que depende del juego (bloqueos reales, susurros entre reinos y facciones, throttle real, `C_EncodingUtil` en Forever, el filtro de chat en el chat nuevo de 12.x, cuentas de prueba) está **sin verificar**: ver `tests/INGAME.md`.
- La protección contra bombas no puede limitar la salida *durante* `DecompressString` (la API no lo permite); se acota la entrada, así que el peor caso transitorio es de unos 4 MB.
- Fuera de alcance: Battle.net (`C_BattleNet.SendGameData`), `NACK` y reanudación, export en líneas para Discord, galería web y QR.
