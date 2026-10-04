-- The WoW combat state adapter (core/Combat.lua). PLAYER_REGEN_DISABLED
-- comes as combat starts and PLAYER_REGEN_ENABLED as it ends. The adapter
-- keeps its own flag from these events instead of asking InCombatLockdown()
-- each time: around the events, the lockdown can start later and end
-- earlier than the events say, and the core must see the same state as the
-- notices it gets.
local _, ns = ...

-- After a /reload in combat, the player is in combat when Seek loads.
local inCombat = InCombatLockdown()

ns.SetCombatState({
  IsInCombat = function()
    return inCombat
  end,
})

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    ns.CombatStarted()
  else
    inCombat = false
    ns.CombatEnded()
  end
end)
