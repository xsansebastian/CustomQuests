# In-game acceptance checklist

Run with `/console scriptErrors 1`. Record client, build (`/dump select(4, GetBuildInfo())`), date and result per line.

## Retail

| # | Step | Expected | Result |
|---|---|---|---|
| 1 | Log in | Chat: "v0.2.0 loaded". No Lua errors | |
| 2 | `/cq` → New → title "Hierro", Item, shift-click an ore in bags, count 20 → Save | Template appears in Templates | |
| 3 | Accept | Tracker shows "Hierro: N/20" with the current bag count | |
| 4 | Loot / destroy ore | Counter goes up / down | |
| 5 | Kill: target an open-world NPC, Kill → Target → count 3 → accept, kill 3 | Counts, quest completes, history +1 | |
| 6 | **Kill in a dungeon**: Kill with this map + approximate checked, and Kill with only map ID | Both count trash kills, approximate icon shown. **Key unknown: does PARTY_KILL reach addons inside instances?** | |
| 7 | Boss: after a boss pull, Boss → Last boss → accept, kill it next run | Counts on ENCOUNTER_END success | |
| 8 | Zone: This map, accept in another zone, travel | Completes on entry (also from a sub-map) | |
| 9 | Location: My spot, walk away, accept, walk back | Completes within radius | |
| 10 | Manual: + in tracker (right-click −) and journal | Clamps 0..goal | |
| 11 | Multi-stage RP quest with giver/description/reward | Stages advance with chat message; journal shows texts | |
| 12 | Daily template: complete, `/cq reset` | Becomes active again from stage 1 | |
| 13 | Export → copy → Import on another character | Identical template | |
| 14 | Import garbage / truncated text | Red error message, no Lua error | |
| 15 | `/reload` and full client restart | Templates, active quests, history, tracker position kept | |
| 16 | Enter text with `|cff...` in title | Shown literally, not coloured | |
