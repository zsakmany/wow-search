-- Cooldowns, seen from the edge of the core: fake sources give entries
-- through the public API, the test types a query the way the search bar
-- does, and reads which result rows may show a cooldown, and for what. The
-- core never reads a cooldown itself; the search bar window reads it live
-- for those rows (docs/adr/0002, docs/adr/0003).

local FakeGame = require("tests.fake_game")

-- An item in the current character's bags; `usable` gives it the use action.
local function Item(name, itemID, usable)
  return {
    name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester", inBags = true, usable = usable,
  }
end

-- A spell of the current character.
local function Spell(name, spellID)
  return { name = name, icon = 135812, kind = "spell", gameID = spellID, owner = "Tester" }
end

-- A quest in the current character's quest log.
local function Quest(title, questID)
  return { name = title, icon = 133745, kind = "quest", gameID = questID, owner = "Tester" }
end

-- Each result row of the view as "name", or "name | cooldown of <action id>
-- <game ID>" for a row that may show a cooldown, top to bottom.
local function Rows(view)
  local rows = {}
  for i, result in ipairs(view.results) do
    local cooldown = result.cooldownOf
    rows[i] = cooldown and ("%s | cooldown of %s %s"):format(result.name, cooldown.actionID, cooldown.gameID)
      or result.name
  end
  return rows
end

describe("a cooldown", function()
  local game, session

  before_each(function()
    game = FakeGame.Started()
    session = game.ns.NewSearchSession()
  end)

  local function GivenSource(id, entries)
    game.Seek.RegisterSource({
      id = id,
      GetEntries = function()
        return entries
      end,
    })
  end

  -- The rows that the search bar shows for this query (see Rows).
  local function Search(query)
    session:Open()
    return Rows(session:SetQuery(query))
  end

  it("may show on an item with a use action, for its use action", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    assert.are.same({ "Hearthstone | cooldown of useItem 6948" }, Search("hearth"))
  end)

  it("may show on a spell, for its cast action", function()
    GivenSource("Test.Spells", { Spell("Frost Nova", 122) })
    assert.are.same({ "Frost Nova | cooldown of castSpell 122" }, Search("frost"))
  end)

  it("never shows on a quest, whose use actions have no game cooldown", function()
    GivenSource("Test.Quests", { Quest("The Missing Diplomat", 1249) })
    assert.are.same({ "The Missing Diplomat" }, Search("diplomat"))
  end)

  it("never shows on an item without a use action", function()
    GivenSource("Test.Bags", { Item("Copper Ore", 2770, false), Item("Linen Cloth", 2589) })
    assert.are.same({ "Copper Ore" }, Search("copper"))
    assert.are.same({ "Linen Cloth" }, Search("linen"))
  end)

  it("leaves the result's rank, look, and actions as they are", function()
    local requests = {}
    game.ns.SetActionAdapter({
      Run = function(_, actionID)
        requests[#requests + 1] = actionID
      end,
    })
    GivenSource("Test.Bags", { Item("Mana Potion", 3827, true), Item("Mana Pearls", 4500, false) })

    -- The same score for both: the order is by name.
    assert.are.same({ "Mana Pearls", "Mana Potion | cooldown of useItem 3827" }, Search("mana p"))
    local view = session:PressKey("DOWN")
    assert.is_false(view.results[2].faded)
    local labels = {}
    for i, row in ipairs(session:PressKey("TAB").actionList.rows) do
      labels[i] = row.label
    end
    assert.are.same({ "Show in bag", "Use" }, labels)

    session:PressKey("ESCAPE")
    session:PressKey("USE")
    assert.are.same({ "useItem" }, requests)
  end)

  it("may show in combat too, also on the row where combat blocked the use key", function()
    GivenSource("Test.Spells", { Spell("Frost Nova", 122) })
    game:EnterCombat()
    assert.are.same({ "Frost Nova | cooldown of castSpell 122" }, Search("frost"))
    local view = session:PressKey("USE")
    assert.is_true(view.results[1].blocked)
    assert.are.same({ "Frost Nova | cooldown of castSpell 122" }, Rows(view))
  end)
end)

describe("a cooldown of another character's item", function()
  it("never shows: the result is faded", function()
    local hearthstone = Item("Hearthstone", 6948, true)
    hearthstone.owner = "Bob-Stormrage"
    local bob = FakeGame.New({ character = "Bob-Stormrage" })
    bob.Seek.RegisterSource({
      id = bob.ns.BAG_SOURCE_ID,
      GetEntries = function()
        return { hearthstone }
      end,
    })
    bob:Start()

    local alice = bob:LogIn("Alice-Stormrage")
    alice:Start()
    local session = alice.ns.NewSearchSession()
    session:Open()
    local view = session:SetQuery("hearth")
    assert.are.same({ "Hearthstone" }, Rows(view))
    assert.is_true(view.results[1].faded)
  end)
end)
