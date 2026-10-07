-- The Character port: who the current character is. The WoW character
-- adapter plugs in when the addon loads; tests plug in a fake.
--
-- A character adapter is a table with one method:
--   Name()  the current character as "Name-Realm", the way an entry names
--           its owner (see GLOSSARY.md)
--
-- Any part of the core can ask ns.CurrentCharacter(): to keep the current
-- character's bags under its name, and to tell another character's entries
-- from its own. ns.OwnerName() shows another character's name: on the row
-- of its result, and in the list of the other characters whose bags Seek
-- keeps.
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

-- An owner's name and realm, from its "Name-Realm". A character's name has
-- no hyphen; the realm follows the first one. Nil for an owner with no
-- realm.
local function SplitOwner(owner)
  return owner:match("^(.-)%-(.+)$")
end

-- Another character, as Seek shows it to the player: the name, and the
-- realm only when it is not the current character's ("Bob", or
-- "Bob-Stormrage").
function ns.OwnerName(owner)
  local name, realm = SplitOwner(owner)
  local _, currentRealm = SplitOwner(ns.CurrentCharacter() or "")
  if realm and realm == currentRealm then
    return name
  end
  return owner
end
