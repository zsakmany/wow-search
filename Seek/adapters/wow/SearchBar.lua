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

-- Shows the query, the hint, the result rows, and the "no results" text.
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

box:SetScript("OnTextChanged", function(self, userInput)
  if userInput then
    Render(session:SetQuery(self:GetText()))
  end
end)

box:SetScript("OnEscapePressed", function()
  Render(session:PressKey("ESCAPE"))
end)

box:SetScript("OnArrowPressed", function(_, key)
  if key == "UP" or key == "DOWN" then
    Render(session:PressKey(key))
  end
end)

-- Enter runs the selected result's main action and closes the bar; with no
-- results it does nothing. The core decides; the handler also keeps the
-- text box from losing focus on its own.
box:SetScript("OnEnterPressed", function()
  Render(session:PressKey("ENTER"))
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
