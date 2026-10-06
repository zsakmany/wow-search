-- The item count, seen from the edge of the core: a fake source gives item
-- entries with a count through the public API, and the test types a query
-- the way the search bar does and reads the rows' count text.

local FakeGame = require("tests.fake_game")

local function Item(name, itemID, count)
  return {
    name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester", inBags = true, count = count,
  }
end

-- Each result row of the view as "name", or "name | count text" for a row
-- that shows a count, top to bottom.
local function Rows(view)
  local rows = {}
  for i, result in ipairs(view.results) do
    rows[i] = result.name .. (result.countText and " | " .. result.countText or "")
  end
  return rows
end

describe("the item count", function()
  local session

  -- Registers a fake source with these entries and opens the search bar.
  local function Given(entries)
    local ns = FakeGame.Started().ns
    ns.api.RegisterSource({
      id = "Test.Bags",
      GetEntries = function()
        return entries
      end,
    })
    session = ns.NewSearchSession()
    session:Open()
  end

  local function Search(query)
    return Rows(session:SetQuery(query))
  end

  it("shows after the name when it is more than 1", function()
    Given({ Item("Silk Cloth", 4306, 57) })
    assert.are.same({ "Silk Cloth | ×57" }, Search("silk"))
  end)

  it("shows nothing for a count of 1 or no count", function()
    Given({ Item("Hearthstone", 6948, 1), Item("Heavy Silk Bandage", 6451) })
    assert.are.same({ "Hearthstone", "Heavy Silk Bandage" }, Search("h"))
  end)

  it("is never matched by the query, and leaves the name's matched letters as they are", function()
    Given({ Item("Silk Cloth", 4306, 57) })
    assert.are.same({}, Search("57"))
    local view = session:SetQuery("silk")
    assert.are.same({ 1, 2, 3, 4 }, view.results[1].matchedLetters)
    assert.are.equal("Silk Cloth", view.results[1].name)
  end)

  it("is left out when it is not a whole number of at least 1; the entry is still found", function()
    Given({
      Item("Copper Ore", 2770, 0),
      Item("Linen Cloth", 2589, -3),
      Item("Rough Stone", 2835, 2.5),
      Item("Silk Cloth", 4306, "57"),
    })
    assert.are.same({ "Copper Ore" }, Search("copper"))
    assert.are.same({ "Linen Cloth" }, Search("linen"))
    assert.are.same({ "Rough Stone" }, Search("rough"))
    assert.are.same({ "Silk Cloth" }, Search("silk"))
  end)
end)

describe("the item count after a reload", function()
  it("shows in combat, from the saved copy, before any source is read", function()
    local game = FakeGame.Started()
    game.Seek.RegisterSource({
      id = "Test.Bags",
      GetEntries = function()
        return { Item("Silk Cloth", 4306, 57) }
      end,
    })

    local after = game:Reload({ inCombat = true })
    local reads = 0
    after.Seek.RegisterSource({
      id = "Test.Bags",
      GetEntries = function()
        reads = reads + 1
        return {}
      end,
    })
    after:Start()
    local session = after.ns.NewSearchSession()
    session:Open()
    assert.are.same({ "Silk Cloth | ×57" }, Rows(session:SetQuery("silk")))
    assert.are.equal(0, reads)
  end)
end)

describe("the item count of another character's item", function()
  -- `character` logs in on the account of `from` (or on a new account), and
  -- a fake source with the id of Seek's bag source gives `items`. Returns
  -- the started game.
  local function LogIn(from, character, items)
    local game = from and from:LogIn(character) or FakeGame.New({ character = character })
    game.Seek.RegisterSource({
      id = game.ns.BAG_SOURCE_ID,
      GetEntries = function()
        return items
      end,
    })
    game:Start()
    return game
  end

  local function Search(game, query)
    local session = game.ns.NewSearchSession()
    session:Open()
    local view = session:SetQuery(query)
    return Rows(view), view.results[1] and view.results[1].faded
  end

  it("is the one in that character's bags when Seek last read them, and the result stays faded", function()
    local silk = Item("Silk Cloth", 4306, 57)
    silk.owner = "Bob-Stormrage"
    local bob = LogIn(nil, "Bob-Stormrage", { silk })
    local alice = LogIn(bob, "Alice-Stormrage", {})
    local rows, faded = Search(alice, "silk")
    assert.are.same({ "Silk Cloth | ×57" }, rows)
    assert.is_true(faded)
  end)
end)

describe("saved data from before item counts", function()
  it("loads, with no counts until the bags are read again", function()
    -- The character's saved copy and the account's saved bags, as the
    -- version of Seek before item counts saved them. Alice reloads in combat.
    local game = FakeGame.New({ character = "Alice-Stormrage", inCombat = true })
    game.storage.data = {
      version = 2,
      sources = {
        ["Seek.Bags"] = {
          { name = "Silk Cloth", kind = "item", icon = 134400, gameID = 4306, owner = "Alice-Stormrage",
            inBags = true },
        },
      },
    }
    game.account.data = {
      bags = {
        version = 1,
        characters = {
          ["Bob-Stormrage"] = { { name = "Silk Cloth", kind = "item", icon = 134400, gameID = 4306 } },
        },
      },
    }
    local silk = Item("Silk Cloth", 4306, 57)
    silk.owner = "Alice-Stormrage"
    game.Seek.RegisterSource({
      id = game.ns.BAG_SOURCE_ID,
      GetEntries = function()
        return { silk }
      end,
    })
    game:Start()
    local session = game.ns.NewSearchSession()
    session:Open()
    local view = session:SetQuery("silk")
    assert.are.same({ "Silk Cloth" }, Rows(view))
    assert.is_falsy(view.results[1].faded)

    -- After combat, Seek reads Alice's bags, and Bob's from the account's
    -- saved bags: his count shows after he logs in again.
    game:LeaveCombat()
    view = session:SetQuery("silk")
    assert.are.same({ "Silk Cloth | ×57", "Silk Cloth" }, Rows(view))
    assert.is_true(view.results[2].faded)
  end)
end)
