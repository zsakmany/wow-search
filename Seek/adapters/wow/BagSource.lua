-- Seek's bag source: one entry per distinct item in the character's bags
-- (the backpack and the equipped bags, not the bank). It registers through
-- the public `Seek` table, like any other addon's source.

local SOURCE_ID = "Seek.Bags"

local FIRST_BAG = Enum.BagIndex.Backpack
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS

-- Items whose data the game is still loading (item ID -> true).
local loading = {}

-- "Name-Realm" of the current character (the realm can be missing early in
-- the login).
local function CurrentCharacter()
  local name, realm = UnitFullName("player")
  if realm and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

-- An item whose data is not loaded yet has no name. Leave it out for now,
-- and send a change notice when the game has loaded it. (Many items can
-- load in one frame; Seek reads the bags once for all of their notices.)
local function GetEntries()
  local entries, seen = {}, {}
  local owner = CurrentCharacter()
  for bag = FIRST_BAG, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local itemID = info and info.itemID
      if itemID and not seen[itemID] then
        seen[itemID] = true
        local item = Item:CreateFromItemID(itemID)
        if item:IsItemDataCached() then
          entries[#entries + 1] = {
            name = item:GetItemName(),
            icon = info.iconFileID,
            kind = "item",
            gameID = itemID,
            owner = owner,
          }
        elseif not loading[itemID] then
          loading[itemID] = true
          item:ContinueOnItemLoad(function()
            loading[itemID] = nil
            Seek.NotifyChanged(SOURCE_ID)
          end)
        end
      end
    end
  end
  return entries
end

Seek.RegisterSource({ id = SOURCE_ID, GetEntries = GetEntries })

-- BAG_UPDATE_DELAYED comes once after a batch of bag changes (loot, sell,
-- move). PLAYER_ENTERING_WORLD reads the bags once they are ready at login.
-- Seek decides when to read: in combat, it waits for the end (ADR 0002).
local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
  Seek.NotifyChanged(SOURCE_ID)
end)
