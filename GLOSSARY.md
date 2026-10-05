# Seek

Seek (work title) is a World of Warcraft addon that opens a search bar on a hotkey and finds the player's own things (bag items, spells, quests, and more) as they type.

## Language

**Search bar**:
The box that opens on the hotkey, where the player types and sees results.
_Avoid_: Launcher, palette, spotlight, search window

**Query**:
The text the player types into the search bar.
_Avoid_: Search term, input, filter

**Source**:
One kind of searchable thing, such as bag items, spells, or quests.
_Avoid_: Provider, category, module, sub-plugin

**Data pack**:
A separate, optional addon that supplies a source with offline game data, such as every item in the game. Anyone can publish one.
_Avoid_: Sub-plugin, database, extension

**Entry**:
One searchable thing that a source supplies, such as one item or one quest.
_Avoid_: Record, document, item (item means a WoW item)

**Long text**:
An entry's optional longer text, besides its name: an item's tooltip text, a spell's description, or a quest's description and objectives. The query matches it only at word starts, never fuzzy, and a name match always ranks above a long text match.
_Avoid_: Description, body, tooltip (for the general idea)

**Saved copy**:
The entries that Seek keeps per character between game sessions. Search uses it right after a reload and in combat, until Seek reads the sources again outside combat.
_Avoid_: Cache, database, snapshot

**Kind**:
What sort of game thing an entry is, such as item, spell, or quest. Actions belong to the kind, so all entries of one kind have the same actions, whatever their source.
_Avoid_: Type, category

**Result**:
An entry that matches the current query and is shown in the search bar.
_Avoid_: Hit, match, suggestion

**Pick**:
One time that the player ran an action on a result, which Seek remembers so it can rank that thing higher later. A blocked action is not a pick.
_Avoid_: History, usage, selection (selection is the highlighted row)

**Action**:
What happens when the player picks a result. Each action is either a show action or a use action.
_Avoid_: Command, handler, activation

**Show action**:
An action that opens or highlights the thing, such as opening the quest log at a quest. Combat never blocks it.
_Avoid_: View, reveal, open

**Use action**:
An action that makes the character do the thing, such as casting the spell or using the item. Combat can block it.
_Avoid_: Do, activate, execute, cast

**Main action**:
The one action a result runs when the player presses Enter. It is always a show action; a result with no show action has no main action.
_Avoid_: Default action, primary action

**Action list**:
The list of all of a result's actions, the main action first, which the player opens from the result.
_Avoid_: Context menu, secondary actions
