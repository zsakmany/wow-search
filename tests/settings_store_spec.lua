-- The settings store (core/SettingsStore.lua), through its public
-- functions: the saving rules for the player's settings (ADR 0004), and
-- the switch between the account's settings and the character's own.
-- A "reload" here is a new store made from what the old one saved, as the
-- WoW settings adapter makes one from the saved variables.

local load_core = require("tests.load_core")

-- The settings as an older and a later version of Seek define them: the
-- later version has a new default. The hidden characters are a set of
-- names.
local SIDES = { "right", "left", "off" }
local DEFINITIONS = {
  visibleResults = { default = 8, min = 3, max = 15 },
  tooltipSide = { default = "right", values = SIDES },
  hiddenCharacters = { default = {} },
}
local LATER_DEFINITIONS = {
  visibleResults = { default = 10, min = 3, max = 15 },
  tooltipSide = { default = "left", values = SIDES },
  hiddenCharacters = { default = {} },
}

describe("the settings store", function()
  local ns, changes

  before_each(function()
    ns = load_core()
    changes = {}
  end)

  -- A store with this saved data (nil: nothing saved yet), and the other
  -- characters whose bags Seek keeps (none when nil). It writes down each
  -- setting that it says has changed.
  local function NewStore(saved, definitions, otherCharacters)
    return ns.NewSettingsStore(definitions or DEFINITIONS, saved or {}, function(name)
      changes[#changes + 1] = name
    end, otherCharacters or {})
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

    it("saves a choice only when the player changed it, and follows a changed default", function()
      local store = NewStore()
      store:Set("tooltipSide", "off")
      assert.are.same({ tooltipSide = "off" }, store:Saved().account.values)
      assert.are.equal("off", NewStore(store:Saved(), LATER_DEFINITIONS):Get("tooltipSide"))
      store:Set("tooltipSide", "right")
      assert.are.same({}, store:Saved().account.values)
      assert.are.equal("left", NewStore(store:Saved(), LATER_DEFINITIONS):Get("tooltipSide"))
    end)

    it("saves a set of names only when it is not empty, and keeps it over a reload", function()
      local store = NewStore()
      store:Set("hiddenCharacters", { ["Bob-Stormrage"] = true })
      assert.are.same({ ["Bob-Stormrage"] = true }, store:Get("hiddenCharacters"))
      assert.are.same({ hiddenCharacters = { ["Bob-Stormrage"] = true } }, store:Saved().account.values)
      assert.are.same({ ["Bob-Stormrage"] = true }, NewStore(store:Saved()):Get("hiddenCharacters"))
      store:Set("hiddenCharacters", {})
      assert.are.same({}, store:Get("hiddenCharacters"))
      assert.are.same({}, store:Saved().account.values)
    end)

    it("keeps its own copy of a set: changing the set that Set got or Get gave changes nothing", function()
      local store = NewStore()
      local hidden = { ["Bob-Stormrage"] = true }
      store:Set("hiddenCharacters", hidden)
      hidden["Carol-ArgentDawn"] = true
      store:Get("hiddenCharacters")["Dave-Stormrage"] = true
      assert.are.same({ ["Bob-Stormrage"] = true }, store:Get("hiddenCharacters"))
      -- Also the default set.
      local fresh = NewStore()
      fresh:Get("hiddenCharacters")["Dave-Stormrage"] = true
      assert.are.same({}, fresh:Get("hiddenCharacters"))
      assert.are.same({}, DEFINITIONS.hiddenCharacters.default)
    end)

    it("tells about a set's change only when its names change", function()
      local store = NewStore()
      store:Set("hiddenCharacters", { ["Bob-Stormrage"] = true })
      store:Set("hiddenCharacters", { ["Bob-Stormrage"] = true })
      store:Set("hiddenCharacters", { ["Carol-ArgentDawn"] = true })
      store:Set("hiddenCharacters", {})
      assert.are.same({ "hiddenCharacters", "hiddenCharacters", "hiddenCharacters" }, changes)
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

    it("ignores a choice that is not one of the setting's values", function()
      local store = NewStore()
      store:Set("tooltipSide", "left")
      store:Set("tooltipSide", "top")
      assert.are.equal("left", store:Get("tooltipSide"))
      assert.are.same({ "tooltipSide" }, changes)
      local saved = { account = { version = 1, values = { tooltipSide = "top" } } }
      assert.are.equal("right", NewStore(saved):Get("tooltipSide"))
    end)

    it("keeps only the names of a saved set of names", function()
      local saved = { account = { version = 1, values = {
        hiddenCharacters = { ["Bob-Stormrage"] = true, [3] = true, ["Carol-ArgentDawn"] = "yes" },
      } } }
      assert.are.same({ ["Bob-Stormrage"] = true }, NewStore(saved):Get("hiddenCharacters"))
      saved = { account = { version = 1, values = { hiddenCharacters = "Bob-Stormrage" } } }
      assert.are.same({}, NewStore(saved):Get("hiddenCharacters"))
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

    it("turned on and off, changes the set of names in use", function()
      local store = Login(nil)
      store:Set("hiddenCharacters", { ["Bob-Stormrage"] = true })
      store:SetCharacterOnly(true)
      assert.are.same({ ["Bob-Stormrage"] = true }, store:Get("hiddenCharacters"))
      store:Set("hiddenCharacters", { ["Carol-ArgentDawn"] = true })
      changes = {}

      store:SetCharacterOnly(false)
      assert.are.same({ ["Bob-Stormrage"] = true }, store:Get("hiddenCharacters"))
      assert.are.same({ "hiddenCharacters" }, changes)
      store = Login(Logout(store))
      store:SetCharacterOnly(true)
      assert.are.same({ ["Carol-ArgentDawn"] = true }, store:Get("hiddenCharacters"))
    end)

    describe("the Defaults button", function()
      -- Blizzard's Defaults button sets each setting on the page to its
      -- default; the hidden characters too (Seek's settings adapter has a
      -- setting without a control for them).
      local function PressDefaults(store)
        store:Set("visibleResults", DEFINITIONS.visibleResults.default)
        store:Set("hiddenCharacters", DEFINITIONS.hiddenCharacters.default)
      end

      it("shows all characters again, and saves no set of names", function()
        local store = Login(nil)
        store:Set("hiddenCharacters", { ["Bob-Stormrage"] = true })
        store:SetCharacterOnly(true)
        store:Set("hiddenCharacters", { ["Carol-ArgentDawn"] = true })
        PressDefaults(store)
        assert.are.same({}, store:Get("hiddenCharacters"))
        assert.are.same({}, store:Saved().character.values)
        store:SetCharacterOnly(false)
        assert.are.same({ ["Bob-Stormrage"] = true }, store:Get("hiddenCharacters"))
        PressDefaults(store)
        assert.are.same({}, store:Get("hiddenCharacters"))
        assert.are.same({}, store:Saved().account.values)
      end)

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

  describe("saved data with the old setting \"Show other characters' bags\"", function()
    local OTHERS = { "Bob-Stormrage", "Carol-ArgentDawn" }

    it("off, hides each other character that Seek knows now, in the account's and the character's settings", function()
      local saved = {
        account = { version = 1, values = { otherCharactersBags = false, visibleResults = 12 } },
        character = { version = 1, characterOnly = true, values = { otherCharactersBags = false } },
      }
      local store = NewStore(saved, DEFINITIONS, OTHERS)
      local hidden = { ["Bob-Stormrage"] = true, ["Carol-ArgentDawn"] = true }
      assert.are.same(hidden, store:Get("hiddenCharacters"))
      assert.are.same({ hiddenCharacters = hidden }, store:Saved().character.values)
      assert.are.same({ visibleResults = 12, hiddenCharacters = hidden }, store:Saved().account.values)
    end)

    it("on, changes nothing", function()
      local saved = { account = { version = 1, values = { otherCharactersBags = true } } }
      local store = NewStore(saved, DEFINITIONS, OTHERS)
      assert.are.same({}, store:Get("hiddenCharacters"))
      assert.are.same({}, store:Saved().account.values)
    end)

    it("off, with no other character known, saves nothing", function()
      local saved = { account = { version = 1, values = { otherCharactersBags = false } } }
      assert.are.same({}, NewStore(saved, DEFINITIONS, {}):Saved().account.values)
    end)

    it("off, is gone once saved: a character that Seek sees later is shown", function()
      local saved = { account = { version = 1, values = { otherCharactersBags = false } } }
      local store = NewStore(NewStore(saved, DEFINITIONS, OTHERS):Saved(), DEFINITIONS,
        { "Bob-Stormrage", "Carol-ArgentDawn", "Dave-Stormrage" })
      assert.are.same({ ["Bob-Stormrage"] = true, ["Carol-ArgentDawn"] = true }, store:Get("hiddenCharacters"))
    end)
  end)
end)
