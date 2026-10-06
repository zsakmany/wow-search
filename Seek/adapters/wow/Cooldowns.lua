-- Cooldowns (see GLOSSARY.md), read live from the game for the search bar's
-- result rows (adapters/wow/SearchBar.lua shows them). The core only tells
-- the window which rows may show one, and for what: the result's first use
-- action and the thing's game ID (core/SearchSession.lua). A cooldown
-- changes every second and must be read in combat too, so it never goes
-- into an entry, the saved copy, or a source read (docs/adr/0002), and only
-- the adapters call the game for it (docs/adr/0003).
--
-- Secret values: in combat (and in encounters, Mythic+, and PvP), the game
-- can hide a spell's cooldown from addons. C_Spell.GetSpellCooldown then
-- gives a secret startTime and duration, which addon code cannot compare or
-- do arithmetic with, and which Cooldown:SetCooldown does not take from
-- addon code. Its isActive and isOnGCD flags are never secret. So Seek reads
-- a spell's time only as a duration object (C_Spell.GetSpellCooldownDuration),
-- which the Cooldown frame and the seconds formatter take as it is, secret
-- or not, and never looks at the times in it. Some spells are never or
-- always secret, whatever the restrictions, so nothing here assumes either.
-- An item's cooldown (C_Container.GetItemCooldown) is never secret.
local _, ns = ...

-- The longest global cooldown, in seconds: the short pause after a spell or
-- an item, which never shows.
local GLOBAL_COOLDOWN_MAX = 1.5

local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = 60 * SECONDS_PER_MINUTE
local SECONDS_PER_DAY = 24 * SECONDS_PER_HOUR

-- The time left, in the game's own short format (SecondsToTimeAbbrev): one
-- unit with a one-letter abbreviation, rounded up, such as "12 m" or
-- "45 s"; each unit is kept up to 1.5 times its range, so 90 seconds show
-- as "90 s". The same set-up as the game's aura duration formatter
-- (Blizzard_AuraContainerShared.lua). A seconds formatter takes a secret
-- duration and gives a secret text, which a font string can show.
local formatter = C_StringUtil.CreateSecondsFormatter()
do
  local Interval = Enum.SecondsFormatterInterval
  -- Points promote on exact matches, so each is one second later, to keep
  -- the band's last whole second in that band.
  local maxInterval = C_CurveUtil.CreateCurve()
  maxInterval:SetType(Enum.LuaCurveType.Step)
  maxInterval:AddPoint(0, Interval.Seconds)
  maxInterval:AddPoint(1 + 1.5 * SECONDS_PER_MINUTE, Interval.Minutes)
  maxInterval:AddPoint(1 + 1.5 * SECONDS_PER_HOUR, Interval.Hours)
  maxInterval:AddPoint(1 + 1.5 * SECONDS_PER_DAY, Interval.Days)
  formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
  formatter:SetRounding(Enum.SecondsFormatterRounding.Truncate)
  formatter:SetCanRoundUpLastUnit(true)
  formatter:SetMinInterval(Interval.Seconds)
  formatter:SetMaxIntervalCurve(maxInterval)
  formatter:SetDesiredUnitCount(1)
end

-- A time text that is never secret and about as wide as the widest that the
-- formatter gives (two digits and the widest unit letter, "89 m"). The
-- search bar measures it in place of a secret time text, whose width it
-- cannot read (see KindWidth in SearchBar.lua).
ns.WIDE_COOLDOWN_TIME_TEXT = formatter:Format(89 * SECONDS_PER_MINUTE)

-- An item's running cooldown as a duration object, or nil when none runs.
-- The values are never secret; they are checked anyway, so that a secret
-- value would hide the cooldown instead of breaking the comparisons below.
-- An `enable` of 0 means that the cooldown is on hold (a potion's, until
-- combat ends): the bags show no sweep then either (CooldownFrame_Set).
local function ItemCooldown(itemID)
  local start, duration, enable = C_Container.GetItemCooldown(itemID)
  if start == nil or issecretvalue(start) or issecretvalue(duration) or issecretvalue(enable) then
    return nil
  end
  if not enable or enable == 0 or duration <= GLOBAL_COOLDOWN_MAX or start + duration <= GetTime() then
    return nil
  end
  local cooldown = C_DurationUtil.CreateDuration()
  cooldown:SetTimeFromStart(start, duration)
  return cooldown
end

-- Whether a spell with charges has a charge left. A spell with charges
-- shows its cooldown only when none is left: the recharge of one charge
-- while others are left is the charge cooldown, which Seek does not show.
-- The game's spell cooldown already runs only when no charge is left (the
-- action bars draw the two apart the same way, ActionButton_ApplyCooldown);
-- this checks the count too, when it is not secret (maxCharges never is).
local function HasChargeLeft(spellID)
  local charges = C_Spell.GetSpellCharges(spellID)
  if not charges or charges.maxCharges <= 1 or issecretvalue(charges.currentCharges) then
    return false
  end
  return charges.currentCharges > 0
end

-- A spell's running cooldown as a duration object, or nil when none runs.
-- The never-secret flags decide: isActive (false for a ready spell, and
-- for a cooldown on hold) and isOnGCD (true when only the global cooldown
-- runs); then the charges (see HasChargeLeft). The duration leaves the
-- global cooldown out (ignoreGCD). isOnGCD can be stale outside
-- SPELL_UPDATE_COOLDOWN; then a zero duration still tells that only the
-- global cooldown runs, when that is not secret.
local function SpellCooldown(spellID)
  local info = C_Spell.GetSpellCooldown(spellID)
  if not info or not info.isActive or info.isOnGCD or HasChargeLeft(spellID) then
    return nil
  end
  local cooldown = C_Spell.GetSpellCooldownDuration(spellID, true)
  if not cooldown then
    return nil
  end
  local isZero = cooldown:IsZero()
  if not issecretvalue(isZero) and isZero then
    return nil
  end
  return cooldown
end

-- How to read the cooldown of each use action that can have one (the
-- actions with `cooldown` in core/Kinds.lua), from the thing's game ID.
local readCooldown = {
  useItem = ItemCooldown,
  castSpell = SpellCooldown,
}

-- The running cooldown of a result row's thing, as a duration object, or
-- nil when none runs. `cooldown` is the row's `cooldown` from the view
-- state (core/SearchSession.lua). Works in combat. The duration object may
-- hold secret times: pass it on as it is, to Cooldown:
-- SetCooldownFromDurationObject and to ns.CooldownTimeText, and never read
-- its times.
function ns.ReadCooldown(cooldown)
  local read = readCooldown[cooldown.actionID]
  return read and read(cooldown.gameID)
end

-- The time left of a running cooldown (from ns.ReadCooldown), in the game's
-- short format. The text is secret when the cooldown is: show it with
-- FontString:SetText or SetFormattedText, which take a secret text, and do
-- nothing else with it.
function ns.CooldownTimeText(cooldown)
  return cooldown:FormatRemainingDuration(formatter)
end

-- Calls `onChange` whenever a cooldown may have started, ended, or ticked
-- down, while `parent` (the search bar) is shown: on SPELL_UPDATE_COOLDOWN
-- and BAG_UPDATE_COOLDOWN, which come for any cooldown, also one started
-- from the action bars, and once a second, so the time counts down. Both
-- stop while `parent` is hidden, so a closed search bar costs nothing. The
-- watcher is a plain child frame: it runs only while its parent is shown,
-- and works in combat.
function ns.WatchCooldowns(parent, onChange)
  local watcher = CreateFrame("Frame", nil, parent)
  local sinceTick = 0
  watcher:SetScript("OnShow", function(self)
    sinceTick = 0
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self:RegisterEvent("BAG_UPDATE_COOLDOWN")
  end)
  watcher:SetScript("OnHide", function(self)
    self:UnregisterAllEvents()
  end)
  -- The events' arguments (the spell) are not needed: every shown row reads
  -- its cooldown again.
  watcher:SetScript("OnEvent", function()
    onChange()
  end)
  watcher:SetScript("OnUpdate", function(_, elapsed)
    sinceTick = sinceTick + elapsed
    if sinceTick >= 1 then
      sinceTick = 0
      onChange()
    end
  end)
end
