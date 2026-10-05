-- The settings store: keeps the player's settings and decides what is
-- saved. The WoW settings adapter makes one from the saved variables, and
-- connects it to Seek's page in the game's Options window and to the
-- Settings port (Settings.lua). Plain Lua, so tests can check the saving
-- rules.
--
-- The saving rules (ADR 0004): the store saves a setting only when the
-- player changed it. An unchanged setting gives its current default from
-- the code, so a changed default in a later version reaches the players
-- who never changed it. A setting that the player puts back to its default
-- counts as unchanged again (this is also how the page's Defaults button
-- resets it).
--
-- Account and character: the settings are account-wide, until the player
-- turns on the switch "use settings for this character only". Then all of
-- them come from the character's own settings, and a change changes only
-- those. The first time it is turned on, the character's settings start
-- from the account's. Turned off, the character uses the account's
-- settings again; its own are kept, and come back when the switch is
-- turned on again. Defaults reset only the settings in use: the account's,
-- or the character's.
--
-- The saved data, one table for each scope:
--   account    { version, values }  the account's changed settings (by name)
--   character  { version, characterOnly, values }  the switch, and the
--              character's own changed settings; `values` is nil until the
--              switch was first turned on
local _, ns = ...

-- The saved settings' shape. Saved data from before settings has none, and
-- loads with the defaults. When the shape changes, raise this and convert
-- the older shape in LoadValues, so that players keep their settings; data
-- of an unknown version is ignored.
local SAVED_VERSION = 1

local SettingsStore = {}
SettingsStore.__index = SettingsStore

-- Whether `value` is one of a choice setting's values.
local function IsChoice(definition, value)
  for _, choice in ipairs(definition.values) do
    if value == choice then
      return true
    end
  end
  return false
end

-- A setting's value as the store keeps it, or nil when `value` does not fit
-- the setting's definition: another type than the default's, a number that
-- is not whole or is outside the lowest and highest value, or not one of a
-- choice setting's values.
local function Valid(definition, value)
  if type(value) ~= type(definition.default) then
    return nil
  end
  if type(value) == "number" and (value % 1 ~= 0 or value < definition.min or value > definition.max) then
    return nil
  end
  if definition.values and not IsChoice(definition, value) then
    return nil
  end
  return value
end

-- The changed settings from saved data of one scope, if it has the right
-- shape: a table of values by name. Values that no longer fit are left out.
local function LoadValues(definitions, saved)
  if type(saved) ~= "table" or saved.version ~= SAVED_VERSION or type(saved.values) ~= "table" then
    return nil
  end
  local values = {}
  for name, definition in pairs(definitions) do
    values[name] = Valid(definition, saved.values[name])
  end
  return values
end

-- A value that the player set, made to fit: a number is rounded to a whole
-- number (a slider can give 11.9999) and kept within its lowest and highest
-- value.
local function Fit(definition, value)
  if type(value) == "number" and type(definition.default) == "number" then
    value = math.floor(value + 0.5)
    return math.max(definition.min, math.min(definition.max, value))
  end
  return value
end

-- Copies a table of values.
local function Copy(values)
  local copy = {}
  for name, value in pairs(values) do
    copy[name] = value
  end
  return copy
end

-- A new store.
--   definitions  each setting by name: its default, and for a number its
--                lowest and highest value, or for a choice its values
--                (ns.settings)
--   saved        the saved data as the last store saved it: { account,
--                character } (each nil when there is none)
--   onChanged    called as onChanged(name) each time a setting's value
--                changes (also when the switch changes it)
function ns.NewSettingsStore(definitions, saved, onChanged)
  local character = LoadValues(definitions, saved.character)
  return setmetatable({
    definitions = definitions,
    account = LoadValues(definitions, saved.account) or {},
    character = character,
    characterOnly = character ~= nil and saved.character.characterOnly == true,
    onChanged = onChanged,
  }, SettingsStore)
end

-- The changed settings in use: the account's, or the character's own.
local function InUse(store)
  if store.characterOnly then
    return store.character
  end
  return store.account
end

-- A setting's value: the player's, or its default.
function SettingsStore:Get(name)
  local value = InUse(self)[name]
  if value == nil then
    return self.definitions[name].default
  end
  return value
end

-- The player changed a setting. Its default makes it unchanged again. A
-- value of another type is ignored.
function SettingsStore:Set(name, value)
  local definition = self.definitions[name]
  local old = self:Get(name)
  value = Valid(definition, Fit(definition, value))
  if value == nil then
    return
  end
  if value == definition.default then
    value = nil
  end
  InUse(self)[name] = value
  if self:Get(name) ~= old then
    self.onChanged(name)
  end
end

-- Whether the character uses its own settings.
function SettingsStore:CharacterOnly()
  return self.characterOnly
end

-- Turns the switch to the character's own settings on or off.
function SettingsStore:SetCharacterOnly(on)
  local old = {}
  for name in pairs(self.definitions) do
    old[name] = self:Get(name)
  end
  on = on == true
  if on and not self.character then
    self.character = Copy(self.account)
  end
  self.characterOnly = on
  for name in pairs(self.definitions) do
    if self:Get(name) ~= old[name] then
      self.onChanged(name)
    end
  end
end

-- The data to save, for the next store (plain tables).
function SettingsStore:Saved()
  return {
    account = { version = SAVED_VERSION, values = self.account },
    character = { version = SAVED_VERSION, characterOnly = self.characterOnly, values = self.character },
  }
end
