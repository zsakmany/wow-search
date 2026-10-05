-- The search bar window: a driving adapter (docs/adr/0003). It sends open,
-- close, the query, and key presses to the core's search session, and shows
-- the view state that comes back. It keeps no search state of its own.
--
-- A plain (not protected) frame, so it can open and close in combat. It has
-- no protected children: the secure button for use actions is not part of
-- it (adapters/wow/Actions.lua).
local _, ns = ...

local L = ns.L

local ROW_HEIGHT = 24
local ROW_INSET = 10 -- between the window's left and right edges and the result rows
local TOP_HEIGHT = 64 -- the title bar and the text box
local QUESTION_MARK_ICON = 134400 -- for an entry without an icon
local LIST_ROW_HEIGHT = 20
local LIST_PADDING = 8 -- between the action list's border and its rows
local LIST_MIN_WIDTH = 140
local LIST_LABEL_GAP = 12 -- between an action's label and its blocked sign or the use key
local GOLD = "|cffffd100" -- the matched letters of a name: the color of quest titles
local TOOLTIP_GAP = 4 -- between the window's edge and the tooltip
local FADED_ALPHA = 0.5 -- the icon, name, and kind of a faded result

-- The use key: Cmd+Enter on a Mac, Ctrl+Enter on Windows, each also with
-- the number pad's Enter (see "Keys for use actions" below). For this
-- platform: its key chords, its label in the action list, and whether its
-- modifier (Cmd or Ctrl) is held.
local USE_KEY = IsMacClient() and {
  chords = { "META-ENTER", "META-NUMPADENTER" },
  label = L.USE_KEY_MAC,
  ModifierDown = IsMetaKeyDown,
} or {
  chords = { "CTRL-ENTER", "CTRL-NUMPADENTER" },
  label = L.USE_KEY_WINDOWS,
  ModifierDown = IsControlKeyDown,
}

local Render -- defined below; the session calls it after a change notice

local session = ns.NewSearchSession(function(view)
  Render(view)
end)

-- Blizzard-style window at the top center of the screen. Not movable.
local frame = CreateFrame("Frame", "SeekSearchBar", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(420, TOP_HEIGHT)
frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
frame:SetFrameStrata("DIALOG")
frame:SetToplevel(true)
frame:EnableMouse(true)
frame.TitleText:SetText(L.NAME)
frame:Hide()

-- Escape closes the bar also when the text box has lost focus (for example,
-- after a click on the game world).
table.insert(UISpecialFrames, frame:GetName())

local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
box:SetHeight(20)
box:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -32)
box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -32)
box:SetAutoFocus(false)
-- Send Up and Down to OnArrowPressed without the Alt key.
box:SetAltArrowKeyMode(false)

local hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
hint:SetPoint("LEFT", box, "LEFT", 0, 0)

local noResults = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
noResults:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -TOP_HEIGHT)

-- A result's name for its row: the letters at the `matched` positions (nil
-- or empty for none) in gold, the others as they are. Each "|" in the name
-- becomes "||", so that a name never breaks the color codes.
local function ColoredName(name, matched)
  local isMatched = {}
  for _, position in ipairs(matched or {}) do
    isMatched[position] = true
  end
  local position, gold = 0, false
  local text = name:gsub(ns.LETTER_PATTERN, function(letter)
    position = position + 1
    local start = ""
    if (isMatched[position] or false) ~= gold then
      gold = not gold
      start = gold and GOLD or "|r"
    end
    -- Not `letter == "|"`: in a broken UTF-8 name, a "|" can come with
    -- stray bytes in one letter.
    return start .. (letter:gsub("|", "||"))
  end)
  return gold and text .. "|r" or text
end

-- The result rows: icon, name, and kind. The selected row is lit. The
-- matched letters of each name are gold, also on the selected row. A faded
-- result (no actions, such as an item in another character's bags) has a
-- gray icon and dim text; its row is lit as brightly when selected. After
-- combat blocked the use key on the selected row, the row shows the
-- "blocked in combat" sign in place of the kind. The core sends as many
-- rows as the visible results setting says; rows are made when more rows
-- than before first need them. Rows do not react to the mouse (yet).
local rows = {}

local function Row(i)
  if rows[i] then
    return rows[i]
  end
  local row = CreateFrame("Frame", nil, frame)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", frame, "TOPLEFT", ROW_INSET, -(TOP_HEIGHT - 4) - (i - 1) * ROW_HEIGHT)
  row:SetPoint("RIGHT", frame, "RIGHT", -ROW_INSET, 0)

  row.selection = row:CreateTexture(nil, "BACKGROUND")
  row.selection:SetAllPoints()
  row.selection:SetColorTexture(1, 1, 1, 0.15)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

  row.kind = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  row.kind:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  row.kind:SetJustifyH("RIGHT")

  row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row.kind, "LEFT", -8, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row:Hide()
  rows[i] = row
  return row
end

-- The action list: a small tooltip-style box to the right of the selected
-- result row, with one row per action. The selected action is lit, like the
-- selected result. The first use action shows the use key, which runs it
-- from the results. Rows are made when a longer list first needs them.
local list = CreateFrame("Frame", nil, frame, "TooltipBackdropTemplate")
list:SetFrameLevel(frame:GetFrameLevel() + 10)
list:Hide()

local listRows = {}

local function ListRow(i)
  local row = listRows[i]
  if not row then
    row = CreateFrame("Frame", nil, list)
    row:SetHeight(LIST_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_PADDING, -LIST_PADDING - (i - 1) * LIST_ROW_HEIGHT)
    row:SetPoint("RIGHT", list, "RIGHT", -LIST_PADDING, 0)

    row.selection = row:CreateTexture(nil, "BACKGROUND")
    row.selection:SetAllPoints()
    row.selection:SetColorTexture(1, 1, 1, 0.15)

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    -- The "blocked in combat" sign, on a blocked action only.
    row.sign = row:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    row.sign:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.sign:SetText(L.BLOCKED_IN_COMBAT)

    -- The use key, on the first use action only.
    row.key = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.key:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.key:SetText(USE_KEY.label)

    listRows[i] = row
  end
  return row
end

-- Shows the action list next to the selected result row, or hides it. The
-- list is as wide as its longest label and sign or key. A blocked action is
-- grayed and shows the "blocked in combat" sign; on the first use action,
-- the sign takes the place of the use key, which does nothing in combat.
local function RenderActionList(view)
  local anchor
  for i, result in ipairs(view.results) do
    if result.selected then
      anchor = rows[i]
    end
  end
  if not view.actionList or not anchor then
    list:Hide()
    return
  end

  local actions = view.actionList.rows
  local width = LIST_MIN_WIDTH
  for i, action in ipairs(actions) do
    local row = ListRow(i)
    row.label:SetText(action.label)
    row.label:SetFontObject(action.blocked and "GameFontDisable" or "GameFontHighlight")
    row.sign:SetShown(action.blocked)
    row.key:SetShown(action.useKey and not action.blocked)
    row.selection:SetShown(action.selected)
    row:Show()
    local rowWidth = row.label:GetStringWidth()
    if action.blocked then
      rowWidth = rowWidth + LIST_LABEL_GAP + row.sign:GetStringWidth()
    elseif action.useKey then
      rowWidth = rowWidth + LIST_LABEL_GAP + row.key:GetStringWidth()
    end
    width = math.max(width, math.ceil(rowWidth) + 12 + 2 * LIST_PADDING)
  end
  for i = #actions + 1, #listRows do
    listRows[i]:Hide()
  end

  list:SetSize(width, #actions * LIST_ROW_HEIGHT + 2 * LIST_PADDING)
  list:ClearAllPoints()
  list:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 16, LIST_PADDING)
  list:Show()
end

-- The WoW tooltip of one result row: Seek only asks the game to show its
-- own tooltip for the thing, so it works in combat too. Items show the
-- general tooltip of the item ID (not a bag slot), spells the spell's, and
-- quests the tooltip of the quest's link.
--
-- Seek has its own tooltip frame, made from Blizzard's GameTooltip template.
-- The shared GameTooltip is used by the whole game: when the mouse moves
-- over the world, a unit, or another window, that code takes GameTooltip
-- and hides or replaces Seek's tooltip. Seek's own frame is never touched
-- by other code.
local tooltip = CreateFrame("GameTooltip", "SeekResultTooltip", UIParent, "GameTooltipTemplate")
tooltip:SetFrameStrata("TOOLTIP")

local tooltipShown -- what the tooltip shows for Seek now, or nil (see RenderTooltip)

-- Each kind (core/Kinds.lua) and how to fill Seek's tooltip with the tooltip
-- of a thing of that kind, from its game ID. Each returns false when the
-- game has nothing to show yet (a quest without a link).
local setTooltip = {
  item = function(itemID)
    tooltip:SetItemByID(itemID)
    return true
  end,
  spell = function(spellID)
    tooltip:SetSpellByID(spellID)
    return true
  end,
  quest = function(questID)
    local link = GetQuestLink(questID)
    if not link then
      return false
    end
    tooltip:SetHyperlink(link)
    return true
  end,
}

local function HideTooltip()
  tooltipShown = nil
  if tooltip:IsOwned(frame) then
    tooltip:Hide()
  end
end

-- Shows the tooltip of the row that the view says, to the right or the
-- left of the window, its top level with the row's top; or hides it. The
-- core decides when there is one (the selected row; none while the
-- action list is open on the right side).
local function RenderTooltip(view)
  local wanted = view.tooltip
  local result = wanted and view.results[wanted.row]
  if not result then
    HideTooltip()
    return
  end
  -- The same thing at the same place: leave it as it is, so it does not
  -- flicker on each key press.
  local shown = table.concat({ result.kind, tostring(result.gameID), wanted.row, wanted.side }, ":")
  if shown == tooltipShown and tooltip:IsOwned(frame) then
    return
  end
  local row = rows[wanted.row]
  tooltip:SetOwner(frame, "ANCHOR_NONE")
  tooltip:ClearAllPoints()
  if wanted.side == "left" then
    tooltip:SetPoint("TOPRIGHT", row, "TOPLEFT", -(ROW_INSET + TOOLTIP_GAP), 0)
  else
    tooltip:SetPoint("TOPLEFT", row, "TOPRIGHT", ROW_INSET + TOOLTIP_GAP, 0)
  end
  local set = setTooltip[result.kind]
  if not (set and set(result.gameID)) then
    HideTooltip()
    return
  end
  tooltip:Show()
  tooltipShown = shown
end

-- Shows the query, the hint, the result rows, the "no results" text, and
-- the action list.
local function RenderContent(view)
  if box:GetText() ~= view.query then
    box:SetText(view.query)
  end
  hint:SetText(view.hint or "")
  hint:SetShown(view.hint ~= nil)
  noResults:SetText(view.noResults or "")
  noResults:SetShown(view.noResults ~= nil)

  for i = 1, math.max(#rows, #view.results) do
    local row, result = Row(i), view.results[i]
    if result then
      row.icon:SetTexture(result.icon or QUESTION_MARK_ICON)
      row.name:SetText(ColoredName(result.name, result.matchedLetters))
      if result.blocked then
        row.kind:SetFontObject("GameFontRedSmall")
        row.kind:SetText(L.BLOCKED_IN_COMBAT)
      else
        row.kind:SetFontObject("GameFontDisableSmall")
        row.kind:SetText(result.kindLabel)
      end
      row.icon:SetDesaturated(result.faded)
      local alpha = result.faded and FADED_ALPHA or 1
      row.icon:SetAlpha(alpha)
      row.name:SetAlpha(alpha)
      row.kind:SetAlpha(alpha)
      row.selection:SetShown(result.selected)
      row:Show()
    else
      row:Hide()
    end
  end

  local height = TOP_HEIGHT
  if #view.results > 0 then
    height = height + #view.results * ROW_HEIGHT + 4
  elseif view.noResults then
    height = height + ROW_HEIGHT
  end
  frame:SetHeight(height)

  RenderActionList(view)
end

-- Keys for use actions: how Enter in the action list, and the use key on
-- the results, reach the secure button.
--
-- While the text box has keyboard focus, no key binding fires, and a use
-- action needs a key binding: WoW runs it only from a real key press on a
-- secure button (adapters/wow/Actions.lua).
--
-- List keys: while the action list is open outside combat, the text box
-- gives up the focus, and the list takes the keyboard with `keys`, a plain
-- keyboard-enabled frame:
--   - Up, Down, Tab, and Escape go to the core, as from the text box. The
--     Seek key closes the bar. The use key goes to the core, which does
--     nothing with it while the list is open. Every other key is swallowed,
--     so that it does not move the character or press an action bar button.
--   - Enter on a use action that the action adapter has prepared goes on to
--     the key bindings, where a priority override binding (owned by `keys`)
--     clicks the secure button. Its PostClick then sends Enter to the core.
--     Enter on any other action goes to the core.
-- When the list closes, or combat starts, the text box gets the focus back
-- (unless the bar closed).
--
-- The use key: while the action list is closed outside combat, and the
-- action adapter has prepared the selected result's first use action, a
-- priority override binding (also owned by `keys`) binds the use key to a
-- click on the secure button. The text box keeps the focus, so typing, copy
-- and paste, and the other keys work as before: its OnKeyDown lets only the
-- use key go on to the key bindings (SetPropagateKeyboardInput), and keeps
-- every other key. The text box's own OnEnterPressed also runs for the use
-- key, and does nothing then. The secure button's PostClick sends the use
-- key to the core. (Tested in the game, see issue #7.)
--
-- Combat: override bindings and keyboard propagation cannot change in
-- combat, so a binding left behind would keep the player's Enter or use key
-- until combat ends, and a text box left passing keys on would also press
-- the player's key bindings while they type. Seek sets them only outside the
-- lockdown, and clears them on PLAYER_REGEN_DISABLED, which comes just
-- before the lockdown starts. In combat, the list works from the text box,
-- as without use actions, the use key reaches the core from the text box's
-- OnEnterPressed, and the core shows use actions as blocked.
local keys = CreateFrame("Frame", nil, frame)
keys:SetAllPoints()
keys:EnableKeyboard(false)

local listKeys = false -- `keys` has the keyboard

-- The key bindings that click the secure button: Enter, in the action
-- list, and the use key, on the results. Each has its key chords and the
-- key that the core gets once the button has run (ns.OnUseButtonClicked).
local ENTER_BINDING = { chords = { "ENTER", "NUMPADENTER" }, coreKey = "ENTER" }
local USE_KEY_BINDING = { chords = USE_KEY.chords, coreKey = "USE" }

-- The key binding that is set now: ENTER_BINDING, USE_KEY_BINDING, or nil.
local buttonBinding = nil

-- True from PLAYER_REGEN_DISABLED to PLAYER_REGEN_ENABLED. The lockdown
-- itself starts just after the first and ends just before the second; Seek
-- leaves the list keys at the first.
local inCombat = InCombatLockdown()

-- Whether a key chord (such as "META-ENTER") is the use key.
local function IsUseKey(chord)
  return tContains(USE_KEY.chords, chord)
end

-- Whether `binding` is set now and a key chord is one of its keys, so that
-- the key clicks the secure button.
local function ClicksButton(binding, chord)
  return buttonBinding == binding and tContains(binding.chords, chord)
end

-- Sets a key binding (see buttonBinding) that clicks the secure button, or
-- clears the bindings for nil. Never in the lockdown.
local function BindKeys(binding)
  if binding == buttonBinding or InCombatLockdown() then
    return
  end
  ClearOverrideBindings(keys)
  for _, chord in ipairs(binding and binding.chords or {}) do
    SetOverrideBindingClick(keys, true, chord, ns.USE_BUTTON_NAME, "LeftButton")
  end
  buttonBinding = binding
end

-- The text box keeps every key: none goes on to the key bindings. Never in
-- the lockdown.
local function KeepAllKeys()
  if not InCombatLockdown() then
    box:SetPropagateKeyboardInput(false)
  end
end

-- Gives the keyboard back from the list keys. `focus` gives the focus back
-- to the text box. EnableKeyboard works in combat on a plain frame.
local function LeaveListKeys(focus)
  keys:EnableKeyboard(false)
  if listKeys and focus then
    box:SetFocus()
  end
  listKeys = false
end

-- The selected row of the action list in a view, or nil.
local function SelectedAction(view)
  for _, action in ipairs(view.actionList and view.actionList.rows or {}) do
    if action.selected then
      return action
    end
  end
end

-- Whether Enter would click the secure button: the selected action is a use
-- action that combat does not block and that the action adapter has
-- prepared.
local function UseActionReady(action)
  return action ~= nil and action.type == "use" and not action.blocked
    and ns.PreparedUseAction() == action.id
end

-- Enter, from the text box or the list keys, when it does not click the
-- secure button. A use action that combat does not block runs only through
-- that button (a blocked one goes to the core, which does nothing): from
-- here, the core would close the bar and nothing would run, so Enter does
-- nothing.
local function PressEnter()
  local action = SelectedAction(session:View())
  if action and action.type == "use" and not action.blocked then
    return
  end
  Render(session:PressKey("ENTER"))
end

-- The use key, from the text box, when it does not click the secure button.
-- Outside combat, the selected result's use action runs only through that
-- button: from here, the core would close the bar and nothing would run, so
-- the use key does nothing (on a result with no use action, the core would
-- do nothing either). In combat, the core blocks it and marks the result.
local function PressUseKey()
  if inCombat then
    Render(session:PressKey("USE"))
  end
end

-- Takes or gives back the keyboard for the action list, and binds the keys
-- that click the secure button, as the view says.
local function RenderKeys(view)
  local outsideCombat = not inCombat and not InCombatLockdown()
  if view.open and view.actionList and outsideCombat then
    box:ClearFocus()
    keys:EnableKeyboard(true)
    listKeys = true
    BindKeys(UseActionReady(SelectedAction(view)) and ENTER_BINDING or nil)
  else
    LeaveListKeys(view.open)
    -- With the action list closed, the core prepares the selected result's
    -- first use action, if it has one.
    local useKeyReady = view.open and not view.actionList and outsideCombat and ns.PreparedUseAction() ~= nil
    BindKeys(useKeyReady and USE_KEY_BINDING or nil)
  end
  if buttonBinding ~= USE_KEY_BINDING then
    KeepAllKeys()
  end
end

-- Shows a view state from the core. The tooltip comes last, once the
-- window is shown or hidden, so that it never belongs to a hidden window.
function Render(view)
  RenderContent(view)
  RenderKeys(view)
  if view.open then
    if not frame:IsShown() then
      frame:Show()
      -- Take the focus one frame later. The key that opened the bar (for
      -- example Cmd+K) also sends its letter, and with focus now, that "k"
      -- would land in the text box.
      C_Timer.After(0, function()
        if frame:IsShown() and not listKeys then
          box:SetFocus()
        end
      end)
    end
  else
    -- Give the keyboard back, so the player's key bindings work again.
    box:ClearFocus()
    frame:Hide()
  end
  RenderTooltip(view)
end

-- Opens the search bar, or closes it when it is open.
function ns.ToggleSearchBar()
  Render(session:Toggle())
end

-- Typing changes the query. It also closes the action list (the core
-- decides), so the player is back at the results of the new query.
box:SetScript("OnTextChanged", function(self, userInput)
  if userInput then
    Render(session:SetQuery(self:GetText()))
  end
end)

-- Escape closes the action list when it is open, else the search bar.
box:SetScript("OnEscapePressed", function()
  Render(session:PressKey("ESCAPE"))
end)

-- Up and Down move in the action list when it is open, else in the results.
box:SetScript("OnArrowPressed", function(_, key)
  if key == "UP" or key == "DOWN" then
    Render(session:PressKey(key))
  end
end)

-- Enter runs the selected result's main action, or the selected action
-- when the action list is open, and closes the bar; with no results, or on
-- a blocked action, it does nothing. The core decides (see PressEnter for
-- use actions); the handler also keeps the text box from losing focus on
-- its own. With the use key's modifier held, this is the use key, which
-- never runs Enter's action: it goes to the secure button through its key
-- binding, or, in combat, to the core (see PressUseKey).
box:SetScript("OnEnterPressed", function()
  if USE_KEY.ModifierDown() then
    PressUseKey()
  else
    PressEnter()
  end
end)

-- Tab opens the selected result's action list; with no results it does
-- nothing. This replaces the template's handler, which would move the focus
-- to another text box.
box:SetScript("OnTabPressed", function()
  Render(session:PressKey("TAB"))
end)

-- While the text box has focus, key bindings do not fire. Catch the Seek
-- binding's key here, so the same key also closes the bar. The use key goes
-- on to its key binding while that is set (see "Keys for use actions"
-- above); every other key stays in the text box.
box:SetScript("OnKeyDown", function(self, key)
  local chord = CreateKeyChordStringUsingMetaKeyState(key)
  if not InCombatLockdown() then
    self:SetPropagateKeyboardInput(ClicksButton(USE_KEY_BINDING, chord))
  end
  if GetBindingAction(chord) == "SEEK_TOGGLE" then
    ns.ToggleSearchBar()
  end
end)

-- A key press while the list keys have the keyboard (see above).
keys:SetScript("OnKeyDown", function(self, key)
  if InCombatLockdown() then
    -- Does not happen: Seek leaves the list keys before the lockdown. If it
    -- does, give the keyboard back; propagation cannot change in combat.
    LeaveListKeys(true)
    return
  end
  local chord = CreateKeyChordStringUsingMetaKeyState(key)
  if ClicksButton(ENTER_BINDING, chord) then
    -- On to the override binding, which clicks the secure button.
    self:SetPropagateKeyboardInput(true)
    return
  end
  self:SetPropagateKeyboardInput(false)
  if GetBindingAction(chord) == "SEEK_TOGGLE" then
    ns.ToggleSearchBar()
    return
  end
  if IsUseKey(chord) then
    Render(session:PressKey("USE"))
  elseif key == "ENTER" or key == "NUMPADENTER" then
    PressEnter()
  elseif key == "ESCAPE" or key == "TAB" or key == "UP" or key == "DOWN" then
    Render(session:PressKey(key))
  end
end)

-- The secure button has run the prepared use action (adapters/wow/
-- Actions.lua): the core runs the key that clicked it, Enter in the action
-- list or the use key on the results, which closes the bar.
function ns.OnUseButtonClicked()
  if buttonBinding then
    Render(session:PressKey(buttonBinding.coreKey))
  end
end

-- Leave the list keys, clear the bindings, and keep every key in the text
-- box at the last moment before the lockdown; take them again after combat
-- (the core also updates the view on both: the blocked signs).
local combatEvents = CreateFrame("Frame")
combatEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
combatEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEvents:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    LeaveListKeys(frame:IsShown())
    BindKeys(nil)
    KeepAllKeys()
  else
    inCombat = false
    if frame:IsShown() then
      Render(session:View())
    end
  end
end)

frame.CloseButton:SetScript("OnClick", function()
  Render(session:Close())
end)

-- The frame can also be hidden from outside (Escape through UISpecialFrames).
-- Tell the core, so its state matches the screen.
frame:SetScript("OnHide", function()
  if session:View().open then
    Render(session:Close())
  end
end)
