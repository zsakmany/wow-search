-- The search bar window: a driving adapter (docs/adr/0003). It sends open,
-- close, the query, and key presses to the core's search session, and shows
-- the view state that comes back. It keeps no search state of its own.
--
-- A plain (not protected) frame, so it can open and close in combat.
local _, ns = ...

local L = ns.L

local VISIBLE_ROWS = 8 -- the core sends at most this many result rows
local ROW_HEIGHT = 24
local TOP_HEIGHT = 64 -- the title bar and the text box
local QUESTION_MARK_ICON = 134400 -- for an entry without an icon
local LIST_ROW_HEIGHT = 20
local LIST_PADDING = 8 -- between the action list's border and its rows
local LIST_MIN_WIDTH = 140

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

-- The result rows: icon, name, and kind. The selected row is lit.
local rows = {}
for i = 1, VISIBLE_ROWS do
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

    listRows[i] = row
  end
  return row
end

-- Shows the action list next to the selected result row, or hides it. The
-- list is as wide as its longest label.
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
    row.selection:SetShown(action.selected)
    row:Show()
    width = math.max(width, math.ceil(row.label:GetStringWidth()) + 12 + 2 * LIST_PADDING)
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

  for i, row in ipairs(rows) do
    local result = view.results[i]
    if result then
      row.icon:SetTexture(result.icon or QUESTION_MARK_ICON)
      row.name:SetText(result.name)
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

-- Shows a view state from the core.
function Render(view)
  RenderContent(view)
  if view.open then
    if not frame:IsShown() then
      frame:Show()
      -- Take the focus one frame later. The key that opened the bar (for
      -- example Cmd+K) also sends its letter, and with focus now, that "k"
      -- would land in the text box.
      C_Timer.After(0, function()
        if frame:IsShown() then
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
-- when the action list is open, and closes the bar; with no results it does
-- nothing. The core decides; the handler also keeps the text box from
-- losing focus on its own.
box:SetScript("OnEnterPressed", function()
  Render(session:PressKey("ENTER"))
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
