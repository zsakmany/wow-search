-- The Actions port: the core asks the action adapter to run an action for an
-- entry. The WoW action adapter plugs in when the addon loads; tests plug in
-- a fake.
--
-- An action adapter is a table with these methods:
--   Run(actionID, entry)      runs the action with this id (see Kinds.lua)
--                             for the entry, which has name, kind, icon,
--                             gameID, owner, and page, as the source gave
--                             them
--   Prepare(actionID, entry)  (optional) gets ready the use action that the
--                             player's next key press would run, or none
--                             when actionID is nil. WoW runs some use
--                             actions (using an item, casting a spell)
--                             only from a real key press on a secure button
--                             that was set up before the press, outside
--                             combat. The core calls it each time that use
--                             action changes, for every use action, and
--                             never with a use action that combat blocks.
local _, ns = ...

local adapter
local prepared -- the action and entry of the last Prepare call, or nil

function ns.SetActionAdapter(actionAdapter)
  adapter = actionAdapter
  prepared = nil
end

-- The copy of the entry that the action adapter gets.
local function AdapterEntry(entry)
  return {
    name = entry.name,
    kind = entry.kind,
    icon = entry.icon,
    gameID = entry.gameID,
    owner = entry.owner,
    page = entry.page,
  }
end

-- Asks the action adapter to run `action` for `entry`. Does nothing when no
-- adapter is plugged in.
function ns.RunAction(action, entry)
  if adapter then
    adapter:Run(action.id, AdapterEntry(entry))
  end
end

-- Whether two Prepare calls are for the same action and the same thing. A
-- source that is read again gives new entry tables.
local function SamePrepared(a, b)
  if a == nil or b == nil then
    return a == b
  end
  local x, y = a.entry, b.entry
  return a.action == b.action and x.kind == y.kind and x.gameID == y.gameID
    and x.owner == y.owner
end

-- Tells the action adapter which use action the next key press would run:
-- `action` for `entry`, or none when `action` is nil. Calls the adapter only
-- when this changes.
function ns.PrepareAction(action, entry)
  local wanted = action and { action = action, entry = entry } or nil
  if SamePrepared(prepared, wanted) then
    return
  end
  prepared = wanted
  if adapter and adapter.Prepare then
    if action then
      adapter:Prepare(action.id, AdapterEntry(entry))
    else
      adapter:Prepare(nil, nil)
    end
  end
end
