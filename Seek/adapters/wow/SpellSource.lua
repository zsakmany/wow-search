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
-- changing form); Seek reads the spellbook once for all of these notices.
-- Seek decides when to read: in combat, it waits for the end (ADR 0002).
local events = CreateFrame("Frame")
events:RegisterEvent("SPELLS_CHANGED")
events:SetScript("OnEvent", function()
  Seek.NotifyChanged(SOURCE_ID)
end)
