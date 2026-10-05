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
local TOP_HEIGHT = 64 -- the title bar and the text box
local QUESTION_MARK_ICON = 134400 -- for an entry without an icon
local LIST_ROW_HEIGHT = 20
local LIST_PADDING = 8 -- between the action list's border and its rows
local LIST_MIN_WIDTH = 140
local LIST_SIGN_GAP = 12 -- between an action's label and its blocked sign
local GOLD = "|cffffd100" -- the matched letters of a name: the color of quest titles

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
-- matched letters of each name are gold, also on the selected row. The core
-- sends as many rows as the visible results setting says; rows are made
-- when more rows than before first need them.
local rows = {}

local function Row(i)
  if rows[i] then
    return rows[i]
  end
  local row = CreateFrame("Frame", nil, frame)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -(TOP_HEIGHT - 4) - (i - 1) * ROW_HEIGHT)
  row:SetPoint("RIGHT", frame, "RIGHT", -10, 0)

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
-- selected result. Rows are made when a longer list first needs them.
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

    listRows[i] = row
  end
  return row
end

-- Shows the action list next to the selected result row, or hides it. The
-- list is as wide as its longest label and sign. A blocked action is grayed
-- and shows the "blocked in combat" sign.
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
    row.selection:SetShown(action.selected)
    row:Show()
    local rowWidth = row.label:GetStringWidth()
    if action.blocked then
      rowWidth = rowWidth + LIST_SIGN_GAP + row.sign:GetStringWidth()
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
      row.kind:SetText(result.kindLabel)
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

-- List keys: how Enter reaches the secure button for use actions.
--
-- While the text box has keyboard focus, no key binding fires, and a use
-- action needs a key binding: WoW runs it only from a real key press on a
-- secure button (adapters/wow/Actions.lua). So while the action list is
-- open outside combat, the text box gives up the focus, and the list takes
-- the keyboard with `keys`, a plain keyboard-enabled frame:
--   - Up, Down, Tab, and Escape go to the core, as from the text box. The
--     Seek key closes the bar. Every other key is swallowed, so that it does
--     not move the character or press an action bar button.
--   - Enter on a use action that the action adapter has prepared goes on to
--     the key bindings, where a priority override binding (owned by `keys`)
--     clicks the secure button. Its PostClick then sends Enter to the core.
--     Enter on any other action goes to the core.
-- When the list closes, or combat starts, the bindings are cleared and the
-- text box gets the focus back (unless the bar closed).
--
-- Combat: override bindings and keyboard propagation cannot change in
-- combat, so a binding left behind would keep the player's Enter until
-- combat ends. Seek sets them only outside the lockdown, and clears them on
-- PLAYER_REGEN_DISABLED, which comes just before the lockdown starts. In
-- combat, the list works from the text box, as without use actions, and
-- the core shows use actions as blocked.
local keys = CreateFrame("Frame", nil, frame)
keys:SetAllPoints()
keys:EnableKeyboard(false)

local listKeys = false -- `keys` has the keyboard
local enterBound = false -- Enter clicks the secure button

-- True from PLAYER_REGEN_DISABLED to PLAYER_REGEN_ENABLED. The lockdown
-- itself starts just after the first and ends just before the second; Seek
-- leaves the list keys at the first.
local inCombat = InCombatLockdown()

-- Binds Enter (and the number pad's Enter) to a click on the secure button,
-- or clears that. Never in the lockdown.
local function BindEnter(bind)
  if bind == enterBound or InCombatLockdown() then
    return
  end
  if bind then
    SetOverrideBindingClick(keys, true, "ENTER", ns.USE_BUTTON_NAME, "LeftButton")
    SetOverrideBindingClick(keys, true, "NUMPADENTER", ns.USE_BUTTON_NAME, "LeftButton")
  else
    ClearOverrideBindings(keys)
  end
  enterBound = bind
end

-- Gives the keyboard back from the list keys. `focus` gives the focus back
-- to the text box. EnableKeyboard works in combat on a plain frame.
local function LeaveListKeys(focus)
  BindEnter(false)
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

-- Takes or gives back the keyboard for the action list, as the view says.
local function RenderKeys(view)
  if view.open and view.actionList and not inCombat and not InCombatLockdown() then
    box:ClearFocus()
    keys:EnableKeyboard(true)
    listKeys = true
    BindEnter(UseActionReady(SelectedAction(view)))
  else
    LeaveListKeys(view.open)
  end
end

-- Shows a view state from the core.
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
-- its own.
box:SetScript("OnEnterPressed", function()
  PressEnter()
end)

-- Tab opens the selected result's action list; with no results it does
-- nothing. This replaces the template's handler, which would move the focus
-- to another text box.
box:SetScript("OnTabPressed", function()
  Render(session:PressKey("TAB"))
end)

-- While the text box has focus, key bindings do not fire. Catch the Seek
-- binding's key here, so the same key also closes the bar.
box:SetScript("OnKeyDown", function(_, key)
  if GetBindingAction(CreateKeyChordStringUsingMetaKeyState(key)) == "SEEK_TOGGLE" then
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
  if enterBound and (chord == "ENTER" or chord == "NUMPADENTER") then
    -- On to the override binding, which clicks the secure button.
    self:SetPropagateKeyboardInput(true)
    return
  end
  self:SetPropagateKeyboardInput(false)
  if GetBindingAction(chord) == "SEEK_TOGGLE" then
    ns.ToggleSearchBar()
    return
  end
  if key == "ENTER" or key == "NUMPADENTER" then
    PressEnter()
  elseif key == "ESCAPE" or key == "TAB" or key == "UP" or key == "DOWN" then
    Render(session:PressKey(key))
  end
end)

-- The secure button has run the prepared use action (adapters/wow/
-- Actions.lua): the core runs Enter, which closes the bar.
function ns.OnUseButtonClicked()
  if enterBound then
    Render(session:PressKey("ENTER"))
  end
end

-- Leave the list keys at the last moment before the lockdown, and take them
-- again after combat (the core also updates the view on both: the blocked
-- signs).
local combatEvents = CreateFrame("Frame")
combatEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
combatEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEvents:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    LeaveListKeys(frame:IsShown())
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
