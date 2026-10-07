-- The confirmation window: a question, such as "Forget all picks of this
-- character? …", with Yes and No, before Seek does something that cannot
-- be undone. A button on Seek's settings page (adapters/wow/Settings.lua)
-- opens it with its question and the function to run on Yes. Only Yes runs
-- it; No, the window's close button, and Escape do nothing.
--
-- Seek's own small window, not the game's StaticPopup: StaticPopup's frames
-- and its table of dialogs (StaticPopupDialogs) are shared Blizzard UI, and
-- a popup that addon code adds and shows taints them, so the game can then
-- block Blizzard's own popups (such as the one that deletes an item). This
-- window shares nothing with Blizzard's: of the Options window it only asks
-- whether it is shown (issue #25: never write into the Options window).
--
-- It is not in UISpecialFrames: Escape first closes the Options window
-- (the game's Escape order puts it before the addons' windows), and this
-- window closes with it, as No does.
local _, ns = ...

local L = ns.L

local WIDTH = 360
local TEXT_TOP = 34 -- between the window's top edge and the question
local TEXT_INSET = 18 -- between the window's left and right edges and the question
local BUTTON_WIDTH = 110
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 12 -- between the Yes and No buttons
local BUTTON_BOTTOM = 14 -- between the buttons and the window's bottom edge
local TEXT_BUTTON_GAP = 16 -- between the question and the buttons

-- The function to run on Yes, while the window is shown.
local onYes

-- Blizzard-style window, like the search bar's, in the middle of the
-- screen. Its strata is above the Options window's (HIGH).
local window = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
window:SetWidth(WIDTH)
window:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
window:SetFrameStrata("DIALOG")
window:SetToplevel(true)
window:EnableMouse(true)
window.TitleText:SetText(L.NAME)
window:Hide()

local question = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
-- A fixed width (not two anchors), so that its height is known at once for
-- the window's height.
question:SetPoint("TOP", window, "TOP", 0, -TEXT_TOP)
question:SetWidth(WIDTH - 2 * TEXT_INSET)
question:SetJustifyH("CENTER")

local yes = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
yes:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
yes:SetPoint("BOTTOMRIGHT", window, "BOTTOM", -BUTTON_GAP / 2, BUTTON_BOTTOM)
yes:SetText(L.CONFIRM_YES)

local no = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
no:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
no:SetPoint("BOTTOMLEFT", window, "BOTTOM", BUTTON_GAP / 2, BUTTON_BOTTOM)
no:SetText(L.CONFIRM_NO)

yes:SetScript("OnClick", function()
  local run = onYes
  window:Hide()
  if run then
    run()
  end
end)

no:SetScript("OnClick", function()
  window:Hide()
end)

window:SetScript("OnHide", function()
  onYes = nil
end)

-- Close with the Options window (see the top of this file).
window:SetScript("OnUpdate", function(self)
  if not SettingsPanel:IsShown() then
    self:Hide()
  end
end)

-- Asks `text`, and runs `run` (with no arguments) if the player clicks Yes.
-- A new question replaces one that is still open.
function ns.Confirm(text, run)
  onYes = run
  question:SetText(text)
  window:SetHeight(TEXT_TOP + question:GetStringHeight() + TEXT_BUTTON_GAP + BUTTON_HEIGHT + BUTTON_BOTTOM)
  window:Show()
  window:Raise()
end
