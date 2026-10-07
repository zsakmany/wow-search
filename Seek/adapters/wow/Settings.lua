-- The WoW settings adapter (core/Settings.lua): Seek's page under the
-- AddOns tab of the game's Options window, and the saved settings. The
-- settings store (core/SettingsStore.lua) keeps them and decides what is
-- saved; this adapter loads it from the saved variables, saves it after
-- each change, and tells the core about each changed value.
--
-- The saved variables (see the TOC): SeekSettings, account-wide, and
-- SeekCharacterSettings, per character. WoW sets them from the files and
-- then sends ADDON_LOADED for Seek; only then does the store load, and the
-- page appear. Until then the core uses the defaults.
--
-- The page uses proxy settings (ADR 0004): Blizzard's page asks the store
-- for each value (the getter) and hands each change to the store (the
-- setter), and never sees Seek's saved tables. So Blizzard never writes a
-- default into them. The page's Defaults button sets each setting to its
-- default through the same setter, and the store then forgets the player's
-- value in the settings in use (the account's, or the character's own).
-- The character switch has no default (Settings.CannotDefault), so Defaults
-- leaves it as it is.
--
-- Under "Show other characters' bags", the button "Remove a character…"
-- removes another character's saved bags (a removed character, see
-- GLOSSARY.md; core/CharacterBags.lua), with its explanation under it. It is
-- not a setting: nothing of it is saved in the settings, and Defaults does
-- not touch it. A click opens the game's menu (Blizzard_Menu) of the saved
-- characters, made anew on each click, and a click on a name asks first in
-- Seek's own dialog (adapters/wow/RemoveCharacterDialog.lua).
--
-- Taint: the page is built only with the Settings API's own calls, and
-- Seek never writes into the Options window's frames (issue #25). The
-- button is Blizzard's button row (CreateSettingsButtonInitializer), with
-- Seek's click function; the explanation is a row of Seek's own template
-- (SettingsText.xml), which the page creates and fills through the row's
-- initializer. The page's list calls each row's initializer only through
-- securecallfunction (Blizzard_SettingsList.lua), so Seek's code there does
-- not taint the list. The menu system is made for addons' menus
-- (Blizzard_Menu's guide, "Taint"), but one write of it is Seek's: when
-- the menu opens from Seek's click, it stops the Options window's list from
-- scrolling under it (MenuManagerMixin:DisableScrollableRegions, the list's
-- SetScrollAllowed). Closing the menu by a pick, a click elsewhere, or
-- Escape runs in Blizzard's own code and allows the scrolling again
-- cleanly. Only when the Options window closes while the menu is still
-- open does that flag stay written by Seek; the list's scrolling is not
-- protected, so it should cost nothing. The game test of #45 checks it.
--
-- Combat: removing a character saves at once, but its items leave the
-- results only when combat ends, when Seek reads the other characters'
-- bags again (ADR 0002).
local addonName, ns = ...

local L = ns.L

local store -- the settings store, once the saved variables are loaded
local page -- Seek's page in the Options window

-- Blizzard's setting objects for the settings that the character switch
-- changes: the visible results slider, the tooltip side dropdown, and the
-- other characters' bags and minimap icon checkboxes.
local pageSettings = {}

ns.SetSettings({
  Get = function(_, name)
    return store and store:Get(name)
  end,
})

-- Saves the store's data into the saved variables; WoW writes them to the
-- files at logout and /reload.
local function Save()
  local saved = store:Saved()
  SeekSettings = saved.account
  SeekCharacterSettings = saved.character
end

-- The labels of the tooltip side setting's values.
local SIDE_LABELS = {
  right = L.SETTING_TOOLTIP_SIDE_RIGHT,
  left = L.SETTING_TOOLTIP_SIDE_LEFT,
  off = L.SETTING_TOOLTIP_SIDE_OFF,
}

-- The tooltip side dropdown's choices, in the order of the setting's values.
local function TooltipSideChoices()
  local container = Settings.CreateControlTextContainer()
  for _, side in ipairs(ns.settings.tooltipSide.values) do
    container:Add(side, SIDE_LABELS[side])
  end
  return container:GetData()
end

-- Registers a proxy setting on the page for the store's setting `name`:
-- the page reads the value from the store, and hands each change to the
-- store, which saves it. `variable` is the setting's unique name for
-- Blizzard. Returns Blizzard's setting object.
local function StoreSetting(variable, name, label)
  local default = ns.settings[name].default
  local setting = Settings.RegisterProxySetting(page, variable, type(default), label, default,
    function()
      return store:Get(name)
    end,
    function(value)
      store:Set(name, value)
      Save()
    end)
  pageSettings[#pageSettings + 1] = setting
  return setting
end

-- The menu of the "Remove a character…" button: the other characters whose
-- bags Seek keeps, by name, read anew on each click. A click on a name asks
-- first (adapters/wow/RemoveCharacterDialog.lua), and closes the menu.
local function RemoveCharacterMenu(_, root)
  local characters = ns.OtherCharacters()
  if #characters == 0 then
    root:CreateTitle(L.SETTING_REMOVE_CHARACTER_NONE)
    return
  end
  for _, character in ipairs(characters) do
    root:CreateButton(character.shownName, function()
      ns.ConfirmRemoveCharacter(character)
    end)
  end
end

-- The "Remove a character…" button and its explanation under it (see the
-- top of this file). The button has no name, so it starts where the other
-- rows' names start, and Seek's game option source leaves it out (rows
-- with no name). Its text is in the Options window's search
-- (addSearchTags).
local function AddRemoveCharacter(layout)
  local button = CreateSettingsButtonInitializer("", L.SETTING_REMOVE_CHARACTER, function(self)
    MenuUtil.CreateContextMenu(self, RemoveCharacterMenu)
  end, nil, true)
  layout:AddInitializer(button)

  local explanation = Settings.CreateElementInitializer("SeekSettingsTextTemplate", {})
  function explanation.InitFrame(_, frame)
    frame.Text:SetText(L.SETTING_REMOVE_CHARACTER_EXPLANATION)
  end
  layout:AddInitializer(explanation)
end

-- The page: the character switch, the visible results slider, the tooltip
-- side dropdown, the other characters' bags checkbox with the "Remove a
-- character…" button, and the minimap icon checkbox.
local function RegisterPage()
  local layout
  page, layout = Settings.RegisterVerticalLayoutCategory(L.NAME)

  -- The switch changes which values the other settings show, so the page
  -- reads them again.
  local characterOnly = Settings.RegisterProxySetting(page, "SEEK_CHARACTER_ONLY",
    Settings.VarType.Boolean, L.SETTING_CHARACTER_ONLY, Settings.CannotDefault,
    function()
      return store:CharacterOnly()
    end,
    function(value)
      store:SetCharacterOnly(value)
      Save()
      for _, setting in ipairs(pageSettings) do
        setting:NotifyUpdate()
      end
    end)
  Settings.CreateCheckbox(page, characterOnly, L.SETTING_CHARACTER_ONLY_TOOLTIP)

  local visibleResults = ns.settings.visibleResults
  local visibleResultsSetting = StoreSetting("SEEK_VISIBLE_RESULTS", "visibleResults", L.SETTING_VISIBLE_RESULTS)
  local options = Settings.CreateSliderOptions(visibleResults.min, visibleResults.max, 1)
  -- The label shows a whole number, also while the slider is between steps.
  options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
    return tostring(math.floor(value + 0.5))
  end)
  Settings.CreateSlider(page, visibleResultsSetting, options, L.SETTING_VISIBLE_RESULTS_TOOLTIP)

  local tooltipSideSetting = StoreSetting("SEEK_TOOLTIP_SIDE", "tooltipSide", L.SETTING_TOOLTIP_SIDE)
  Settings.CreateDropdown(page, tooltipSideSetting, TooltipSideChoices, L.SETTING_TOOLTIP_SIDE_TOOLTIP)

  local otherCharactersBagsSetting = StoreSetting("SEEK_OTHER_CHARACTERS_BAGS", "otherCharactersBags",
    L.SETTING_OTHER_CHARACTERS_BAGS)
  Settings.CreateCheckbox(page, otherCharactersBagsSetting, L.SETTING_OTHER_CHARACTERS_BAGS_TOOLTIP)
  AddRemoveCharacter(layout)

  local minimapIconSetting = StoreSetting("SEEK_MINIMAP_ICON", "minimapIcon", L.SETTING_MINIMAP_ICON)
  Settings.CreateCheckbox(page, minimapIconSetting, L.SETTING_MINIMAP_ICON_TOOLTIP)

  Settings.RegisterAddOnCategory(page)
  -- The game option source lists the page's settings as game options.
  ns.GameOptionPageAdded()
end

-- Seek's page in the Options window, or nil before it is registered.
function ns.SettingsPage()
  return page
end

-- Opens the Options window at Seek's page (/seek settings, a right click on
-- the Seek entry in the addon button at the minimap or on the minimap
-- icon).
function ns.OpenSettings()
  if page then
    Settings.OpenToCategory(page:GetID())
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
  if name == addonName then
    self:UnregisterEvent("ADDON_LOADED")
    store = ns.NewSettingsStore(ns.settings, { account = SeekSettings, character = SeekCharacterSettings },
      ns.SettingChanged)
    -- The core used the defaults until now; tell it the loaded values.
    for setting in pairs(ns.settings) do
      ns.SettingChanged(setting)
    end
    RegisterPage()
  end
end)
