-- The kind registry: the kinds that Seek knows, and each kind's actions. An
-- entry must have one of these kinds, or Seek rejects it. Actions belong to
-- the kind, not to the source, so every entry of a kind gets the same
-- actions, whatever source gave it.
--
-- Each kind has a label from the locale table and a list of actions. Each
-- action has:
--   id     a stable name; the action adapter runs the action by this id
--   label  the action's name, from the locale table
--   type   "show" (opens or highlights the thing; combat never blocks it)
--          or "use" (makes the character do the thing; in combat it is
--          blocked, see SearchSession.lua)
--   needs  (optional) the name of an entry fact that must be true for the
--          entry to have this action, such as "usable": only an item that
--          can be used gets "use"
-- The first action is the kind's main action, which Enter runs, when it is
-- a show action; Enter never makes the character do something. A kind with
-- no show action has no main action: Enter does nothing for it. The action
-- list shows all of the actions, in this order: the show actions first,
-- then the use actions.
local _, ns = ...

local L = ns.L

ns.kinds = {
  item = {
    label = L.KIND_ITEM,
    actions = {
      { id = "showInBag", label = L.ACTION_SHOW_IN_BAG, type = "show" },
      { id = "useItem", label = L.ACTION_USE, type = "use", needs = "usable" },
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

-- The main action of an entry's kind, or nil when the kind has no show
-- action.
function ns.MainAction(entry)
  local first = ns.kinds[entry.kind].actions[1]
  if first.type == "show" then
    return first
  end
end

-- All actions of an entry, the main action first: what its action list
-- shows. An action that needs an entry fact is left out when the entry does
-- not have it.
function ns.EntryActions(entry)
  local actions = {}
  for _, action in ipairs(ns.kinds[entry.kind].actions) do
    if not action.needs or entry[action.needs] == true then
      actions[#actions + 1] = action
    end
  end
  return actions
end
