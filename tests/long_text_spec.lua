-- Search in long text, seen from the edge of the core: a fake source gives
-- entries with long text (an item's tooltip text, a spell's description, a
-- quest's description and objectives) through the public API, and the test
-- types a query the way the search bar does.

local FakeGame = require("tests.fake_game")

local function Item(name, itemID, longText)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester", longText = longText }
end

local function Names(view)
  local names = {}
  for i, result in ipairs(view.results) do
    names[i] = result.name
  end
  return names
end

describe("long text", function()
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

  local function Search(query)
    return Names(session:SetQuery(query))
  end

  it("finds an entry by a word in its long text", function()
    Given({
      Item("Hearthstone", 6948, "Use: Returns you to Goldshire. Speak to an Innkeeper in a different place"
        .. " to change your home location."),
      Item("Linen Cloth", 2589, "Crafting Reagent"),
    })
    assert.are.same({ "Hearthstone" }, Search("innkeeper"))
  end)

  it("finds an entry by the start of a word, but not by letters inside a word", function()
    Given({ Item("Hearthstone", 6948, "Use: Returns you to Goldshire.") })
    assert.are.same({ "Hearthstone" }, Search("gold"))
    assert.are.same({}, Search("shire"))
    assert.are.same({}, Search("urns"))
  end)

  it("does not match letters with gaps (no fuzzy matching on long text)", function()
    Given({ Item("Hearthstone", 6948, "Use: Returns you to Goldshire.") })
    assert.are.same({}, Search("gldshr"))
    assert.are.same({}, Search("rtrns"))
  end)

  it("ignores case", function()
    Given({ Item("Hearthstone", 6948, "Use: Returns you to Goldshire.") })
    assert.are.same({ "Hearthstone" }, Search("GOLDSHIRE"))
  end)

  it("needs each query word to start a word in the text, in any order", function()
    Given({
      Item("Hearthstone", 6948, "Use: Returns you to Goldshire."),
      Item("Scroll of Recall", 1, "Use: Returns you to Stormwind."),
    })
    assert.are.same({ "Hearthstone" }, Search("gold ret"))
    assert.are.same({}, Search("gold storm"))
  end)

  it("ranks a name match above a long text match", function()
    -- "fire" matches "Field Repair Bot 74A" only with gaps, and "Ember Torch"
    -- has the whole word "fire" in its text; the name match still comes first.
    Given({
      Item("Ember Torch", 1, "Use: Lights a fire."),
      Item("Field Repair Bot 74A", 18232, "Use: Unfolds into a repair robot."),
    })
    assert.are.same({ "Field Repair Bot 74A", "Ember Torch" }, Search("fire"))
  end)

  it("ranks long text matches by name, whatever order the source gives", function()
    Given({ Item("Wool Cloth", 2592, "Crafting Reagent"), Item("Linen Cloth", 2589, "Crafting Reagent") })
    assert.are.same({ "Linen Cloth", "Wool Cloth" }, Search("reagent"))
  end)

  it("finds UTF-8 words from non-English game clients", function()
    Given({ Item("Ruhestein", 6948, "Benutzen: Bringt Euch nach Goldhain zurück. Größe: klein.") })
    assert.are.same({ "Ruhestein" }, Search("zurück"))
    assert.are.same({ "Ruhestein" }, Search("größe KLEIN"))
    assert.are.same({}, Search("öße"))
  end)

  it("finds a word next to a typographic quote, dash, or no-break space", function()
    -- „…“ (German quotes), — (em dash), and the no-break space that French
    -- clients put before a colon.
    Given({
      Item("Ruhestein", 6948, "„Bringt Euch heim“—sofort."),
      Item("Pierre de foyer", 1, "Utiliser\194\160: vous ramène à l’auberge."),
    })
    assert.are.same({ "Ruhestein" }, Search("bringt"))
    assert.are.same({ "Ruhestein" }, Search("heim"))
    assert.are.same({ "Ruhestein" }, Search("sofort"))
    assert.are.same({ "Pierre de foyer" }, Search("utiliser"))
    assert.are.same({ "Pierre de foyer" }, Search("auberge"))
  end)

  it("gives an entry once when both its name and its long text match", function()
    Given({ Item("Hearthstone", 6948, "Hearthstone. Use: Returns you home.") })
    assert.are.same({ "Hearthstone" }, Search("hearthstone"))
  end)

  it("is left out when it is not a string; the entry is still found by name", function()
    Given({ Item("Hearthstone", 6948, { "Use: Returns you home." }), Item("Linen Cloth", 2589, 42) })
    assert.are.same({ "Hearthstone" }, Search("hearth"))
    assert.are.same({}, Search("returns"))
    assert.are.same({}, Search("42"))
  end)
end)

describe("long text after a reload", function()
  it("is found in combat, from the saved copy, before any source is read", function()
    local game = FakeGame.Started()
    game.Seek.RegisterSource({
      id = "Test.Bags",
      GetEntries = function()
        return { Item("Hearthstone", 6948, "Use: Returns you to Goldshire.") }
      end,
    })

    local after = game:Reload({ inCombat = true })
    local reads = 0
    after.Seek.RegisterSource({
      id = "Test.Bags",
      GetEntries = function()
        reads = reads + 1
        return {}
      end,
    })
    after:Start()
    local session = after.ns.NewSearchSession()
    session:Open()
    assert.are.same({ "Hearthstone" }, Names(session:SetQuery("goldshire")))
    assert.are.equal(0, reads)
  end)
end)
