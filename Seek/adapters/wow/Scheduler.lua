-- The WoW scheduler adapter (core/Scheduler.lua): runs the core's work in
-- steps on each frame, until the frame's small time budget is used up, so
-- that reading sources never freezes the game.
local _, ns = ...

-- Milliseconds of work per frame. A frame at 60 frames per second has
-- about 16.
local BUDGET_MS = 3

local queue = {} -- work in the order it came; each is a step function

local frame = CreateFrame("Frame")
frame:Hide()
frame:SetScript("OnUpdate", function(self)
  local start = debugprofilestop()
  -- At least one step each frame, so that the work always moves on.
  repeat
    local step = queue[1]
    -- A step that fails (for example, another addon's source) shows its
    -- error and is dropped, so that it does not stop the other work.
    local ok, more = xpcall(step, geterrorhandler())
    if not ok or not more then
      table.remove(queue, 1)
    end
  until not queue[1] or debugprofilestop() - start >= BUDGET_MS
  if not queue[1] then
    self:Hide()
  end
end)

ns.SetScheduler({
  Run = function(_, step)
    queue[#queue + 1] = step
    frame:Show()
  end,
})
