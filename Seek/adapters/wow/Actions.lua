-- The WoW action adapter: runs the actions that the core asks for through
-- the Actions port (core/Actions.lua). Show actions only change what the
-- player sees, so they also work in combat; the exceptions are the world
-- map and the Options window, which WoW does not let addons open in combat,
-- and the talent window, which opens through a secure button that Seek's
-- keys cannot reach in combat (see ClickTalentButton). There is no "show
-- in spellbook": opening the spellbook from addon code taints it (issue
-- #29); "show in talents" opens the same window, at its talents tab, from
-- the game's own talent button. The core blocks every use action in
-- combat. Use on an item, cast on a spell, and show in talents run through
-- secure buttons (see below); a quest's focus and tracking call no
-- protected function, so Run runs them itself, like a show action.
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

-- The "Track" action: tracks the quest (see ToggleTracked).
local function TrackQuest(entry)
  ToggleTracked(entry, true)
end

-- The "Untrack" action: untracks the quest (see ToggleTracked).
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

-- "Show in talents": opens the talent window at its talents tab, the way
-- the player's own click on the game's talent button does. Seek's secure
-- button for Enter (see below) clicks the game's TalentMicroButton (the
-- secure action type "click" with the "clickbutton" attribute,
-- SECURE_ACTIONS.click in Blizzard_FrameXML/SecureTemplates.lua) from the
-- player's real key press. The button's own OnClick then opens the window
-- (PlayerSpellsMicroButtonMixin:OnClick in Blizzard_MicroMenu/Mainline/
-- MainMenuBarMicroButtons.lua: with `talentsOnly`, it calls
-- PlayerSpellsUtil.TogglePlayerSpellsFrame at the talents tab), as
-- Blizzard's own, secure code. The window shows the talents of the spec
-- group that it showed last; Seek does not switch it, and does not light
-- up the talent: writing into the window's own search box from Seek's code
-- would taint it, as it tainted the Options window (issue #25).
--
-- The game's button is a toggle: when the window is open at the talents
-- tab, the click closes it; open at another tab, it switches to the
-- talents tab.
--
-- The click does nothing when the game's button is disabled (WoW does not
-- click a disabled button): before the character has earned a talent
-- point (PlayerSpellsMicroButtonMixin:UpdateMicroButton), and while a full
-- screen frame disables the micro buttons (DisableMicroButtons). It also
-- does nothing in the game's quick keybind mode, and when the game has no
-- TalentMicroButton. A hidden button (a game rule can leave it out of the
-- micro menu) still takes the click. Either way, the search bar closes,
-- and it is a pick.
--
-- Combat: the game's button opens the window in combat too, but in combat
-- no key press of Seek's reaches the secure button. The search bar sets no
-- key bindings in combat (adapters/wow/SearchBar.lua), and the core
-- prepares nothing then. So Enter goes to the core, which closes the search
-- bar and asks Run, and Run does nothing (see AlreadyRun): opening the
-- window from Seek's code would taint it again. After a /reload in combat,
-- the buttons are set up only when combat ends (see SetUp); until then
-- Enter on a talent does the same.
--
-- Taint: Seek calls none of Blizzard's talent window code. Before issue
-- #56, Seek opened the window with PlayerSpellsUtil.OpenToClassTalentsTab
-- from its own code: the window's OnShow then ran MultiActionBar_
-- ShowAllGrids as Seek's code, which tainted action bar state, and the
-- action bars hid in the next fight.
local function ClickTalentButton()
  return { type = "click", clickbutton = TalentMicroButton }
end

-- Use on an item, cast on a spell, and show in talents go through secure
-- action buttons (SecureActionButtonTemplate, Blizzard_FrameXML/
-- SecureTemplates.lua). WoW runs the first two only from Blizzard's secure
-- code, started by a real key press or click; addon code that calls
-- UseItemByName or CastSpellByID itself is blocked. The third would work
-- from addon code, but taints (see ClickTalentButton). So:
--   1. Prepare (below): when the core says which action a key would run
--      next (Enter, or the use key), Seek sets the attributes of that key's
--      secure button. Attributes of a secure button can only change outside
--      combat; the core prepares nothing in combat, and Prepare checks the
--      lockdown too.
--   2. The search bar binds the key to a click on its button
--      (adapters/wow/SearchBar.lua): Enter while that action is selected in
--      the action list or is the selected result's main action, or the use
--      key while the action list is closed and that use action is the
--      selected result's first one. The player's key press is the real key
--      press.
--   3. The button's own secure OnClick runs the action. Then its PostClick
--      tells the search bar, which sends that key to the core, and the core
--      asks Run for the action. Run has nothing left to do then.
--
-- Each key has its own button: on one result, Enter's show action and the
-- use key's use action can both need one. The buttons are not children of
-- the search bar: a protected child would make the search bar protected
-- too, and it could no longer open and close in combat. They are hidden; a
-- key binding clicks them all the same.

-- The actions that run through a secure button, and the button's
-- attributes for each, from the entry's game ID. The other actions run
-- from Run (see the list of actions at the end).
local ON_SECURE_BUTTON = {
  useItem = function(gameID)
    return { type = "item", item = "item:" .. gameID }
  end,
  castSpell = function(gameID)
    return { type = "spell", spell = gameID }
  end,
  showInTalents = ClickTalentButton,
}

-- Every attribute that ON_SECURE_BUTTON sets, so that a button keeps none
-- of an earlier action's.
local ATTRIBUTES = { "type", "item", "spell", "clickbutton" }

-- The secure buttons, by the core's name of the key that clicks them. Each
-- has its global name, its frame, the action that the core asked for last
-- for its key (`requested`: { id, entry }, or nil), and the action that its
-- attributes are set to (`preparedID`, or nil).
local buttons = {
  ENTER = { name = "SeekEnterButton" },
  USE = { name = "SeekUseButton" },
}
for _, button in pairs(buttons) do
  button.frame = CreateFrame("Button", button.name, UIParent, "SecureActionButtonTemplate")
end

local setUp = false -- the buttons' fixed settings are made

-- Sets a button's attributes for its requested action, or clears them when
-- there is none. Only outside combat; in combat nothing changes, and the
-- button counts as not prepared.
local function Apply(button)
  if not setUp or InCombatLockdown() then
    button.preparedID = nil
    return
  end
  local requested = button.requested
  local Attributes = requested and ON_SECURE_BUTTON[requested.id]
  local attributes = Attributes and Attributes(requested.entry.gameID) or {}
  for _, name in ipairs(ATTRIBUTES) do
    button.frame:SetAttribute(name, attributes[name])
  end
  button.preparedID = attributes.type and requested.id or nil
end

-- The buttons' fixed settings, once, outside combat (a /reload in combat
-- waits for its end, and then prepares what the core asked for meanwhile).
-- Hidden, and only a key binding clicks them. They act on the key's down
-- press, whatever the player's "cast on key down" setting is:
-- SecureActionButton_OnClick reads the "useOnKeyDown" attribute before
-- that setting. They get no up click, so the action never runs twice.
local function SetUp()
  if setUp or InCombatLockdown() then
    return
  end
  for key, button in pairs(buttons) do
    local frame = button.frame
    frame:Hide()
    frame:RegisterForClicks("AnyDown")
    frame:SetAttribute("useOnKeyDown", true)
    frame:SetScript("PostClick", function(_, _, down)
      if down and button.preparedID and ns.OnSecureButtonClicked then
        ns.OnSecureButtonClicked(key)
      end
    end)
  end
  setUp = true
  for _, button in pairs(buttons) do
    Apply(button)
  end
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

-- The global name of the secure button that `key` ("ENTER" or "USE")
-- clicks, for a key binding that clicks it.
function ns.SecureButtonName(key)
  return buttons[key].name
end

-- The action that the secure button of `key` runs on its next click, or
-- nil.
function ns.PreparedSecureAction(key)
  if InCombatLockdown() then
    return nil
  end
  return buttons[key].preparedID
end

-- Whether the action that the core asked for last for `key` (the one that
-- the player's next press of that key would run, see Prepare) runs through
-- the secure button, whether or not the button is ready for it. False when
-- the core asked for none (always in combat), and for an action that Run
-- runs itself: the search bar sends the key to the core for that one.
function ns.SecureButtonRequested(key)
  local requested = buttons[key].requested
  return requested ~= nil and ON_SECURE_BUTTON[requested.id] ~= nil
end

-- The key press on a secure button has already run the action. In combat,
-- no key press reaches a secure button (see ClickTalentButton): then Run
-- comes alone, a use action never does (the core blocks it), and "show in
-- talents" does nothing.
local function AlreadyRun() end

-- Each action id from the kind registry (core/Kinds.lua) and how to run it.
local run = {
  showInBag = ShowInBag,
  showOnMap = ShowOnMap,
  openInOptionsWindow = OpenInOptionsWindow,
  showInTalents = AlreadyRun,
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
  Prepare = function(_, key, actionID, entry)
    local button = buttons[key]
    button.requested = actionID and { id = actionID, entry = entry } or nil
    Apply(button)
  end,
  NeedsSecureButton = function(_, actionID)
    return ON_SECURE_BUTTON[actionID] ~= nil
  end,
})
