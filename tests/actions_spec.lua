-- Actions, seen from the edge of the core: a fake source gives entries
-- through the public API, the test types a query and presses keys the way
-- the search bar does, and a fake action adapter writes down each action
-- that the core asks it to run.

local FakeGame = require("tests.fake_game")

local function Item(name, itemID)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester" }
end

local function Spell(name, spellID)
  return { name = name, icon = 135812, kind = "spell", gameID = spellID, owner = "Tester" }
end

local function Quest(title, questID)
  return { name = title, icon = 133745, kind = "quest", gameID = questID, owner = "Tester" }
end

describe("actions", function()
  local ns, session, requests

  before_each(function()
    ns = FakeGame.Started().ns
    -- The fake action adapter: each request is the action id, and the kind
    -- and game ID of the entry.
    requests = {}
    ns.SetActionAdapter({
      Run = function(_, actionID, entry)
        requests[#requests + 1] = { action = actionID, kind = entry.kind, gameID = entry.gameID }
      end,
    })
    session = ns.NewSearchSession()
  end)

  -- Registers a fake source with this id and these entries.
  local function GivenSource(id, entries)
    ns.api.RegisterSource({
      id = id,
      GetEntries = function()
        return entries
      end,
    })
  end

  it("runs show in bag for the item on Enter, and closes the search bar", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948) })
    session:Open()
    session:SetQuery("hearth")
    local view = session:PressKey("ENTER")
    assert.are.same({ { action = "showInBag", kind = "item", gameID = 6948 } }, requests)
    assert.is_false(view.open)
  end)

  it("runs show in spellbook for the spell on Enter, and closes the search bar", function()
    GivenSource("Test.Spells", { Spell("Fireball", 133) })
    session:Open()
    session:SetQuery("fireb")
    local view = session:PressKey("ENTER")
    assert.are.same({ { action = "showInSpellbook", kind = "spell", gameID = 133 } }, requests)
    assert.is_false(view.open)
  end)

  it("runs the main action of the selected result", function()
    GivenSource("Test.Bags", { Item("Healing Potion", 929), Item("Mana Potion", 2455) })
    session:Open()
    session:SetQuery("potion")
    session:PressKey("DOWN")
    session:PressKey("ENTER")
    assert.are.same({ { action = "showInBag", kind = "item", gameID = 2455 } }, requests)
  end)

  it("gives an item entry from any source the same item actions", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948) })
    GivenSource("Test.Bank", { Item("Linen Cloth", 2589) })
    session:Open()
    session:SetQuery("hearth")
    session:PressKey("ENTER")
    session:Open()
    session:SetQuery("linen")
    session:PressKey("ENTER")
    assert.are.same({
      { action = "showInBag", kind = "item", gameID = 6948 },
      { action = "showInBag", kind = "item", gameID = 2589 },
    }, requests)
  end)

  it("runs open quest log for the quest on Enter, and closes the search bar", function()
    GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
    session:Open()
    session:SetQuery("defias")
    local view = session:PressKey("ENTER")
    assert.are.same({ { action = "openQuestLog", kind = "quest", gameID = 65 } }, requests)
    assert.is_false(view.open)
  end)

  it("does nothing on Enter when nothing matches", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948) })
    session:Open()
    session:SetQuery("zzz")
    local view = session:PressKey("ENTER")
    assert.are.same({}, requests)
    assert.is_true(view.open)
    assert.are.equal("zzz", view.query)
  end)

  it("does nothing on Enter while the query is empty", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948) })
    session:Open()
    local view = session:PressKey("ENTER")
    assert.are.same({}, requests)
    assert.is_true(view.open)
  end)
end)
