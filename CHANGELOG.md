# Changelog

## Unreleased

- Tracker: left-click a quest title to open the Journal on that quest.
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
