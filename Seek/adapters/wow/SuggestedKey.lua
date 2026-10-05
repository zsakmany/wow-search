-- The suggested key: on the first login, Seek binds Cmd+K (META-K) on a Mac
-- or Ctrl+K (CTRL-K) on Windows to the SEEK_TOGGLE binding (Bindings.xml),
-- and saves the bindings. Only when that key has no action and Seek has no
-- key yet, and only once: after that, the key is the player's, also when
-- they change or clear it in the Keybindings menu.
local _, ns = ...

local L = ns.L

local ACTION = "SEEK_TOGGLE"

-- Which binding sets Seek has already offered its key to. The account-wide
-- saved variable SeekSuggestedKey (see the TOC), not the per-character
-- saved copy: WoW keeps either one account binding set or, when the player
-- turns on character-specific key bindings, one set per character. The flag
-- must follow the binding set that Seek wrote to:
--   account = true      the account set; all characters that use it share it
--   characters[guid]    that character's own set
-- A per-character flag alone would set the key again in the account set on
-- each new character, after the player cleared it. An account flag alone
-- would never give a key to a character with its own set.
local function Offered()
  SeekSuggestedKey = SeekSuggestedKey or {}
  SeekSuggestedKey.characters = SeekSuggestedKey.characters or {}
  return SeekSuggestedKey
end

local function SuggestedKey()
  if IsMacClient() then
    return "META-K"
  end
  return "CTRL-K"
end

local function OfferKey()
  local offered = Offered()
  local character = UnitGUID("player")
  local characterSet = GetCurrentBindingSet() == Enum.BindingSet.Character
  local done
  if characterSet then
    done = offered.characters[character]
  else
    done = offered.account
  end

  if not done then
    local key = SuggestedKey()
    -- GetBindingAction gives "" for a key with no action. A player who
    -- already gave Seek a key keeps only that one.
    if not GetBindingKey(ACTION) and GetBindingAction(key) == "" and SetBinding(key, ACTION) then
      SaveBindings(GetCurrentBindingSet())
      print(L.SUGGESTED_KEY_SET:format(GetBindingText(key)))
    end
  end

  -- Mark this character too while it uses the account set: if the player
  -- later turns on character-specific key bindings, the game copies the
  -- account set (with or without Seek's key) into the new set, and Seek
  -- must not set its key there again.
  offered.characters[character] = true
  if not characterSet then
    offered.account = true
  end
end

-- Change bindings only when the game has loaded them. Before that, the
-- binding set can be empty: the key would look free, and SaveBindings could
-- write an empty set over the player's bindings. Blizzard waits for the
-- same three events before it changes bindings (Blizzard_RPE_TurnStrafe).
local waitingFor = {
  PLAYER_ENTERING_WORLD = true,
  VARIABLES_LOADED = true,
  BINDINGS_LOADED = true,
}

local events = CreateFrame("Frame")
for event in pairs(waitingFor) do
  events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(self, event)
  self:UnregisterEvent(event)
  waitingFor[event] = nil
  if next(waitingFor) then
    return
  end
  -- SetBinding and SaveBindings cannot be called in combat (for example,
  -- after logging in or /reload while in combat). Ask the lockdown itself,
  -- not the core's combat state, because the lockdown is what blocks them.
  if InCombatLockdown() then
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    return
  end
  OfferKey()
end)
