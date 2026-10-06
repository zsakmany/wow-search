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
  KIND_GAME_OPTION = "Game option",

  -- The kind shown on the row of another character's result: the kind, and
  -- the owner's name (with the realm when it is not the current
  -- character's), such as "Item · Bob" or "Item · Bob-Stormrage"
  KIND_WITH_OWNER = "%s · %s",

  -- The name on the row of a game option: its name, and the game option
  -- page that holds it, such as "Auto Loot · Controls"
  NAME_WITH_PAGE = "%s · %s",

  -- The actions' names, as the action list shows them
  ACTION_SHOW_IN_BAG = "Show in bag",
  ACTION_SHOW_IN_QUEST_LOG = "Show in quest log",
  ACTION_SHOW_ON_MAP = "Show on map",
  ACTION_OPEN_IN_OPTIONS_WINDOW = "Open in the Options window",
  ACTION_USE = "Use",
  ACTION_CAST = "Cast",

  -- The sign on a use action in the action list while the player is in
  -- combat, when WoW does not let Seek run it, and on the selected result
  -- after the player pressed the use key there in combat
  BLOCKED_IN_COMBAT = "Blocked in combat",

  -- The use key, as the action list shows it next to the first use action:
  -- on a Mac, and on Windows
  USE_KEY_MAC = "Cmd+Enter",
  USE_KEY_WINDOWS = "Ctrl+Enter",

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
  SETTING_OTHER_CHARACTERS_BAGS = "Show other characters' bags",
  SETTING_OTHER_CHARACTERS_BAGS_TOOLTIP = "Search also finds the items in the bags of your other characters "
    .. "on this account, faded, with the character's name. A character's bags show after it has logged in "
    .. "once with Seek.",
  SETTING_MINIMAP_ICON = "Show minimap icon",
  SETTING_MINIMAP_ICON_TOOLTIP = "Shows Seek's magnifying glass at the edge of the minimap. A left click "
    .. "on it opens or closes the search bar, and a right click opens these settings. Drag it to move it "
    .. "along the edge.",

  -- The hover text of the minimap icon, under its title (NAME)
  HOVER_TEXT_LEFT_CLICK = "Left click: open or close the search bar",
  HOVER_TEXT_RIGHT_CLICK = "Right click: settings",

  -- In chat, once, after Seek has set its suggested key; %s is the key
  SUGGESTED_KEY_SET = "Seek: press %s to open the search bar. You can change the key in the Keybindings menu.",
}
