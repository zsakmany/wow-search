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
-- a show action, so that Enter never makes the character do something.
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
