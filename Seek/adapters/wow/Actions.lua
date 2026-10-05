-- The WoW action adapter: runs the actions that the core asks for through
-- the Actions port (core/Actions.lua). Show actions only change what the
-- player sees, so they also work in combat; the exceptions are the
-- spellbook, the quest log, and the world map, which WoW does not let addons
-- open in combat.
--
-- Show in bag works with the default Blizzard bags. With a bag addon that
-- replaces them (such as Bagnon), the bag addon's own window opens if it
-- takes over OpenBag, and nothing is highlighted: Seek finds no shown
-- Blizzard bag button to light.
local _, ns = ...

local FIRST_BAG = Enum.BagIndex.Backpack
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS

local HIGHLIGHT_SECONDS = 4

-- The bag slots to highlight ({ bag, slot, itemID } each) and when to stop.
local targets = {}
local highlightEnds = 0

-- Seek's glow texture on each bag button that has had one (button -> glow).
-- Kept here, not as a field on Blizzard's button, so Seek writes nothing
-- into Blizzard's tables (that would taint them).
local glows = setmetatable({}, { __mode = "k" })

-- A pulsing glow like the game's own "new item" glow, on top of the icon.
local function GlowOn(button)
  local glow = glows[button]
  if not glow then
    glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetAtlas("bags-glow-white", true)
    glow:SetPoint("CENTER")
    glow:SetBlendMode("ADD")
    glow.pulse = glow:CreateAnimationGroup()
    glow.pulse:SetLooping("BOUNCE")
    local fade = glow.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.2)
    fade:SetDuration(0.5)
    -- A new texture starts shown; hide it so the check below starts the pulse.
    glow:Hide()
    glows[button] = glow
  end
  if not glow:IsShown() then
    glow:Show()
    glow.pulse:Play()
  end
end

local function GlowOff(glow)
  glow.pulse:Stop()
  glow:Hide()
end

-- Blizzard's bags reuse their item buttons (for example when the player
-- switches between one combined bag and separate bags), so a button can
-- show another slot later. Each frame while the highlight lasts, find the
-- buttons that show the target slots now, and light only those. The glow
-- goes off after a few seconds, or as soon as the bags close or the item
-- leaves its slot.
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
  local lit = {}
  if GetTime() < highlightEnds then
    for _, target in ipairs(targets) do
      local button = ContainerFrameUtil_GetItemButtonAndContainer(target.bag, target.slot)
      if button and button:IsVisible()
          and C_Container.GetContainerItemID(target.bag, target.slot) == target.itemID then
        lit[button] = true
      end
    end
  else
    self:Hide()
  end
  -- Light the buttons first: a button gets its glow the first time here.
  for button in pairs(lit) do
    GlowOn(button)
  end
  for button, glow in pairs(glows) do
    if not lit[button] and glow:IsShown() then
      GlowOff(glow)
    end
  end
end)

-- Opens the bags and highlights every slot that holds the item.
local function ShowInBag(entry)
  targets = {}
  for bag = FIRST_BAG, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      if C_Container.GetContainerItemID(bag, slot) == entry.gameID then
        targets[#targets + 1] = { bag = bag, slot = slot, itemID = entry.gameID }
      end
    end
  end

  -- Open only the bags that hold the item. With the game's "Combine bags"
  -- option on, OpenBag opens the combined bag instead.
  for _, target in ipairs(targets) do
    if not IsBagOpen(target.bag) then
      OpenBag(target.bag)
    end
  end

  -- Without Blizzard's bag code there is nothing to highlight.
  if ContainerFrameUtil_GetItemButtonAndContainer and #targets > 0 then
    highlightEnds = GetTime() + HIGHLIGHT_SECONDS
    driver:Show()
  end
end

-- Opens the spellbook at the spell, with Blizzard's own helper for this
-- (Blizzard_FrameXMLUtil, PlayerSpellsUtil.lua). It loads the spellbook (a
-- load-on-demand addon) when it is not loaded yet, opens it, and turns to
-- the page that holds the spell.
--
-- Taint (not tested in the game yet): this runs Blizzard's spellbook code
-- from addon code. The spellbook's spell buttons cast with a protected call,
-- and what Blizzard's code writes while Seek's call runs (the tab, the page,
-- each shown spell's slot) counts as Seek's. A click that casts from such a
-- page may then be blocked, as in issue #27 with the bags. No taint-free way
-- to turn to a spell exists for addon code; Seek keeps the risk small: it
-- calls only this one helper, writes nothing into Blizzard's tables, and
-- does not open flyouts (they share buttons with the action bars).
--
-- Not in combat: WoW lets only Blizzard's code open a window such as the
-- spellbook in combat (ShowUIPanel shows an "action blocked" message for
-- addon code). So in combat this action does nothing.
local function ShowInSpellbook(entry)
  if InCombatLockdown() or not PlayerSpellsUtil then
    return
  end
  local knownSpellsOnly, toggleFlyout = true, false
  PlayerSpellsUtil.OpenToSpellBookTabAtSpell(entry.gameID, knownSpellsOnly, toggleFlyout)
end

-- Opens the quest log (the side panel of the world map on Forever) at the
-- quest's details, through the function that Blizzard's own objective
-- tracker calls when the player clicks a quest there.
--
-- Not in combat: Blizzard lets no addon show a UI panel such as the world
-- map in combat, and shows "Interface action failed because of an AddOn"
-- when one tries. So in combat this does nothing. It also does nothing when
-- the quest has left the log since Seek read it.
--
-- Taint: Blizzard's code runs here as Seek's code, so the fields it writes
-- (such as the quest that the details panel shows) count as Seek's until
-- the player closes the world map, which clears them. The quest log has no
-- secure buttons of its own, and the map refreshes its secure parts in a
-- way that ignores Seek. See issue #27 for the same risk with the bags.
local function OpenQuestLog(entry)
  if InCombatLockdown() or not QuestMapFrame_OpenToQuestDetails
      or not C_QuestLog.GetLogIndexForQuestID(entry.gameID) then
    return
  end
  if C_GameRules and C_GameRules.IsGameRuleActive(Enum.GameRule.WorldMapDisabled) then
    return
  end
  QuestMapFrame_OpenToQuestDetails(entry.gameID)
end

-- Opens the world map at the zone of the quest's objectives and pings the
-- quest's pin there, the way Blizzard's own prey hunt widget shows its quest
-- on the map (Blizzard_UIWidgetTemplatePreyHuntProgress.lua): the quest's
-- map from GetQuestUiMapID, OpenWorldMap, and the "MapCanvas.PingQuestID"
-- event that the map's quest pins listen to. Unlike "show in quest log", it
-- does not open the quest's details. A quest with no place on the map opens
-- the map where it is.
--
-- Not in combat, as with the quest log: OpenWorldMap shows a UI panel,
-- which Blizzard lets no addon do in combat. It also does nothing when the
-- quest has left the log since Seek read it.
--
-- Taint: Blizzard's map code runs here as Seek's code, so what it writes
-- while this call runs (the shown map, the pinged pin) counts as Seek's.
-- The world map's pins are not secure, and Seek touches less than "show in
-- quest log" does: it neither selects the quest (C_QuestLog.SetSelectedQuest)
-- nor fills the details panel. Seek writes nothing into Blizzard's tables.
-- See issue #27 for the same risk with the bags.
local function ShowOnMap(entry)
  if InCombatLockdown() or not OpenWorldMap or not GetQuestUiMapID
      or not C_QuestLog.GetLogIndexForQuestID(entry.gameID) then
    return
  end
  local ignoreWaypoints = true -- the quest's own map, where its pin is
  local mapID = GetQuestUiMapID(entry.gameID, ignoreWaypoints)
  if not mapID or mapID == 0 then
    OpenWorldMap()
    return
  end
  OpenWorldMap(mapID)
  EventRegistry:TriggerEvent("MapCanvas.PingQuestID", entry.gameID)
end

-- Each action id from the kind registry (core/Kinds.lua) and how to run it.
local run = {
  showInBag = ShowInBag,
  showInSpellbook = ShowInSpellbook,
  openQuestLog = OpenQuestLog,
  showOnMap = ShowOnMap,
}

ns.SetActionAdapter({
  Run = function(_, actionID, entry)
    local action = run[actionID]
    if not action then
      error("Seek: the WoW action adapter cannot run the action " .. tostring(actionID))
    end
    action(entry)
  end,
})
