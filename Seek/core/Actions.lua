-- The Actions port: the core asks the action adapter to run an action for an
-- entry. The WoW action adapter plugs in when the addon loads; tests plug in
-- a fake.
--
-- An action adapter is a table with one method:
--   Run(actionID, entry)  runs the action with this id (see Kinds.lua) for
--                         the entry, which has name, kind, icon, gameID, and
--                         owner, as the source gave them
local _, ns = ...

local adapter

function ns.SetActionAdapter(actionAdapter)
  adapter = actionAdapter
end

-- Asks the action adapter to run `action` for `entry`. Does nothing when no
-- adapter is plugged in.
function ns.RunAction(action, entry)
  if adapter then
    adapter:Run(action.id, {
      name = entry.name,
      kind = entry.kind,
      icon = entry.icon,
      gameID = entry.gameID,
      owner = entry.owner,
    })
  end
end
