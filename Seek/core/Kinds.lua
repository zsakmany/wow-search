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
--          or "use" (makes the character do the thing; combat can block it)
-- The first action is the kind's main action, which Enter runs. It must be
-- a show action, so that Enter never makes the character do something. The
-- action list shows all of them, in this order.
local _, ns = ...

local L = ns.L

ns.kinds = {
  item = {
    label = L.KIND_ITEM,
    actions = {
      { id = "showInBag", label = L.ACTION_SHOW_IN_BAG, type = "show" },
    },
  },
  spell = {
    label = L.KIND_SPELL,
    actions = {
      { id = "showInSpellbook", label = L.ACTION_SHOW_IN_SPELLBOOK, type = "show" },
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
  local main = kind.actions[1]
  if not main or main.type ~= "show" then
    error("Seek: the main action of the kind " .. name .. " must be a show action")
  end
end

-- The main action of an entry's kind.
function ns.MainAction(entry)
  return ns.kinds[entry.kind].actions[1]
end

-- All actions of an entry, the main action first: what its action list
-- shows. Today every entry of a kind has all of the kind's actions; an
-- action that depends on the entry (such as "use" only on a usable item)
-- is left out here.
function ns.EntryActions(entry)
  return ns.kinds[entry.kind].actions
end
