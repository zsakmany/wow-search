-- Removed characters, seen from the edge of the core: each of the player's
-- characters logs in (a fake game with the character's own saved data and
-- the account's shared saved data), a fake bag source with the id of Seek's
-- bag source gives the character's items, the test lists and removes saved
-- characters the way Seek's settings page does, and searches the way the
-- search bar does.

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

describe("a removed character", function()
  local carol

  -- Bob and Carol have logged in once: Bob with silk cloth in the bags,
  -- Carol, on another realm, with wool cloth.
  before_each(function()
    local bob = LogIn(nil, "Bob-Stormrage", { Item("Silk Cloth", 4306, "Bob-Stormrage") })
    carol = LogIn(bob, "Carol-ArgentDawn", { Item("Wool Cloth", 2592, "Carol-ArgentDawn") })
  end)

  it("can be chosen from the other characters whose bags Seek keeps, never the current one", function()
    local alice = LogIn(carol, "Alice-Stormrage", { Item("Hearthstone", 6948, "Alice-Stormrage") })
    assert.are.same({
      { owner = "Bob-Stormrage", shownName = "Bob" },
      { owner = "Carol-ArgentDawn", shownName = "Carol-ArgentDawn" },
    }, alice.ns.OtherCharacters())
  end)

  it("leaves the results at once, and the list of other characters", function()
    local alice, session = LogIn(carol, "Alice-Stormrage", {})
    assert.are.same({ "Silk Cloth | Item · Bob" }, Search(session, "silk"))
    alice.ns.RemoveCharacter("Bob-Stormrage")
    assert.are.same({}, Search(session, "silk"))
    assert.are.same({ { owner = "Carol-ArgentDawn", shownName = "Carol-ArgentDawn" } }, alice.ns.OtherCharacters())
  end)

  it("leaves the other characters' items, and the current character's own, as they are", function()
    local alice, session = LogIn(carol, "Alice-Stormrage", { Item("Linen Cloth", 2589, "Alice-Stormrage") })
    alice.ns.RemoveCharacter("Bob-Stormrage")
    assert.are.same({ "Linen Cloth | Item", "Wool Cloth | Item · Carol-ArgentDawn" }, Search(session, "cloth"))
  end)

  it("stays removed after a reload, and on the account's other characters", function()
    local alice = LogIn(carol, "Alice-Stormrage", {})
    alice.ns.RemoveCharacter("Bob-Stormrage")

    local reloaded, session = Start(alice:Reload(), {})
    assert.are.same({}, Search(session, "silk"))
    assert.are.same({ { owner = "Carol-ArgentDawn", shownName = "Carol-ArgentDawn" } }, reloaded.ns.OtherCharacters())

    local _, daveSession = LogIn(alice, "Dave-Stormrage", {})
    assert.are.same({}, Search(daveSession, "silk"))
  end)

  it("comes back when it logs in again, with the bags it has then", function()
    local alice = LogIn(carol, "Alice-Stormrage", {})
    alice.ns.RemoveCharacter("Bob-Stormrage")
    local bob = LogIn(alice, "Bob-Stormrage", { Item("Mageweave Cloth", 4338, "Bob-Stormrage") })
    local again, session = LogIn(bob, "Alice-Stormrage", {})
    assert.are.same({
      "Mageweave Cloth | Item · Bob",
      "Wool Cloth | Item · Carol-ArgentDawn",
    }, Search(session, "cloth"))
    assert.are.same({
      { owner = "Bob-Stormrage", shownName = "Bob" },
      { owner = "Carol-ArgentDawn", shownName = "Carol-ArgentDawn" },
    }, again.ns.OtherCharacters())
  end)

  it("can be removed while \"Show other characters' bags\" is off, and stays away when it is on again", function()
    local alice, session = LogIn(carol, "Alice-Stormrage", {})
    alice:ChangeSetting("otherCharactersBags", false)
    assert.are.same({
      { owner = "Bob-Stormrage", shownName = "Bob" },
      { owner = "Carol-ArgentDawn", shownName = "Carol-ArgentDawn" },
    }, alice.ns.OtherCharacters())
    alice.ns.RemoveCharacter("Bob-Stormrage")
    alice:ChangeSetting("otherCharactersBags", true)
    assert.are.same({ "Wool Cloth | Item · Carol-ArgentDawn" }, Search(session, "cloth"))
  end)
end)
