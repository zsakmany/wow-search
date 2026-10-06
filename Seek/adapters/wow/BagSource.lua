-- Seek's bag source: one entry per distinct item in the character's bags
-- (the backpack and the equipped bags, not the bank), with the item's
-- tooltip text as its long text, and its item count: the stacks of all of
-- the slots that hold the item, added up. It registers through the public
-- `Seek` table, like any other addon's source. Each entry has the `inBags`
-- fact, which gives it its actions. The core also keeps these items, with
-- their counts, as the character's bags, for the player's other characters
-- (core/CharacterBags.lua).
local _, ns = ...

local SOURCE_ID = ns.BAG_SOURCE_ID

local FIRST_BAG = Enum.BagIndex.Backpack
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS

local ITEM_NAME_LINE = Enum.TooltipDataLineType.ItemName

-- Items whose data the game is still loading (item ID -> true).
local loading = {}

-- The tooltip text of the item in a bag slot: each line's left and right
-- text, without the line with the item's name (the entry's name already has
-- it). The tooltip data comes from the game, without showing a tooltip.
local function TooltipText(bag, slot)
  local data = C_TooltipInfo.GetBagItem(bag, slot)
  local pieces = {}
  for _, line in ipairs(data and data.lines or {}) do
    if line.type ~= ITEM_NAME_LINE then
      pieces[#pieces + 1] = line.leftText
      pieces[#pieces + 1] = line.rightText
    end
  end
  return ns.LongText(pieces)
end

-- Whether the item gets the "use" action: it has a "Use:" spell (a
-- Hearthstone, a potion, food, a quest item that is used), and it is not
-- something to wear. C_Item.GetItemSpell tells the first from the item's
-- data alone, so the answer does not change with mana, cooldowns, or
-- combat, and can go into the saved copy; C_Item.IsUsableItem would answer
-- "can it be used right now", which changes. Seek's use action uses the
-- secure "item" action, which equips an item that can be worn instead of
-- using it, so those items get no use action (a trinket with a "Use:"
-- effect, for example). Ore, cloth, and other items without a "Use:" spell
-- get none either.
local function Usable(itemID)
  return C_Item.GetItemSpell(itemID) ~= nil and not C_Item.IsEquippableItem(itemID)
end

-- An item whose data is not loaded yet has no name, and its tooltip text
-- can be incomplete. Leave it out for now, and send a change notice when the
-- game has loaded it. (Many items can load in one frame; Seek reads the bags
-- once for all of their notices.)
local function GetEntries()
  local entries, seen, byItemID = {}, {}, {}
  local owner = ns.CurrentCharacter()
  for bag = FIRST_BAG, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local itemID = info and info.itemID
      local entry = itemID and byItemID[itemID]
      if entry then
        -- Another stack of an item that already has its entry.
        entry.count = entry.count + info.stackCount
      elseif itemID and not seen[itemID] then
        seen[itemID] = true
        local item = Item:CreateFromItemID(itemID)
        if item:IsItemDataCached() then
          entry = {
            name = item:GetItemName(),
            icon = info.iconFileID,
            kind = "item",
            gameID = itemID,
            owner = owner,
            longText = TooltipText(bag, slot),
            count = info.stackCount,
            inBags = true,
            usable = Usable(itemID),
          }
          entries[#entries + 1] = entry
          byItemID[itemID] = entry
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
