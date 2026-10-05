-- Use actions and the combat rule, seen from the edge of the core: a fake
-- source gives entries through the public API, the test types a query and
-- presses keys the way the search bar does, reads the view state, turns a
-- fake combat state on and off, and a fake action adapter writes down each
-- action that the core asks it to run or to prepare.

local FakeGame = require("tests.fake_game")

local function Item(name, itemID, usable)
  return {
    name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester", inBags = true, usable = usable,
  }
end

local function Spell(name, spellID)
  return { name = name, icon = 135812, kind = "spell", gameID = spellID, owner = "Tester" }
end

local function Quest(title, questID)
  return { name = title, icon = 133745, kind = "quest", gameID = questID, owner = "Tester" }
end

-- The action list's rows as "label" or "label (blocked)", top to bottom, and
-- the label of the selected row. Nil when the action list is closed.
local function ListRows(view)
  if not view.actionList then
    return nil
  end
  local rows, selected = {}, nil
  for i, row in ipairs(view.actionList.rows) do
    rows[i] = row.blocked and row.label .. " (blocked)" or row.label
    if row.selected then
      selected = row.label
    end
  end
  return rows, selected
end

-- A fake action adapter: `requests` holds each action that the core asked
-- to run, and `prepared` the use action that the core asked to prepare last
-- ("action kind gameID", or false for none).
local function NewActionAdapter()
  local adapter = { requests = {}, prepared = false }
  function adapter:Run(actionID, entry)
    self.requests[#self.requests + 1] = { action = actionID, kind = entry.kind, gameID = entry.gameID }
  end
  function adapter:Prepare(actionID, entry)
    self.prepared = actionID and (actionID .. " " .. entry.kind .. " " .. entry.gameID) or false
  end
  return adapter
end

describe("use actions", function()
  local game, session, actions, shown

  before_each(function()
    game = FakeGame.Started()
    actions = NewActionAdapter()
    game.ns.SetActionAdapter(actions)
    shown = nil
    session = game.ns.NewSearchSession(function(view)
      shown = view
    end)
  end)

  local function GivenSource(id, entries)
    game.Seek.RegisterSource({
      id = id,
      GetEntries = function()
        return entries
      end,
    })
  end

  -- Opens the search bar, types the query, and opens the action list of the
  -- best result.
  local function OpenList(query)
    session:Open()
    session:SetQuery(query)
    return session:PressKey("TAB")
  end

  it("a usable item has a use action after its show action", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    assert.are.same({ "Show in bag", "Use" }, (ListRows(OpenList("hearth"))))
  end)

  it("Tab opens the action list with the use action selected", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    local _, selected = ListRows(OpenList("hearth"))
    assert.are.equal("Use", selected)
  end)

  it("an item that cannot be used has no use action, and Tab selects its main action", function()
    GivenSource("Test.Bags", { Item("Copper Ore", 2770, false), Item("Linen Cloth", 2589) })
    local rows, selected = ListRows(OpenList("copper"))
    assert.are.same({ "Show in bag" }, rows)
    assert.are.equal("Show in bag", selected)
    rows, selected = ListRows(OpenList("linen"))
    assert.are.same({ "Show in bag" }, rows)
    assert.are.equal("Show in bag", selected)
  end)

  it("a spell has only a cast action (no show action, see issue #29), and Tab selects it", function()
    GivenSource("Test.Spells", { Spell("Fireball", 133) })
    local rows, selected = ListRows(OpenList("fireb"))
    assert.are.same({ "Cast" }, rows)
    assert.are.equal("Cast", selected)
  end)

  it("Enter on a result still runs the main action, a show action", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    GivenSource("Test.Spells", { Spell("Fireball", 133) })
    session:Open()
    session:SetQuery("hearth")
    session:PressKey("ENTER")
    session:Open()
    session:SetQuery("fireb")
    session:PressKey("ENTER")
    -- The spell has no show action, so Enter runs nothing for it, not its cast.
    assert.are.same({
      { action = "showInBag", kind = "item", gameID = 6948 },
    }, actions.requests)
  end)

  it("out of combat, Tab, Enter asks for the use action and closes the search bar", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    OpenList("hearth")
    local view = session:PressKey("ENTER")
    assert.are.same({ { action = "useItem", kind = "item", gameID = 6948 } }, actions.requests)
    assert.is_false(view.open)
  end)

  it("out of combat, Tab, Enter asks for the cast", function()
    GivenSource("Test.Spells", { Spell("Fireball", 133) })
    OpenList("fireb")
    session:PressKey("ENTER")
    assert.are.same({ { action = "castSpell", kind = "spell", gameID = 133 } }, actions.requests)
  end)

  it("in combat, Tab still selects the use action, shown as blocked, and Enter asks for nothing", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    game:EnterCombat()
    local rows, selected = ListRows(OpenList("hearth"))
    assert.are.same({ "Show in bag", "Use (blocked)" }, rows)
    assert.are.equal("Use", selected)

    local view = session:PressKey("ENTER")
    assert.are.same({}, actions.requests)
    assert.is_true(view.open)
    assert.are.equal("Use", select(2, ListRows(view)))
  end)

  it("Up from the use action selects the main action, and Enter runs it", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    OpenList("hearth")
    local _, selected = ListRows(session:PressKey("UP"))
    assert.are.equal("Show in bag", selected)
    local view = session:PressKey("ENTER")
    assert.are.same({ { action = "showInBag", kind = "item", gameID = 6948 } }, actions.requests)
    assert.is_false(view.open)
  end)

  it("in combat, show actions are not blocked and still run", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
    game:EnterCombat()
    assert.are.same({ "Show in bag", "Use (blocked)" }, (ListRows(OpenList("hearth"))))
    assert.are.same({ "Show in quest log", "Show on map" }, (ListRows(OpenList("defias"))))

    session:PressKey("DOWN")
    local view = session:PressKey("ENTER")
    assert.are.same({ { action = "showOnMap", kind = "quest", gameID = 65 } }, actions.requests)
    assert.is_false(view.open)
  end)

  it("updates the marks when combat starts and ends while the search bar is open", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    OpenList("hearth")

    game:EnterCombat()
    assert.are.same({ "Show in bag", "Use (blocked)" }, (ListRows(shown)))
    session:PressKey("ENTER")
    assert.are.same({}, actions.requests)

    game:LeaveCombat()
    assert.are.same({ "Show in bag", "Use" }, (ListRows(shown)))
    session:PressKey("ENTER")
    assert.are.same({ { action = "useItem", kind = "item", gameID = 6948 } }, actions.requests)
  end)

  it("does not update a closed search bar when combat starts", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    game:EnterCombat()
    assert.is_nil(shown)
  end)

  it("keeps the item's use action in the saved copy, for a reload in combat", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    -- After the reload, the bag source registers again but is not read in
    -- combat: search uses the saved copy.
    local after = game:Reload({ inCombat = true })
    after.Seek.RegisterSource({
      id = "Test.Bags",
      GetEntries = function()
        return {}
      end,
    })
    after:Start()
    local again = after.ns.NewSearchSession()
    again:Open()
    again:SetQuery("hearth")
    assert.are.same({ "Show in bag", "Use (blocked)" }, (ListRows(again:PressKey("TAB"))))
  end)

  describe("preparing", function()
    it("prepares the use action that Tab selects at once, with no other key press", function()
      GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
      OpenList("hearth")
      assert.are.equal("useItem item 6948", actions.prepared)
    end)

    it("prepares the selected use action, and nothing on a show action", function()
      GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
      OpenList("hearth")
      session:PressKey("UP")
      assert.is_false(actions.prepared)
      session:PressKey("DOWN")
      assert.are.equal("useItem item 6948", actions.prepared)
    end)

    it("prepares nothing once the action list or the search bar closes", function()
      GivenSource("Test.Spells", { Spell("Fireball", 133) })
      OpenList("fireb")
      assert.are.equal("castSpell spell 133", actions.prepared)
      session:PressKey("ESCAPE")
      assert.is_false(actions.prepared)

      session:PressKey("TAB")
      session:Close()
      assert.is_false(actions.prepared)
    end)

    it("prepares nothing in combat, and the selected use action again when combat ends", function()
      GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
      OpenList("hearth")
      game:EnterCombat()
      assert.is_false(actions.prepared)
      game:LeaveCombat()
      assert.are.equal("useItem item 6948", actions.prepared)
    end)

    it("prepares nothing when the selected use action is blocked from the start", function()
      GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
      game:EnterCombat()
      OpenList("hearth")
      assert.is_false(actions.prepared)
    end)
  end)
end)
