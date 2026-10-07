# Seek

Seek (work title) is a World of Warcraft addon that opens a search bar on a hotkey and finds the player's own things (bag items, spells, quests, and more) as they type.

## Language

**Search bar**:
The box that opens on the hotkey, where the player types and sees results.
_Avoid_: Launcher, palette, spotlight, search window

**Query**:
The text the player types into the search bar.
_Avoid_: Search term, input, filter

**Prefix**:
A character at the very start of the query that makes the search find only one kind: ">" finds only game options. That kind's entries are never found without it.
_Avoid_: Mode, scope, filter, command mode

**Source**:
One kind of searchable thing, such as bag items, spells, or quests.
_Avoid_: Provider, category, module, sub-plugin

**Data pack**:
A separate, optional addon that supplies a source with offline game data, such as every item in the game. Anyone can publish one.
_Avoid_: Sub-plugin, database, extension

**Entry**:
One searchable thing that a source supplies, such as one item or one quest.
_Avoid_: Record, document, item (item means a WoW item)

**Tooltip**:
The game's own info box for a thing, which the search bar shows beside the selected result. Not the same as long text, even when an item's long text comes from its tooltip, and not the same as hover text.
_Avoid_: Preview, popup, card

**Hover text**:
Seek's own short help text that shows while the mouse is on one of Seek's controls, such as the minimap icon. It tells what the clicks do; it is never a tooltip.
_Avoid_: Tooltip (for this), hint, help popup

**Item count**:
How many of an item its owner has in the backpack, the equipped bags, and the keyring, all stacks together. An item result shows it after the name, only when it is more than 1. Another character's item count is the one from the last time that character was played.
_Avoid_: Stack, stack size, quantity, amount

**Long text**:
An entry's optional longer text, besides its name: an item's tooltip text, a spell's description, or a quest's description and objectives. The query matches it only at word starts, never fuzzy, and a name match always ranks above a long text match.
_Avoid_: Description, body, tooltip (for the general idea)

**Saved copy**:
The entries that Seek keeps per character between game sessions. Search uses it right after a reload and in combat, until Seek reads the sources again outside combat.
_Avoid_: Cache, database, snapshot

**Kind**:
What sort of game thing an entry is, such as item, spell, or quest. Show actions and use actions belong to the kind, whatever the entry's source; an entry gets only those of its kind's actions that it can do (only a usable item gets the use action).
_Avoid_: Type, category

**Cooldown**:
The time until the character can use a thing again, such as a Hearthstone or a spell, after using it. A result with a use action shows its cooldown only while it runs; a ready thing shows nothing. A cooldown never changes a result's look or rank, and the game, not Seek, refuses a use action while it runs.
_Avoid_: Timer, recharge, lockout

**Talent**:
One talent in the talent trees of the character's class, for the spec group that the character uses now. Every talent of those trees belongs to the character, whether it has points in it or not. A talent result shows its points, as spent and possible points.
_Avoid_: Trait, node, perk

**Owner**:
The character that has an entry's thing, named as "Name-Realm". The owner can be another character of the player, for example for an item in another character's bags.
_Avoid_: Character (alone), alt, toon

**Hidden character**:
Another character of the player whose items the player chose not to show, for example after deleting or renaming it. Each other character is shown or hidden, as a setting; a character that Seek sees for the first time is shown. Seek keeps a hidden character's bags, so showing it again brings its items back.
_Avoid_: Removed character, forgotten character (forget is for picks), deleted character

**Result**:
An entry that matches the current query and is shown in the search bar. While the query is empty, the results are the recently picked things. A result with no actions is faded: the player can select it to see its tooltip, but cannot act on it or pick it.
_Avoid_: Hit, match, suggestion

**Pick**:
One time that the player ran an action on a result, which Seek remembers so it can rank that thing higher later. A blocked action is not a pick, and the forget action is never a pick. Seek keeps the picks per character, next to the saved copy. The button "Forget all picks" on Seek's settings page forgets all picks of the current character at once.
_Avoid_: History, usage, selection (selection is the highlighted row)

**Setting**:
A choice the player makes about how Seek behaves, such as the number of visible results. Each setting has a default that applies until the player changes it.
_Avoid_: Option, config, preference

**Game option**:
One option in the game's Options window, such as Auto Loot. Seek's own settings are on a page in that window too, so each of them also shows there as a game option; "setting" is still the word for the choice itself.
_Avoid_: Setting (for this), option (alone), CVar, preference

**Game option page**:
One page of the game's Options window, such as Audio, which holds game options. Its entries have the same kind as game options.
_Avoid_: Category, panel, tab, options page

**Action**:
Something the player can run on a result. Each action is a show action, a use action, or the forget action.
_Avoid_: Command, handler, activation

**Show action**:
An action that opens or highlights the thing, such as showing a quest on the map. It changes nothing in the game. Combat never blocks it.
_Avoid_: View, reveal, open

**Use action**:
An action that changes something in the game: the character does the thing, such as casting the spell or using the item, or the thing changes, such as a quest's focus or tracking. Combat can block it.
_Avoid_: Do, activate, execute, cast

**Forget action**:
The action that removes all picks of a recently picked thing, so the thing leaves the recently picked things and its picks no longer lift it. Only a result among the recently picked things has it, as the last action in its action list. It is never a pick and never the main action, combat never blocks it, and the search bar stays open after it.
_Avoid_: Remove, delete, clear, unpick

**Main action**:
The one action a result runs when the player presses Enter. It is always a show action; a result with no show action has no main action.
_Avoid_: Default action, primary action

**Use key**:
The key that runs the selected result's first use action without opening the action list: Cmd+Enter on a Mac, Ctrl+Enter on Windows. Combat blocks it, like every use action.
_Avoid_: Shortcut, hotkey, quick use

**Focus**:
The one quest that the game points the player to, with the arrow on the minimap. The player can focus a quest, which also tracks it, or remove the focus.
_Avoid_: Super track, waypoint, highlight

**Tracked quest**:
A quest that the game shows in its objective tracker. The player can track and untrack a quest.
_Avoid_: Watched quest, followed quest

**Minimap icon**:
Seek's own icon at the edge of the minimap, which opens the search bar. Not the addon button.
_Avoid_: Minimap button, launcher, LDB icon

**Addon button**:
The game's shared button at the minimap that lists the addons; Seek has an entry in it. Not the minimap icon.
_Avoid_: Addon compartment (outside code), minimap button

**Action list**:
The list of all of a result's actions, the main action first, which the player opens from the result.
_Avoid_: Context menu, secondary actions
