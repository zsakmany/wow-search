-- Picks, seen from the edge of the core: a fake source gives entries through
-- the public API, the test types a query and presses keys the way the
-- search bar does, and reads the results in the view state. Each action the
-- core runs is a pick. A fake action adapter takes the actions, a fake
-- combat state blocks use actions, an in-memory storage keeps the picks
-- over a reload, and a fake clock lets days pass.

local FakeGame = require("tests.fake_game")

local HINT = "Search bags, spells, quests…"

local function Item(name, itemID, usable)
  return {
    name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester", inBags = true, usable = usable,
  }
end

local function ItemWithText(name, itemID, longText)
  return {
    name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester", inBags = true, longText = longText,
  }
end

-- The names of the results the search bar shows, top to bottom.
local function Names(view)
  local names = {}
  for i, result in ipairs(view.results) do
    names[i] = result.name
  end
  return names
end

describe("picks", function()
  local game, session, requests

  -- A started game with a fake action adapter and a search session. The
  -- adapter writes down each action that the core asks it to run, as
  -- "action gameID".
  local function NewGame(options)
    game = FakeGame.Started(options)
    requests = {}
    game.ns.SetActionAdapter({
      Run = function(_, actionID, entry)
        requests[#requests + 1] = actionID .. " " .. tostring(entry.gameID)
      end,
    })
    session = game.ns.NewSearchSession()
  end

  before_each(function()
    NewGame()
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

  -- What the search bar shows for this query, from a fresh opening.
  local function Search(query)
    session:Open()
    local view = session:SetQuery(query)
    session:Close()
    return Names(view)
  end

  -- The name of the selected result row.
  local function Selected(view)
    for _, result in ipairs(view.results) do
      if result.selected then
        return result.name
      end
    end
  end

  -- The player opens the search bar, types the query, moves down to the
  -- result with this name, and presses Enter: a pick of that result. With
  -- `times`, the player does it that many times.
  local function Pick(query, name, times)
    for _ = 1, times or 1 do
      session:Open()
      local view = session:SetQuery(query)
      for _ = 1, view.total do
        if Selected(view) == name then
          break
        end
        view = session:PressKey("DOWN")
      end
      assert.are.equal(name, Selected(view))
      session:PressKey("ENTER")
    end
  end

  describe("what counts as a pick", function()
    -- "Hearthstone" and "Hearty Rhino Hide" both match "hearth"; the score
    -- puts "Hearthstone" first.
    local entries = { Item("Hearthstone", 6948, true), Item("Hearty Rhino Hide", 8171, true) }

    -- The player opens the action list of "Hearty Rhino Hide" for "hea",
    -- moves down to its use action, and presses Enter.
    local function UseFromActionList()
      session:Open()
      session:SetQuery("hea")
      session:PressKey("DOWN")
      session:PressKey("TAB")
      session:PressKey("DOWN")
      return session:PressKey("ENTER")
    end

    it("an action from the action list is a pick", function()
      GivenSource("Test.Bags", entries)
      UseFromActionList()
      assert.are.same({ "Hearty Rhino Hide", "Hearthstone" }, Search("hearth"))
    end)

    it("a use action that combat blocks is not a pick", function()
      GivenSource("Test.Bags", entries)
      game:EnterCombat()
      assert.is_true(UseFromActionList().open)
      session:Close()
      game:LeaveCombat()
      assert.are.same({ "Hearthstone", "Hearty Rhino Hide" }, Search("hearth"))
    end)

    it("an action on a result without a game ID is not a pick", function()
      -- A source may leave out the game ID; Seek cannot tell such things
      -- apart.
      GivenSource("Test.Bags", {
        { name = "Healing Potion", kind = "item" },
        { name = "Mana Potion", kind = "item" },
      })
      Pick("potion", "Mana Potion")
      assert.are.same({ "Healing Potion", "Mana Potion" }, Search("potion"))
      assert.are.equal(HINT, session:Open().hint)
    end)

    it("a pick from the empty search bar lifts the result only a little, as for any query", function()
      -- "Heavy Leather" matches "h" 12 points better than "Ashen Axe".
      GivenSource("Test.Bags", { Item("Heavy Leather", 4234), Item("Ashen Axe", 1) })
      Pick("x", "Ashen Axe")
      Pick("", "Ashen Axe", 2)
      assert.are.same({ "Heavy Leather", "Ashen Axe" }, Search("h"))
    end)

    it("a pick of an item from one source lifts the same item from another source", function()
      local bags = { Item("Hearty Rhino Hide", 8171) }
      GivenSource("Test.Bags", bags)
      Pick("hea", "Hearty Rhino Hide")
      -- The player puts the hide into the bank.
      table.remove(bags, 1)
      game.Seek.NotifyChanged("Test.Bags")
      GivenSource("Test.Bank", entries)
      assert.are.same({ "Hearty Rhino Hide", "Hearthstone" }, Search("hearth"))
    end)
  end)

  describe("ranking", function()
    it("lifts a picked result above one that matches slightly better", function()
      -- "h" starts a word in "Heavy Leather" (28 points), but not in
      -- "Ashen Axe" (16).
      GivenSource("Test.Bags", { Item("Heavy Leather", 4234), Item("Ashen Axe", 1) })
      assert.are.same({ "Heavy Leather", "Ashen Axe" }, Search("h"))
      Pick("h", "Ashen Axe", 10)
      assert.are.same({ "Ashen Axe", "Heavy Leather" }, Search("h"))
    end)

    it("does not lift a picked result above one that matches much better", function()
      -- For "sto", "Rough Stone" scores 76 and "Mistletoe" 51: 25 points
      -- more, which no number of picks makes up.
      GivenSource("Test.Bags", { Item("Rough Stone", 2836), Item("Mistletoe", 21519) })
      Pick("sto", "Mistletoe", 50)
      assert.are.same({ "Rough Stone", "Mistletoe" }, Search("sto"))
    end)

    it("a pick made with hea lifts the result for h and for hearth", function()
      -- For "hearth", "Hearthstone" scores 148 and "Hearty Rhino Hide" 142.
      GivenSource("Test.Bags", { Item("Hearthstone", 6948), Item("Hearty Rhino Hide", 8171) })
      assert.are.same({ "Hearthstone", "Hearty Rhino Hide" }, Search("hearth"))
      Pick("hea", "Hearty Rhino Hide")
      assert.are.same({ "Hearty Rhino Hide", "Hearthstone" }, Search("h"))
      assert.are.same({ "Hearty Rhino Hide", "Hearthstone" }, Search("hearth"))
    end)

    it("ignores case and spaces at the ends when it compares queries", function()
      GivenSource("Test.Bags", { Item("Hearthstone", 6948), Item("Hearty Rhino Hide", 8171) })
      Pick("HEA ", "Hearty Rhino Hide")
      assert.are.same({ "Hearty Rhino Hide", "Hearthstone" }, Search("hearth"))
    end)

    it("a pick made with x lifts the result for h much less than one made with h", function()
      -- As above: "Heavy Leather" matches "h" 12 points better.
      GivenSource("Test.Bags", { Item("Heavy Leather", 4234), Item("Ashen Axe", 1) })
      Pick("x", "Ashen Axe", 2)
      assert.are.same({ "Heavy Leather", "Ashen Axe" }, Search("h"))
      Pick("h", "Ashen Axe", 2)
      assert.are.same({ "Ashen Axe", "Heavy Leather" }, Search("h"))
    end)

    it("a pick lifts the result a little for any query that matches it", function()
      -- "Hearthstone" and "Heavy Leather" match "h" equally well; the name
      -- puts "Hearthstone" first.
      GivenSource("Test.Bags", { Item("Hearthstone", 6948), Item("Heavy Leather", 4234) })
      assert.are.same({ "Hearthstone", "Heavy Leather" }, Search("h"))
      Pick("lea", "Heavy Leather")
      assert.are.same({ "Heavy Leather", "Hearthstone" }, Search("h"))
    end)

    it("counts a pick half after 14 days", function()
      -- "Healing Potion" and "Mana Potion" match "potion" equally well; the
      -- name puts "Healing Potion" first.
      GivenSource("Test.Bags", { Item("Healing Potion", 929), Item("Mana Potion", 3827) })
      Pick("potion", "Healing Potion", 3)
      game:PassDays(14)
      -- The 3 old picks count as 1.5 new ones.
      Pick("potion", "Mana Potion")
      assert.are.same({ "Healing Potion", "Mana Potion" }, Search("potion"))
      Pick("potion", "Mana Potion")
      assert.are.same({ "Mana Potion", "Healing Potion" }, Search("potion"))
    end)

    it("never lifts a long text match above a name match, but reorders long text matches", function()
      -- "fire" matches the name "Field Repair Bot 74A", and only the long
      -- text of the other two.
      GivenSource("Test.Bags", {
        Item("Field Repair Bot 74A", 18232),
        ItemWithText("Ember Torch", 1, "Use: Lights a fire."),
        ItemWithText("Flint and Tinder", 4471, "Use: Starts a fire."),
      })
      assert.are.same({ "Field Repair Bot 74A", "Ember Torch", "Flint and Tinder" }, Search("fire"))
      Pick("fire", "Flint and Tinder", 50)
      assert.are.same({ "Field Repair Bot 74A", "Flint and Tinder", "Ember Torch" }, Search("fire"))
    end)

    -- The three examples of the rule in issue #1. "Healing Potion" and
    -- "Hearthstone" match "h" equally well (28 points each), and
    -- "Healing Potion" does not match "hearth" at all.
    describe("the examples of issue #1", function()
      local entries = {
        Item("Hearthstone", 6948),
        Item("Healing Potion", 929),
        Item("Heavy Leather", 4234),
        Item("Ashen Axe", 1),
      }

      it("1. after 10 picks of Healing Potion with h, it ranks first for h", function()
        GivenSource("Test.Bags", entries)
        Pick("h", "Healing Potion", 10)
        assert.are.equal("Healing Potion", Search("h")[1])
      end)

      it("2. after the same picks, Hearthstone ranks first for hearth", function()
        GivenSource("Test.Bags", entries)
        Pick("h", "Healing Potion", 10)
        assert.are.equal("Hearthstone", Search("hearth")[1])
      end)

      it("3. with no picks, the order is by match only, as before picks", function()
        GivenSource("Test.Bags", entries)
        -- Best score first, then by name (see matching_spec.lua).
        assert.are.same({ "Healing Potion", "Hearthstone", "Heavy Leather", "Ashen Axe" }, Search("h"))
        assert.are.same({ "Hearthstone" }, Search("hearth"))
      end)
    end)
  end)

  describe("the empty search bar", function()
    -- "Potion 01" to "Potion 10", item IDs 1 to 10.
    local potions
    before_each(function()
      potions = {}
      for i = 1, 10 do
        potions[i] = Item(("Potion %02d"):format(i), i)
      end
    end)

    it("shows the hint and no results when the player has no picks", function()
      GivenSource("Test.Bags", potions)
      local view = session:Open()
      assert.are.same({}, view.results)
      assert.are.equal(HINT, view.hint)
      assert.is_nil(view.noResults)
    end)

    it("shows the 8 most recent picks, newest first, each thing once", function()
      GivenSource("Test.Bags", potions)
      for i = 1, 10 do
        Pick(("potion %02d"):format(i), potions[i].name)
      end
      Pick("potion 05", "Potion 05")
      local view = session:Open()
      assert.are.same({
        "Potion 05", "Potion 10", "Potion 09", "Potion 08",
        "Potion 07", "Potion 06", "Potion 04", "Potion 03",
      }, Names(view))
      assert.are.equal(8, view.total)
      assert.is_nil(view.hint)
      assert.is_nil(view.noResults)
      assert.are.equal("Potion 05", Selected(view))
    end)

    it("leaves out things the player no longer has, and shows them again when they come back", function()
      GivenSource("Test.Bags", potions)
      Pick("potion 01", "Potion 01")
      Pick("potion 02", "Potion 02")
      local drunk = table.remove(potions, 2)
      game.Seek.NotifyChanged("Test.Bags")
      assert.are.same({ "Potion 01" }, Names(session:Open()))

      table.insert(potions, drunk)
      game.Seek.NotifyChanged("Test.Bags")
      assert.are.same({ "Potion 02", "Potion 01" }, Names(session:Open()))
    end)

    it("shows the hint when the player no longer has any picked thing", function()
      GivenSource("Test.Bags", potions)
      Pick("potion 01", "Potion 01")
      table.remove(potions, 1)
      game.Seek.NotifyChanged("Test.Bags")
      local view = session:Open()
      assert.are.same({}, view.results)
      assert.are.equal(HINT, view.hint)
    end)

    it("leaves out a picked thing that is left only as a faded result (no actions)", function()
      GivenSource("Test.Bags", potions)
      -- Another source has the same thing, but not in the bags: no actions.
      GivenSource("Test.Elsewhere", { { name = "Potion 01", icon = 134400, kind = "item", gameID = 1 } })
      Pick("potion 01", "Potion 01")
      assert.are.same({ "Potion 01" }, Names(session:Open()))
      table.remove(potions, 1)
      game.Seek.NotifyChanged("Test.Bags")
      local view = session:Open()
      assert.are.same({}, view.results)
      assert.are.equal(HINT, view.hint)
    end)

    it("works like other results: Enter, Down, and the action list", function()
      GivenSource("Test.Bags", potions)
      Pick("potion 01", "Potion 01")
      Pick("potion 02", "Potion 02")
      requests = {}
      session:Open()
      session:PressKey("ENTER")
      assert.are.same({ "showInBag 2" }, requests)

      session:Open()
      session:PressKey("DOWN")
      local view = session:PressKey("TAB")
      assert.are.equal("Show in bag", view.actionList.rows[1].label)
      session:PressKey("ENTER")
      assert.are.same({ "showInBag 2", "showInBag 1" }, requests)
    end)
  end)

  describe("over a reload", function()
    local entries = { Item("Hearthstone", 6948), Item("Hearty Rhino Hide", 8171) }

    -- A /reload: the source registers again (with `sourceEntries`, or else
    -- `entries`) and the core starts, as in WoW. With `inCombat`, the
    -- player is in combat, and search uses the saved copy. The test goes on
    -- with the new game and a new search session.
    local function Reload(options, sourceEntries)
      game = game:Reload(options)
      game.ns.SetActionAdapter({ Run = function() end })
      GivenSource("Test.Bags", sourceEntries or entries)
      game:Start()
      session = game.ns.NewSearchSession()
    end

    it("keeps the picks", function()
      GivenSource("Test.Bags", entries)
      Pick("hea", "Hearty Rhino Hide")
      Reload()
      assert.are.same({ "Hearty Rhino Hide", "Hearthstone" }, Search("hearth"))
      assert.are.same({ "Hearty Rhino Hide" }, Names(session:Open()))
    end)

    it("keeps the picks and the saved copy, whichever was saved last", function()
      GivenSource("Test.Bags", entries)
      Pick("hea", "Hearty Rhino Hide")
      -- The source is read again, and the saved copy saved again.
      game.Seek.NotifyChanged("Test.Bags")
      Reload({ inCombat = true })
      assert.are.same({ "Hearty Rhino Hide", "Hearthstone" }, Search("hearth"))
    end)

    it("keeps the 200 most recent picks", function()
      -- "Healing Potion" and "Mana Potion" match "potion" equally well; the
      -- name puts "Healing Potion" first.
      local items = { Item("Healing Potion", 929), Item("Mana Potion", 3827) }
      for i = 1, 200 do
        items[#items + 1] = Item(("Rune %03d"):format(i), 1000 + i)
      end
      GivenSource("Test.Bags", items)
      Pick("potion", "Mana Potion")
      for i = 1, 199 do
        Pick(("rune %03d"):format(i), ("Rune %03d"):format(i))
      end
      assert.are.same({ "Mana Potion", "Healing Potion" }, Search("potion"))
      -- The 201st pick: the pick of "Mana Potion" is the oldest, and goes.
      Pick("rune 200", "Rune 200")
      assert.are.same({ "Healing Potion", "Mana Potion" }, Search("potion"))
      Reload({}, items)
      assert.are.same({ "Healing Potion", "Mana Potion" }, Search("potion"))
      assert.are.equal("Rune 200", Names(session:Open())[1])
    end)

    it("drops picks older than 90 days", function()
      GivenSource("Test.Bags", entries)
      Pick("hea", "Hearty Rhino Hide")
      game:PassDays(89)
      assert.are.same({ "Hearty Rhino Hide" }, Names(session:Open()))
      game:PassDays(2)
      assert.are.equal(HINT, session:Open().hint)
      Reload()
      assert.are.equal(HINT, session:Open().hint)
    end)

    describe("saved data from before picks", function()
      -- Starts a game in combat (so search uses the saved copy) with this
      -- saved data, as an earlier version of Seek saved it.
      local function StartWith(data)
        game = FakeGame.New({ inCombat = true })
        game.storage.data = data
        GivenSource("Test.Bags", {})
        game:Start()
        session = game.ns.NewSearchSession()
      end

      local savedCopy = {
        ["Test.Bags"] = { { name = "Hearthstone", kind = "item", icon = 134400, gameID = 6948, owner = "Tester" } },
      }

      it("still loads, with no picks", function()
        StartWith({ version = 2, sources = savedCopy })
        assert.are.same({ "Hearthstone" }, Search("hearth"))
        assert.are.equal(HINT, session:Open().hint)
      end)

      it("with picks of an unknown version still loads the saved copy, and ignores the picks", function()
        StartWith({
          version = 2,
          sources = savedCopy,
          picks = { version = 99, list = { { kind = "item", gameID = 6948, query = "h", time = game.clock:Now() } } },
        })
        assert.are.same({ "Hearthstone" }, Search("hearth"))
        assert.are.equal(HINT, session:Open().hint)
      end)
    end)
  end)
end)
