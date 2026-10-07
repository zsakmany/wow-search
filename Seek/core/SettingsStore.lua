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
-- resets it). A set of names (such as the hidden characters) is its default
-- when it has the same names; the store keeps its own copy of each set, so
-- that no caller can change the store's values.
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

-- A set of names as the store keeps it: its own copy, with only the names
-- (strings) that are in it (true).
local function NameSet(value)
  local set = {}
  for name, inSet in pairs(value) do
    if type(name) == "string" and inSet == true then
      set[name] = true
    end
  end
  return set
end

-- A setting's value as the store keeps it, or nil when `value` does not fit
-- the setting's definition: another type than the default's, a number that
-- is not whole or is outside the lowest and highest value, or not one of a
-- choice setting's values. A set of names is copied, so that a change of
-- the caller's table does not change the store.
local function Valid(definition, value)
  if type(value) ~= type(definition.default) then
    return nil
  end
  if type(value) == "table" then
    return NameSet(value)
  end
  if type(value) == "number" and (value % 1 ~= 0 or value < definition.min or value > definition.max) then
    return nil
  end
  if definition.values and not IsChoice(definition, value) then
    return nil
  end
  return value
end

-- Whether two values of a setting are the same: for a set of names, the
-- same names.
local function Same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for name in pairs(a) do
    if not b[name] then
      return false
    end
  end
  for name in pairs(b) do
    if not a[name] then
      return false
    end
  end
  return true
end

-- The changed settings from saved data of one scope, if it has the right
-- shape: a table of values by name. Values that no longer fit are left out.
--
-- Saved data from before hidden characters can have the setting
-- otherCharactersBags ("Show other characters' bags"), which hid all other
-- characters at once, on every character of the account. Off, it becomes
-- the hidden characters: each of `knownCharacters`, every character whose
-- bags Seek keeps now. That is the current character too, so that its
-- items stay hidden when the player logs in on another character; the
-- current character never sees its own items as another's, so hiding it
-- costs nothing. On (its default), nothing changes. The store does not
-- save it again, so this happens only once. A saved value that is the
-- same as the default (such as an empty set) counts as not saved.
local function LoadValues(definitions, saved, knownCharacters)
  if type(saved) ~= "table" or saved.version ~= SAVED_VERSION or type(saved.values) ~= "table" then
    return nil
  end
  local values = {}
  for name, definition in pairs(definitions) do
    local value = Valid(definition, saved.values[name])
    if value ~= nil and not Same(value, definition.default) then
      values[name] = value
    end
  end
  if saved.values.otherCharactersBags == false and values.hiddenCharacters == nil and knownCharacters[1] then
    local hidden = {}
    for _, owner in ipairs(knownCharacters) do
      hidden[owner] = true
    end
    values.hiddenCharacters = hidden
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

-- Copies a table of values. A set of names in it is not copied: the store
-- replaces a set, but never changes one.
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
--   knownCharacters
--                (optional) every character whose bags Seek keeps now, the
--                current one too, by owner ("Name-Realm"), for saved data
--                from before hidden characters (see LoadValues)
function ns.NewSettingsStore(definitions, saved, onChanged, knownCharacters)
  knownCharacters = knownCharacters or {}
  local character = LoadValues(definitions, saved.character, knownCharacters)
  return setmetatable({
    definitions = definitions,
    account = LoadValues(definitions, saved.account, knownCharacters) or {},
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

-- A setting's value: the player's, or its default. A set of names is a
-- copy, which the caller may change.
function SettingsStore:Get(name)
  local value = InUse(self)[name]
  if value == nil then
    value = self.definitions[name].default
  end
  if type(value) == "table" then
    return NameSet(value)
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
  if Same(value, definition.default) then
    value = nil
  end
  InUse(self)[name] = value
  if not Same(self:Get(name), old) then
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
    if not Same(self:Get(name), old[name]) then
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
