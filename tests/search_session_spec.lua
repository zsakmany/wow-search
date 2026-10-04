-- The search session, driven the way the search bar window drives it: open,
-- close, set the query, press keys, and read the view state that comes back.

local load_core = require("tests.load_core")

local HINT = "Search bags, spells, quests…"

describe("the search session", function()
  local session

  before_each(function()
    session = load_core().NewSearchSession()
  end)

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
end)
