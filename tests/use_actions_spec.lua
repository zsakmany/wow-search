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

-- The result rows as "name", "name (selected)", or "name (blocked,
-- selected)", top to bottom.
local function ResultRows(view)
  local rows = {}
  for i, row in ipairs(view.results) do
    local marks = {}
    if row.blocked then
      marks[#marks + 1] = "blocked"
    end
    if row.selected then
      marks[#marks + 1] = "selected"
    end
    rows[i] = #marks > 0 and row.name .. " (" .. table.concat(marks, ", ") .. ")" or row.name
  end
  return rows
end

-- The label of the action list's row that shows the use key, or nil.
local function UseKeyRow(view)
  for _, row in ipairs(view.actionList.rows) do
    if row.useKey then
      return row.label
    end
  end
end

-- A fake action adapter: `requests` holds each action that the core asked
-- to run, and `prepared` the action that the core asked to prepare last
-- for each key, Enter ("ENTER") and the use key ("USE"): "action kind
-- gameID", or false for none.
local function NewActionAdapter()
  local adapter = { requests = {}, prepared = { ENTER = false, USE = false } }
  function adapter:Run(actionID, entry)
    self.requests[#self.requests + 1] = { action = actionID, kind = entry.kind, gameID = entry.gameID }
  end
  function adapter:Prepare(key, actionID, entry)
    self.prepared[key] = actionID and (actionID .. " " .. entry.kind .. " " .. entry.gameID) or false
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
    local rows, selected = ListRows(OpenList("hearth"))
    assert.are.same({ "Show in bag", "Use" }, rows)
    assert.are.equal("Show in bag", selected)
  end)

  it("an item that cannot be used has no use action", function()
    GivenSource("Test.Bags", { Item("Copper Ore", 2770, false), Item("Linen Cloth", 2589) })
    assert.are.same({ "Show in bag" }, (ListRows(OpenList("copper"))))
    assert.are.same({ "Show in bag" }, (ListRows(OpenList("linen"))))
  end)

  it("a spell has only a cast action (no show action, see issue #29)", function()
    GivenSource("Test.Spells", { Spell("Fireball", 133) })
    assert.are.same({ "Cast" }, (ListRows(OpenList("fireb"))))
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

  it("out of combat, picking use asks for it and closes the search bar", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    OpenList("hearth")
    session:PressKey("DOWN")
    local view = session:PressKey("ENTER")
    assert.are.same({ { action = "useItem", kind = "item", gameID = 6948 } }, actions.requests)
    assert.is_false(view.open)
  end)

  it("out of combat, picking cast asks for it", function()
    GivenSource("Test.Spells", { Spell("Fireball", 133) })
    OpenList("fireb")
    session:PressKey("DOWN")
    session:PressKey("ENTER")
    assert.are.same({ { action = "castSpell", kind = "spell", gameID = 133 } }, actions.requests)
  end)

  it("in combat, use actions are blocked and picking one asks for nothing", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    game:EnterCombat()
    local rows = ListRows(OpenList("hearth"))
    assert.are.same({ "Show in bag", "Use (blocked)" }, rows)

    session:PressKey("DOWN")
    local view = session:PressKey("ENTER")
    assert.are.same({}, actions.requests)
    assert.is_true(view.open)
    local _, selected = ListRows(view)
    assert.are.equal("Use", selected)
  end)

  it("in combat, show actions are not blocked and still run", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
    game:EnterCombat()
    assert.are.same({ "Show in bag", "Use (blocked)" }, (ListRows(OpenList("hearth"))))
    assert.are.same({ "Show on map", "Focus (blocked)", "Track (blocked)" }, (ListRows(OpenList("defias"))))

    local view = session:PressKey("ENTER")
    assert.are.same({ { action = "showOnMap", kind = "quest", gameID = 65 } }, actions.requests)
    assert.is_false(view.open)
  end)

  it("updates the marks when combat starts and ends while the search bar is open", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
    OpenList("hearth")
    session:PressKey("DOWN")

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

  describe("the use key", function()
    -- "Hearthstone" and "Hearty Rhino Hide" both match "hea"; the score puts
    -- "Hearthstone" first. Both can be used.
    local bags = { Item("Hearthstone", 6948, true), Item("Hearty Rhino Hide", 8171, true) }

    before_each(function()
      GivenSource("Test.Bags", bags)
    end)

    -- Opens the search bar, types "hea", and moves down to "Hearty Rhino
    -- Hide".
    local function SelectHide()
      session:Open()
      session:SetQuery("hea")
      return session:PressKey("DOWN")
    end

    it("uses the selected item and closes the search bar", function()
      SelectHide()
      local view = session:PressKey("USE")
      assert.are.same({ { action = "useItem", kind = "item", gameID = 8171 } }, actions.requests)
      assert.is_false(view.open)
    end)

    it("runs the selected spell's use action (Cast)", function()
      GivenSource("Test.Spells", { Spell("Fireball", 133) })
      session:Open()
      session:SetQuery("fireb")
      session:PressKey("USE")
      assert.are.same({ { action = "castSpell", kind = "spell", gameID = 133 } }, actions.requests)
    end)

    it("does nothing on a result with no use action, and never runs the main action instead", function()
      GivenSource("Test.Cloth", { Item("Linen Cloth", 2589) })
      GivenSource("Test.Options", {
        { name = "Auto Loot", kind = "gameOption", gameID = "Controls\nAuto Loot", page = "Controls" },
      })
      for _, query in ipairs({ "linen", "> auto loot" }) do
        session:Open()
        assert.are.equal(1, session:SetQuery(query).total)
        assert.is_true(session:PressKey("USE").open)
      end
      assert.are.same({}, actions.requests)
    end)

    it("does nothing on a faded result", function()
      -- Another character's Hearthstone: it has no actions.
      GivenSource("Test.Others", {
        { name = "Hearthstone", icon = 134400, kind = "item", gameID = 6948, owner = "Bob", usable = true },
      })
      session:Open()
      session:SetQuery("hearthst")
      local view = session:PressKey("DOWN")
      assert.are.same({ "Hearthstone", "Hearthstone (selected)" }, ResultRows(view))
      assert.is_true(view.results[2].faded)
      view = session:PressKey("USE")
      assert.are.same({}, actions.requests)
      assert.is_true(view.open)
    end)

    it("does nothing while the action list is open", function()
      SelectHide()
      session:PressKey("TAB")
      local view = session:PressKey("USE")
      assert.are.same({}, actions.requests)
      assert.are.same({ "Show in bag", "Use" }, (ListRows(view)))
    end)

    it("shows in the action list, next to the first use action", function()
      GivenSource("Test.Spells", { Spell("Fireball", 133) })
      GivenSource("Test.Cloth", { Item("Linen Cloth", 2589) })
      assert.are.equal("Use", UseKeyRow(OpenList("hearth")))
      assert.are.equal("Cast", UseKeyRow(OpenList("fireb")))
      assert.is_nil(UseKeyRow(OpenList("linen")))
    end)

    it("in combat, runs nothing, keeps the search bar open, and shows the sign on the result", function()
      game:EnterCombat()
      SelectHide()
      local view = session:PressKey("USE")
      assert.are.same({}, actions.requests)
      assert.is_true(view.open)
      assert.are.same({ "Hearthstone", "Hearty Rhino Hide (blocked, selected)" }, ResultRows(view))
    end)

    it("takes the sign away on the next key, and when combat ends", function()
      game:EnterCombat()
      SelectHide()
      session:PressKey("USE")
      session:PressKey("TAB")
      local view = session:PressKey("ESCAPE")
      assert.are.same({ "Hearthstone", "Hearty Rhino Hide (selected)" }, ResultRows(view))

      session:PressKey("USE")
      game:LeaveCombat()
      assert.are.same({ "Hearthstone", "Hearty Rhino Hide (selected)" }, ResultRows(shown))
    end)
  end)

  describe("preparing", function()
    it("prepares the selected use action for Enter in the action list, and nothing on a show action", function()
      GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
      OpenList("hearth")
      assert.are.same({ ENTER = false, USE = false }, actions.prepared)
      session:PressKey("DOWN")
      assert.are.same({ ENTER = "useItem item 6948", USE = false }, actions.prepared)
      session:PressKey("UP")
      assert.are.same({ ENTER = false, USE = false }, actions.prepared)
    end)

    it("prepares the selected result's first use action for the use key while the action list is closed", function()
      GivenSource("Test.Bags", { Item("Hearthstone", 6948, true), Item("Hearty Rhino Hide", 8171) })
      session:Open()
      session:SetQuery("hea")
      -- Enter runs the main action, Show in bag, which needs no preparing.
      assert.are.same({ ENTER = false, USE = "useItem item 6948" }, actions.prepared)
      -- The hide cannot be used.
      session:PressKey("DOWN")
      assert.are.same({ ENTER = false, USE = false }, actions.prepared)
      session:PressKey("UP")
      assert.are.same({ ENTER = false, USE = "useItem item 6948" }, actions.prepared)
    end)

    it("prepares the result's use action again once the action list closes, and nothing once the search bar closes",
      function()
        GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
        OpenList("hearth")
        assert.are.same({ ENTER = false, USE = false }, actions.prepared)
        session:PressKey("ESCAPE")
        assert.are.same({ ENTER = false, USE = "useItem item 6948" }, actions.prepared)

        session:Close()
        assert.are.same({ ENTER = false, USE = false }, actions.prepared)
      end)

    it("prepares nothing in combat, and the selected use action again when combat ends", function()
      GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
      OpenList("hearth")
      session:PressKey("DOWN")
      game:EnterCombat()
      assert.are.same({ ENTER = false, USE = false }, actions.prepared)
      game:LeaveCombat()
      assert.are.same({ ENTER = "useItem item 6948", USE = false }, actions.prepared)
    end)

    it("prepares nothing for the selected result in combat, and its use action again when combat ends", function()
      GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
      session:Open()
      session:SetQuery("hearth")
      game:EnterCombat()
      assert.are.same({ ENTER = false, USE = false }, actions.prepared)
      game:LeaveCombat()
      assert.are.same({ ENTER = false, USE = "useItem item 6948" }, actions.prepared)
    end)

    describe("with show actions that run through a secure button", function()
      -- The fake action adapter also says which show actions run only from
      -- a key press on a secure button: those in `secure`.
      local function GivenSecureShowActions(secure)
        function actions.NeedsKeyPress(_, actionID)
          return secure[actionID] == true
        end
      end

      it("prepares no show action that the action adapter does not name", function()
        GivenSecureShowActions({ showInTalents = true })
        GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
        GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
        session:Open()
        session:SetQuery("hearth")
        assert.are.same({ ENTER = false, USE = "useItem item 6948" }, actions.prepared)
        OpenList("defias")
        assert.are.same({ ENTER = false, USE = false }, actions.prepared)
      end)

      it("prepares a named show action for Enter, and the use action for the use key, on the same result", function()
        GivenSecureShowActions({ showInBag = true })
        GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
        session:Open()
        session:SetQuery("hearth")
        assert.are.same({ ENTER = "showInBag item 6948", USE = "useItem item 6948" }, actions.prepared)
        session:PressKey("TAB")
        assert.are.same({ ENTER = "showInBag item 6948", USE = false }, actions.prepared)
        session:PressKey("DOWN")
        assert.are.same({ ENTER = "useItem item 6948", USE = false }, actions.prepared)
      end)
    end)

    it("prepares nothing when the selected use action is blocked from the start", function()
      GivenSource("Test.Bags", { Item("Hearthstone", 6948, true) })
      game:EnterCombat()
      OpenList("hearth")
      session:PressKey("DOWN")
      assert.are.same({ ENTER = false, USE = false }, actions.prepared)
    end)
  end)
end)
