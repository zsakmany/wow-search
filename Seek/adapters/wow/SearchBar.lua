-- The search bar window: a driving adapter (docs/adr/0003). It sends open,
-- close, the query, and key presses to the core's search session, and shows
-- the view state that comes back. It keeps no search state of its own.
--
-- A plain (not protected) frame, so it can open and close in combat.
local _, ns = ...

local L = ns.L

local session = ns.NewSearchSession()

-- Blizzard-style window at the top center of the screen. Not movable.
local frame = CreateFrame("Frame", "SeekSearchBar", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(420, 64)
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
box:SetPoint("LEFT", frame, "LEFT", 18, -10)
box:SetPoint("RIGHT", frame, "RIGHT", -14, -10)
box:SetAutoFocus(false)

local hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
hint:SetPoint("LEFT", box, "LEFT", 0, 0)

-- Shows a view state from the core.
local function Render(view)
  if box:GetText() ~= view.query then
    box:SetText(view.query)
  end
  hint:SetText(view.hint or "")
  hint:SetShown(view.hint ~= nil)
  if view.open then
    frame:Show()
    -- Take the focus one frame later. The key that opened the bar (for
    -- example Cmd+K) also sends its letter, and with focus now, that "k"
    -- would land in the text box.
    C_Timer.After(0, function()
      if frame:IsShown() then
        box:SetFocus()
      end
    end)
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
