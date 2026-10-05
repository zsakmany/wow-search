-- SecureOpenProbe: a THROWAWAY research prototype for Seek issue #39.
-- It is not part of Seek. It has no tests and no polish. Delete it when
-- #39 is answered. The test plan is in docs/research/secure-window-opening.md.
--
-- Question: can a secure action button, or a key binding command, open
-- Blizzard's bags, spellbook, and world map / quest log without taint,
-- when the player's Enter is the key press?
--
-- How it works: each "/sop <window> <method>" command prepares one method
-- (out of combat only) and binds Enter to it. The next Enter press runs it
-- once. The "insecure" methods call Blizzard's functions from addon code,
-- the way Seek did, so the taint logs can be compared.
--
-- Safety: the probe binds Enter only out of combat, and clears the binding
-- after one use, on /sop off, after 20 seconds, or when combat starts
-- (PLAYER_REGEN_DISABLED comes just before the lockdown), whichever is
-- first. The probe writes nothing into Blizzard's tables.

local PREFIX = "|cff33ff99SOP:|r "
local ARM_SECONDS = 20
local GLOW_SECONDS = 4

local function Say(text, ...)
  if select("#", ...) > 0 then
    text = text:format(...)
  end
  print(PREFIX .. text)
end

-- ---------------------------------------------------------------------------
-- The secure button that Enter clicks, and the helper ("proxy") buttons
-- that its macros /click. A macro can /click only named buttons; a proxy
-- of type "click" gives a name to an unnamed Blizzard button.
-- ---------------------------------------------------------------------------

local owner = CreateFrame("Frame", nil, UIParent) -- owns the Enter binding

local button = CreateFrame("Button", "SecureOpenProbeButton", UIParent, "SecureActionButtonTemplate")
local buttonArt = button:CreateTexture(nil, "ARTWORK")
buttonArt:SetAllPoints()
buttonArt:SetColorTexture(0.2, 0.6, 1, 0.8)
local buttonLabel = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
buttonLabel:SetPoint("TOP", button, "BOTTOM", 0, -2)
buttonLabel:SetText("SOP (pinned)")

-- Short names on purpose: the spellbook macro repeats them, and a macro
-- has at most 255 characters.
local proxies = {}
for _, name in ipairs({ "SOPTab", "SOPPrev", "SOPNext", "SOPQuest" }) do
  proxies[name] = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
end

-- Secure buttons are protected: their size, place, visibility, and
-- attributes can only change outside combat. A /reload in combat waits.
local setUp = false
local function SetUp()
  if setUp or InCombatLockdown() then
    return
  end
  button:SetSize(40, 40)
  button:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
  button:Hide()
  -- Keys act on the down press (like Seek's use button); a mouse click on
  -- the pinned button acts on the up press (SecureActionButton_OnClick).
  button:RegisterForClicks("AnyDown", "AnyUp")
  button:SetAttribute("useOnKeyDown", true)
  for _, proxy in pairs(proxies) do
    -- /click sends an up click (down = false).
    proxy:Hide()
    proxy:RegisterForClicks("AnyDown", "AnyUp")
    proxy:SetAttribute("useOnKeyDown", false)
    proxy:SetAttribute("type", "click")
  end
  setUp = true
end
SetUp()

-- ---------------------------------------------------------------------------
-- Glow on the bag slots that hold the item: the same idea as Seek's
-- (adapters/wow/Actions.lua), to check that it still works after a secure
-- open. The glow is the probe's own texture; Blizzard's tables get no field.
-- ---------------------------------------------------------------------------

local glows = setmetatable({}, { __mode = "k" })
local glowSlots, glowItem, glowEnds = {}, nil, 0

local glowDriver = CreateFrame("Frame")
glowDriver:Hide()
glowDriver:SetScript("OnUpdate", function(self)
  local lit = {}
  if GetTime() < glowEnds then
    for _, target in ipairs(glowSlots) do
      local itemButton = ContainerFrameUtil_GetItemButtonAndContainer(target.bag, target.slot)
      if itemButton and itemButton:IsVisible()
          and C_Container.GetContainerItemID(target.bag, target.slot) == glowItem then
        lit[itemButton] = true
      end
    end
  else
    self:Hide()
  end
  for itemButton in pairs(lit) do
    local glow = glows[itemButton]
    if not glow then
      glow = itemButton:CreateTexture(nil, "OVERLAY", nil, 7)
      glow:SetAtlas("bags-glow-white", true)
      glow:SetPoint("CENTER")
      glow:SetBlendMode("ADD")
      glows[itemButton] = glow
    end
    glow:Show()
  end
  for itemButton, glow in pairs(glows) do
    if not lit[itemButton] then
      glow:Hide()
    end
  end
end)

local function Glow(slots, itemID)
  if not ContainerFrameUtil_GetItemButtonAndContainer then
    Say("No Blizzard bag code: nothing to glow.")
    return
  end
  glowSlots, glowItem, glowEnds = slots, itemID, GetTime() + GLOW_SECONDS
  glowDriver:Show()
  Say("Glow started on %d slot(s) for %d seconds.", #slots, GLOW_SECONDS)
end

-- ---------------------------------------------------------------------------
-- Arming Enter
-- ---------------------------------------------------------------------------

local armed -- what Enter does now (text), or nil
local armToken = 0
local actOn = "down" -- the press on which the secure button acts: "down" or "up"
local after -- runs once after the armed method ran
local clearAfterCombat = false

-- Sees Enter for the binding-command methods (they have no PostClick).
-- It passes every key on to the bindings.
local watcher = CreateFrame("Frame", nil, UIParent)
watcher:Hide()
watcher:EnableKeyboard(true)

local LeaveKeys -- the Enter test window's; defined below

-- Clears the Enter binding. `force`: also when nothing seems armed
-- (/sop off), in case an error left a binding behind.
local function Disarm(reason, force)
  if not armed and not force then
    return
  end
  if InCombatLockdown() then
    -- Does not happen: PLAYER_REGEN_DISABLED disarms first.
    Say("In combat: cannot clear the Enter binding now. It is cleared when combat ends.")
    clearAfterCombat = true
    return
  end
  ClearOverrideBindings(owner)
  watcher:Hide()
  if actOn == "up" then
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("useOnKeyDown", true)
    actOn = "down"
  end
  armed, after = nil, nil
  if reason ~= "re-armed" then
    LeaveKeys(true) -- gives the Enter test window's text box the keys back
  end
  Say("Enter is normal again (%s).", reason)
end

local function CanArm()
  if InCombatLockdown() then
    Say("In combat: cannot prepare (attributes and bindings are locked). Try after combat.")
    return false
  end
  SetUp()
  return true
end

local function StartArm(text, afterFn)
  armed, after = text, afterFn
  armToken = armToken + 1
  local token = armToken
  C_Timer.After(ARM_SECONDS, function()
    if token == armToken and armed then
      Disarm("timed out")
    end
  end)
  Say("Armed: press Enter to %s. (%d seconds; /sop off to cancel)", text, ARM_SECONDS)
end

-- Enter clicks the secure button, which runs `attributes`.
-- `up`: the button acts on Enter's up press instead (question 4 test).
local function ArmButton(text, attributes, afterFn, up)
  if not CanArm() then
    return
  end
  Disarm("re-armed")
  for _, key in ipairs({ "type", "clickbutton", "macrotext" }) do
    button:SetAttribute(key, nil)
  end
  for key, value in pairs(attributes) do
    button:SetAttribute(key, value)
  end
  if up then
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    actOn = "up"
  end
  SetOverrideBindingClick(owner, true, "ENTER", button:GetName(), "LeftButton")
  StartArm(text, afterFn)
end

-- Enter runs a Blizzard key binding command (from Bindings.xml) directly.
local function ArmBinding(command, afterFn)
  if not CanArm() then
    return
  end
  Disarm("re-armed")
  SetOverrideBinding(owner, true, "ENTER", command)
  watcher:SetPropagateKeyboardInput(true)
  watcher:Show()
  StartArm("run the binding " .. command, afterFn)
end

watcher:SetScript("OnKeyDown", function(_, key)
  if key == "ENTER" and armed then
    Say("Enter went on to the binding command.")
    local afterFn = after
    C_Timer.After(0, function()
      if afterFn then
        afterFn()
      end
      Disarm("used")
    end)
  end
end)

-- With Enter armed, the click comes from the key: it acts on the `actOn`
-- press. Not armed, it is a mouse click on the pinned button: a secure
-- mouse click acts on the up press (SecureActionButton_OnClick).
button:SetScript("PostClick", function(_, _, down)
  local actsOnDown = armed and actOn == "down"
  if actsOnDown ~= (down and true or false) then
    return -- the other half of the press; the action did not run on it
  end
  Say("Secure button clicked (type %s, %s press, %s).", tostring(button:GetAttribute("type")),
    down and "down" or "up", armed and "Enter" or "mouse")
  local afterFn = after
  if armed then
    Disarm("used")
  end
  if afterFn then
    afterFn()
  end
end)

-- Prints what a secure click would see on a Blizzard button.
local function Report(name, frame)
  frame = frame or _G[name]
  if not frame then
    Say("%s: does not exist (yet).", name)
    return nil
  end
  local constrained = frame.HasAccessConstraints and frame:HasAccessConstraints()
  local forbidden = frame.HasAnyForbiddenAspects and Enum.ForbiddenAspect
    and frame:HasAnyForbiddenAspects(Enum.ForbiddenAspect.ScriptedInput)
  Say("%s: visible=%s, enabled=%s, accessConstraints=%s, forbidsScriptedInput=%s", name,
    tostring(frame:IsVisible()), tostring(frame:IsEnabled()), tostring(constrained), tostring(forbidden))
  return frame
end

-- ---------------------------------------------------------------------------
-- Bags
-- ---------------------------------------------------------------------------

local BAG_BUTTON = {
  [0] = "MainMenuBarBackpackButton",
  [1] = "CharacterBag0Slot",
  [2] = "CharacterBag1Slot",
  [3] = "CharacterBag2Slot",
  [4] = "CharacterBag3Slot",
  [5] = "CharacterReagentBag0Slot",
}

-- Bindings_Camelot.xml: TOGGLEBAG1 is ToggleBag(4), and so on down.
local BAG_BINDING = {
  [0] = "TOGGLEBACKPACK",
  [1] = "TOGGLEBAG4",
  [2] = "TOGGLEBAG3",
  [3] = "TOGGLEBAG2",
  [4] = "TOGGLEBAG1",
  [5] = "TOGGLEREAGENTBAG1",
}

local function Combined(bag)
  return ContainerFrameSettingsManager and ContainerFrameSettingsManager:IsUsingCombinedBags(bag) or false
end

-- The slots that hold the item, and the closed bags to open. Bag buttons
-- and bag bindings toggle, so open bags are left out. With combined bags,
-- the held bags are one window: only the first of them is opened.
local function FindItem(itemID)
  local slots, bags, combinedTaken = {}, {}, false
  for bag = 0, 5 do
    local found = false
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      if C_Container.GetContainerItemID(bag, slot) == itemID then
        slots[#slots + 1] = { bag = bag, slot = slot }
        found = true
      end
    end
    if found and not IsBagOpen(bag) then
      if not Combined(bag) then
        bags[#bags + 1] = bag
      elseif not combinedTaken then
        bags[#bags + 1] = bag
        combinedTaken = true
      end
    end
  end
  return slots, bags
end

local function BagCommand(method, arg)
  if method == "all" then
    ArmBinding("OPENALLBAGS")
    return
  end
  local itemID = tonumber(arg)
  if not itemID or not (method == "insecure" or method == "click" or method == "macro" or method == "bind") then
    Say("Usage: /sop bag insecure|click|macro|bind <itemID>, or /sop bag all")
    return
  end
  local slots, bags = FindItem(itemID)
  if #slots == 0 then
    Say("Item %d is not in your bags.", itemID)
    return
  end
  Say("Item %d: %d slot(s). Closed bags to open: %s. Combined bags: %s.", itemID, #slots,
    #bags > 0 and table.concat(bags, ", ") or "none", tostring(Combined(0)))
  local function glow()
    Glow(slots, itemID)
  end

  if method == "insecure" then
    for _, bag in ipairs(bags) do
      OpenBag(bag)
    end
    Say("Called OpenBag from addon code (Seek's current way).")
    glow()
  elseif #bags == 0 then
    Say("The bags are already open. A toggle would close them: close the bags and try again.")
    glow()
  elseif method == "click" then
    local name = BAG_BUTTON[bags[1]]
    local frame = Report(name)
    if frame then
      ArmButton("click " .. name .. " (type click)", { type = "click", clickbutton = frame }, glow)
    end
  elseif method == "macro" then
    local lines = {}
    for _, bag in ipairs(bags) do
      Report(BAG_BUTTON[bag])
      lines[#lines + 1] = "/click " .. BAG_BUTTON[bag]
    end
    ArmButton("run the macro: " .. table.concat(lines, " | "),
      { type = "macro", macrotext = table.concat(lines, "\n") }, glow)
  else
    ArmBinding(BAG_BINDING[bags[1]], glow)
  end
end

-- ---------------------------------------------------------------------------
-- Spellbook
-- ---------------------------------------------------------------------------

local function SpellBook()
  return PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
end

local function BookCommand(method, arg1, arg2)
  if method == "insecure" then
    local spellID = tonumber(arg1)
    if not spellID then
      Say("Usage: /sop book insecure <spellID>")
    elseif InCombatLockdown() then
      Say("In combat: the probe does not open the spellbook from addon code.")
    else
      PlayerSpellsUtil.OpenToSpellBookTabAtSpell(spellID, true, false, nil)
      Say("Called PlayerSpellsUtil.OpenToSpellBookTabAtSpell(%d) from addon code (the old \"show in spellbook\", #29).",
        spellID)
    end
  elseif (method == "click" or method == "bind") and PlayerSpellsFrame and PlayerSpellsFrame:IsShown() then
    Say("The spellbook is already open. A toggle would close it: close it and try again.")
  elseif method == "click" then
    local frame = Report("SpellbookMicroButton")
    if frame then
      ArmButton("click SpellbookMicroButton (type click)", { type = "click", clickbutton = frame })
    end
  elseif method == "bind" then
    ArmBinding(arg1 == "pet" and "TOGGLEPETBOOK" or "TOGGLESPELLBOOK")
  elseif method == "tabs" then
    local book = SpellBook()
    if not book then
      Say("The spellbook is not loaded yet. Open and close it once by hand, then try again.")
      return
    end
    for tabID = 1, 20 do
      local tab = book.CategoryTabSystem:GetTabButton(tabID)
      if not tab then
        break
      end
      Say("Tab %d: %s", tabID, tostring(tab.GetTooltipText and tab:GetTooltipText()))
    end
  elseif method == "page" then
    local tabID, pages = tonumber(arg1), tonumber(arg2) or 0
    local book = SpellBook()
    if not tabID or pages < 0 or pages > 8 then
      Say("Usage: /sop book page <tab> <next page clicks 0-8>. /sop book tabs lists the tabs.")
      return
    elseif not book then
      Say("The spellbook is not loaded yet. Open and close it once by hand, then try again.")
      return
    end
    local tab = Report("tab " .. tabID, book.CategoryTabSystem:GetTabButton(tabID))
    local controls = book.PagedSpellsFrame and book.PagedSpellsFrame.PagingControls
    if not tab or not controls or not CanArm() then
      return
    end
    proxies.SOPTab:SetAttribute("clickbutton", tab)
    proxies.SOPPrev:SetAttribute("clickbutton", controls.PrevPageButton)
    proxies.SOPNext:SetAttribute("clickbutton", controls.NextPageButton)
    local lines = {}
    if not book:IsVisible() then
      lines[#lines + 1] = "/click SpellbookMicroButton"
    end
    lines[#lines + 1] = "/click SOPTab"
    -- Back to page 1, in case the tab keeps its page: at least as many
    -- clicks as the page shown now (a click on page 1 does nothing).
    local current = controls.GetCurrentPage and controls:GetCurrentPage() or 1
    for _ = 1, math.max(current - 1, 2) do
      lines[#lines + 1] = "/click SOPPrev"
    end
    for _ = 1, pages do
      lines[#lines + 1] = "/click SOPNext"
    end
    local text = table.concat(lines, "\n")
    if #text > 255 then
      Say("The macro would be %d characters (limit 255). Try fewer pages.", #text)
      return
    end
    Say("Macro is %d characters (limit 255).", #text)
    ArmButton(("open the spellbook at tab %d, page %d (macro of %d lines)"):format(tabID, pages + 1, #lines),
      { type = "macro", macrotext = text })
  else
    Say("Usage: /sop book insecure <spellID> | click | bind [pet] | tabs | page <tab> <n>")
  end
end

-- ---------------------------------------------------------------------------
-- Quest log and world map
-- ---------------------------------------------------------------------------

local probeQuestID

-- Finds the quest's title button in the quest log just before the click,
-- after the macro's first line has opened the log. Out of combat only.
proxies.SOPQuest:SetScript("PreClick", function(self)
  if InCombatLockdown() then
    Say("SOPQuest: in combat, its target cannot change.")
    return
  end
  local title = probeQuestID and QuestLogQuests_GetQuestButton and QuestLogQuests_GetQuestButton(probeQuestID)
  self:SetAttribute("clickbutton", title)
  if title then
    Say("SOPQuest: clicking the title button of quest %d.", probeQuestID)
  else
    Say("SOPQuest: no title button for quest %d (collapsed header, or the log was not built yet).", probeQuestID or 0)
  end
end)

local function QuestLogOpen()
  return WorldMapFrame and WorldMapFrame:IsShown() and QuestMapFrame and QuestMapFrame:IsShown()
end

local function LogCommand(method, arg)
  local questID = tonumber(arg)
  if method == "insecure" then
    if not questID then
      Say("Usage: /sop log insecure <questID>")
    elseif InCombatLockdown() then
      Say("In combat: addon code cannot open the quest log (Blizzard blocks it).")
    else
      QuestMapFrame_OpenToQuestDetails(questID)
      Say("Called QuestMapFrame_OpenToQuestDetails(%d) from addon code (Seek's \"show in quest log\").", questID)
    end
  elseif (method == "click" or method == "bind") and WorldMapFrame and WorldMapFrame:IsShown() then
    Say("The world map is already open. A toggle would close it: close it and try again.")
  elseif method == "click" then
    local frame = Report("QuestLogMicroButton")
    if frame then
      ArmButton("click QuestLogMicroButton (type click)", { type = "click", clickbutton = frame })
    end
  elseif method == "bind" then
    ArmBinding("TOGGLEQUESTLOG")
  elseif method == "quest" then
    if not questID then
      Say("Usage: /sop log quest <questID>")
      return
    end
    probeQuestID = questID
    local lines = {}
    if not QuestLogOpen() then
      Report("QuestLogMicroButton")
      lines[#lines + 1] = "/click QuestLogMicroButton"
    end
    lines[#lines + 1] = "/click SOPQuest"
    ArmButton(("open the quest log at quest %d (macro: %s)"):format(questID, table.concat(lines, " | ")),
      { type = "macro", macrotext = table.concat(lines, "\n") })
  else
    Say("Usage: /sop log insecure <questID> | click | bind | quest <questID>")
  end
end

local function MapCommand(method, arg)
  local questID = tonumber(arg)
  if method == "insecure" then
    if not questID then
      Say("Usage: /sop map insecure <questID>")
    elseif InCombatLockdown() then
      Say("In combat: addon code cannot open the world map (Blizzard blocks it).")
    else
      local mapID = GetQuestUiMapID(questID, true)
      if mapID and mapID ~= 0 then
        OpenWorldMap(mapID)
        EventRegistry:TriggerEvent("MapCanvas.PingQuestID", questID)
      else
        OpenWorldMap()
      end
      Say("Called OpenWorldMap(%s) and the quest ping from addon code (Seek's \"show on map\").", tostring(mapID))
    end
  elseif method == "bind" and WorldMapFrame and WorldMapFrame:IsShown() then
    Say("The world map is already open. A toggle would close it: close it and try again.")
  elseif method == "bind" then
    ArmBinding("TOGGLEWORLDMAP")
  else
    Say("Usage: /sop map insecure <questID> | bind. (No world map micro button in Forever: see /sop log.)")
  end
end

-- ---------------------------------------------------------------------------
-- Question 4: Enter from a focused text box. A small window with a text
-- box, like Seek's search bar.
--   - With focus, Enter goes to the text box. Does the Enter binding fire?
--   - Down: the text box gives up focus, and a plain frame takes the
--     keyboard (Seek's #22 action list method); Enter goes on to the binding.
--   - "/sop box up": on Enter's down press the text box gives up focus, and
--     the secure button acts on the up press. Does the up press reach it?
-- The secure button clicks the backpack button, which toggles the backpack.
-- ---------------------------------------------------------------------------

local box = CreateFrame("Frame", "SecureOpenProbeBox", UIParent, "BasicFrameTemplateWithInset")
box:SetSize(340, 70)
box:SetPoint("TOP", UIParent, "TOP", 0, -200)
box:SetFrameStrata("DIALOG")
box.TitleText:SetText("SecureOpenProbe: Enter test")
box:Hide()

local edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
edit:SetHeight(20)
edit:SetPoint("TOPLEFT", box, "TOPLEFT", 18, -32)
edit:SetPoint("TOPRIGHT", box, "TOPRIGHT", -14, -32)
edit:SetAutoFocus(false)
edit:SetAltArrowKeyMode(false)

local keys = CreateFrame("Frame", nil, box)
keys:SetAllPoints()
keys:EnableKeyboard(false)

local boxMode = "down" -- or "up"
local listKeys = false

function LeaveKeys(focus)
  keys:EnableKeyboard(false)
  if listKeys and focus then
    edit:SetFocus()
  end
  listKeys = false
end

local function ArmBackpack()
  local frame = Report("MainMenuBarBackpackButton")
  if frame then
    ArmButton("click the backpack button" .. (boxMode == "up" and " on Enter's UP press" or ""),
      { type = "click", clickbutton = frame }, function()
        LeaveKeys(box:IsShown())
      end, boxMode == "up")
  end
end

local function TakeKeys()
  if InCombatLockdown() then
    Say("In combat: the text box keeps the keyboard (bindings are locked).")
    return
  end
  ArmBackpack() -- first: re-arming gives the keys back
  edit:ClearFocus()
  keys:EnableKeyboard(true)
  listKeys = true
  Say("The text box gave up focus; a plain frame has the keyboard. Press Enter, or Escape/Up to go back.")
end

edit:SetScript("OnEnterPressed", function()
  if boxMode == "up" then
    Say("Enter also reached the text box (OnEnterPressed), after it gave up focus on the down press.")
  else
    Say("Enter reached the text box (OnEnterPressed): the binding did not fire while the box had focus.")
  end
end)

edit:SetScript("OnKeyDown", function(self, key)
  if boxMode == "up" and key == "ENTER" then
    self:ClearFocus()
    Say("Enter down: the text box gave up focus. Did the secure button run on the up press?")
  end
end)

edit:SetScript("OnArrowPressed", function(_, key)
  if key == "DOWN" and boxMode == "down" then
    TakeKeys()
  end
end)

edit:SetScript("OnEscapePressed", function()
  box:Hide()
end)

keys:SetScript("OnKeyDown", function(self, key)
  if InCombatLockdown() then
    LeaveKeys(true) -- does not happen: combat start leaves the keys first
    return
  end
  if key == "ENTER" and armed then
    self:SetPropagateKeyboardInput(true) -- on to the override binding
    return
  end
  self:SetPropagateKeyboardInput(false)
  if key == "ESCAPE" or key == "UP" then
    LeaveKeys(true)
    Say("The text box has the focus again.")
  end
end)

box:SetScript("OnHide", function()
  LeaveKeys(false)
  edit:ClearFocus()
  Disarm("test window closed")
end)

local function BoxCommand(mode)
  boxMode = mode == "up" and "up" or "down"
  if not CanArm() then
    return
  end
  LeaveKeys(false)
  box:Show()
  edit:SetText("")
  edit:SetFocus()
  ArmBackpack()
  if boxMode == "up" then
    Say("The text box has focus. Press Enter once and watch the messages.")
  else
    Say("The text box has focus. 1) Press Enter. 2) Press Down, then Enter. Escape closes the window.")
  end
end

-- ---------------------------------------------------------------------------
-- Combat, status, and the slash command
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    LeaveKeys(box:IsShown())
    Disarm("combat started")
    if button:IsShown() then
      Say("Combat: the pinned button keeps its last method. Click it to test a secure open in combat.")
    end
  else
    SetUp()
    if clearAfterCombat then
      clearAfterCombat = false
      Disarm("combat ended")
    end
  end
end)

local function Status()
  Say("In combat: %s. Armed: %s. Enter binding: %s.", tostring(InCombatLockdown()), armed or "no",
    tostring(GetBindingAction("ENTER", true)))
  Say("Button type: %s. Clicks on the %s press. Pinned: %s.", tostring(button:GetAttribute("type")), actOn,
    tostring(button:IsShown()))
  local open = {}
  for bag = 0, 5 do
    open[#open + 1] = bag .. "=" .. tostring(IsBagOpen(bag))
  end
  Say("Combined bags: %s. Bags open: %s.", tostring(Combined(0)), table.concat(open, " "))
  Say("Spellbook shown: %s. World map shown: %s. Quest log shown: %s.",
    tostring(PlayerSpellsFrame and PlayerSpellsFrame:IsShown() or false),
    tostring(WorldMapFrame and WorldMapFrame:IsShown() or false), tostring(QuestLogOpen() or false))
end

local HELP = {
  "THROWAWAY probe for Seek #39. Each command arms Enter once (out of combat).",
  "/sop bag insecure|click|macro|bind <itemID>   /sop bag all",
  "/sop book insecure <spellID> | click | bind [pet] | tabs | page <tab> <n>",
  "/sop log insecure <questID> | click | bind | quest <questID>",
  "/sop map insecure <questID> | bind",
  "/sop box [up]   Enter from a focused text box (question 4)",
  "/sop pin   show/hide the secure button for mouse clicks (also in combat)",
  "/sop status   /sop off",
}

SLASH_SECUREOPENPROBE1 = "/sop"
SlashCmdList.SECUREOPENPROBE = function(message)
  local window, method, arg1, arg2 = strsplit(" ", strtrim(message or ""):lower())
  if window == "bag" then
    BagCommand(method, arg1)
  elseif window == "book" then
    BookCommand(method, arg1, arg2)
  elseif window == "log" then
    LogCommand(method, arg1)
  elseif window == "map" then
    MapCommand(method, arg1)
  elseif window == "box" then
    BoxCommand(method)
  elseif window == "pin" then
    if InCombatLockdown() then
      Say("In combat: the button cannot be shown or hidden.")
    else
      button:SetShown(not button:IsShown())
      Say("Pinned button %s. Its method is the last one armed with a secure button.",
        button:IsShown() and "shown" or "hidden")
    end
  elseif window == "status" then
    Status()
  elseif window == "off" then
    Disarm("/sop off", true)
  else
    for _, line in ipairs(HELP) do
      Say(line)
    end
  end
end
