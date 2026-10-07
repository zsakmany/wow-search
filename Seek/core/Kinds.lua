-- The kind registry: the kinds that Seek knows, and each kind's actions. An
-- entry must have one of these kinds, or Seek rejects it. Actions belong to
-- the kind, not to the source, so an entry gets its kind's actions (those
-- that it can do, see below), whatever source gave it.
--
-- Each kind has a label from the locale table and a list of actions. A
-- kind can also have a prefix (see GLOSSARY.md): then its entries are found
-- only when the query starts with the prefix, and then no other kind's
-- entries are (SearchSession.lua). Its prefixHint is the text that the
-- search bar shows when the query is only the prefix and nothing of the
-- kind was picked yet. Each action has:
--   id     a stable name; the action adapter runs the action by this id
--   label  the action's name, from the locale table
--   type   "show" (opens or highlights the thing and changes nothing in
--          the game; combat never blocks it; the action adapter may run it
--          through a secure button, see Actions.lua) or "use" (changes
--          something in the game: the character does the thing, or the
--          thing changes, such as a quest's focus; in combat it is blocked,
--          see SearchSession.lua)
--   needs  (optional) the names of the entry facts that must be true for
--          the entry to have this action, such as "usable": only an item
--          that can be used gets "use"
--   lacks  (optional) the names of the entry facts that must not be true
--          for the entry to have this action. Two actions with the same
--          fact, one in `needs` and one in `lacks`, give an entry one of
--          the two, so the label follows the fact: "Focus" on a quest
--          without the focus, "Remove Focus" on the focused quest
--   cooldown (optional) true on a use action that the game can put on a
--          cooldown (see GLOSSARY.md): using an item, casting a spell. A
--          result whose first use action has it may show its cooldown; the
--          search bar window reads the cooldown live
--          (adapters/wow/Cooldowns.lua)
-- An entry gets only those of its kind's actions that it can do. Its first
-- action is its main action, which Enter runs, when it is a show action;
-- Enter never changes anything in the game; the use key runs the entry's
-- first use action instead. An entry with no show action has no main
-- action: Enter does nothing for it. An entry with no actions at all is a
-- faded result (see GLOSSARY.md). The action list shows all of the
-- entry's actions, in this order: the show actions first, then the use
-- actions; for a recently picked thing, SearchSession.lua adds the forget
-- action last, which belongs to no kind.
local _, ns = ...

local L = ns.L

ns.kinds = {
  item = {
    label = L.KIND_ITEM,
    -- Only an item in the current character's bags can be shown or used;
    -- an item in another character's bags has no actions.
    actions = {
      { id = "showInBag", label = L.ACTION_SHOW_IN_BAG, type = "show", needs = { "inBags" } },
      { id = "useItem", label = L.ACTION_USE, type = "use", needs = { "inBags", "usable" }, cooldown = true },
    },
  },
  spell = {
    label = L.KIND_SPELL,
    actions = {
      -- No show action: opening the spellbook from addon code taints it and
      -- can break casting and the action bars in combat (issue #29).
      { id = "castSpell", label = L.ACTION_CAST, type = "use", cooldown = true },
    },
  },
  quest = {
    label = L.KIND_QUEST,
    actions = {
      { id = "showOnMap", label = L.ACTION_SHOW_ON_MAP, type = "show" },
      -- A quest gets one action of each pair, by its facts `focused` and
      -- `tracked`. Focus (or Remove Focus) is the first use action, so the
      -- use key runs it.
      { id = "focusQuest", label = L.ACTION_FOCUS, type = "use", lacks = { "focused" } },
      { id = "removeFocus", label = L.ACTION_REMOVE_FOCUS, type = "use", needs = { "focused" } },
      { id = "trackQuest", label = L.ACTION_TRACK, type = "use", lacks = { "tracked" } },
      { id = "untrackQuest", label = L.ACTION_UNTRACK, type = "use", needs = { "tracked" } },
    },
  },
  -- A game option or a game option page (see GLOSSARY.md): both have this
  -- kind. Opening the Options window from addon code is blocked in combat;
  -- then the action does nothing (issue #28).
  gameOption = {
    label = L.KIND_GAME_OPTION,
    prefix = ">",
    prefixHint = L.PREFIX_HINT_GAME_OPTION,
    actions = {
      { id = "openInOptionsWindow", label = L.ACTION_OPEN_IN_OPTIONS_WINDOW, type = "show" },
    },
  },
  -- A talent (see GLOSSARY.md). Its row's kind text shows its points. No
  -- use action: Seek never spends points or changes talents. The WoW action
  -- adapter opens the talent window through a secure button, from the
  -- player's key press (NeedsSecureButton in Actions.lua); in combat no key
  -- press reaches that button, and then the action does nothing.
  talent = {
    label = L.KIND_TALENT,
    actions = {
      { id = "showInTalents", label = L.ACTION_SHOW_IN_TALENTS, type = "show" },
    },
  },
}

-- Check the rules above when the addon loads, so a wrong kind fails at once.
for name, kind in pairs(ns.kinds) do
  if #kind.actions == 0 then
    error("Seek: the kind " .. name .. " has no actions")
  end
  for i = 2, #kind.actions do
    if kind.actions[i].type == "show" and kind.actions[i - 1].type == "use" then
      error("Seek: the kind " .. name .. " has a show action after a use action")
    end
  end
end

-- Whether the entry has every fact that `action` needs, and none that it
-- lacks.
local function CanDo(entry, action)
  for _, fact in ipairs(action.needs or {}) do
    if entry[fact] ~= true then
      return false
    end
  end
  for _, fact in ipairs(action.lacks or {}) do
    if entry[fact] == true then
      return false
    end
  end
  return true
end

-- All of an entry's kind's actions, the main action first: what its
-- action list shows, besides the forget action. An action is left out when
-- the entry does not have a fact that it needs.
function ns.EntryActions(entry)
  local actions = {}
  for _, action in ipairs(ns.kinds[entry.kind].actions) do
    if CanDo(entry, action) then
      actions[#actions + 1] = action
    end
  end
  return actions
end

-- Whether the entry has any actions. An entry with none is a faded result
-- (see GLOSSARY.md).
function ns.HasActions(entry)
  return #ns.EntryActions(entry) > 0
end

-- The entry's main action: its first action, when that is a show action.
-- Nil when the entry has no show action.
function ns.MainAction(entry)
  local first = ns.EntryActions(entry)[1]
  if first and first.type == "show" then
    return first
  end
end

-- The entry's first use action: what the use key runs. Nil when the entry
-- has no use action.
function ns.FirstUseAction(entry)
  for _, action in ipairs(ns.EntryActions(entry)) do
    if action.type == "use" then
      return action
    end
  end
end
