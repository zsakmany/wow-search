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
local addonName, ns = ...

local L = ns.L

local store -- the settings store, once the saved variables are loaded
local page -- Seek's page in the Options window

-- Blizzard's setting objects for the settings that the character switch
-- changes: the visible results slider, the tooltip side dropdown, and the
-- other characters' bags checkbox.
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

-- The page: the character switch, the visible results slider, the tooltip
-- side dropdown, and the other characters' bags checkbox.
local function RegisterPage()
  page = Settings.RegisterVerticalLayoutCategory(L.NAME)

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

  Settings.RegisterAddOnCategory(page)
end

-- Opens the Options window at Seek's page (/seek settings, a right click on
-- the Seek entry in the addon button at the minimap).
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
