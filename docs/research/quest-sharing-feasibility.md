# Viabilidad: compartir misiones entre jugadores (en juego y fuera)

Fecha: 2026-11-01 · Rama: `feature/quest-sharing` · Solo investigación, sin cambios de código.

**Estado:** fases 0-2 implementadas (ver ADR-006); fase 3 pendiente.

**Evidencia usada.** Snapshot `wow-addon-dev` 2.1.0, que fija Gethe/wow-ui-source en Retail `d07eb002` (12.1.5.70688) y en Forever `ca8368f2` (1.60.1.70532). Además, warcraft.wiki.gg, el código de WeakAuras y prensa sobre los cambios de 12.0.

**Grados de evidencia:**
- **[fuente]**: declarado en el código de Blizzard en los commits fijados.
- **[wiki]**: documentado en warcraft.wiki.gg.
- **[sin verificar]**: no confirmado. Nada se ha probado en el juego.

## TL;DR

| Opción | Viabilidad | Esfuerzo | Veredicto |
|---|---|---|---|
| 1. Addon messages (grupo/hermandad/susurro) con oferta → aceptar → import | **Alta** | **M** | Base de todo. Es el MVP. |
| 2. Enlace clicable en chat que pide los datos al emisor | **Media-alta** | **S** encima de la 1 | Fase 2. Funciona con el patrón de WeakAuras. |
| 3. UX de "compartir misión" (dialogo, anti-spam, opt-out) | **Alta** | Va incluida en la 1 | Obligatoria desde el MVP. |
| 4. Compresión nativa (`C_EncodingUtil`) | **Alta** (está declarada en ambos clientes) | **S** | Fase 3. Reduce los fragmentos a 2,5× menos. Opcional. |
| 5. Galería web, Discord, QR | Alta (web/Discord), baja (QR) | **S** | Galería en el repo y export partido en líneas. Se descarta el QR. |

Ninguna opción necesita librerías ni `loadstring`. Todas reutilizan `Serializer.Import` → `Model.ValidateTemplate` → `Model.SaveImported`, así que se cumplen ADR-001 y ADR-003.

---

## Datos medidos (tamaños reales)

Medidos con los ficheros de `screenshots/imports/` y `tests/imports/`.

**Leyenda de columnas:**
- **«crudo»**: la serialización antes de pasarla a base64.
- **«deflate+b64»**: aproxima `C_EncodingUtil.CompressString` (Deflate) seguido de base64.
- **Fragmentos**: de 240 bytes útiles cada uno (255 menos unos 15 de cabecera).

| Fichero | CQ1 | crudo | deflate | deflate+b64 | fragmentos CQ1 | fragmentos deflate+b64 |
|---|---:|---:|---:|---:|---:|---:|
| 01-the-ember-oath (cadena larga) | 6072 | 4550 | 1828 | 2444 | 26 | 11 |
| 03-personal-goals | 4636 | 3473 | 1305 | 1744 | 20 | 8 |
| 02-dailies-and-weeklies | 3808 | 2852 | 1176 | 1572 | 16 | 7 |
| 09-seccion-completa | 3032 | 2269 | 410 | 552 | 13 | 3 |
| 05-the-innkeepers-favour (1 misión rol) | 1300 | 970 | 566 | 760 | 6 | 4 |
| 02-diaria (1 misión simple) | 560 | 415 | 282 | 380 | 3 | 2 |

**Peor caso permitido.** `Serializer.MAX_LENGTH` = 16384 ≈ **69 fragmentos** sin comprimir. Deflate deja el texto entre el 18 % y el 68 % del crudo (mejor cuanto más se repite).

**Coste en tiempo:**
- Con el throttle de PARTY/RAID/GUILD (ráfaga de 10 y luego 1 por segundo), la cadena más grande sin comprimir tarda unos 17 s y el peor caso unos 60 s. Comprimida, la cadena más grande cabe en la ráfaga (alrededor de 1 s).
- Por WHISPER fuera de instancias no hay throttle por prefijo [wiki], así que el tiempo da igual.

---

## 1. Addon messages — viabilidad ALTA

### Hechos de la API

**Funciones y evento [fuente].** `C_ChatInfo.RegisterAddonMessagePrefix`, `SendAddonMessage`, `SendAddonMessageLogged` y el evento `CHAT_MSG_ADDON` están declarados en Retail y en Forever con la misma firma.
- `SendAddonMessage` devuelve `Enum.SendAddonMessageResult`, con 13 valores: `AddonMessageThrottle`=3, `ChannelThrottle`=8, `NotInGroup`=5, `NotInGuild`=10, `AddOnMessageLockdown`=11 y `TargetOffline`=12, entre otros.
- Sus argumentos son `SecretArguments = NotAllowed`: nunca se le puede pasar un valor secreto.
- Enlaces: [Retail ChatInfoDocumentation.lua#L515](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua#L515), [L534 Logged](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua#L534), [L800 CHAT_MSG_ADDON](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua#L800).

**Límites [wiki]** ([C_ChatInfo.SendAddonMessage](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)):
- El prefijo admite como máximo 16 caracteres y el mensaje 255.
- Se permiten los bytes del 1 al 255; el NUL no.
- Un `Success` solo significa que el mensaje se encoló, no que se haya entregado.

**Throttle [wiki].** Cada prefijo tiene una reserva de **10 mensajes que se recupera a 1 por segundo**.
- Desde 10.2.7 se aplica a todos los tipos de chat.
- **No se aplica a WHISPER fuera de contenido instanciado.**
- Blizzard puede cambiar estas cifras.

**Canales [wiki]:**
- PARTY, RAID (cae a PARTY si no estás en banda), INSTANCE_CHAT, GUILD, OFFICER, WHISPER y CHANNEL.
- WHISPER solo funciona con el mismo reino o reinos conectados.

**Contenido de usuario [wiki].** `SendAddonMessageLogged` es la vía recomendada para el contenido que escriben los jugadores, porque permite denunciarlo. Llega como `CHAT_MSG_ADDON_LOGGED`.
- Exige **texto imprimible**: los caracteres no imprimibles hacen que falle sin avisar.
- El CQ1 en base64 ya cumple ese requisito.

**Cuentas Trial y Veteran [wiki].** No pueden enviar addon messages en Forever (1.60.1). Según la wiki, Retail hará lo mismo a partir de 12.1.7 (PTR).

**Restricciones de 12.x:**
- [fuente] `AddOnRestrictionType` incluye `Combat`, `Encounter`, `ChallengeMode`, `PvPMatch`, `Map` y `Chat`. Existen `C_ChatInfo.InChatMessagingLockdown()` y el evento `ADDON_RESTRICTION_STATE_CHANGED`, en ambos clientes. Enlace: [RestrictedActionsConstantsDocumentation.lua#L18](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsConstantsDocumentation.lua#L18).
- [fuente] `CHAT_MSG_WHISPER` lleva `SecretInChatMessagingLockdown = true`: durante el bloqueo, el texto y el remitente son secretos.
- Blizzard (Kaivax, alfa de Midnight) dijo que el bloqueo de chat y de addon comms se limitaría a **encuentros de banda activos y partidas de M+**. La intención declarada es no afectar a lo que se comparte antes o después del combate. Fuentes: [Warcraft Tavern](https://www.warcrafttavern.com/wow/news/blizzard-walks-back-some-api-changes-for-addons-in-midnight/), [Icy Veins](https://www.icy-veins.com/wow/news/combat-addon-restrictions-eased-in-midnight/).
- Un addon de terceros (Whisper Messenger, 2026) enumera como restringidos M+, BG puntuados y encuentros de banda. [sin verificar oficialmente]

**Battle.net:**
- [fuente] `C_BattleNet.SendGameData(gameAccountID, prefix, data)` y `BN_CHAT_MSG_ADDON` (payload `senderID`) existen en ambos clientes.
- [wiki] El antiguo `BNSendGameData` está obsoleto en 12.0, admitía hasta 4078 bytes y **no garantiza el orden de entrega** ([wiki](https://warcraft.wiki.gg/wiki/API_BNSendGameData)).
- [sin verificar] El límite de tamaño de `C_BattleNet.SendGameData` y si funciona entre facciones o reinos distintos.

### Diseño propuesto (sin librerías)

**Prefijo.** Uno solo: `"CustomQuests"` (12 caracteres) o `"CQSH"`.

**Formato de cada trama.** `v1|<tipo>|<transferID>|<i>/<n>|<datos>`:
- Tipos: `OFFER` (título saneado, número de misiones y bytes), `ACCEPT`, `DECLINE`, `DATA`, `NACK` (lista de índices que faltan, fase 3) y `ABORT`.
- `transferID` aleatorio de 6 caracteres; el receptor solo acepta `DATA` de una transferencia que **él** aceptó y que venga del mismo `sender`.

**Reensamblado:**
- Por índice, sin suponer orden (BN lo desordena seguro; el resto, por si acaso).
- Límites: 30 s de timeout, como mucho 2 transferencias a la vez por remitente, como mucho 69 fragmentos y 16 KB en total. Si se pasa, se descarta.
- Al completar, el texto pasa por `Serializer.Import`, igual que el import manual. Así cualquier corrupción se convierte en un `ERR_IMPORT_*` y nunca en un error de Lua.

**Throttle propio.** Un token bucket de unas 40 a 60 líneas, sin ChatThrottleLib:
- Cola FIFO más `C_Timer.NewTicker(0.1)`, con 10 tokens que se recuperan a 1 por segundo en canales de grupo y hermandad, y unos 5 por segundo en WHISPER por cortesía.
- Si llega `AddonMessageThrottle` o `ChannelThrottle`, se reencola con backoff. Si llega `AddOnMessageLockdown`, se pausa hasta `ADDON_RESTRICTION_STATE_CHANGED`. Si llega `TargetOffline`, `NotInGroup` o `NotInGuild`, se aborta y se avisa.
- Antes de enviar se comprueba `C_ChatInfo.InChatMessagingLockdown()`.
- Es posible porque el protocolo es pequeño y la API devuelve códigos de resultado desde 10.2.7.

**Flujo de grupo.**
1. Se anuncia `OFFER` en PARTY, RAID o INSTANCE_CHAT.
2. Cada jugador que acepta recibe los `DATA` por WHISPER, que no tiene throttle fuera de instancias.
3. Si el WHISPER falla, por ejemplo con un compañero de grupo de un reino no conectado, se hace un broadcast en el canal de grupo con el `transferID`. [sin verificar] Queda pendiente probar en el juego si el WHISPER de addon llega a ese caso.

### Riesgos

- El bloqueo en encuentros, M+ y PvP. Se mitiga con una cola y un mensaje de «se enviará al salir del combate o encuentro».
- Las cuentas Trial y Veteran no pueden enviar.
- WHISPER entre reinos no conectados y entre facciones [sin verificar].
- Blizzard puede cambiar el throttle.
- Duplicados: `Model.SaveImported` no deduplica, así que compartir dos veces crea dos copias. No hay tope global de plantillas.

### Cambios en este código (esfuerzo M)

**Ficheros nuevos:**
- `Comm.lua`: transporte puro y testeable offline (fragmentar, reensamblar, token bucket y timeouts).
- `Share.lua`: protocolo de oferta, aceptación y datos, y política de quién puede ofrecer.

**`Compat/Common.lua`.** Es el único sitio con llamadas al cliente (regla de SPEC). Funciones nuevas en `ns.api`:
- `api.RegisterCommPrefix`, `api.SendComm` (envuelve `SendAddonMessageLogged` y devuelve el resultado normalizado) y `api.InChatLockdown`.
- `api.IsIgnored(name)` → `C_FriendList.IsIgnored` [fuente en ambos clientes: [FriendListDocumentation.lua#L234](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_APIDocumentationGenerated/FriendListDocumentation.lua#L234)].
- `api.IsInGroup` y `api.IsInGuild`.

**`Core.lua`:**
- Handlers `CHAT_MSG_ADDON_LOGGED`, `CHAT_MSG_ADDON` y `ADDON_RESTRICTION_STATE_CHANGED`.
- Registrar el prefijo en `PLAYER_LOGIN`.
- Cuidado: el `OnEvent` actual hace `handlers[event](...)` sin comprobar nada.

**`Serializer.lua`.** Nada obligatorio: `Serializer.ExportChain` y `ExportSection` ya producen el texto. Opcional: una `Serializer.Peek(text)` que dé un resumen (título y número de misiones) para el diálogo.

**`Model.lua`:**
- `CleanOptions` y `OPTION_DEFAULTS` ganan `sharing = { enabled, fromGroup, fromGuild, fromWhisper }`.
- Opcional: un tope `MAX_TEMPLATES`.

**Interfaz:**
- `UI/Dialogs.lua`: popup `CUSTOMQUESTS_SHARE_OFFER`, que muestra el remitente, el título y el número de misiones, todo pasado por `UI.QuestText` o `Util.SafeText`, con `timeout` de unos 60 s. Más una barra o texto de progreso en la ventana Transfer.
- `UI/Journal.lua`: en el menú contextual (cerca de la línea 460, junto a `L["EXPORT"]`), «Compartir con el grupo», «… con el objetivo» y «… con la hermandad». Lo mismo en el menú de sección (cerca de la línea 277).
- `UI/Options.lua`: casillas para aceptar ofertas de grupo, hermandad y susurros.

**Resto:**
- `Locales/*.lua` (4 idiomas): unas 15 claves.
- `CustomQuests.toc`: `Comm.lua` y `Share.lua` detrás de `Serializer.lua`.
- `tests/run.lua`: fragmentar y reensamblar en orden aleatorio, fragmentos perdidos con timeout, `DATA` no solicitado, exceso de tamaño, remitente cambiado a mitad, y throttle con un reloj falso.
- Docs: `docs/decisions/ADR-006-compartir-por-addon-messages.md` y la sección «Compartir» en `SPEC.md`.

---

## 2. Enlace clicable en chat — viabilidad MEDIA-ALTA

### Hechos

**El tipo de enlace `addon` es solo local.** No se puede enviar por chat ([wiki Hyperlinks](https://warcraft.wiki.gg/wiki/Hyperlinks)).
- [fuente, en ambos clientes] `LinkUtil.RegisterLinkHandler(LinkTypes.AddOn, …)` dispara `EventRegistry:TriggerEvent("SetItemRef", link, text, button, frame)`, con el comentario «local links only».
- Enlaces: [Retail ItemRefHandlersShared.lua#L278](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_UIPanels_Game/Shared/ItemRefHandlersShared.lua#L278), [Forever #L279](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Shared/ItemRefHandlersShared.lua#L279).

**Filtros de chat [fuente, en ambos clientes].** `ChatFrameUtil.AddMessageEventFilter(event, callback)` está en `Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua#L202`. El global antiguo `ChatFrame_AddMessageEventFilter` solo aparece en `Blizzard_DeprecatedChatInfo`.

**Patrón probado (WeakAuras, [Transmission.lua](https://github.com/WeakAuras/WeakAuras2/blob/main/WeakAuras/Transmission.lua)):**
1. Se envía **texto plano** `[WeakAuras: Personaje - Nombre]`.
2. El filtro del receptor lo convierte en `|Hgarrmission:weakauras|h…|h`.
3. Al hacer clic, se pide por addon whisper (`dR`).
4. El emisor solo responde si ese aura se enlazó hace menos de 5 minutos.
5. En los susurros de desconocidos que no son del grupo, la hermandad ni amigos de BN, el filtro no hace nada.

**Tamaño.** Un mensaje de chat tiene un máximo de 255 caracteres, y la misión más pequeña ocupa 560. Por eso el enlace solo lleva la referencia; los datos se piden por la vía de la opción 1.

### Diseño

**Envío.** Mayús+clic en el diario inserta `[CustomQuests: <Título saneado>]` en el editbox. El emisor recuerda `{ título → templateID, hora }` durante 10 minutos.

**Recepción:**
- Un filtro en `CHAT_MSG_PARTY/RAID/GUILD/OFFICER/WHISPER/INSTANCE_CHAT/SAY` (sin canales numerados) **comprueba `issecretvalue` sobre el texto y el remitente** antes de buscar el patrón; durante el bloqueo son secretos.
- El texto se sustituye por `|Haddon:CustomQuests:<remitente>:<token>|h[CustomQuests: …]|h`.
- Usar `addon` en lugar de `garrmission` es lo correcto ahora: el enlace se crea localmente en el filtro, así que no tiene que viajar.

**Clic.** `EventRegistry:RegisterCallback("SetItemRef", …)` → `REQ` por WHISPER → el emisor comprueba que lo enlazó hace poco → `OFFER` y `DATA`, con el mismo flujo y el mismo popup de la opción 1.

### Riesgos

- El emisor tiene que estar conectado.
- WHISPER entre reinos no conectados [sin verificar]. WeakAuras usa Chomp para el caso entre reinos, lo que sugiere que ahí hay limitaciones.
- Quien no tiene el addon ve texto plano, que es aceptable.
- Spam en canales públicos: no se filtran SAY ni canales numerados, o se hace con una opción.

### Esfuerzo (S, sobre la opción 1)

- Fichero nuevo `UI/ChatLink.lua` (filtro, handler y mayús+clic).
- `UI/Journal.lua`: hook de mayús+clic en las filas.
- `Share.lua`: tipo `REQ` y caché de enlaces recientes.
- `Compat/Common.lua`: `api.AddChatFilter`, con fallback a `ChatFrame_AddMessageEventFilter` si `ChatFrameUtil` no existe.
- Locales y tests del parser del marcador.

---

## 3. UX tipo "Compartir misión" y anti-abuso

**Flujo.** Menú «Compartir» → `OFFER` → en el receptor, `StaticPopup` con «X quiere compartir "Título" (N misiones)» y los botones Aceptar, Rechazar e Ignorar a X durante la sesión → transferencia → `Serializer.Import` → `Model.SaveImported` → mensaje «Importada: …» (el mismo que `Dialogs.ShowImport`, para reutilizar `L["IMPORTED"]`).

**Controles obligatorios desde el MVP:**
- **Opt-out y alcance:** casillas en Options. Por defecto: grupo y hermandad activados; susurros de desconocidos solo si son amigos, del grupo o de la hermandad.
- **Lista de ignorados:** `C_FriendList.IsIgnored(sender)`, y una lista de ignorados propia de la sesión.
- **Límite de ofertas:** como mucho 1 cada 30 s por remitente y 1 popup abierto a la vez. Las ofertas que no caben se descartan sin avisar y se cuentan.
- **Tamaño:** como mucho 16 KB y 69 fragmentos. Se respetan los mismos límites de `Model` (20 etapas, 10 objetivos, 80 y 500 caracteres) y de cadena o sección (50).
- **Nunca se ejecuta código:** la vía es la misma que el import manual (ADR-003).
- **Combate:** no se muestra el popup con `InCombatLockdown()`; queda en cola hasta `PLAYER_REGEN_ENABLED`, como hace WeakAuras.

**Saneado de textos:**
- `OFFER` lleva un título de muestra. En el receptor se **ignora** y se muestra el del CQ1 ya validado. Si se quiere enseñar antes de aceptar, pasa por `Util.SafeText`, que ya escapa `|`.
- En el marcador de chat se quitan `| [ ] :`, los caracteres de control (<32) y los saltos de línea, y se recorta a 40 bytes. Así nadie puede cerrar el corchete o inyectar `|H` o `|T` y suplantar otro enlace.
- El nombre del remitente sale **solo** del evento, porque el servidor lo rellena; nunca del cuerpo del mensaje.

**Ya está bien hecho:**
- `UI.QuestText` = `SafeText` + tokens.
- Los textos se guardan crudos y se escapan al mostrarlos.
- Los popups usan `text = "%s"` con el texto ya escapado.

---

## 4. Compresión y tamaño

**API nativa [fuente, en ambos clientes].** `C_EncodingUtil.CompressString(source, method=Deflate, level=Default)` y `DecompressString`, con `MayReturnNothing` y `SecretArguments = AllowedWhenUntainted`. También existen `EncodeBase64`, `DecodeBase64`, `SerializeCBOR` y `SerializeJSON`.
- Enlaces: [Retail EncodingUtilDocumentation.lua#L10](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_APIDocumentationGenerated/EncodingUtilDocumentation.lua#L10), [Forever #L10](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/EncodingUtilDocumentation.lua#L10), [wiki](https://warcraft.wiki.gg/wiki/API_C_EncodingUtil.CompressString).
- [sin verificar] El parche en que apareció y si funciona de verdad en Forever.

**Recomendación:**
- Comprimir **solo en el transporte**: CQ1 → crudo → Deflate → `EncodeBase64`, porque `SendAddonMessageLogged` exige texto imprimible.
- Hacerlo con detección de capacidad: si no existe `C_EncodingUtil`, se manda CQ1 tal cual. Un flag en `OFFER` (`z=1`) lo indica.
- No cambiar el formato de copiar y pegar todavía. Un `CQ2:` comprimido no se puede testear con LuaJIT offline sin implementar Deflate en Lua.

**Bomba de descompresión.** `DecompressString` no tiene límite de salida.
- Medidas: limitar la entrada comprimida a unos 8 KB, comprobar que la salida no pase de 16 KB **antes** de llamar a `Serializer.Decode`, y no descomprimir nunca nada no solicitado.
- [sin verificar] El coste de memoria del peor caso.

**Orden y pérdidas:**
- MVP: índice por fragmento y timeout; si algo falla, se reintenta todo.
- Fase 3: `NACK` con los índices que faltan.
- No hace falta checksum: el parser y `ValidateTemplate` ya detectan la corrupción. Se puede añadir el total de bytes en `OFFER`.

---

## 5. Compartir fuera del juego (resumen)

- **Galería en GitHub o CurseForge:** ya existe `screenshots/imports/`, generado por `tools/make_screenshot_imports.lua` y probado en CI. Se puede ampliar a `gallery/` con un README por plantilla y enlazarlo desde la descripción de CurseForge. Esfuerzo S, riesgo nulo.
- **Formato para Discord:**
  - `fromBase64` ya **ignora espacios en blanco** (`text:gsub("%s","")`), así que se puede exportar partido en líneas de 76 caracteres dentro de un bloque de código sin tocar el import.
  - Basta con una opción «partir en líneas» en `Dialogs.ShowExport`. Ojo: `MAX_LENGTH` cuenta también los saltos de línea.
  - [sin verificar] El límite de Discord es de unos 2000 caracteres por mensaje sin Nitro. La cadena más grande (6 KB) no cabe, así que hay que adjuntarla como `.txt`.
- **Wago o webs de terceros:** no hay plataforma genérica conocida para un addon como este [sin verificar]. Una página propia (GitHub Pages) que lea y muestre CQ1 es posible, pero no aporta mucho.
- **QR:** descartado. Los cerca de 6 KB no caben cómodamente, en el juego no hay cámara y no resuelve nada que no resuelva copiar y pegar.

---

## 6. Seguridad, privacidad y política

**Ejecución de código:** ninguna. Se usa el mismo parser y validador que en el import manual (ADR-003). La superficie nueva es la de **disponibilidad** (spam y memoria), no la de ejecución.

**Riesgos y mitigaciones:**
- Popups de spam: límite de ofertas, opt-out y lista de ignorados.
- Memoria en el reensamblado: topes y timeouts.
- Bomba de descompresión: ver el punto 4.
- Relleno de SavedVariables con imports repetidos: tope de plantillas y aviso.
- Suplantación visual en el título o el enlace: saneado (punto 3).
- `DATA` no solicitado: se descarta.

**Contenido ofensivo** en textos de rol: usar `SendAddonMessageLogged`, que según la wiki existe para que se pueda denunciar.

**Privacidad:**
- Solo se expone el nombre del personaje, que va en el evento de todos modos.
- Nada de pings de versión ni de presencia automáticos por GUILD sin opt-in.
- No se recopila nada.

**Política de Blizzard (UI Add-On Development Policy):** [blizzard.com](https://www.blizzard.com/en-us/legal/1b40bc3c-6264-4ce4-a8a2-fa1bc8eef4ad/ui-add-on-development-policy). **No se pudo leer en esta sesión (HTTP 504).** De memoria, sin verificar: los addons deben ser gratuitos, con código no ofuscado, sin impacto negativo en el rendimiento del servidor ni comunicación excesiva, y sin publicidad ni spam en el juego.
- El diseño propuesto lo cumple: transferencias bajo demanda, con throttle y por WHISPER cuando se puede.

---

## 7. Compatibilidad con Forever

| Pieza | Retail 12.1.5 | Forever 1.60.1 |
|---|---|---|
| `SendAddonMessage(Logged)`, `CHAT_MSG_ADDON`, enum de resultados | [fuente] | [fuente], idéntico |
| `InChatMessagingLockdown`, `ADDON_RESTRICTION_STATE_CHANGED`, `AddOnRestrictionType.Chat` | [fuente] | [fuente]. Cuándo se activa: **[sin verificar]** |
| Trial y Veteran no pueden enviar | Desde 12.1.7 (PTR) [wiki] | Sí [wiki] |
| `C_BattleNet.SendGameData` | [fuente] | [fuente] |
| `LinkTypes.AddOn` → `EventRegistry "SetItemRef"` | [fuente] L278 | [fuente] L279 |
| `ChatFrameUtil.AddMessageEventFilter` | [fuente] | [fuente] |
| `C_EncodingUtil.*` | [fuente] | [fuente] |
| `C_FriendList.IsIgnored` | [fuente] | [fuente] |

Conclusión: las tres opciones encajan en `Compat/Common.lua` sin ramas por cliente, solo con detección de capacidad. Forever sigue **sin probar en el juego** (SPEC §115).

---

## Plan por fases

1. **Fase 0 (S):**
   - ADR-006 y la sección «Compartir» de SPEC.
   - Opción de export partido en líneas para Discord.
   - Galería.
   - Tope de plantillas.
   - Helper `Util.SafeLinkLabel` y sus tests.
2. **Fase 1, MVP (M):**
   - `Comm.lua`, `Share.lua` y los cambios en `Compat`.
   - «Compartir con el grupo, el objetivo o la hermandad» con oferta, popup e import; CQ1 sin comprimir por `SendAddonMessageLogged`.
   - Throttle propio, manejo del bloqueo, opciones de opt-out y tests offline.
3. **Fase 2 (S):**
   - Marcador en chat → enlace local `addon` → petición al emisor.
4. **Fase 3 (S-M):**
   - Compresión nativa con detección de capacidad.
   - `NACK` y reanudación.
   - Amigos de Battle.net por `C_BattleNet.SendGameData`.
   - Deduplicación por un hash de origen.

## Preguntas abiertas que hay que probar en el juego

1. ¿`SendAddonMessageLogged` por PARTY o RAID devuelve `AddOnMessageLockdown` en mazmorras normales o heroicas fuera de combate, o solo durante encuentros y M+? ¿Y en Forever?
2. ¿Llega `CHAT_MSG_ADDON(_LOGGED)` durante el bloqueo, o se encola o se pierde? ¿El payload llega secreto? La fuente solo marca `SecretInChatMessagingLockdown` en `CHAT_MSG_WHISPER`; hay que confirmarlo para `CHAT_MSG_ADDON`.
3. WHISPER de addon a: un compañero de grupo de un reino **no conectado**, un jugador de la otra facción en el grupo, y un jugador de la otra facción fuera del grupo.
4. Throttle real por WHISPER fuera de instancias: ¿cuántos mensajes por segundo sin desconexión ni pérdidas?
5. ¿Funciona `C_EncodingUtil.CompressString` y da resultados deterministas en Forever? ¿Y en Retail? ¿Cuánto tarda con 16 KB?
6. Límite real de bytes y throttle de `C_BattleNet.SendGameData`. ¿Funciona entre Retail y Forever? Probablemente no, porque son productos distintos.
7. ¿Llega `CHAT_MSG_ADDON` sin errores a un receptor Trial y Veteran?
8. ¿El filtro de chat con un enlace `|Haddon:` funciona en todos los marcos de chat, incluido el nuevo chat de 12.x, y el clic llega al callback `SetItemRef`?

## No verificado en esta sesión

- La política de addons de Blizzard (HTTP 504).
- El límite de Discord.
- Los límites de `C_BattleNet.SendGameData`.
- Los contextos exactos del bloqueo de chat en 12.1.5 y en Forever.
- WHISPER entre reinos y entre facciones.
- La versión en que apareció `C_EncodingUtil`.
- Todo el comportamiento en ejecución: lo marcado como [fuente] es una declaración en el código, no una prueba en el juego.
