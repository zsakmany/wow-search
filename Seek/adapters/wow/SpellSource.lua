-- Seek's spell source: one entry per spell that the character knows and can
-- cast, as the spellbook shows it. It registers through the public `Seek`
-- table, like any other addon's source.
--
-- Left out: spells not learned yet ("future" spells), passive spells, lower
-- ranks of a spell (the spellbook hides them too), spells of a specialization
-- that is not active, skill lines that the spellbook hides, and pet spells.

local SOURCE_ID = "Seek.Spells"

local PLAYER = Enum.SpellBookSpellBank.Player
local SPELL = Enum.SpellBookItemType.Spell

local noticeQueued = false
local changedInCombat = false

-- "Name-Realm" of the current character (the realm can be missing early in
-- the login).
local function CurrentCharacter()
  local name, realm = UnitFullName("player")
  if realm and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

local function GetEntries()
  local entries, seen = {}, {}
  local owner = CurrentCharacter()
  for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
    local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
    if lineInfo and not lineInfo.shouldHide and not lineInfo.offSpecID then
      local offset = lineInfo.itemIndexOffset
      for slot = offset + 1, offset + lineInfo.numSpellBookItems do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, PLAYER)
        -- The spell ID the player sees: the overriding spell, if any.
        local spellID = info and (info.spellID or info.actionID)
        if info and info.itemType == SPELL and not info.isPassive and not info.isOffSpec
            and not C_SpellBook.IsSpellBookItemLowRank(slot, PLAYER) and not seen[spellID] then
          seen[spellID] = true
          entries[#entries + 1] = {
            name = info.name,
            icon = info.iconID,
            kind = "spell",
            gameID = spellID,
            owner = owner,
          }
        end
      end
    end
  end
  return entries
end

Seek.RegisterSource({ id = SOURCE_ID, GetEntries = GetEntries })

-- SPELLS_CHANGED often comes several times in one frame (learning a spell,
-- changing form). Send one change notice on the next frame. In combat, wait
-- for its end: data read in combat can be hidden from addons (ADR 0002).
local function QueueNotice()
  if InCombatLockdown() then
    changedInCombat = true
  elseif not noticeQueued then
    noticeQueued = true
    C_Timer.After(0, function()
      noticeQueued = false
      Seek.NotifyChanged(SOURCE_ID)
    end)
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    if changedInCombat then
      changedInCombat = false
      QueueNotice()
    end
  else
    QueueNotice()
  end
end)
