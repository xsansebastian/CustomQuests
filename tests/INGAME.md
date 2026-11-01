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
| 17 | Templates → Add section → name it (Enter and the Accept button) | Empty section header appears with (0); an empty name shows an error | |
| 18 | Templates → Edit list → tick quests → Move to section → pick one / No section / New section | Ticked quests move; moving a chain quest moves the whole chain | |
| 19 | Right-click a section header in Templates | Menu: rename, move up, move down, export, delete; delete keeps the quests | |
| 20 | Editor → Section field → save | Quest (and its chain) land in that section; "New section..." works from there | |
| 21 | Fold sections in Templates, Active and the tracker, then `/reload` | Folds kept; Active/tracker folds are per character and independent | |
| 22 | Accept quests from two sections and some without section | Active and tracker group them, "Other quests" last; empty sections hidden | |
| 23 | Export a section, import it on another character / after deleting it | Section recreated by name; importing again reuses it (no duplicate) | |
| 24 | Import `tests/imports/08` to `11` (see README there) | Sections created as described; no Lua errors | |
| 25 | Narrowest Journal (drag the corner), edit-list mode | "Add section" button and the "Move to section" menu fit; headers stretch with the list | |
| 26 | Hold Shift over the tracker, drag the corner grip | Tracker gets wider/narrower (200-520) and taller/shorter; banner and section bars stretch, text rewraps; size kept after `/reload` | |
| 27 | Make the tracker shorter than its quests; mouse wheel over it; right-click the grip | Quests scroll; right-click returns to the fitting height; folding the tracker shrinks it to the banner | |

## Sharing (ADR-006)

Needs two accounts (or a friend) with the addon; some rows need a third player, a guild, another realm or faction, a Trial account and both clients. Open questions from `docs/research/quest-sharing-feasibility.md` are marked **Q**.

| # | Step | Expected | Result |
|---|---|---|---|
| S1 | A: right-click a template > Share with > My target (B targeted, same realm) | B: popup with A's name, title, "a quest", count and KB; A: "Offered ... Waiting" | |
| S1b | A: right-click an active quest > Share with... (and Shift+click it) | Same as S1; the quest comes from its template. No menu if the template was deleted | |
| S2 | B: Accept | B: "Shared by A", "Template imported"; A: "B received". Template identical to A's (compare Export texts) | |
| S3 | Repeat S1-S2 after 30 s | B: "Already in your templates"; A: "B already had"; no second copy | |
| S4 | Share a chain of 3+ quests and a section with long texts (several fragments) | Imported whole, links and section rebuilt | |
| S5 | B: Decline; then Block on the next offer (after 30 s) | A: "B declined"; after Block A's offers never pop up on B, A gets nothing; Options shows "Unblock all (1)" and clears it | |
| S6 | Put A on B's game ignore list, offer again | No popup | |
| S7 | B Options: "Friends, guild and group" (default); A is a stranger, not grouped, whispers an offer | No popup; with "Anyone" it pops up; with "Nobody" never | |
| S8 | A sends two offers within 30 s; three other players offer at once | Second offer from A dropped; at most 3 waiting, one popup at a time; next shows after answering | |
| S9 | Group of 3: A > Share with > My group | B and C get popups (A doesn't); each accepts on their own and imports | |
| S10 | Guild: A > Share with > My guild | Guild members with the addon get popups | |
| S11 | B in combat when the offer arrives | Popup appears after leaving combat | |
| S12 | Popup left alone for 60 s | Closes; nothing imported, A gets no answer | |
| S13 | `/cq share`, `/cq share Name`, `/cq share group`, `/cq share guild` with a template selected; and with none | Same as the menu; without a selection a hint | |
| S14 | Offer to an offline / misspelled player | "wasn't sent: ... offline or out of reach" | |
| S15 | Link in chat (and Shift+click a template) in party, guild and whisper | `[CustomQuests: Title]` inserted; B sees a blue clickable link, players without the addon plain text | |
| S15b | Link in chat in a whisper to yourself, and in party as the sender | The link shows coloured (light blue) on your own line too, as on the receiver; clicking your own link does nothing | |
| S16 | B clicks the link; again within 10 s; after 10 min | Offer popup from A (even with "Nobody"); "Wait a few seconds"; "no longer offers that quest" | |
| S17 | Chat text with a forged `[CustomQuests: x|Hitem...]` or colons in the label | Stays plain text | |
| S18 | Options: untick chat links | Markers stay plain text | |
| S19 | **Q1** Start an offer inside a normal/heroic dungeon out of combat, in a raid encounter and in M+ (Retail and Forever) | Note `SendAddonMessageLogged` results; during lockdown: "Sharing paused..." once, sent when it ends; no Lua error | |
| S20 | **Q2** Receive during a lockdown | Note whether `CHAT_MSG_ADDON_LOGGED` arrives, is queued, lost or secret (secret payloads must be ignored silently) | |
| S21 | **Q3** Whisper share to: a group member from a non-connected realm; an opposite-faction group member; an opposite-faction player outside the group | Note which work; failures show a clear message | |
| S22 | **Q4** Share a 16 KB section by whisper outside instances, uncompressed (receiver without `C_EncodingUtil`, or set a breakpoint) | Arrives whole; no disconnect; note time | |
| S23 | **Q5** Both clients with `C_EncodingUtil`: share the biggest chain; `/dump C_EncodingUtil ~= nil` on Forever | Arrives compressed (fewer messages) and identical; note time for 16 KB; Forever works or falls back to plain | |
| S24 | **Q7** Trial / Veteran account | Sending: "Trial and Veteran accounts can't send..."; receiving works with no Lua errors | |
| S25 | **Q8** Chat link in every chat frame, including the new 12.x chat, and after `/reload` | Link shown; click reaches the request | |
| S26 | Retail ↔ Forever | Not expected to work (different realms); no Lua errors | |
