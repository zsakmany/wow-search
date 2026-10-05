-- Matching and ranking, seen from the edge of the core: a fake source gives
-- entries through the public API, the test types a query the way the search
-- bar does, and reads the results in the view state.

local FakeGame = require("tests.fake_game")

local function Item(name, itemID)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester", inBags = true }
end

local function Spell(name, spellID)
  return { name = name, icon = 135812, kind = "spell", gameID = spellID, owner = "Tester" }
end

-- The names of the results the search bar shows, top to bottom.
local function Names(view)
  local names = {}
  for i, result in ipairs(view.results) do
    names[i] = result.name
  end
  return names
end

local session

-- Registers a fake source with these entries and opens the search bar.
local function Given(entries)
  local ns = FakeGame.Started().ns
  ns.api.RegisterSource({
    id = "Test.Bags",
    GetEntries = function()
      return entries
    end,
  })
  session = ns.NewSearchSession()
  session:Open()
end

describe("matching", function()
  it("finds a name from its letters in order, with gaps", function()
    Given({ Item("Hearthstone", 6948), Item("Linen Cloth", 2589) })
    assert.are.same({ "Hearthstone" }, Names(session:SetQuery("hrth")))
  end)

  it("ignores case", function()
    Given({ Item("Hearthstone", 6948), Item("Linen Cloth", 2589) })
    assert.are.same({ "Hearthstone" }, Names(session:SetQuery("HEARTH")))
  end)

  it("shows each result's icon, name, and kind", function()
    Given({ Item("Hearthstone", 6948) })
    local result = session:SetQuery("hearth").results[1]
    assert.are.equal("Hearthstone", result.name)
    assert.are.equal(134400, result.icon)
    assert.are.equal("item", result.kind)
    assert.are.equal("Item", result.kindLabel)
  end)

  it("ranks a match at a word start higher", function()
    -- Both match "st" as two letters next to each other; only in
    -- "Rough Stone" do they start a word.
    Given({ Item("Frost Lotus", 1), Item("Rough Stone", 2) })
    assert.are.same({ "Rough Stone", "Frost Lotus" }, Names(session:SetQuery("st")))
  end)

  it("ranks letters next to each other higher than letters with a gap", function()
    -- Neither "e" nor "a" starts a word in these names.
    Given({ Item("Iced Water", 1), Item("Leather", 2) })
    assert.are.same({ "Leather", "Iced Water" }, Names(session:SetQuery("ea")))
  end)

  it("keeps the same order for equal scores, whatever order the source gives", function()
    local names = { "Mana Potion", "Healing Potion", "Swiftness Potion" }
    local expected = { "Healing Potion", "Mana Potion", "Swiftness Potion" }

    Given({ Item(names[1], 1), Item(names[2], 2), Item(names[3], 3) })
    assert.are.same(expected, Names(session:SetQuery("potion")))

    Given({ Item(names[3], 3), Item(names[2], 2), Item(names[1], 1) })
    assert.are.same(expected, Names(session:SetQuery("potion")))
  end)

  it("finds UTF-8 names from non-English game clients", function()
    Given({ Item("Großer Heiltrank", 1), Item("Trank der Größe", 2), Item("Ölkanne", 3) })
    assert.are.same({ "Großer Heiltrank" }, Names(session:SetQuery("groß")))
    assert.are.same({ "Großer Heiltrank" }, Names(session:SetQuery("GROß HEIL")))
    assert.are.same({ "Trank der Größe" }, Names(session:SetQuery("größe")))
    assert.are.same({ "Ölkanne" }, Names(session:SetQuery("Ölk")))
  end)

  it("treats letters such as ö and ß as part of a word", function()
    -- The "e" after "ß" does not start a word; the "E" of "Elementar" does.
    Given({ Item("Trank der Größe", 1), Item("Urtümlicher Elementar", 2) })
    assert.are.same({ "Urtümlicher Elementar", "Trank der Größe" }, Names(session:SetQuery("e")))
  end)

  it("ranks spells and items together in one list, best first", function()
    -- "st" starts a word in "Rough Stone" and "Stealth", but not in "Frost
    -- Oil" and "Frostbolt". Equal scores sort by name, whatever the kind.
    Given({
      Item("Frost Oil", 3829),
      Spell("Frostbolt", 116),
      Item("Rough Stone", 2835),
      Spell("Stealth", 1784),
      Spell("Fireball", 133),
    })
    local view = session:SetQuery("st")
    assert.are.same({ "Rough Stone", "Stealth", "Frost Oil", "Frostbolt" }, Names(view))
    local kinds = {}
    for i, result in ipairs(view.results) do
      kinds[i] = result.kindLabel
    end
    assert.are.same({ "Item", "Spell", "Item", "Spell" }, kinds)
  end)
end)

-- The letters of a result's name that matched the query: the search bar
-- shows them in gold. Positions count whole letters, not bytes.
describe("matched letters", function()
  -- The matched letter positions of each result row, top to bottom. A row
  -- with no matched letters gives an empty list.
  local function MatchedLetters(view)
    local letters = {}
    for i, result in ipairs(view.results) do
      letters[i] = result.matchedLetters or {}
    end
    return letters
  end

  it("gives the letters that the ranking used", function()
    -- H, then r, t, h right after each other: H(1) r(4) t(5) h(6), not the
    -- second t (8).
    Given({ Item("Hearthstone", 6948) })
    assert.are.same({ { 1, 4, 5, 6 } }, MatchedLetters(session:SetQuery("hrth")))
  end)

  it("gives the best-scoring way when the name matches in several ways", function()
    -- "he" fits "Heavy Leather" at "He" (a word start) and at "he" in
    -- "Leather"; the word start scores higher.
    Given({ Item("Heavy Leather", 4234) })
    assert.are.same({ { 1, 2 } }, MatchedLetters(session:SetQuery("he")))
    -- Not the first fit ("he" in "Shell"), but the word start "He".
    Given({ Item("Shell Helmet", 1) })
    assert.are.same({ { 7, 8 } }, MatchedLetters(session:SetQuery("he")))
  end)

  it("counts whole letters in UTF-8 names, not bytes", function()
    -- "ö" and "ß" take two bytes each; the letters of "Größe" are 11 to 15.
    Given({ Item("Trank der Größe", 1) })
    assert.are.same({ { 11, 12, 13, 14, 15 } }, MatchedLetters(session:SetQuery("größe")))
  end)

  it("gives no letters for a result found only by its long text", function()
    local hearthstone = Item("Hearthstone", 6948)
    hearthstone.longText = "Use: Returns you to Goldshire."
    Given({ hearthstone, Item("Golden Pearl", 7971) })
    local view = session:SetQuery("gold")
    assert.are.same({ "Golden Pearl", "Hearthstone" }, Names(view))
    assert.are.same({ { 1, 2, 3, 4 }, {} }, MatchedLetters(view))
  end)

  it("gives no letters for the recently picked things in the empty search bar", function()
    Given({ Item("Hearthstone", 6948) })
    session:SetQuery("hearth")
    session:PressKey("ENTER") -- a pick; it closes the search bar
    local view = session:Open()
    assert.are.same({ "Hearthstone" }, Names(view))
    assert.are.same({ {} }, MatchedLetters(view))
  end)
end)

-- Special characters in the query (not a letter or digit) never block a
-- result and never match by themselves.
describe("special characters in the query", function()
  it("do not block a name or a long text match", function()
    local hearthstone = Item("Hearthstone", 6948)
    hearthstone.longText = "Use: Speak to an Innkeeper to change your home location."
    Given({ hearthstone, Item("Innkeeper's Daughter", 2), Item("Linen Cloth", 2589) })
    local expected = { "Innkeeper's Daughter", "Hearthstone" }
    assert.are.same(expected, Names(session:SetQuery("innkee")))
    assert.are.same(expected, Names(session:SetQuery("innkee=")))
  end)

  it("do not change the matched letters of a name", function()
    -- The name keeps its apostrophe (letter 5); neither query matches it.
    Given({ Item("Rhok'delar, Longbow of the Ancient Keepers", 18713) })
    local letters = { 1, 2, 3, 4, 6, 7, 8, 9, 10 }
    local view = session:SetQuery("rhok'delar")
    assert.are.same({ "Rhok'delar, Longbow of the Ancient Keepers" }, Names(view))
    assert.are.same(letters, view.results[1].matchedLetters)
    view = session:SetQuery("rhokdelar")
    assert.are.same({ "Rhok'delar, Longbow of the Ancient Keepers" }, Names(view))
    assert.are.same(letters, view.results[1].matchedLetters)
  end)

  it("alone give no results, not the recently picked things", function()
    Given({ Item("Jack-o'-Lantern", 20516), Item("Hearthstone", 6948) })
    session:SetQuery("hearth")
    session:PressKey("ENTER") -- a pick; it closes the search bar
    session:Open()
    local view = session:SetQuery("=")
    assert.are.same({}, Names(view))
    assert.are.equal(0, view.total)
    view = session:SetQuery("--")
    assert.are.same({}, Names(view))
    assert.are.equal(0, view.total)
  end)

  it("between letters do not change the ranking", function()
    -- Without skipping, "-" would match only the hyphen of "Sharp-Tooth".
    Given({ Item("Frost Lotus", 1), Item("Sharp-Tooth Necklace", 2), Item("Rough Stone", 3) })
    local expected = { "Rough Stone", "Sharp-Tooth Necklace", "Frost Lotus" }
    assert.are.same(expected, Names(session:SetQuery("st")))
    assert.are.same(expected, Names(session:SetQuery("s-t")))
    assert.are.same(expected, Names(session:SetQuery("s t")))
  end)
end)
