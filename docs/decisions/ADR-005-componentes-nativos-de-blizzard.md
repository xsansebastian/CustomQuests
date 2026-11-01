# ADR-005: Usar los componentes nativos de Blizzard para dropdowns e iconos

## Status
Accepted

## Date
2026-11-01

## Context
El editor tenía botones que cambiaban de opción con cada clic y un selector con 24 iconos fijos. El usuario pidió:
- que los selectores de opciones sean **dropdowns**;
- que el selector de iconos tenga **la misma lista que la ventana de macros**, con los usados recientemente arriba.

Comprobado en el código de la UI de Retail (Gethe/wow-ui-source, commit `d07eb002`):
- `WowStyle1DropdownTemplate` + `DropdownButtonMixin:SetupMenu` / `CreateRadio` / `SetScrollMode` (`Blizzard_Menu`, Retail 11+).
- `IconDataProviderMixin` con `IconDataProviderExtraType.Spellbook`, que es exactamente lo que usa `Blizzard_MacroUI.lua:123`. Por debajo, `GetMacroIcons` y `GetMacroItemIcons`.

## Decision
- **Dropdowns:** un único envoltorio, `UI.CreateDropdown(parent, width, getItems, getValue, onSelect)`, sobre `WowStyle1DropdownTemplate`. Todas las selecciones (tipo, repetición, cadena, tipo de objetivo) lo usan. Las listas largas se desplazan con `SetScrollMode`.
- **Iconos:** `UI/IconPicker.lua` crea un `IconDataProviderMixin` (tipo Spellbook) al abrirse y lo libera (`Release`) al cerrarse, porque mantiene en memoria todo el catálogo. La rejilla es virtual (10×7 botones reutilizados) con rueda y barra.
- Los iconos se guardan normalizados: fileID numérico o nombre de archivo (`Model.NormalizeIcon`).
- **Recientes:** los últimos 10, por cuenta (`CustomQuestsDB.recentIcons`).

## Alternatives Considered

### `UIDropDownMenu` (API antigua)
- Pros: existe también en clientes clásicos.
- Cons: en desuso en Retail, propenso a taint y con otro aspecto que el resto de la UI moderna.
- Rejected para Retail. Puede ser la implementación de Forever si allí no se carga `Blizzard_Menu`.

### Reutilizar `IconSelectorPopupFrameTemplate` entero
- Pros: idéntico visualmente al de macros.
- Cons: está pensado para nombre + icono de macro, espera su propio marco de bordes y modos, y no tiene sección de recientes.
- Rejected: reutilizamos el **proveedor de datos**, que es la parte que importa, con una rejilla propia.

### Lista de iconos fija en el addon
- Pros: sin dependencias.
- Cons: no es la lista de macros y se queda desactualizada con cada parche.
- Rejected.

## Consequences
- La UI depende de `Blizzard_Menu` y de `IconDataProviderMixin`, que son de Retail. Al portar a Forever (ADR-001) hay que comprobar que se cargan, y si no, dar implementaciones alternativas detrás de `UI.CreateDropdown` y `ns.IconPicker`.
- Si Blizzard cambia esas APIs, el cambio queda localizado en `UI/Common.lua` y `UI/IconPicker.lua`.
- La barra de la rejilla de iconos es un `Slider` hecho a mano, sin plantilla de scroll de Blizzard; si se ve mal en juego, se puede cambiar sin tocar el resto.
