-- The Settings port: the player's settings (see GLOSSARY.md), such as the
-- number of visible results. The WoW settings adapter plugs in when the
-- addon loads (it connects Seek's page in the game's Options window to the
-- settings store, SettingsStore.lua); tests plug in fake settings that they
-- change.
--
-- A settings adapter is a table with one method:
--   Get(name)  the setting's value, or nil for its default
-- It also tells the core when a setting's value changes, by calling
-- ns.SettingChanged(name).
--
-- Any part of the core can ask ns.Setting(name), or watch changes with
-- ns.WatchSettings(). A change takes effect at once, with no /reload.
local _, ns = ...

-- Each setting: its default, and the lowest and highest value (for a
-- number) or the values it can have (for a choice); a setting with a
-- true or false default is a switch. A changed default here
-- reaches every player who has not changed the setting (ADR 0004).
ns.settings = {
  -- How many result rows the search bar shows at once, and how many
  -- recently picked things the empty search bar shows.
  visibleResults = { default = 8, min = 3, max = 15 },
  -- Where the search bar shows the WoW tooltip of the selected
  -- result: to its right, to its left, or nowhere.
  tooltipSide = { default = "right", values = { "right", "left", "off" } },
  -- Whether search shows the items in the bags of the player's other
  -- characters (CharacterBags.lua).
  otherCharactersBags = { default = true },
}

local adapter
local watchers = {}

function ns.SetSettings(settings)
  adapter = settings
end

-- A setting's value: the adapter's, or the default when no adapter is
-- plugged in or it gives nil or a value of another type.
function ns.Setting(name)
  local default = ns.settings[name].default
  local value = adapter and adapter:Get(name)
  if type(value) ~= type(default) then
    return default
  end
  return value
end

-- Calls `watcher(name)` each time a setting's value changes.
function ns.WatchSettings(watcher)
  watchers[#watchers + 1] = watcher
end

-- The settings adapter calls this when a setting's value changed.
function ns.SettingChanged(name)
  for _, watcher in ipairs(watchers) do
    watcher(name)
  end
end
