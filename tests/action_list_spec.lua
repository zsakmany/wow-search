-- The action list, seen from the edge of the core: a fake source gives
-- entries through the public API, the test types a query and presses keys
-- the way the search bar does, reads the view state, and a fake action
-- adapter writes down each action that the core asks it to run.

local FakeGame = require("tests.fake_game")

local function Item(name, itemID)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester", inBags = true }
end

local function Quest(title, questID)
  return { name = title, icon = 133745, kind = "quest", gameID = questID, owner = "Tester" }
end

-- The labels of the action list's rows, top to bottom, and the label of the
-- selected row. Nil when the action list is closed.
local function ListRows(view)
  if not view.actionList then
    return nil
  end
  local labels, selected = {}, nil
  for i, row in ipairs(view.actionList.rows) do
    labels[i] = row.label
    if row.selected then
      selected = row.label
    end
  end
  return labels, selected
end

-- The name of the selected result row.
local function SelectedResult(view)
  for _, result in ipairs(view.results) do
    if result.selected then
      return result.name
    end
  end
end

describe("the action list", function()
  local game, session, requests

  before_each(function()
    game = FakeGame.Started()
    -- The fake action adapter: each request is the action id, and the kind
    -- and game ID of the entry.
    requests = {}
    game.ns.SetActionAdapter({
      Run = function(_, actionID, entry)
        requests[#requests + 1] = { action = actionID, kind = entry.kind, gameID = entry.gameID }
      end,
    })
    session = game.ns.NewSearchSession()
  end)

  -- Registers a fake source with this id and these entries. The source
  -- gives whatever `entries` holds when Seek reads it.
  local function GivenSource(id, entries)
    game.Seek.RegisterSource({
      id = id,
      GetEntries = function()
        return entries
      end,
    })
  end

  it("is closed while the player only searches", function()
    GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
    session:Open()
    assert.is_nil(session:SetQuery("defias").actionList)
  end)

  it("opens on Tab with the quest's actions, the main action first and selected", function()
    GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
    session:Open()
    session:SetQuery("defias")
    local view = session:PressKey("TAB")
    local labels, selected = ListRows(view)
    assert.are.same({ "Show in quest log", "Show on map" }, labels)
    assert.are.equal("Show in quest log", selected)
    assert.is_true(view.open)
    assert.are.equal("The Defias Brotherhood", SelectedResult(view))
    assert.are.same({}, requests)
  end)

  it("moves with Up and Down, and stays on the first and last action", function()
    GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
    session:Open()
    session:SetQuery("defias")
    session:PressKey("TAB")
    local _, selected = ListRows(session:PressKey("DOWN"))
    assert.are.equal("Show on map", selected)
    _, selected = ListRows(session:PressKey("DOWN"))
    assert.are.equal("Show on map", selected)
    _, selected = ListRows(session:PressKey("UP"))
    assert.are.equal("Show in quest log", selected)
    _, selected = ListRows(session:PressKey("UP"))
    assert.are.equal("Show in quest log", selected)
  end)

  it("runs the selected action on Enter, and closes the search bar", function()
    GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
    session:Open()
    session:SetQuery("defias")
    session:PressKey("TAB")
    session:PressKey("DOWN")
    local view = session:PressKey("ENTER")
    assert.are.same({ { action = "showOnMap", kind = "quest", gameID = 65 } }, requests)
    assert.is_false(view.open)
    assert.is_nil(view.actionList)
  end)

  it("runs the main action on Enter when the player has not moved in the list", function()
    GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
    session:Open()
    session:SetQuery("defias")
    session:PressKey("TAB")
    session:PressKey("ENTER")
    assert.are.same({ { action = "openQuestLog", kind = "quest", gameID = 65 } }, requests)
  end)

  it("belongs to the selected result, and Up and Down in it leave the results alone", function()
    GivenSource("Test.Quests", {
      Quest("The Defias Brotherhood", 65),
      Quest("The Defias Traitor", 155),
    })
    session:Open()
    session:SetQuery("defias")
    session:PressKey("DOWN")
    session:PressKey("TAB")
    local view = session:PressKey("DOWN")
    assert.are.equal("The Defias Traitor", SelectedResult(view))
    session:PressKey("ENTER")
    assert.are.same({ { action = "showOnMap", kind = "quest", gameID = 155 } }, requests)
  end)

  it("closes on Escape, back at the same result; a second Escape closes the search bar", function()
    GivenSource("Test.Quests", {
      Quest("The Defias Brotherhood", 65),
      Quest("The Defias Traitor", 155),
    })
    session:Open()
    session:SetQuery("defias")
    session:PressKey("DOWN")
    session:PressKey("TAB")
    session:PressKey("DOWN")

    local view = session:PressKey("ESCAPE")
    assert.is_nil(view.actionList)
    assert.is_true(view.open)
    assert.are.equal("defias", view.query)
    assert.are.equal("The Defias Traitor", SelectedResult(view))

    view = session:PressKey("ESCAPE")
    assert.is_false(view.open)
    assert.are.same({}, requests)
  end)

  it("works with the results again after Escape", function()
    GivenSource("Test.Quests", {
      Quest("The Defias Brotherhood", 65),
      Quest("The Defias Traitor", 155),
    })
    session:Open()
    session:SetQuery("defias")
    session:PressKey("TAB")
    session:PressKey("ESCAPE")
    assert.are.equal("The Defias Traitor", SelectedResult(session:PressKey("DOWN")))
    session:PressKey("ENTER")
    assert.are.same({ { action = "openQuestLog", kind = "quest", gameID = 155 } }, requests)
  end)

  it("does not open on Tab when nothing matches", function()
    GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
    session:Open()
    session:SetQuery("zzz")
    local view = session:PressKey("TAB")
    assert.is_nil(view.actionList)
    assert.is_true(view.open)
    assert.are.equal("zzz", view.query)
    -- Enter and Escape still work as without a list.
    assert.is_true(session:PressKey("ENTER").open)
    assert.is_false(session:PressKey("ESCAPE").open)
    assert.are.same({}, requests)
  end)

  it("does not open on Tab while the query is empty", function()
    GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
    session:Open()
    local view = session:PressKey("TAB")
    assert.is_nil(view.actionList)
    assert.is_true(view.open)
  end)

  it("closes when the player types, and the results follow the new query", function()
    GivenSource("Test.Quests", {
      Quest("The Defias Brotherhood", 65),
      Quest("The Defias Traitor", 155),
    })
    session:Open()
    session:SetQuery("defias")
    session:PressKey("TAB")
    local view = session:SetQuery("defias t")
    assert.is_nil(view.actionList)
    assert.are.equal("The Defias Traitor", SelectedResult(view))
    session:PressKey("ENTER")
    assert.are.same({ { action = "openQuestLog", kind = "quest", gameID = 155 } }, requests)
  end)

  it("is closed when the search bar opens again", function()
    GivenSource("Test.Quests", { Quest("The Defias Brotherhood", 65) })
    session:Open()
    session:SetQuery("defias")
    session:PressKey("TAB")
    assert.is_nil(session:Toggle().actionList)
    assert.is_nil(session:Toggle().actionList)
  end)

  it("stays open when the source's data changes and the selected result is the same", function()
    local quests = { Quest("The Defias Brotherhood", 65) }
    GivenSource("Test.Quests", quests)
    session:Open()
    session:SetQuery("defias")
    session:PressKey("TAB")
    session:PressKey("DOWN")
    -- A new quest that does not match the query comes into the log.
    quests[2] = Quest("Wolves Across the Border", 33)
    game.Seek.NotifyChanged("Test.Quests")
    local _, selected = ListRows(session:View())
    assert.are.equal("Show on map", selected)
    session:PressKey("ENTER")
    assert.are.same({ { action = "showOnMap", kind = "quest", gameID = 65 } }, requests)
  end)

  it("closes when the source's data changes and the selected result is gone", function()
    local quests = { Quest("The Defias Brotherhood", 65), Quest("The Defias Traitor", 155) }
    GivenSource("Test.Quests", quests)
    session:Open()
    session:SetQuery("defias")
    session:PressKey("TAB")
    -- The player turns in the selected quest.
    table.remove(quests, 1)
    game.Seek.NotifyChanged("Test.Quests")
    local view = session:View()
    assert.is_nil(view.actionList)
    assert.are.equal("The Defias Traitor", SelectedResult(view))
  end)

  it("shows the main action alone for an item", function()
    GivenSource("Test.Bags", { Item("Hearthstone", 6948) })
    session:Open()
    session:SetQuery("hearth")
    local labels, selected = ListRows(session:PressKey("TAB"))
    assert.are.same({ "Show in bag" }, labels)
    assert.are.equal("Show in bag", selected)
    session:PressKey("ENTER")
    assert.are.same({ { action = "showInBag", kind = "item", gameID = 6948 } }, requests)
  end)

  it("does not open for an item that is not in the character's bags, and Enter does nothing", function()
    -- Not in the bags: the entry has no `inBags`.
    GivenSource("Test.Things", { { name = "Hearthstone", icon = 134400, kind = "item", gameID = 6948 } })
    session:Open()
    session:SetQuery("hearth")
    local view = session:PressKey("TAB")
    assert.is_nil(view.actionList)
    view = session:PressKey("ENTER")
    assert.is_true(view.open)
    assert.are.equal("Hearthstone", SelectedResult(view))
    assert.are.same({}, requests)
  end)
end)
