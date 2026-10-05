-- The WoW clock adapter (core/Clock.lua). It uses GetServerTime(): the
-- realm's time, in seconds since 1970. Picks are saved between game
-- sessions, so their times must stay on one scale: GetTime() starts again
-- with each client start, and time() follows the computer's own clock,
-- which can be wrong or change (another time zone, a fixed clock), and
-- would then fade or drop picks too early or too late.
local _, ns = ...

ns.SetClock({
  Now = function()
    return GetServerTime()
  end,
})
