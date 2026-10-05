-- Other characters' bags, seen from the edge of the core: each of the
-- player's characters logs in (a fake game with the character's own saved
-- data and the account's shared saved data), a fake bag source with the id
-- of Seek's bag source gives the character's items, and the test searches
-- and presses keys the way the search bar does.

local FakeGame = require("tests.fake_game")

local HINT = "Search bags, spells, quests…"

-- An item as Seek's bag source gives it: in the current character's bags.
local function Item(name, itemID, owner)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = owner, inBags = true }
end

-- Each result row of the view as "name | kind text", with " (faded)" for a
-- faded row, top to bottom.
local function Rows(view)
  local rows = {}
  for i, result in ipairs(view.results) do
    rows[i] = result.name .. " | " .. result.kindLabel .. (result.faded and " (faded)" or "")
  end
  return rows
end

-- `character` logs in: on the account of `from` (a game of another
-- character), or on a new account when `from` is nil. Its bag source gives
-- whatever `items` holds when Seek reads it. Returns the started game and
-- a search session.
local function LogIn(from, character, items, options)
  local game = from and from:LogIn(character, options) or FakeGame.New({ character = character })
  game.Seek.RegisterSource({
    id = game.ns.BAG_SOURCE_ID,
    GetEntries = function()
      return items
    end,
  })
  game:Start()
  return game, game.ns.NewSearchSession()
end

-- The result rows for this query, from a fresh opening.
local function Search(session, query)
  session:Open()
  local view = session:SetQuery(query)
  session:Close()
  return Rows(view)
end

describe("other characters' bags", function()
  local bob

  -- Bob has logged in once, with silk cloth in his bags.
  before_each(function()
    bob = LogIn(nil, "Bob-Stormrage", { Item("Silk Cloth", 4306, "Bob-Stormrage") })
  end)

  it("show an item in another character's bags, faded, with the character's name", function()
    local _, session = LogIn(bob, "Alice-Stormrage", { Item("Hearthstone", 6948, "Alice-Stormrage") })
    assert.are.same({ "Silk Cloth | Item · Bob (faded)" }, Search(session, "silk"))
    assert.are.same({ "Hearthstone | Item" }, Search(session, "hearth"))
  end)

  it("show the realm too when the other character is on another realm", function()
    local carol = LogIn(bob, "Carol-ArgentDawn", { Item("Mageweave Cloth", 4338, "Carol-ArgentDawn") })
    local _, session = LogIn(carol, "Alice-Stormrage", {})
    assert.are.same({
      "Mageweave Cloth | Item · Carol-ArgentDawn (faded)",
      "Silk Cloth | Item · Bob (faded)",
    }, Search(session, "cloth"))
  end)

  it("give one result for each character that has the item, the current character's first", function()
    local _, session = LogIn(bob, "Alice-Stormrage", { Item("Silk Cloth", 4306, "Alice-Stormrage") })
    assert.are.same({ "Silk Cloth | Item", "Silk Cloth | Item · Bob (faded)" }, Search(session, "silk"))
  end)

  it("can be selected and show their tooltip, but Enter and Tab do nothing, and nothing is picked", function()
    local alice, session = LogIn(bob, "Alice-Stormrage", { Item("Silk Bandage", 6450, "Alice-Stormrage") })
    local requests = {}
    alice.ns.SetActionAdapter({
      Run = function(_, actionID)
        requests[#requests + 1] = actionID
      end,
    })
    session:Open()
    session:SetQuery("silk")
    local view = session:PressKey("DOWN")
    assert.are.same({ "Silk Bandage | Item", "Silk Cloth | Item · Bob (faded)" }, Rows(view))
    assert.is_true(view.results[2].selected)
    assert.are.same({ row = 2, side = "right" }, view.tooltip)

    view = session:PressKey("TAB")
    assert.is_nil(view.actionList)
    view = session:PressKey("ENTER")
    assert.is_true(view.open)
    assert.is_true(view.results[2].selected)
    assert.are.same({}, requests)

    session:Close()
    assert.are.equal(HINT, session:Open().hint)
  end)

  it("leave the current character's items their actions", function()
    local hearthstone = Item("Hearthstone", 6948, "Alice-Stormrage")
    hearthstone.usable = true
    local _, session = LogIn(bob, "Alice-Stormrage", { hearthstone })
    session:Open()
    session:SetQuery("hearth")
    local labels = {}
    for i, row in ipairs(session:PressKey("TAB").actionList.rows) do
      labels[i] = row.label
    end
    assert.are.same({ "Show in bag", "Use" }, labels)
  end)

  it("never show the current character's own items from the account's saved bags", function()
    -- Bob logs in again, and his bag source has not registered (yet): his
    -- silk cloth is in the account's saved bags, but it is his own.
    local again = bob:LogIn("Bob-Stormrage")
    again:Start()
    assert.are.same({}, Search(again.ns.NewSearchSession(), "silk"))
  end)

  it("follow each read of a character's bags", function()
    local bags = { Item("Silk Cloth", 4306, "Bob-Stormrage") }
    bob = LogIn(nil, "Bob-Stormrage", bags)
    -- Bob sells his silk cloth and loots some wool.
    bags[1] = Item("Wool Cloth", 2592, "Bob-Stormrage")
    bob.Seek.NotifyChanged(bob.ns.BAG_SOURCE_ID)
    local _, session = LogIn(bob, "Alice-Stormrage", {})
    assert.are.same({ "Wool Cloth | Item · Bob (faded)" }, Search(session, "cloth"))
  end)

  describe("with the setting \"Show other characters' bags\"", function()
    it("off, do not show; turned on, show again without a reload", function()
      local alice, session = LogIn(bob, "Alice-Stormrage", {})
      alice:ChangeSetting("otherCharactersBags", false)
      assert.are.same({}, Search(session, "silk"))
      alice:ChangeSetting("otherCharactersBags", true)
      assert.are.same({ "Silk Cloth | Item · Bob (faded)" }, Search(session, "silk"))
    end)

    it("off, still keep the current character's bags for the other characters", function()
      -- The settings are the account's: the setting is off on Alice too.
      bob:ChangeSetting("otherCharactersBags", false)
      local alice = LogIn(bob, "Alice-Stormrage", { Item("Hearthstone", 6948, "Alice-Stormrage") })
      alice:ChangeSetting("otherCharactersBags", true)
      local _, session = LogIn(alice, "Bob-Stormrage", {})
      assert.are.same({ "Hearthstone | Item · Alice (faded)" }, Search(session, "hearth"))
    end)
  end)
end)

describe("saved data from before other characters' bags", function()
  it("loads with no errors, and with no other characters yet", function()
    -- The character's saved copy, as an earlier version of Seek saved it,
    -- and no account-wide saved data.
    local game = FakeGame.New({ character = "Alice-Stormrage" })
    game.storage.data = {
      version = 1,
      sources = {
        ["Seek.Bags"] = {
          { name = "Hearthstone", kind = "item", icon = 134400, gameID = 6948, owner = "Alice-Stormrage" },
        },
      },
    }
    game.Seek.RegisterSource({
      id = game.ns.BAG_SOURCE_ID,
      GetEntries = function()
        return { Item("Hearthstone", 6948, "Alice-Stormrage"), Item("Silk Cloth", 4306, "Alice-Stormrage") }
      end,
    })
    game:Start()
    local session = game.ns.NewSearchSession()
    assert.are.same({ "Hearthstone | Item" }, Search(session, "hearth"))
    assert.are.same({ "Silk Cloth | Item" }, Search(session, "silk"))
  end)

  it("ignores an earlier version's saved copy, so the player's own items never show faded", function()
    -- That copy's items have no inBags, and its owners can be named
    -- differently ("Alice" early in the login). A reload in combat must not
    -- show them as another character's items with no actions.
    local game = FakeGame.New({ character = "Alice-Stormrage", inCombat = true })
    game.storage.data = {
      version = 1,
      sources = {
        ["Seek.Bags"] = {
          { name = "Hearthstone", kind = "item", icon = 134400, gameID = 6948, owner = "Alice" },
        },
      },
    }
    game.Seek.RegisterSource({
      id = game.ns.BAG_SOURCE_ID,
      GetEntries = function()
        return { Item("Hearthstone", 6948, "Alice-Stormrage") }
      end,
    })
    game:Start()
    local session = game.ns.NewSearchSession()
    assert.are.same({}, Search(session, "hearth"))
    game:LeaveCombat()
    game:RunSteps()
    assert.are.same({ "Hearthstone | Item" }, Search(session, "hearth"))
  end)
end)
