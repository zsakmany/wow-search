-- The Combat state port: whether the player is in combat, and notices when
-- combat starts and ends. The WoW combat state adapter plugs in when the
-- addon loads; tests plug in a fake.
--
-- A combat state adapter is a table with one method:
--   IsInCombat()  true while the player is in combat
-- It also tells the core when combat starts and ends, by calling
-- ns.CombatStarted() and ns.CombatEnded().
--
-- Any part of the core can ask ns.InCombat(), or watch combat start and end
-- with ns.WatchCombat(). The sources use it to read the game only outside
-- combat (ADR 0002).
local _, ns = ...

local adapter
local watchers = {}

function ns.SetCombatState(combatState)
  adapter = combatState
end

-- Whether the player is in combat. False when no adapter is plugged in.
function ns.InCombat()
  return adapter ~= nil and adapter:IsInCombat() == true
end

-- Calls `watcher(inCombat)` each time combat starts (true) or ends (false).
function ns.WatchCombat(watcher)
  watchers[#watchers + 1] = watcher
end

local function Tell(inCombat)
  for _, watcher in ipairs(watchers) do
    watcher(inCombat)
  end
end

-- The combat state adapter calls these.
function ns.CombatStarted()
  Tell(true)
end

function ns.CombatEnded()
  Tell(false)
end
