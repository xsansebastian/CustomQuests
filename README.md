# CustomQuests

Create your own quests for roleplay and personal goals, with auto-tracking and reusable templates.
Targets: **Retail** (interface 120105) and **Forever** (interface 16001), one package for both (single TOC listing both interfaces, client detected by build number): `python tools/build.py`. Forever is untested in game until verified there (see `SPEC.md`).

## Usage

- `/cq` opens the journal (Active, Templates, History). `/cq tracker` toggles the tracker.
- Objective types: item (bag count), kill (NPC and/or map), boss (encounter), zone, location, manual.
- Templates repeat one-time, daily or weekly. Export/Import shares them as `CQ1:` text.

## Layout

| File | Role |
|---|---|
| `Compat/Common.lua` | The only file that calls client APIs (`ns.api`). |
| `tools/build.py`, `.pkgmeta` | Build `dist/CustomQuests-<version>.zip`, the one package for both clients. |
| `Util.lua`, `Model.lua` | Helpers, schema, validation, SavedVariables. |
| `Serializer.lua` | `CQ1:` export/import; never executes imported text. |
| `Objectives.lua`, `Lifecycle.lua` | Progress engine, stages, resets, history. |
| `Core.lua` | Events and slash commands. |
| `UI/` | Tracker, journal, editor, dialogs. |
| `tests/run.lua` | Offline tests: `luajit tests/run.lua` from this folder (LuaJIT = Lua 5.1 semantics). |
| `tests/INGAME.md` | Manual checklist for the game client. |
| `docs/decisions/` | Architecture decision records (why things are built this way). |
