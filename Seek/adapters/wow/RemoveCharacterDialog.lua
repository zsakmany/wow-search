-- The question before Seek removes a character (a removed character, see
-- GLOSSARY.md): "Remove Bob? …", with Yes and No. A click on a name in the
-- menu of the "Remove a character…" button on Seek's settings page
-- (adapters/wow/Settings.lua) opens it. Only Yes removes the character.
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

-- The character that the window asks about ("Name-Realm"), while it is
-- shown.
local owner

-- Blizzard-style window, like the search bar's, in the middle of the
-- screen, above the Options window.
local dialog = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
dialog:SetWidth(WIDTH)
dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
dialog:SetFrameStrata("DIALOG")
dialog:SetToplevel(true)
dialog:EnableMouse(true)
dialog.TitleText:SetText(L.NAME)
dialog:Hide()

local question = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
-- A fixed width (not two anchors), so that its height is known at once for
-- the window's height.
question:SetPoint("TOP", dialog, "TOP", 0, -TEXT_TOP)
question:SetWidth(WIDTH - 2 * TEXT_INSET)
question:SetJustifyH("CENTER")

local yes = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
yes:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
yes:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -BUTTON_GAP / 2, BUTTON_BOTTOM)
yes:SetText(L.REMOVE_CHARACTER_YES)

local no = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
no:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
no:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", BUTTON_GAP / 2, BUTTON_BOTTOM)
no:SetText(L.REMOVE_CHARACTER_NO)

yes:SetScript("OnClick", function()
  local removed = owner
  dialog:Hide()
  if removed then
    ns.RemoveCharacter(removed)
  end
end)

no:SetScript("OnClick", function()
  dialog:Hide()
end)

dialog:SetScript("OnHide", function()
  owner = nil
end)

-- Close with the Options window (see the top of this file).
dialog:SetScript("OnUpdate", function(self)
  if not SettingsPanel:IsShown() then
    self:Hide()
  end
end)

-- Asks whether to remove `character`, one of ns.OtherCharacters(): its
-- `owner` and its `name` as Seek shows it. A new question replaces one
-- that is still open.
function ns.ConfirmRemoveCharacter(character)
  owner = character.owner
  question:SetText(L.REMOVE_CHARACTER_QUESTION:format(character.shownName))
  dialog:SetHeight(TEXT_TOP + question:GetStringHeight() + TEXT_BUTTON_GAP + BUTTON_HEIGHT + BUTTON_BOTTOM)
  dialog:Show()
  dialog:Raise()
end
