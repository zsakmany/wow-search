-- All of Seek's own text that the player sees. English only in version 1;
-- other languages can be added here later.
local _, ns = ...

ns.L = {
  -- The search bar's title, and the header in the game's Keybindings menu
  NAME = "Seek",

  -- The search bar's text box while the query is empty
  HINT = "Search bags, spells, quests…",

  -- The search bar's text when the query matches nothing
  NO_RESULTS = "No results",

  -- The kind shown on each result row
  KIND_ITEM = "Item",
  KIND_SPELL = "Spell",
  KIND_QUEST = "Quest",

  -- The actions' names, as the action list shows them
  ACTION_SHOW_IN_BAG = "Show in bag",
  ACTION_SHOW_IN_SPELLBOOK = "Show in spellbook",
  ACTION_SHOW_IN_QUEST_LOG = "Show in quest log",
  ACTION_SHOW_ON_MAP = "Show on map",

  -- The key binding in the game's Keybindings menu
  BINDING_TOGGLE = "Open or close the search bar",

  -- In chat, once, after Seek has set its suggested key; %s is the key
  SUGGESTED_KEY_SET = "Seek: press %s to open the search bar. You can change the key in the Keybindings menu.",
}
