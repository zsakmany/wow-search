-- The settings store (core/SettingsStore.lua), through its public
-- functions: the saving rules for the player's settings (ADR 0004), and
-- the switch between the account's settings and the character's own.
-- A "reload" here is a new store made from what the old one saved, as the
-- WoW settings adapter makes one from the saved variables.

local load_core = require("tests.load_core")

-- The settings as an older and a later version of Seek define them: the
-- later version has a new default.
local DEFINITIONS = { visibleResults = { default = 8, min = 3, max = 15 } }
local LATER_DEFINITIONS = { visibleResults = { default = 10, min = 3, max = 15 } }

describe("the settings store", function()
  local ns, changes

  before_each(function()
    ns = load_core()
    changes = {}
  end)

  -- A store with this saved data (nil: nothing saved yet). It writes down
  -- each setting that it says has changed.
  local function NewStore(saved, definitions)
    return ns.NewSettingsStore(definitions or DEFINITIONS, saved or {}, function(name)
      changes[#changes + 1] = name
    end)
  end

  describe("saving", function()
    it("gives the default for a setting that the player has not changed", function()
      local store = NewStore()
      assert.are.equal(8, store:Get("visibleResults"))
    end)

    it("saves only the settings that the player changed", function()
      local store = NewStore()
      assert.are.same({}, store:Saved().account.values)
      store:Set("visibleResults", 12)
      assert.are.equal(12, store:Get("visibleResults"))
      assert.are.same({ visibleResults = 12 }, store:Saved().account.values)
    end)

    it("keeps a changed setting over a reload", function()
      local store = NewStore()
      store:Set("visibleResults", 12)
      assert.are.equal(12, NewStore(store:Saved()):Get("visibleResults"))
    end)

    it("saves nothing for a setting that the player puts back to its default", function()
      local store = NewStore()
      store:Set("visibleResults", 12)
      store:Set("visibleResults", 8)
      assert.are.same({}, store:Saved().account.values)
    end)

    it("an unchanged setting follows a changed default in a later version", function()
      local store = NewStore()
      store:Set("visibleResults", 12)
      store:Set("visibleResults", 8)
      assert.are.equal(10, NewStore(store:Saved(), LATER_DEFINITIONS):Get("visibleResults"))
    end)

    it("a changed setting keeps the player's value in a later version", function()
      local store = NewStore()
      store:Set("visibleResults", 12)
      assert.are.equal(12, NewStore(store:Saved(), LATER_DEFINITIONS):Get("visibleResults"))
    end)

    it("tells about a change only when the value changes", function()
      local store = NewStore()
      store:Set("visibleResults", 12)
      store:Set("visibleResults", 12)
      store:Set("visibleResults", 8)
      assert.are.same({ "visibleResults", "visibleResults" }, changes)
    end)
  end)

  describe("values that do not fit", function()
    it("rounds a number to a whole number within its lowest and highest value", function()
      local store = NewStore()
      store:Set("visibleResults", 11.9999)
      assert.are.equal(12, store:Get("visibleResults"))
      store:Set("visibleResults", 40)
      assert.are.equal(15, store:Get("visibleResults"))
      store:Set("visibleResults", 1)
      assert.are.equal(3, store:Get("visibleResults"))
    end)

    it("ignores a value of another type", function()
      local store = NewStore()
      store:Set("visibleResults", 12)
      store:Set("visibleResults", "5")
      store:Set("visibleResults", nil)
      assert.are.equal(12, store:Get("visibleResults"))
    end)

    it("ignores saved values that no longer fit", function()
      local store = NewStore({ account = { version = 1, values = { visibleResults = 99, gone = true } } })
      assert.are.equal(8, store:Get("visibleResults"))
      assert.are.same({}, store:Saved().account.values)
      assert.are.equal(8, NewStore({ account = { version = 1, values = { visibleResults = 10.5 } } })
        :Get("visibleResults"))
    end)

    it("ignores saved settings of an unknown version", function()
      local store = NewStore({
        account = { version = 99, values = { visibleResults = 12 } },
        character = { version = 99, characterOnly = true, values = { visibleResults = 5 } },
      })
      assert.is_false(store:CharacterOnly())
      assert.are.equal(8, store:Get("visibleResults"))
    end)
  end)

  describe("the switch to the character's own settings", function()
    -- What a character saves: the account's settings are shared by all
    -- characters, each character has its own.
    local account

    -- The store of one character, after a login: the shared account
    -- settings and this character's own saved settings.
    local function Login(character)
      return NewStore({ account = account, character = character })
    end

    -- Saves a store's data as WoW does at logout; returns the character's.
    local function Logout(store)
      local saved = store:Saved()
      account = saved.account
      return saved.character
    end

    before_each(function()
      account = nil
      local store = Login(nil)
      store:Set("visibleResults", 12)
      Logout(store)
      changes = {}
    end)

    it("is off at first: the character uses the account's settings", function()
      local store = Login(nil)
      assert.is_false(store:CharacterOnly())
      assert.are.equal(12, store:Get("visibleResults"))
    end)

    it("turned on, starts the character's own settings from the account's", function()
      local store = Login(nil)
      store:SetCharacterOnly(true)
      assert.is_true(store:CharacterOnly())
      assert.are.equal(12, store:Get("visibleResults"))
      assert.are.same({}, changes)
    end)

    it("turned on, changes only the character's own settings", function()
      local store = Login(nil)
      store:SetCharacterOnly(true)
      store:Set("visibleResults", 5)
      assert.are.equal(5, store:Get("visibleResults"))
      local character = Logout(store)

      -- Another character still uses the account's settings.
      assert.are.equal(12, Login(nil):Get("visibleResults"))
      -- This character keeps its own over a reload.
      store = Login(character)
      assert.is_true(store:CharacterOnly())
      assert.are.equal(5, store:Get("visibleResults"))
    end)

    it("turned off, uses the account's settings and keeps the character's for later", function()
      local store = Login(nil)
      store:SetCharacterOnly(true)
      store:Set("visibleResults", 5)
      changes = {}

      store:SetCharacterOnly(false)
      assert.is_false(store:CharacterOnly())
      assert.are.equal(12, store:Get("visibleResults"))
      assert.are.same({ "visibleResults" }, changes)

      -- Turned on again, even after a reload, the character's own values
      -- come back, not the account's.
      store = Login(Logout(store))
      store:SetCharacterOnly(true)
      assert.are.equal(5, store:Get("visibleResults"))
    end)

    it("saves only the settings that the player changed in the character's own", function()
      local store = Login(nil)
      store:SetCharacterOnly(true)
      store:Set("visibleResults", 8)
      assert.are.same({}, store:Saved().character.values)
      -- The account's settings stay as they are.
      assert.are.same({ visibleResults = 12 }, store:Saved().account.values)
    end)

    describe("the Defaults button", function()
      -- Blizzard's Defaults button sets each setting on the page to its
      -- default.
      local function PressDefaults(store)
        store:Set("visibleResults", DEFINITIONS.visibleResults.default)
      end

      it("with the switch on, resets only the character's settings", function()
        local store = Login(nil)
        store:SetCharacterOnly(true)
        PressDefaults(store)
        assert.are.equal(8, store:Get("visibleResults"))
        store:SetCharacterOnly(false)
        assert.are.equal(12, store:Get("visibleResults"))
      end)

      it("with the switch off, resets only the account's settings", function()
        local store = Login(nil)
        store:SetCharacterOnly(true)
        store:Set("visibleResults", 5)
        store:SetCharacterOnly(false)
        PressDefaults(store)
        assert.are.equal(8, store:Get("visibleResults"))
        store:SetCharacterOnly(true)
        assert.are.equal(5, store:Get("visibleResults"))
      end)
    end)
  end)
end)
