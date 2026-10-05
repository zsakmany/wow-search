-- Seek's spell source: one entry per spell that the character knows and can
-- cast, as the spellbook shows it, with the spell's description as its long
-- text. It registers through the public `Seek` table, like any other addon's
-- source.
--
-- Left out: spells not learned yet ("future" spells), passive spells, lower
-- ranks of a spell (the spellbook hides them too), spells of a specialization
-- that is not active, skill lines that the spellbook hides, and pet spells.
local _, ns = ...

local SOURCE_ID = "Seek.Spells"

local PLAYER = Enum.SpellBookSpellBank.Player
local SPELL = Enum.SpellBookItemType.Spell

-- Spells whose description was empty at the last read (spell ID -> true).
-- The game may still be loading it.
local waiting = {}

-- The game has loaded a spell's data or text: if Seek waits for it, read the
-- spells again. (Many spells can load in one frame; Seek reads the spellbook
-- once for all of their notices.)
local function TextLoaded(spellID)
  if waiting[spellID] then
    waiting[spellID] = nil
    Seek.NotifyChanged(SOURCE_ID)
  end
end

-- The spell's description, or nil. The description is empty until the game
-- has loaded the spell's data; then wait for it, and read again when it
-- comes (SPELL_TEXT_UPDATE below, or the spell data load). Some spells have
-- no description at all; they wait for nothing more once their data is
-- loaded.
local function Description(spellID)
  local description = C_Spell.GetSpellDescription(spellID)
  if description and description ~= "" then
    waiting[spellID] = nil
    return ns.LongText({ description })
  end
  if not waiting[spellID] then
    waiting[spellID] = true
    local spell = Spell:CreateFromSpellID(spellID)
    if not spell:IsSpellDataCached() then
      spell:ContinueOnSpellLoad(function()
        TextLoaded(spellID)
      end)
    end
  end
  return nil
end

local function GetEntries()
  local entries, seen = {}, {}
  local owner = ns.CurrentCharacter()
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
            longText = Description(spellID),
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
-- SPELL_TEXT_UPDATE comes when a spell's description is ready. Seek decides
-- when to read: in combat, it waits for the end (ADR 0002).
local events = CreateFrame("Frame")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("SPELL_TEXT_UPDATE")
events:SetScript("OnEvent", function(_, event, spellID)
  if event == "SPELL_TEXT_UPDATE" then
    TextLoaded(spellID)
  else
    Seek.NotifyChanged(SOURCE_ID)
  end
end)
