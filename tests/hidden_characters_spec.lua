-- Hidden characters, seen from the edge of the core: each of the player's
-- characters logs in (a fake game with the character's own saved data and
-- the account's shared saved data), a fake bag source with the id of Seek's
-- bag source gives the character's items, the test lists the other
-- characters and changes the setting of the hidden characters the way
-- Seek's settings page does, and searches the way the search bar does.

local FakeGame = require("tests.fake_game")

-- An item as Seek's bag source gives it: in the current character's bags.
local function Item(name, itemID, owner)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = owner, inBags = true }
end

-- Each result row of the view as "name | kind text", top to bottom.
local function Rows(view)
  local rows = {}
  for i, result in ipairs(view.results) do
    rows[i] = result.name .. " | " .. result.kindLabel
  end
  return rows
end

-- Starts `game`, whose bag source gives whatever `items` holds when Seek
-- reads it. Returns the game and a search session.
local function Start(game, items)
  game.Seek.RegisterSource({
    id = game.ns.BAG_SOURCE_ID,
    GetEntries = function()
      return items
    end,
  })
  game:Start()
  return game, game.ns.NewSearchSession()
end

-- `character` logs in: on the account of `from` (a game of another
-- character), or on a new account when `from` is nil, with these `items`.
-- Returns the started game and a search session.
local function LogIn(from, character, items)
  return Start(from and from:LogIn(character) or FakeGame.New({ character = character }), items)
end

-- The result rows for this query, from a fresh opening.
local function Search(session, query)
  session:Open()
  local view = session:SetQuery(query)
  session:Close()
  return Rows(view)
end

-- The player hides these characters (by owner) on Seek's settings page and
-- shows all others.
local function Hide(game, ...)
  local hidden = {}
  for _, owner in ipairs({ ... }) do
    hidden[owner] = true
  end
  game:ChangeSetting("hiddenCharacters", hidden)
end

describe("a hidden character", function()
  local carol

  -- Bob and Carol have logged in once: Bob with silk cloth in the bags,
  -- Carol, on another realm, with wool cloth.
  before_each(function()
    local bob = LogIn(nil, "Bob-Stormrage", { Item("Silk Cloth", 4306, "Bob-Stormrage") })
    carol = LogIn(bob, "Carol-ArgentDawn", { Item("Wool Cloth", 2592, "Carol-ArgentDawn") })
  end)

  it("leaves the results at once, and comes back when the player shows it again", function()
    local alice, session = LogIn(carol, "Alice-Stormrage", {})
    assert.are.same({ "Silk Cloth | Item · Bob" }, Search(session, "silk"))
    Hide(alice, "Bob-Stormrage")
    assert.are.same({}, Search(session, "silk"))
    Hide(alice)
    assert.are.same({ "Silk Cloth | Item · Bob" }, Search(session, "silk"))
  end)

  it("leaves the other characters' items, and the current character's own, as they are", function()
    local alice, session = LogIn(carol, "Alice-Stormrage", { Item("Linen Cloth", 2589, "Alice-Stormrage") })
    Hide(alice, "Bob-Stormrage")
    assert.are.same({ "Linen Cloth | Item", "Wool Cloth | Item · Carol-ArgentDawn" }, Search(session, "cloth"))
  end)

  it("is in the list of the other characters, as hidden; the current character never is", function()
    local alice = LogIn(carol, "Alice-Stormrage", { Item("Hearthstone", 6948, "Alice-Stormrage") })
    assert.are.same({
      { owner = "Bob-Stormrage", shownName = "Bob", hidden = false },
      { owner = "Carol-ArgentDawn", shownName = "Carol-ArgentDawn", hidden = false },
    }, alice.ns.OtherCharacters())
    Hide(alice, "Bob-Stormrage")
    assert.are.same({
      { owner = "Bob-Stormrage", shownName = "Bob", hidden = true },
      { owner = "Carol-ArgentDawn", shownName = "Carol-ArgentDawn", hidden = false },
    }, alice.ns.OtherCharacters())
  end)

  it("stays hidden after a reload", function()
    local alice = LogIn(carol, "Alice-Stormrage", {})
    Hide(alice, "Bob-Stormrage")
    local _, session = Start(alice:Reload(), {})
    assert.are.same({}, Search(session, "silk"))
  end)

  it("stays hidden while a character that Seek sees for the first time is shown", function()
    local alice = LogIn(carol, "Alice-Stormrage", {})
    Hide(alice, "Bob-Stormrage")
    local dave = LogIn(alice, "Dave-Stormrage", { Item("Runecloth", 14047, "Dave-Stormrage") })
    local _, session = LogIn(dave, "Alice-Stormrage", {})
    assert.are.same({ "Wool Cloth | Item · Carol-ArgentDawn", "Runecloth | Item · Dave" }, Search(session, "cloth"))
  end)

  it("keeps its bags: they follow its logins, and show when the player shows it again", function()
    local alice = LogIn(carol, "Alice-Stormrage", {})
    Hide(alice, "Bob-Stormrage")
    local bob = LogIn(alice, "Bob-Stormrage", { Item("Mageweave Cloth", 4338, "Bob-Stormrage") })
    local again, session = LogIn(bob, "Alice-Stormrage", {})
    assert.are.same({ "Wool Cloth | Item · Carol-ArgentDawn" }, Search(session, "cloth"))
    Hide(again)
    assert.are.same({
      "Mageweave Cloth | Item · Bob",
      "Wool Cloth | Item · Carol-ArgentDawn",
    }, Search(session, "cloth"))
  end)

  it("in combat, leaves the results when combat ends", function()
    local alice, session = LogIn(carol, "Alice-Stormrage", {})
    alice:EnterCombat()
    Hide(alice, "Bob-Stormrage")
    assert.are.same({ "Silk Cloth | Item · Bob" }, Search(session, "silk"))
    alice:LeaveCombat()
    alice:RunSteps()
    assert.are.same({}, Search(session, "silk"))
  end)
end)
