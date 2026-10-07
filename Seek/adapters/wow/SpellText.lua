-- Spell descriptions as long text, for the sources that need them (the
-- spell source and the talent source). A spell's description is empty
-- until the game has loaded the spell's data, so a source waits for it, and
-- reads again when it comes.
--
-- Call the description function only while Seek reads the source, which is
-- only outside combat (see LongText.lua, ADR 0002).
local _, ns = ...

-- A description function and a text-loaded function for the source with
-- this id. Each source gets its own, with its own list of the spells that it
-- waits for.
--   Description(spellID)  the spell's description as long text, or nil.
--                         When it is empty, the source waits for it. Some
--                         spells have no description at all; they wait for
--                         nothing more once their data is loaded.
--   TextLoaded(spellID)   call it on SPELL_TEXT_UPDATE: when the source waits
--                         for that spell, Seek reads the source again. (Many
--                         spells can load in one frame; Seek reads the source
--                         once for all of their notices.)
function ns.SpellDescriptions(sourceID)
  -- Spells whose description was empty at the last read (spell ID -> true).
  local waiting = {}

  local function TextLoaded(spellID)
    if waiting[spellID] then
      waiting[spellID] = nil
      Seek.NotifyChanged(sourceID)
    end
  end

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

  return Description, TextLoaded
end
