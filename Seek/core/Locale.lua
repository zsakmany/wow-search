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
  ACTION_SHOW_IN_QUEST_LOG = "Show in quest log",
  ACTION_SHOW_ON_MAP = "Show on map",
  ACTION_USE = "Use",
  ACTION_CAST = "Cast",

  -- The sign on a use action in the action list while the player is in
  -- combat, when WoW does not let Seek run it
  BLOCKED_IN_COMBAT = "Blocked in combat",

  -- The key binding in the game's Keybindings menu
  BINDING_TOGGLE = "Open or close the search bar",

  -- Seek's settings page in the game's Options window
  SETTING_CHARACTER_ONLY = "Use settings for this character only",
  SETTING_CHARACTER_ONLY_TOOLTIP = "This character gets its own Seek settings, which start from the "
    .. "account's settings. Turned off, the character uses the account's settings again, and its own "
    .. "settings are kept for later.",
  SETTING_VISIBLE_RESULTS = "Visible results",
  SETTING_VISIBLE_RESULTS_TOOLTIP = "How many results the search bar shows at once, and how many recently "
    .. "picked things it shows while the query is empty.",
  SETTING_TOOLTIP_SIDE = "Tooltip side",
  SETTING_TOOLTIP_SIDE_TOOLTIP = "Where the search bar shows the game's tooltip of the result under the "
    .. "mouse, or else of the selected result. On the right, the tooltip hides while the action list "
    .. "is open.",
  SETTING_TOOLTIP_SIDE_RIGHT = "Right",
  SETTING_TOOLTIP_SIDE_LEFT = "Left",
  SETTING_TOOLTIP_SIDE_OFF = "Off",

  -- In chat, once, after Seek has set its suggested key; %s is the key
  SUGGESTED_KEY_SET = "Seek: press %s to open the search bar. You can change the key in the Keybindings menu.",
}
