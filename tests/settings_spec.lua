-- Settings, seen from the edge of the core: the test changes a setting
-- through the fake settings port, as the player does on Seek's settings
-- page, and reads the search bar's view state, as the search bar window
-- does.

local FakeGame = require("tests.fake_game")

local function Item(name, itemID)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester", inBags = true }
end

-- "Potion 01" to "Potion <last>"
local function Potions(first, last)
  local names = {}
  for i = first, last do
    names[#names + 1] = ("Potion %02d"):format(i)
  end
  return names
end

-- The names of the visible result rows, top to bottom, and the name of the
-- selected row.
local function Rows(view)
  local names, selected = {}, nil
  for i, result in ipairs(view.results) do
    names[i] = result.name
    if result.selected then
      selected = result.name
    end
  end
  return names, selected
end

describe("the visible results setting", function()
  local game, session, shown

  before_each(function()
    game = FakeGame.Started()
    game.ns.SetActionAdapter({ Run = function() end })
    shown = nil
    session = game.ns.NewSearchSession(function(view)
      shown = view
    end)
    local entries = {}
    for i, name in ipairs(Potions(1, 20)) do
      entries[i] = Item(name, i)
    end
    game.Seek.RegisterSource({
      id = "Test.Bags",
      GetEntries = function()
        return entries
      end,
    })
  end)

  it("shows as many result rows as the setting says", function()
    game:ChangeSetting("visibleResults", 5)
    session:Open()
    local view = session:SetQuery("potion")
    assert.are.same(Potions(1, 5), Rows(view))
    assert.are.equal(20, view.total)
  end)

  it("is 8 by default", function()
    session:Open()
    assert.are.same(Potions(1, 8), Rows(session:SetQuery("potion")))
  end)

  it("changes the rows at once while the search bar is open", function()
    session:Open()
    session:SetQuery("potion")
    game:ChangeSetting("visibleResults", 12)
    assert.are.same(Potions(1, 12), Rows(shown))
    assert.are.same(Potions(1, 12), Rows(session:View()))

    game:ChangeSetting("visibleResults", 3)
    assert.are.same(Potions(1, 3), Rows(shown))
  end)

  it("keeps the selected result in view when the rows get fewer", function()
    session:Open()
    session:SetQuery("potion")
    for _ = 1, 6 do
      session:PressKey("DOWN")
    end
    game:ChangeSetting("visibleResults", 3)
    local rows, selected = Rows(shown)
    assert.are.same(Potions(5, 7), rows)
    assert.are.equal("Potion 07", selected)
  end)

  it("goes back to the default when the player puts it back", function()
    game:ChangeSetting("visibleResults", 5)
    session:Open()
    session:SetQuery("potion")
    game:ChangeSetting("visibleResults", nil)
    assert.are.same(Potions(1, 8), Rows(shown))
  end)

  it("does not tell the search bar about a change while it is closed", function()
    game:ChangeSetting("visibleResults", 5)
    assert.is_nil(shown)
  end)

  describe("in the empty search bar", function()
    -- The player picks "Potion 01" to "Potion 12" in turn: the most recent
    -- pick is "Potion 12".
    before_each(function()
      for i = 1, 12 do
        session:Open()
        session:SetQuery(("potion %02d"):format(i))
        session:PressKey("ENTER")
      end
    end)

    it("shows that many recent picks at most", function()
      game:ChangeSetting("visibleResults", 4)
      local view = session:Open()
      assert.are.same({ "Potion 12", "Potion 11", "Potion 10", "Potion 09" }, Rows(view))
      assert.are.equal(4, view.total)
    end)

    it("shows more recent picks at once when the setting grows while it is open", function()
      session:Open()
      game:ChangeSetting("visibleResults", 10)
      assert.are.equal(10, shown.total)
      assert.are.same({
        "Potion 12", "Potion 11", "Potion 10", "Potion 09", "Potion 08",
        "Potion 07", "Potion 06", "Potion 05", "Potion 04", "Potion 03",
      }, Rows(shown))
    end)
  end)
end)
