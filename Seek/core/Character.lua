-- The Character port: who the current character is. The WoW character
-- adapter plugs in when the addon loads; tests plug in a fake.
--
-- A character adapter is a table with one method:
--   Name()  the current character as "Name-Realm", the way an entry names
--           its owner (see GLOSSARY.md)
--
-- Any part of the core can ask ns.CurrentCharacter(): to keep the current
-- character's bags under its name, to tell another character's entries
-- from its own, and to show the owner of another character's result.
local _, ns = ...

local adapter

function ns.SetCharacter(character)
  adapter = character
end

-- The current character's "Name-Realm", or nil when no adapter is plugged
-- in.
function ns.CurrentCharacter()
  return adapter and adapter:Name()
end
