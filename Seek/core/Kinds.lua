-- The kind registry: the kinds that Seek knows, and each kind's actions. An
-- entry must have one of these kinds, or Seek rejects it. Actions belong to
-- the kind, not to the source, so an entry gets its kind's actions (those
-- that it can do, see below), whatever source gave it.
--
-- Each kind has a label from the locale table and a list of actions. Each
-- action has:
--   id     a stable name; the action adapter runs the action by this id
--   label  the action's name, from the locale table
--   type   "show" (opens or highlights the thing; combat never blocks it)
--          or "use" (makes the character do the thing; in combat it is
--          blocked, see SearchSession.lua)
--   needs  (optional) the names of the entry facts that must be true for
--          the entry to have this action, such as "usable": only an item
--          that can be used gets "use"
-- An entry gets only those of its kind's actions that it can do. Its first
-- action is its main action, which Enter runs, when it is a show action;
-- Enter never makes the character do something; the use key runs the
-- entry's first use action instead. An entry with no show action has no
-- main action: Enter does nothing for it. An entry with no actions at all
-- is a faded result (see GLOSSARY.md). The action list shows all of the
-- entry's actions, in this order: the show actions first, then the use
-- actions.
local _, ns = ...

local L = ns.L

ns.kinds = {
  item = {
    label = L.KIND_ITEM,
    -- Only an item in the current character's bags can be shown or used;
    -- an item in another character's bags has no actions.
    actions = {
      { id = "showInBag", label = L.ACTION_SHOW_IN_BAG, type = "show", needs = { "inBags" } },
      { id = "useItem", label = L.ACTION_USE, type = "use", needs = { "inBags", "usable" } },
    },
  },
  spell = {
    label = L.KIND_SPELL,
    actions = {
      -- No show action: opening the spellbook from addon code taints it and
      -- can break casting and the action bars in combat (issue #29).
      { id = "castSpell", label = L.ACTION_CAST, type = "use" },
    },
  },
  quest = {
    label = L.KIND_QUEST,
    actions = {
      { id = "openQuestLog", label = L.ACTION_SHOW_IN_QUEST_LOG, type = "show" },
      { id = "showOnMap", label = L.ACTION_SHOW_ON_MAP, type = "show" },
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

-- Whether the entry has every fact that `action` needs.
local function CanDo(entry, action)
  for _, fact in ipairs(action.needs or {}) do
    if entry[fact] ~= true then
      return false
    end
  end
  return true
end

-- All actions of an entry, the main action first: what its action list
-- shows. An action is left out when the entry does not have a fact that it
-- needs.
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
