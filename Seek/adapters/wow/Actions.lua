-- The WoW action adapter: runs the actions that the core asks for through
-- the Actions port (core/Actions.lua). Show actions only change what the
-- player sees, so they also work in combat; the exceptions are the quest
-- log and the world map, which WoW does not let addons open in combat.
-- There is no "show in spellbook": opening the spellbook from addon code
-- taints it (issue #29). Use actions run through a secure button (see below); the
-- core blocks them in combat.
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

-- Use actions ("use" on an item, "cast" on a spell) go through a secure
-- action button (SecureActionButtonTemplate, Blizzard_FrameXML/
-- SecureTemplates.lua). WoW runs a use action only from Blizzard's secure
-- code, started by a real key press or click; addon code that calls
-- UseItemByName or CastSpellByID itself is blocked. So:
--   1. Prepare (below): when the core says which use action the next key
--      press would run, Seek sets the button's attributes. Attributes of a
--      secure button can only change outside combat; the core prepares
--      nothing in combat, and Prepare checks the lockdown too.
--   2. The search bar binds Enter to a click on this button while that use
--      action is selected in the action list (adapters/wow/SearchBar.lua).
--      The player's Enter is the real key press.
--   3. The button's own secure OnClick runs the action. Then its PostClick
--      tells the search bar, which sends Enter to the core, and the core asks
--      Run for the use action. Run has nothing left to do then.
--
-- The button is not a child of the search bar: a protected child would make
-- the search bar protected too, and it could no longer open and close in
-- combat. It is hidden; a key binding clicks it all the same.
local USE_BUTTON_NAME = "SeekUseButton"

local useButton = CreateFrame("Button", USE_BUTTON_NAME, UIParent, "SecureActionButtonTemplate")

local setUp = false -- the button's fixed settings are made
local requested -- the use action that the core asked for last ({ id, entry }), or nil
local preparedID -- the use action that the button's attributes are set to, or nil

-- Sets the button's attributes for the requested use action, or clears them
-- when there is none. Only outside combat; in combat nothing changes, and
-- the button counts as not prepared.
local function Apply()
  if not setUp or InCombatLockdown() then
    preparedID = nil
    return
  end
  local actionType, item, spell
  if requested and requested.id == "useItem" then
    actionType, item = "item", "item:" .. requested.entry.gameID
  elseif requested and requested.id == "castSpell" then
    actionType, spell = "spell", requested.entry.gameID
  end
  useButton:SetAttribute("type", actionType)
  useButton:SetAttribute("item", item)
  useButton:SetAttribute("spell", spell)
  preparedID = actionType and requested.id or nil
end

-- The button's fixed settings, once, outside combat (a /reload in combat
-- waits for its end, and then prepares what the core asked for meanwhile).
-- Hidden, and only a key binding clicks it. It acts on the key's down
-- press, whatever the player's "cast on key down" setting is:
-- SecureActionButton_OnClick reads the "useOnKeyDown" attribute before
-- that setting. It gets no up click, so the action never runs twice.
local function SetUp()
  if setUp or InCombatLockdown() then
    return
  end
  useButton:Hide()
  useButton:RegisterForClicks("AnyDown")
  useButton:SetAttribute("useOnKeyDown", true)
  useButton:SetScript("PostClick", function(_, _, down)
    if down and preparedID and ns.OnUseButtonClicked then
      ns.OnUseButtonClicked()
    end
  end)
  setUp = true
  Apply()
end

SetUp()
if not setUp then
  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_REGEN_ENABLED")
  events:SetScript("OnEvent", function(self)
    SetUp()
    if setUp then
      self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
  end)
end

-- The secure button's global name, for a key binding that clicks it.
ns.USE_BUTTON_NAME = USE_BUTTON_NAME

-- The use action that the secure button runs on its next click, or nil.
function ns.PreparedUseAction()
  if InCombatLockdown() then
    return nil
  end
  return preparedID
end

-- The key press on the secure button has already run the use action.
local function AlreadyRun() end

-- Each action id from the kind registry (core/Kinds.lua) and how to run it.
local run = {
  showInBag = ShowInBag,
  openQuestLog = OpenQuestLog,
  showOnMap = ShowOnMap,
  useItem = AlreadyRun,
  castSpell = AlreadyRun,
}

ns.SetActionAdapter({
  Run = function(_, actionID, entry)
    local action = run[actionID]
    if not action then
      error("Seek: the WoW action adapter cannot run the action " .. tostring(actionID))
    end
    action(entry)
  end,
  Prepare = function(_, actionID, entry)
    requested = actionID and { id = actionID, entry = entry } or nil
    Apply()
  end,
})
