-- The Clock port: the current time, so that picks can fade with age (see
-- Picks.lua). The WoW clock adapter plugs in when the addon loads; tests
-- plug in a fake clock that they move on.
--
-- A clock adapter is a table with one method:
--   Now()  the current time in seconds, on a scale that stays the same
--          between game sessions (such as seconds since 1970)
local _, ns = ...

local adapter

function ns.SetClock(clock)
  adapter = clock
end

-- The current time in seconds. 0 when no adapter is plugged in.
function ns.Now()
  return adapter and adapter:Now() or 0
end
