-- The Actions port: the core asks the action adapter to run an action for an
-- entry. The WoW action adapter plugs in when the addon loads; tests plug in
-- a fake.
--
-- An action adapter is a table with these methods:
--   Run(actionID, entry)      runs the action with this id (see Kinds.lua)
--                             for the entry, which has name, kind, icon,
--                             gameID, owner, and page, as the source gave
--                             them
--   Prepare(key, actionID, entry)
--                             (optional) gets ready the action that the
--                             player's next press of `key` would run, or
--                             none when actionID is nil. `key` is "ENTER"
--                             or "USE" (the use key), as in
--                             SearchSession:PressKey. Some actions run
--                             only from a real key press on a secure button
--                             that was set up before the press, outside
--                             combat: WoW runs using an item and casting a
--                             spell only so, and the adapter runs the show
--                             actions that NeedsSecureButton names so,
--                             since opening some game windows from addon
--                             code taints them. The core calls it each
--                             time a key's action changes, for every use
--                             action and for the show actions that
--                             NeedsSecureButton names, and never in combat:
--                             WoW lets no addon set up a secure button
--                             then.
--   NeedsSecureButton(actionID)
--                             (optional) true for a show action that the
--                             adapter runs only from a key press on a
--                             secure button, so the core prepares it like a
--                             use action. It still changes nothing in the
--                             game, and combat never blocks it. The core
--                             asks only about show actions.
local _, ns = ...

local adapter
-- The action and entry of the last Prepare call for each key ("ENTER",
-- "USE"); none for a key with no Prepare call yet, or with none prepared.
local prepared = {}

function ns.SetActionAdapter(actionAdapter)
  adapter = actionAdapter
  prepared = {}
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

-- Whether the action adapter runs the show action `action` only from a key
-- press on a secure button (see NeedsSecureButton above).
function ns.NeedsSecureButton(action)
  return adapter ~= nil and adapter.NeedsSecureButton ~= nil and adapter:NeedsSecureButton(action.id) == true
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

-- Tells the action adapter which action the next press of `key` ("ENTER" or
-- "USE") would run: `action` for `entry`, or none when `action` is nil.
-- Calls the adapter only when this changes.
function ns.PrepareAction(key, action, entry)
  local wanted = action and { action = action, entry = entry } or nil
  if SamePrepared(prepared[key], wanted) then
    return
  end
  prepared[key] = wanted
  if adapter and adapter.Prepare then
    if action then
      adapter:Prepare(key, action.id, AdapterEntry(entry))
    else
      adapter:Prepare(key, nil, nil)
    end
  end
end
