-- A quest's actions, seen from the edge of the core: a fake source gives
-- quests through the public API, with the facts whether each is tracked
-- and whether it has the focus; the test types a query and presses keys
-- the way the search bar does, reads the view state, turns a fake combat
-- state on and off, and a fake action adapter writes down each action that
-- the core asks it to run.

local FakeGame = require("tests.fake_game")

-- A quest entry. `facts` (optional) holds `tracked` and `focused`.
local function Quest(title, questID, facts)
  facts = facts or {}
  return {
    name = title, icon = 133745, kind = "quest", gameID = questID, owner = "Tester",
    tracked = facts.tracked, focused = facts.focused,
  }
end

-- The action list's rows as "label" or "label (blocked)", top to bottom.
-- Nil when the action list is closed.
local function ListRows(view)
  if not view.actionList then
    return nil
  end
  local rows = {}
  for i, row in ipairs(view.actionList.rows) do
    rows[i] = row.blocked and row.label .. " (blocked)" or row.label
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

describe("a quest's actions", function()
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

  -- Registers a fake source with these quests. The source gives whatever
  -- `quests` holds when Seek reads it.
  local function GivenQuests(quests)
    game.Seek.RegisterSource({
      id = "Test.Quests",
      GetEntries = function()
        return quests
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

  it("are Show on map, Focus, and Track for an untracked quest without the focus", function()
    GivenQuests({ Quest("The Defias Brotherhood", 65) })
    assert.are.same({ "Show on map", "Focus", "Track" }, ListRows(OpenList("defias")))
  end)

  it("are Show on map, Focus, and Untrack for a tracked quest without the focus", function()
    GivenQuests({ Quest("The Defias Brotherhood", 65, { tracked = true }) })
    assert.are.same({ "Show on map", "Focus", "Untrack" }, ListRows(OpenList("defias")))
  end)

  it("are Show on map, Remove Focus, and Untrack for the focused quest", function()
    GivenQuests({ Quest("The Defias Brotherhood", 65, { tracked = true, focused = true }) })
    assert.are.same({ "Show on map", "Remove Focus", "Untrack" }, ListRows(OpenList("defias")))
  end)

  it("are Show on map, Remove Focus, and Track for the focused quest that is not tracked", function()
    GivenQuests({ Quest("The Defias Brotherhood", 65, { focused = true }) })
    assert.are.same({ "Show on map", "Remove Focus", "Track" }, ListRows(OpenList("defias")))
  end)

  it("show the use key next to Focus, or next to Remove Focus on the focused quest", function()
    GivenQuests({
      Quest("The Defias Brotherhood", 65),
      Quest("Wolves Across the Border", 33, { tracked = true, focused = true }),
    })
    assert.are.equal("Focus", UseKeyRow(OpenList("defias")))
    assert.are.equal("Remove Focus", UseKeyRow(OpenList("wolves")))
  end)

  describe("out of combat", function()
    -- The recently picked things, as the search bar shows them on a fresh
    -- opening.
    local function RecentlyPicked()
      local names = {}
      for i, result in ipairs(session:Open().results) do
        names[i] = result.name
      end
      session:Close()
      return names
    end

    it("Enter shows the quest on the map, is a pick, and closes the search bar", function()
      GivenQuests({ Quest("The Defias Brotherhood", 65) })
      session:Open()
      session:SetQuery("defias")
      local view = session:PressKey("ENTER")
      assert.are.same({ { action = "showOnMap", kind = "quest", gameID = 65 } }, requests)
      assert.is_false(view.open)
      assert.are.same({ "The Defias Brotherhood" }, RecentlyPicked())
    end)

    it("the use key focuses the quest, is a pick, and closes the search bar", function()
      GivenQuests({ Quest("The Defias Brotherhood", 65) })
      session:Open()
      session:SetQuery("defias")
      local view = session:PressKey("USE")
      assert.are.same({ { action = "focusQuest", kind = "quest", gameID = 65 } }, requests)
      assert.is_false(view.open)
      assert.are.same({ "The Defias Brotherhood" }, RecentlyPicked())
    end)

    it("the use key removes the focus from the focused quest", function()
      GivenQuests({ Quest("The Defias Brotherhood", 65, { tracked = true, focused = true }) })
      session:Open()
      session:SetQuery("defias")
      local view = session:PressKey("USE")
      assert.are.same({ { action = "removeFocus", kind = "quest", gameID = 65 } }, requests)
      assert.is_false(view.open)
    end)

    it("Track from the action list tracks the quest, is a pick, and closes the search bar", function()
      GivenQuests({ Quest("The Defias Brotherhood", 65) })
      OpenList("defias")
      session:PressKey("DOWN")
      session:PressKey("DOWN")
      local view = session:PressKey("ENTER")
      assert.are.same({ { action = "trackQuest", kind = "quest", gameID = 65 } }, requests)
      assert.is_false(view.open)
      assert.are.same({ "The Defias Brotherhood" }, RecentlyPicked())
    end)

    it("Untrack from the action list untracks the tracked quest", function()
      GivenQuests({ Quest("The Defias Brotherhood", 65, { tracked = true }) })
      OpenList("defias")
      session:PressKey("DOWN")
      session:PressKey("DOWN")
      local view = session:PressKey("ENTER")
      assert.are.same({ { action = "untrackQuest", kind = "quest", gameID = 65 } }, requests)
      assert.is_false(view.open)
    end)
  end)

  describe("in combat", function()
    it("Focus and Track are blocked, and Show on map is not", function()
      GivenQuests({ Quest("The Defias Brotherhood", 65) })
      game:EnterCombat()
      assert.are.same({ "Show on map", "Focus (blocked)", "Track (blocked)" }, ListRows(OpenList("defias")))
    end)

    it("Remove Focus and Untrack are blocked too", function()
      GivenQuests({ Quest("The Defias Brotherhood", 65, { tracked = true, focused = true }) })
      game:EnterCombat()
      assert.are.same({ "Show on map", "Remove Focus (blocked)", "Untrack (blocked)" },
        ListRows(OpenList("defias")))
    end)

    it("the use key runs nothing, is no pick, and shows the sign on the quest", function()
      GivenQuests({ Quest("The Defias Brotherhood", 65) })
      game:EnterCombat()
      session:Open()
      session:SetQuery("defias")
      local view = session:PressKey("USE")
      assert.are.same({}, requests)
      assert.is_true(view.open)
      assert.is_true(view.results[1].blocked)
      session:Close()
      assert.are.same({}, session:Open().results)
    end)

    it("Track from the action list runs nothing, is no pick, and keeps the search bar open", function()
      GivenQuests({ Quest("The Defias Brotherhood", 65) })
      game:EnterCombat()
      OpenList("defias")
      session:PressKey("DOWN")
      session:PressKey("DOWN")
      local view = session:PressKey("ENTER")
      assert.are.same({}, requests)
      assert.is_true(view.open)
      session:Close()
      assert.are.same({}, session:Open().results)
    end)

    it("Enter still shows the quest on the map", function()
      GivenQuests({ Quest("The Defias Brotherhood", 65) })
      game:EnterCombat()
      session:Open()
      session:SetQuery("defias")
      local view = session:PressKey("ENTER")
      assert.are.same({ { action = "showOnMap", kind = "quest", gameID = 65 } }, requests)
      assert.is_false(view.open)
    end)
  end)

  describe("the labels follow the game's state", function()
    it("once the source reads the quests again", function()
      local quests = { Quest("The Defias Brotherhood", 65) }
      GivenQuests(quests)
      assert.are.same({ "Show on map", "Focus", "Track" }, ListRows(OpenList("defias")))
      session:Close()
      -- The player focuses the quest in the game's own UI, which also
      -- tracks it.
      quests[1] = Quest("The Defias Brotherhood", 65, { tracked = true, focused = true })
      game.Seek.NotifyChanged("Test.Quests")
      assert.are.same({ "Show on map", "Remove Focus", "Untrack" }, ListRows(OpenList("defias")))
    end)

    it("from the saved copy after a reload in combat", function()
      GivenQuests({ Quest("The Defias Brotherhood", 65, { tracked = true, focused = true }) })
      -- After the reload, the quest source registers again but is not read
      -- in combat: search uses the saved copy.
      local after = game:Reload({ inCombat = true })
      after.Seek.RegisterSource({
        id = "Test.Quests",
        GetEntries = function()
          return {}
        end,
      })
      after:Start()
      session = after.ns.NewSearchSession()
      assert.are.same({ "Show on map", "Remove Focus (blocked)", "Untrack (blocked)" },
        ListRows(OpenList("defias")))
    end)
  end)
end)
