-- Each character's bags, kept account-wide, and Seek's source of the items
-- in the bags of the player's other characters.
--
-- Each time Seek reads the current character's bags (Seek's bag source,
-- adapters/wow/BagSource.lua), it keeps that character's items in the
-- account-wide saved data (the Storage port), under the character's name
-- (its owner, "Name-Realm").
--
-- The source "other characters' bags" gives one entry per distinct item per
-- other character from that data: all of the account's characters, on all
-- realms, of both factions, but never the current character, whose items
-- come from the bag source, live. A character shows only after it has
-- logged in once with this version of Seek. The entries have no `inBags`
-- fact, so they have no actions: they are faded results (see GLOSSARY.md).
--
-- The player can hide another character (a hidden character, see
-- GLOSSARY.md) on Seek's settings page: the setting hiddenCharacters, a set
-- of owners. The source leaves out a hidden character's items, but Seek
-- still keeps its bags, which follow its logins, so showing it again brings
-- its items back. A character that Seek sees for the first time is shown.
-- A change of the setting reads the source again, so it takes effect
-- without a reload (in combat, when combat ends: ADR 0002). Seek never
-- deletes a character's bags.
local _, ns = ...

-- Seek's bag source registers with this id.
ns.BAG_SOURCE_ID = "Seek.Bags"

local SOURCE_ID = "Seek.OtherBags"

-- Change this when the saved bags' shape changes; Seek then ignores older
-- saved bags.
local SAVED_VERSION = 1

-- Each character's items, by owner: lists of tables with the fields of an
-- entry that do not depend on the owner (name, kind, icon, gameID,
-- longText, count: the item count when Seek last read the character's
-- bags). Saved as the field `characters` of the saved bags. Bags saved
-- before item counts have none, until the character logs in again.
local bagsByOwner = {}

-- Takes each character's bags from the account-wide saved data (see
-- Storage.lua), if they have the right shape. ns.Start() calls it, before
-- Seek reads any source. Saved data from before other characters' bags has
-- none: no other characters yet.
function ns.LoadCharacterBags(data)
  local saved = type(data) == "table" and data.bags
  if type(saved) ~= "table" or saved.version ~= SAVED_VERSION or type(saved.characters) ~= "table" then
    return
  end
  for owner, items in pairs(saved.characters) do
    if type(owner) == "string" and type(items) == "table" then
      bagsByOwner[owner] = items
    end
  end
end

-- Saves each character's bags into the account-wide saved data.
local function SaveBags()
  ns.SaveAccount({ bags = { version = SAVED_VERSION, characters = bagsByOwner } })
end

-- Sources.lua calls this after each read of a source, with the entries that
-- it accepted. A read of Seek's bag source replaces the current character's
-- items, and saves them.
function ns.KeepCharacterBags(id, copies)
  local owner = ns.CurrentCharacter()
  if id ~= ns.BAG_SOURCE_ID or not owner then
    return
  end
  local items = {}
  for i, copy in ipairs(copies) do
    items[i] = {
      name = copy.name, kind = copy.kind, icon = copy.icon, gameID = copy.gameID, longText = copy.longText,
      count = copy.count,
    }
  end
  bagsByOwner[owner] = items
  SaveBags()
end

-- The other characters' items, the owners in name order, so that the
-- same items always come in the same order.
local function GetEntries()
  local entries = {}
  local current = ns.CurrentCharacter()
  if not current then
    return entries
  end
  local hidden = ns.Setting("hiddenCharacters")
  local owners = {}
  for owner in pairs(bagsByOwner) do
    if owner ~= current and not hidden[owner] then
      owners[#owners + 1] = owner
    end
  end
  table.sort(owners)
  for _, owner in ipairs(owners) do
    for _, item in ipairs(bagsByOwner[owner]) do
      if type(item) == "table" then
        entries[#entries + 1] = {
          name = item.name,
          kind = item.kind,
          icon = item.icon,
          gameID = item.gameID,
          longText = item.longText,
          count = item.count,
          owner = owner,
        }
      end
    end
  end
  return entries
end

ns.api.RegisterSource({ id = SOURCE_ID, GetEntries = GetEntries })

-- The other characters whose bags Seek keeps, for Seek's settings page,
-- where the player shows or hides each one: a list of tables with the
-- character's `owner` ("Name-Realm"), its `shownName`, as Seek shows it
-- (ns.OwnerName), and whether it is `hidden`, in the order of the shown
-- names. Never the current character.
function ns.OtherCharacters()
  local characters = {}
  local current = ns.CurrentCharacter()
  local hidden = ns.Setting("hiddenCharacters")
  for owner in pairs(bagsByOwner) do
    if owner ~= current then
      characters[#characters + 1] = {
        owner = owner, shownName = ns.OwnerName(owner), hidden = hidden[owner] == true,
      }
    end
  end
  table.sort(characters, function(a, b)
    return a.shownName < b.shownName
  end)
  return characters
end

ns.WatchSettings(function(name)
  if name == "hiddenCharacters" then
    ns.api.NotifyChanged(SOURCE_ID)
  end
end)
