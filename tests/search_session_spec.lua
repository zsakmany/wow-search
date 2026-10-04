-- The search session, driven the way the search bar window drives it: open,
-- close, set the query, press keys, and read the view state that comes back.

local load_core = require("tests.load_core")

local HINT = "Search bags, spells, quests…"
local NO_RESULTS = "No results"

local function Item(name, itemID)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester" }
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

-- "Potion 01" to "Potion <last>"
local function Potions(first, last)
  local names = {}
  for i = first, last do
    names[#names + 1] = ("Potion %02d"):format(i)
  end
  return names
end

describe("the search session", function()
  local ns, session

  before_each(function()
    ns = load_core()
    session = ns.NewSearchSession()
  end)

  -- Registers a fake source with these entries.
  local function GivenEntries(entries)
    ns.api.RegisterSource({
      id = "Test.Bags",
      GetEntries = function()
        return entries
      end,
    })
  end

  it("opens with an empty query, the hint, and no results", function()
    local view = session:Open()
    assert.is_true(view.open)
    assert.are.equal("", view.query)
    assert.are.equal(HINT, view.hint)
    assert.are.same({}, view.results)
  end)

  it("closes when the player presses Escape", function()
    session:Open()
    local view = session:PressKey("ESCAPE")
    assert.is_false(view.open)
  end)

  it("starts closed", function()
    assert.is_false(session:View().open)
  end)

  it("toggles open and closed, as the key binding and /seek do", function()
    assert.is_true(session:Toggle().open)
    assert.is_false(session:Toggle().open)
  end)

  it("shows the hint only while the query is empty", function()
    session:Open()
    local view = session:SetQuery("hearth")
    assert.are.equal("hearth", view.query)
    assert.is_nil(view.hint)
    assert.are.equal(HINT, session:SetQuery("").hint)
  end)

  it("starts each opening with an empty query", function()
    session:Open()
    session:SetQuery("hearth")
    session:PressKey("ESCAPE")
    local view = session:Open()
    assert.are.equal("", view.query)
    assert.are.equal(HINT, view.hint)
  end)

  it("shows the no results text when nothing matches", function()
    GivenEntries({ Item("Hearthstone", 6948) })
    session:Open()
    local view = session:SetQuery("zzz")
    assert.are.same({}, view.results)
    assert.are.equal(NO_RESULTS, view.noResults)
    assert.is_nil(view.hint)
  end)

  it("shows no results text while the query is empty, only the hint", function()
    GivenEntries({ Item("Hearthstone", 6948) })
    local view = session:Open()
    assert.are.same({}, view.results)
    assert.is_nil(view.noResults)
    assert.are.equal(HINT, view.hint)
    assert.is_nil(session:SetQuery("hearth").noResults)
  end)

  it("selects the best result", function()
    GivenEntries({ Item("Hearthstone", 6948), Item("Heavy Leather", 4234) })
    session:Open()
    local _, selected = Rows(session:SetQuery("hea"))
    assert.are.equal("Hearthstone", selected)
  end)

  it("shows 8 rows and scrolls as the selection moves down and up", function()
    local entries = {}
    for i, name in ipairs(Potions(1, 12)) do
      entries[i] = Item(name, i)
    end
    GivenEntries(entries)
    session:Open()

    local rows, selected = Rows(session:SetQuery("potion"))
    assert.are.same(Potions(1, 8), rows)
    assert.are.equal("Potion 01", selected)

    -- Down to the last visible row: no scrolling yet.
    for _ = 1, 7 do
      rows, selected = Rows(session:PressKey("DOWN"))
    end
    assert.are.same(Potions(1, 8), rows)
    assert.are.equal("Potion 08", selected)

    -- One more: the list scrolls by one row.
    rows, selected = Rows(session:PressKey("DOWN"))
    assert.are.same(Potions(2, 9), rows)
    assert.are.equal("Potion 09", selected)

    -- Down past the last result stays on the last result.
    for _ = 1, 5 do
      rows, selected = Rows(session:PressKey("DOWN"))
    end
    assert.are.same(Potions(5, 12), rows)
    assert.are.equal("Potion 12", selected)

    -- Up to the first visible row: no scrolling yet.
    for _ = 1, 7 do
      rows, selected = Rows(session:PressKey("UP"))
    end
    assert.are.same(Potions(5, 12), rows)
    assert.are.equal("Potion 05", selected)

    -- One more: the list scrolls back by one row.
    rows, selected = Rows(session:PressKey("UP"))
    assert.are.same(Potions(4, 11), rows)
    assert.are.equal("Potion 04", selected)

    -- Up past the first result stays on the first result.
    for _ = 1, 5 do
      rows, selected = Rows(session:PressKey("UP"))
    end
    assert.are.same(Potions(1, 8), rows)
    assert.are.equal("Potion 01", selected)
  end)

  it("selects the best result again when the query changes", function()
    local entries = {}
    for i, name in ipairs(Potions(1, 12)) do
      entries[i] = Item(name, i)
    end
    GivenEntries(entries)
    session:Open()
    session:SetQuery("potion")
    for _ = 1, 10 do
      session:PressKey("DOWN")
    end
    local rows, selected = Rows(session:SetQuery("potion 1"))
    assert.are.same({ "Potion 10", "Potion 11", "Potion 12", "Potion 01" }, rows)
    assert.are.equal("Potion 10", selected)
  end)
end)
