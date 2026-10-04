-- The Scheduler port: runs work in small steps over several frames, so that
-- Seek never freezes the game. The WoW scheduler adapter plugs in when the
-- addon loads; tests plug in a fake that the test runs step by step.
--
-- A scheduler adapter is a table with one method:
--   Run(step)  calls step() again and again, a few times per frame, until it
--              returns false (the work is done). Work runs in the order it
--              came: the next work starts when the one before is done.
local _, ns = ...

local adapter

function ns.SetScheduler(scheduler)
  adapter = scheduler
end

-- Runs `step` until it returns false: through the scheduler adapter, or at
-- once when no adapter is plugged in.
function ns.Schedule(step)
  if adapter then
    adapter:Run(step)
  else
    while step() do
    end
  end
end
