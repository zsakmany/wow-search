-- Talents, seen from the edge of the core: a fake source gives talent
-- entries through the public API, with their spent and possible points;
-- the test types a query and presses keys the way the search bar does,
-- reads the view state, turns a fake combat state on and off, and a fake
-- action adapter writes down each action that the core asks it to run or
-- to prepare.

local FakeGame = require("tests.fake_game")

-- A talent entry, with its points (spent and possible) and its long text.
local function Talent(name, entryID, spentPoints, possiblePoints, longText)
  return {
    name = name, icon = 135812, kind = "talent", gameID = entryID, owner = "Tester",
    spentPoints = spentPoints, possiblePoints = possiblePoints, longText = longText,
  }
end

-- Each result row of the view as "name | kind text", top to bottom.
local function Rows(view)
  local rows = {}
  for i, result in ipairs(view.results) do
    rows[i] = result.name .. " | " .. result.kindLabel
  end
  return rows
end

describe("a talent", function()
  local game, session, requests

  before_each(function()
    game = FakeGame.Started()
    -- The fake action adapter: each request is "action name".
    requests = {}
    game.ns.SetActionAdapter({
      Run = function(_, actionID, entry)
        requests[#requests + 1] = actionID .. " " .. entry.name
      end,
    })
    session = game.ns.NewSearchSession()
  end)

  -- Registers a fake source with these entries.
  local function GivenEntries(entries)
    game.Seek.RegisterSource({
      id = "Test.Talents",
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

  it("is found by its name, and its kind text shows its spent and possible points", function()
    GivenEntries({ Talent("Improved Fireball", 1001, 2, 3) })
    assert.are.same({ "Improved Fireball | Talent · 2/3" }, Search("fireball"))
  end)

  it("with no points spent shows 0 points in its kind text", function()
    GivenEntries({ Talent("Blazing Speed", 1002, 0, 1) })
    assert.are.same({ "Blazing Speed | Talent · 0/1" }, Search("blazing"))
  end)

  it("is found by a word of its description", function()
    GivenEntries({
      Talent("Improved Fireball", 1001, 2, 3, "Reduces the casting time of your Fireball spell by 0.2 sec."),
    })
    assert.are.same({ "Improved Fireball | Talent · 2/3" }, Search("casting"))
  end)

  it("leaves out points that make no sense, such as 3 of 2 or 1.5; the talent is still found",
    function()
      GivenEntries({
        Talent("Arcane Focus", 2001, 4, 3),
        Talent("Arcane Mind", 2002, -1, 3),
        Talent("Arcane Power", 2003, 0.5, 1),
        Talent("Arcane Shield", 2004, 0, 0),
        Talent("Arcane Subtlety", 2005, "1", 2),
        Talent("Arcane Barrage", 2006, 1, math.huge),
        Talent("Arcane Blast", 2007, 1, nil),
        Talent("Arcane Bolt", 2008, nil, 2),
      })
      assert.are.same({
        "Arcane Barrage | Talent", "Arcane Blast | Talent", "Arcane Bolt | Talent", "Arcane Focus | Talent",
        "Arcane Mind | Talent", "Arcane Power | Talent", "Arcane Shield | Talent", "Arcane Subtlety | Talent",
      }, Search("arcane"))
    end)

  it("gives its row's kind, game ID, and spent points, for the game's talent tooltip at that rank", function()
    GivenEntries({ Talent("Improved Fireball", 1001, 2, 3) })
    session:Open()
    local result = session:SetQuery("fireball").results[1]
    assert.are.same({ "talent", 1001, 2 }, { result.kind, result.gameID, result.spentPoints })
  end)

  it("has one action, Show in talents, and its row is not faded", function()
    GivenEntries({ Talent("Blazing Speed", 1002, 0, 1) })
    session:Open()
    local view = session:SetQuery("blazing")
    assert.is_false(view.results[1].faded)
    local rows = session:PressKey("TAB").actionList.rows
    assert.are.equal(1, #rows)
    assert.are.equal("Show in talents", rows[1].label)
    assert.are.equal("show", rows[1].type)
  end)

  it("runs Show in talents on Enter, as its main action, with its name", function()
    GivenEntries({ Talent("Blazing Speed", 1002, 0, 1) })
    session:Open()
    session:SetQuery("blazing")
    local view = session:PressKey("ENTER")
    assert.are.same({ "showInTalents Blazing Speed" }, requests)
    assert.is_false(view.open)
  end)

  it("runs Show in talents in combat too: combat never blocks a show action", function()
    GivenEntries({ Talent("Blazing Speed", 1002, 0, 1) })
    game:EnterCombat()
    session:Open()
    session:SetQuery("blazing")
    session:PressKey("ENTER")
    assert.are.same({ "showInTalents Blazing Speed" }, requests)
  end)

  it("has no use action: the use key does nothing", function()
    GivenEntries({ Talent("Blazing Speed", 1002, 0, 1) })
    session:Open()
    session:SetQuery("blazing")
    local view = session:PressKey("USE")
    assert.are.same({}, requests)
    assert.is_true(view.open)
  end)

  it("is a pick after Show in talents: it shows among the recently picked things", function()
    GivenEntries({ Talent("Blazing Speed", 1002, 0, 1), Talent("Improved Fireball", 1001, 2, 3) })
    session:Open()
    session:SetQuery("blazing")
    session:PressKey("ENTER")
    assert.are.same({ "Blazing Speed | Talent · 0/1" }, Search(""))
  end)
end)

describe("a talent's Show in talents, through the secure button", function()
  local game, session, actions

  -- A fake action adapter that runs Show in talents only from a key press
  -- on a secure button, as the WoW action adapter does. `requests` holds
  -- each action that the core asked it to run ("action name"), and
  -- `prepared` what the core asked it to prepare last for each key ("ENTER"
  -- or "USE"): "action name", or false for none.
  local function NewActionAdapter()
    local adapter = { requests = {}, prepared = { ENTER = false, USE = false } }
    function adapter:Run(actionID, entry)
      self.requests[#self.requests + 1] = actionID .. " " .. entry.name
    end
    function adapter:Prepare(key, actionID, entry)
      self.prepared[key] = actionID and (actionID .. " " .. entry.name) or false
    end
    function adapter.NeedsSecureButton(_, actionID)
      return actionID == "showInTalents"
    end
    return adapter
  end

  before_each(function()
    game = FakeGame.Started()
    actions = NewActionAdapter()
    game.ns.SetActionAdapter(actions)
    session = game.ns.NewSearchSession()
    game.Seek.RegisterSource({
      id = "Test.Talents",
      GetEntries = function()
        return { Talent("Blazing Speed", 1002, 0, 1), Talent("Improved Fireball", 1001, 2, 3) }
      end,
    })
  end)

  it("is prepared for Enter while its result is selected", function()
    session:Open()
    session:SetQuery("blazing")
    assert.are.equal("showInTalents Blazing Speed", actions.prepared.ENTER)
    assert.is_false(actions.prepared.USE)
  end)

  it("is prepared for Enter while it is selected in the action list", function()
    session:Open()
    session:SetQuery("fireball")
    session:PressKey("TAB")
    assert.are.same({ ENTER = "showInTalents Improved Fireball", USE = false }, actions.prepared)
  end)

  -- The secure button runs it on the key press; then the search bar sends
  -- Enter to the core, which asks the adapter to run it, as for a use action.
  it("still runs as the main action, a show action, on Enter: it closes the search bar, and is a pick", function()
    session:Open()
    session:SetQuery("blazing")
    local view = session:PressKey("ENTER")
    assert.are.same({ "showInTalents Blazing Speed" }, actions.requests)
    assert.is_false(view.open)
    assert.are.same({ ENTER = false, USE = false }, actions.prepared)

    session:Open()
    assert.are.equal("Blazing Speed", session:View().results[1].name)
    session:PressKey("TAB")
    assert.are.equal("show", session:View().actionList.rows[1].type)
  end)

  -- In combat, WoW lets no addon set up a secure button, so the core
  -- prepares nothing; Enter still reaches the core, as for any show action.
  it("is prepared for nothing in combat, is never blocked there, and is prepared again when combat ends", function()
    session:Open()
    session:SetQuery("blazing")
    game:EnterCombat()
    assert.are.same({ ENTER = false, USE = false }, actions.prepared)
    game:LeaveCombat()
    assert.are.same({ ENTER = "showInTalents Blazing Speed", USE = false }, actions.prepared)

    game:EnterCombat()
    local view = session:PressKey("TAB")
    assert.is_falsy(view.actionList.rows[1].blocked)
    assert.are.same({ ENTER = false, USE = false }, actions.prepared)
    view = session:PressKey("ENTER")
    assert.are.same({ "showInTalents Blazing Speed" }, actions.requests)
    assert.is_false(view.open)
  end)
end)

describe("a talent's points after a reload", function()
  it("show in combat, from the saved copy, before any source is read", function()
    local game = FakeGame.Started()
    game.Seek.RegisterSource({
      id = "Test.Talents",
      GetEntries = function()
        return { Talent("Improved Fireball", 1001, 2, 3) }
      end,
    })

    local after = game:Reload({ inCombat = true })
    local reads = 0
    after.Seek.RegisterSource({
      id = "Test.Talents",
      GetEntries = function()
        reads = reads + 1
        return {}
      end,
    })
    after:Start()
    local session = after.ns.NewSearchSession()
    session:Open()
    assert.are.same({ "Improved Fireball | Talent · 2/3" }, Rows(session:SetQuery("fireball")))
    assert.are.equal(0, reads)
  end)
end)

describe("a talent that teaches a spell", function()
  it("shows as a talent, and the spell shows too, each with its own kind text", function()
    local game = FakeGame.Started()
    game.Seek.RegisterSource({
      id = "Test.Talents",
      GetEntries = function()
        return { Talent("Blast Wave", 11113, 1, 1) }
      end,
    })
    game.Seek.RegisterSource({
      id = "Test.Spells",
      GetEntries = function()
        return { { name = "Blast Wave", icon = 135903, kind = "spell", gameID = 11113, owner = "Tester" } }
      end,
    })
    local session = game.ns.NewSearchSession()
    session:Open()
    assert.are.same({ "Blast Wave | Spell", "Blast Wave | Talent · 1/1" }, Rows(session:SetQuery("blast wave")))
  end)
end)
