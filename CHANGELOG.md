# Changelog

## Unreleased

- New objective type **Near NPC**: completes when you get close to an NPC (talking to it, its soft interaction target, or your target, mouseover or a visible nameplate within about 10 yards). Pick the NPC with **Target**. An optional **popup text** opens a window with the NPC's portrait, its name and the text (scrolls when long), with the quest title on its title bar; it opens once, when the objective completes. While the objective is pending, the NPC's tooltip shows the quest and the objective's text. Inside instances the game hides who an NPC is, so it can't count there.
- Location and Near NPC objectives have a **Shown text** field that replaces the default "Reach..." / "Approach...". The popup text has its own multi-line box in the editor.
- Objectives: at most 5 per stage (was 10); the objectives list of the editor scrolls. The example quests that went over it were split into stages.
- Completing the last objective of a quest no longer announces it twice.
- Journal: a checkbox next to the search box (Templates) hides the quests this character has already completed. Shift+click on an Active quest tracks or untracks it (with a chat box open it still links it).
- Tracker: Shift+click a quest title stops tracking it.
- Quest icons all fit the same square, keeping their proportions; before, some were stretched.
- Journal: a search box above the list (Templates, Active and History, each with its own text) filters as you type. Every word must appear in the title, the section name or a stage's text; folded sections and chains open while you search.
- Item tooltips: an item that an active quest asks for shows a line with the quest's title and how many you have of how many it needs (green when done).
- Tracker: left-click a quest title to open the Journal on that quest.
- Share quests in game: right-click a template, an active quest or a section header > **Share with...** your target, group, guild or any player by name (also `/cq share <player|group|guild>`). The receiver sees a popup with the sender, the title, how many quests and the size, and chooses Accept, Decline or Block; nothing is added without Accept. Received quests go through the same checks as a pasted import.
- Accepting a shared quest also starts it when it can start (first link of a chain, level fits, not already running); turn this off in Options > AddOns > CustomQuests.
- Chat links: **Link in chat** (or Shift+click a template or an active quest) types `[CustomQuests: Title]`; players with the addon can click it to ask you for the quest.
- Sharing safeguards: offers only from friends, guild and group by default (Options > AddOns > CustomQuests: anyone or nobody too), the game's ignore list and your own block list, one offer per sender every 30 seconds, at most 3 waiting, size caps on every transfer, no popups in combat. Offers made during raid encounters, Mythic+ or rated PvP wait until the chat restriction ends. Trial and Veteran accounts are told they can't send.
- Transfers are compressed when both players' clients support it, and work uncompressed otherwise.
- Importing a quest you already have no longer creates a second copy; the chat says it was already there. Imports stop at 1000 templates.
- Journal: when the window is made narrow, the buttons under a quest wrap onto a second row instead of spilling out of the window.

## 0.7.0

- Options: the name on the tracker's banner can be changed (default CustomQuests); leaving it empty restores the default.
- Tracker: hold Shift and a grip appears in its bottom-right corner; drag it to change the tracker's width (200 to 520) and height. When the quests don't fit, scroll with the mouse wheel. Right-click the grip to go back to a height that fits the quests. The size is remembered per character.
- Quest sections: group templates under sections you make up (a "Lost Isles" section, a "Daily routine" one...). In Templates, Edit list > "Move to" moves the ticked quests into a section or makes a new one; right-click a section header to rename, move, export or delete it; the quest editor has a Section field. The Journal (Active and Templates) and the tracker show the headers like the game's own "Quests" bar, with a fold button; folds are remembered per character. A chain always moves as a whole (moving one of its quests moves them all), and quests without a section go last under "Other quests". Deleting a section keeps its quests.
- Export/import carries the section by name: importing creates it, or reuses one with the same name. A section can also be exported whole.
- The Journal, the quest editor, the turn-in window and the import/export window can be resized by dragging their bottom-right corner; each remembers its size. In the Journal you can also drag the divider to make the quest list wider or narrower. In the editor the extra height goes to the description and the preview.
- Journal: more space between a quest's title and the line under it. Tracker: quest icons are as big as the game's own tracker icons.
- Templates list: the new Edit list button under the tree shows a checkbox on every row, and Delete (N) removes the ticked templates at once. When a deleted quest has quests after it in a chain you choose between deleting the whole branch or only the selected ones (the rest stay linked to the quest before). The Delete button in the detail asks the same.
- Chains are easier to build: in Templates, "Add next quest" creates the next quest already linked after the selected one. The editor field now reads "Unlocks after completing", the list of quests is a tree, and a line under it shows the whole chain path.
- Only the first quest of a chain can be accepted by hand. The others start on their own when the previous one is turned in; their Accept button is off and the list says so.
- A quest that belongs to a chain stays out of the tracker until the one before it has been turned in.
- Templates list: chains are now a tree. The first quest of a chain is its title, the rest hang below it (folding with the +/- button), and follow-ups of follow-ups nest further down.
- Quests now use the game's own quest icons instead of custom ones: campaign for chains, recurring for daily and weekly, and the plain side-quest icon for the rest, each with its in-progress and turn-in versions. The template icon picker is gone.
- New tracker appearance settings in Options > AddOns > CustomQuests (also `/cq options`): font (including SharedMedia fonts if installed) and text size, background color and opacity, border style and color, with a live preview and a reset button. The tracker also has a little more margin on the left, and a header banner like the game's own objective tracker, with a red button to fold it.

## 0.6.0

- New minimap button: left-click opens the journal, right-click shows/hides the tracker, Shift+drag moves it. `/cq minimap` hides or shows it.
- Tracker: quests and the tracker now fold with right-click only.
- Journal: simpler buttons. One swaps between Active and History, Templates has its own button, and inside Templates the swap becomes Back. New and Import only appear in Templates.
- Journal: removed the objective progress bars; counts stay in the text.
- Editor: new Help button on the Objectives tab explaining where IDs come from (Wowhead) and which buttons fill each field, plus hints on the ID boxes.
- Editor: shift-clicking an item now fills its ID on current clients.
- Spanish: the quest giver label now reads "NPC".

## 0.5.1

- Added German (deDE) and French (frFR) translations.
- Completed missing Spanish texts (durations, X/Y labels, kill objective names).

## 0.5.0

First public release, for Retail and Forever in a single package.

- Quest journal (Active, Templates, History) and tracker. Open with `/cq`.
- In-game quest editor with description, reward and completion texts, colour toolbar and live preview.
- Objectives: items, kills, bosses, zones, subzones, locations, levels and manual counters.
- Stages inside a quest and chains of separate quests.
- Quests wait for you to complete them: a yellow "?" opens the turn-in window with your own completion text.
- Yellow on-screen messages and a sound for progress, finished objectives, new stages and completed quests.
- Tracker: fold individual quests, Shift+drag to move it.
- One-time, daily and weekly quests, with history.
- Export and import quests and whole chains as `CQ1:` text.
- English and Spanish.
