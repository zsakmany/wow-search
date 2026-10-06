-- Game options and game option pages, seen from the edge of the core: a
-- fake source gives them through the public API, as the WoW source does
-- from the game's Options window, and the test types a query and presses
-- keys the way the search bar does. A fake action adapter writes down each
-- action that the core asks it to run.

local FakeGame = require("tests.fake_game")

-- A game option on the game option page `page`. Its game ID is a stable
-- text, as the WoW source makes it.
local function GameOption(name, page, longText)
  return { name = name, kind = "gameOption", gameID = page .. "\n" .. name, page = page, longText = longText }
end

-- A game option page: an entry with no page of its own.
local function GameOptionPage(name)
  return { name = name, kind = "gameOption", gameID = name }
end

local function Names(view)
  local names = {}
  for i, result in ipairs(view.results) do
    names[i] = result.name
  end
  return names
end

describe("a game option", function()
  local game, session, requests

  before_each(function()
    game = FakeGame.Started()
    requests = {}
    game.ns.SetActionAdapter({
      Run = function(_, actionID, entry)
        requests[#requests + 1] = { action = actionID, name = entry.name, page = entry.page, gameID = entry.gameID }
      end,
    })
    session = game.ns.NewSearchSession()
  end)

  -- Registers a fake game option source with these entries.
  local function Given(entries)
    game.Seek.RegisterSource({
      id = "Test.GameOptions",
      GetEntries = function()
        return entries
      end,
    })
    session:Open()
  end

  it("opens in the Options window on Enter, at its page, and the search bar closes", function()
    Given({ GameOption("Auto Loot", "Controls") })
    session:SetQuery("auto loot")
    local view = session:PressKey("ENTER")
    assert.are.same({
      { action = "openInOptionsWindow", name = "Auto Loot", page = "Controls", gameID = "Controls\nAuto Loot" },
    }, requests)
    assert.is_false(view.open)
  end)

  it("shows its name and its game option page on its row, with the kind", function()
    Given({ GameOption("Auto Loot", "Controls") })
    local view = session:SetQuery("auto loot")
    assert.are.equal("Auto Loot · Controls", view.results[1].name)
    assert.are.equal("Game option", view.results[1].kindLabel)
  end)

  it("has one action, which the action list shows", function()
    Given({ GameOption("Auto Loot", "Controls") })
    session:SetQuery("auto loot")
    local view = session:PressKey("TAB")
    assert.are.equal(1, #view.actionList.rows)
    assert.are.equal("Open in the Options window", view.actionList.rows[1].label)
    assert.are.equal("show", view.actionList.rows[1].type)
  end)

  it("can be a game option page, which shows only its name and opens on Enter", function()
    Given({ GameOptionPage("Audio"), GameOption("Master Volume", "Audio") })
    local view = session:SetQuery("audio")
    assert.are.same({ "Audio" }, Names(view))
    assert.are.equal("Game option", view.results[1].kindLabel)
    session:PressKey("ENTER")
    assert.are.same({ { action = "openInOptionsWindow", name = "Audio", gameID = "Audio" } }, requests)
  end)

  it("is found by its name, also with letters left out", function()
    Given({ GameOption("Auto Loot", "Controls"), GameOption("Interact on Left Click", "Controls") })
    assert.are.same({ "Auto Loot · Controls" }, Names(session:SetQuery("autlt")))
  end)

  it("is not found by its game option page's name", function()
    Given({ GameOption("Auto Loot", "Controls") })
    assert.are.same({}, Names(session:SetQuery("controls")))
  end)

  it("is found by the start of a word in its long text, but not by letters inside a word", function()
    Given({
      GameOption("Auto Loot", "Controls", "Automatically loot all items when you open a corpse."),
      GameOption("Sticky Targeting", "Controls", "Keeps your target when you click empty ground."),
    })
    assert.are.same({ "Auto Loot · Controls" }, Names(session:SetQuery("corpse")))
    assert.are.same({}, Names(session:SetQuery("orpse")))
    assert.are.same({}, Names(session:SetQuery("crps")))
  end)

  it("ranks a name match above a long text match", function()
    -- "target" is in the name of Sticky Targeting and in the long text of
    -- Auto Loot, which comes first by name alone.
    Given({
      GameOption("Auto Loot", "Controls", "Loots your target's corpse at once."),
      GameOption("Sticky Targeting", "Controls"),
    })
    assert.are.same({ "Sticky Targeting · Controls", "Auto Loot · Controls" }, Names(session:SetQuery("target")))
  end)
end)

describe("a game option after a reload", function()
  -- In the game, the source registers only when the game has built its
  -- pages, after the start, and maybe in combat.
  it("is found in combat with its page, from the saved copy, before the source is read", function()
    local game = FakeGame.Started()
    game.Seek.RegisterSource({
      id = "Test.GameOptions",
      GetEntries = function()
        return { GameOption("Auto Loot", "Controls", "Loots the corpse at once.") }
      end,
    })

    local after = game:Reload({ inCombat = true })
    after:Start()
    local reads = 0
    after.Seek.RegisterSource({
      id = "Test.GameOptions",
      GetEntries = function()
        reads = reads + 1
        return {}
      end,
    })
    local session = after.ns.NewSearchSession()
    session:Open()
    assert.are.same({ "Auto Loot · Controls" }, Names(session:SetQuery("auto loot")))
    assert.are.same({ "Auto Loot · Controls" }, Names(session:SetQuery("corpse")))
    assert.are.equal(0, reads)
  end)
end)
