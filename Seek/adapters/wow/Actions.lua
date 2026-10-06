-- The WoW action adapter: runs the actions that the core asks for through
-- the Actions port (core/Actions.lua). Show actions only change what the
-- player sees, so they also work in combat; the exceptions are the world
-- map and the Options window, which WoW does not let addons open in combat.
-- There is no "show in spellbook": opening the spellbook from addon code
-- taints it (issue #29). The core blocks every use action in combat. Use
-- on an item and cast on a spell run through a secure button (see below);
-- a quest's focus and tracking call no protected function, so Run runs
-- them itself, like a show action.
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

-- Opens the world map with the quest's details in its side panel (the
-- quest log, on Forever), through the function that Blizzard's own
-- objective tracker calls when the player clicks a quest there. Blizzard's
-- details panel shows the map of the quest's objectives and pings the
-- quest's pin there (QuestMapFrame_ShowQuestDetails in Blizzard_UIPanels_
-- Game/Mainline/QuestMapFrame.lua). For a quest with a waypoint (a route to
-- objectives in another zone), it shows the waypoint's map instead, as the
-- game does, and the panel's button switches to the objectives' map. Seek
-- cannot pick the map itself: the details panel closes when the map
-- changes to any other map than the one it opened. A quest with no place
-- on the map still opens its details.
--
-- Not in combat: Blizzard lets no addon show a UI panel such as the world
-- map in combat, and shows "Interface action failed because of an AddOn"
-- when one tries. So in combat this does nothing. It also does nothing when
-- the quest has left the log since Seek read it.
--
-- Taint: Blizzard's code runs here as Seek's code, so the fields it writes
-- (such as the quest that the details panel shows, and the map's scroll
-- position) count as Seek's. The quest log has no secure buttons of its
-- own, but the map's quest pins can be blocked when the player opens the
-- map again in combat (issue #38). See issue #27 for the same risk with the
-- bags.
local function ShowOnMap(entry)
  if InCombatLockdown() or not QuestMapFrame_OpenToQuestDetails
      or not C_QuestLog.GetLogIndexForQuestID(entry.gameID) then
    return
  end
  if C_GameRules and C_GameRules.IsGameRuleActive(Enum.GameRule.WorldMapDisabled) then
    return
  end
  QuestMapFrame_OpenToQuestDetails(entry.gameID)
end

-- Whether the quest is a tracked quest: one that the objective tracker
-- shows (QuestUtils_IsQuestWatched in Blizzard_FrameXMLUtil/Mainline/
-- QuestUtils.lua).
local function IsTracked(questID)
  return C_QuestLog.GetQuestWatchType(questID) ~= nil
end

-- Gives the quest the focus (the arrow on the minimap), the way a click on
-- the quest's icon does in the game (POIButtonMixin:OnClick in
-- Blizzard_POIButton/POIButton.lua): a quest that is not tracked is tracked
-- first, then it gets the focus. Like that click, it does not check the
-- limit of tracked quests itself. It does nothing when the quest has left
-- the log since Seek read it.
--
-- Combat: neither function is protected; the core blocks this in combat
-- like every use action. Taint: Seek calls only the game's C_ functions and
-- writes nothing into Blizzard's tables. The game then sends
-- QUEST_WATCH_LIST_CHANGED and SUPER_TRACKING_CHANGED, and Blizzard's own
-- frames update from those events.
local function FocusQuest(entry)
  local questID = entry.gameID
  if not C_QuestLog.GetLogIndexForQuestID(questID) then
    return
  end
  if not IsTracked(questID) then
    C_QuestLog.AddQuestWatch(questID)
  end
  C_SuperTrack.SetSuperTrackedQuestID(questID)
end

-- Takes the focus away from the quest, when it still has it, the way the
-- game does for a quest that the player turns in (SuperTrackEventMixin in
-- Blizzard_FrameXMLUtil/Mainline/Blizzard_QuestSuperTracking.lua). The
-- quest stays tracked. Combat and taint as for FocusQuest.
local function RemoveFocus(entry)
  if C_SuperTrack.GetSuperTrackedQuestID() == entry.gameID then
    C_SuperTrack.SetSuperTrackedQuestID(0)
  end
end

-- Tracks or untracks the quest through the game's own track toggle, the
-- one that the quest log's menu and the world map call
-- (QuestMapQuestOptions_TrackQuest in Blizzard_UIPanels_Game/Mainline/
-- QuestMapFrame.lua), so the game makes its own checks and shows its own
-- messages: at the limit of tracked quests it shows "You can't track any
-- more quests." and tracks nothing, and in the New Player Experience it
-- does not untrack. `track` is what the action's label promised: when the
-- game's state has already changed since Seek read the quest, nothing
-- happens, so "Track" never untracks. It also does nothing when the quest
-- has left the log since Seek read it.
--
-- Combat: the toggle calls no protected function; the core blocks this in
-- combat like every use action. Taint: Blizzard's toggle runs here as
-- Seek's code, but it only reads, calls the game's C_ functions, and adds
-- a line to UIErrorsFrame; it writes nothing into Blizzard's tables.
local function ToggleTracked(entry, track)
  local questID = entry.gameID
  if not QuestMapQuestOptions_TrackQuest or not C_QuestLog.GetLogIndexForQuestID(questID)
      or IsTracked(questID) == track then
    return
  end
  QuestMapQuestOptions_TrackQuest(questID)
end

local function TrackQuest(entry)
  ToggleTracked(entry, true)
end

local function UntrackQuest(entry)
  ToggleTracked(entry, false)
end

-- Opens the game's Options window at a game option's page, scrolled so
-- that the game option's row is at the top (it is not highlighted), or at a
-- game option page. The page is looked up again by its name: its ID can
-- change between sessions (see adapters/wow/GameOptionSource.lua). The
-- scroll finds the row by its name, which is the entry's name.
--
-- Not in combat: Blizzard lets no addon open the Options window in combat
-- (ADDON_ACTION_BLOCKED), so in combat this does nothing (issue #28). It
-- also does nothing when the page is gone since Seek read it.
--
-- Taint: Settings.OpenToCategory only asks the game to open the window; the
-- game then sends SETTINGS_PANEL_OPEN, and Blizzard's own code opens the
-- window and the page from that event. A test in the game showed that the
-- window's state (its search text, its page, its layout) stays secure, and
-- that casting and using items still work afterwards. Seek never fills in
-- the window's own search box: that taints it until a /reload.
local function OpenInOptionsWindow(entry)
  if InCombatLockdown() then
    return
  end
  local pageID = ns.GameOptionPageID(entry.page or entry.name)
  if not pageID then
    return
  end
  if entry.page then
    Settings.OpenToCategory(pageID, entry.name)
  else
    Settings.OpenToCategory(pageID)
  end
end

-- Use on an item and cast on a spell go through a secure action button
-- (SecureActionButtonTemplate, Blizzard_FrameXML/SecureTemplates.lua). WoW
-- runs them only from Blizzard's secure code, started by a real key press
-- or click; addon code that calls UseItemByName or CastSpellByID itself is
-- blocked. So:
--   1. Prepare (below): when the core says which use action the next key
--      press would run, Seek sets the button's attributes. Attributes of a
--      secure button can only change outside combat; the core prepares
--      nothing in combat, and Prepare checks the lockdown too.
--   2. The search bar binds a key to a click on this button
--      (adapters/wow/SearchBar.lua): Enter while that use action is
--      selected in the action list, or the use key while the action list is
--      closed and that use action is the selected result's first one. The
--      player's key press is the real key press.
--   3. The button's own secure OnClick runs the action. Then its PostClick
--      tells the search bar, which sends that key to the core, and the core
--      asks Run for the use action. Run has nothing left to do then.
--
-- The button is not a child of the search bar: a protected child would make
-- the search bar protected too, and it could no longer open and close in
-- combat. It is hidden; a key binding clicks it all the same.
local USE_BUTTON_NAME = "SeekUseButton"

-- The use actions that run through the secure button. The others run from
-- Run (see the list of actions at the end).
local ON_USE_BUTTON = { useItem = true, castSpell = true }

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

-- Whether the use action that the core asked for last (the one that the
-- player's next key press would run, see Prepare) runs through the secure
-- button, whether or not the button is ready for it. False when the core
-- asked for none (always in combat), and for a use action that Run runs
-- itself: the search bar sends the key to the core for that one.
function ns.UseButtonRequested()
  return requested ~= nil and ON_USE_BUTTON[requested.id] == true
end

-- The key press on the secure button has already run the use action.
local function AlreadyRun() end

-- Each action id from the kind registry (core/Kinds.lua) and how to run it.
local run = {
  showInBag = ShowInBag,
  showOnMap = ShowOnMap,
  openInOptionsWindow = OpenInOptionsWindow,
  useItem = AlreadyRun,
  castSpell = AlreadyRun,
  focusQuest = FocusQuest,
  removeFocus = RemoveFocus,
  trackQuest = TrackQuest,
  untrackQuest = UntrackQuest,
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
