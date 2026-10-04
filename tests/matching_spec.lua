-- Matching and ranking, seen from the edge of the core: a fake source gives
-- entries through the public API, the test types a query the way the search
-- bar does, and reads the results in the view state.

local load_core = require("tests.load_core")

local function Item(name, itemID)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester" }
end

-- The names of the results the search bar shows, top to bottom.
local function Names(view)
  local names = {}
  for i, result in ipairs(view.results) do
    names[i] = result.name
  end
  return names
end

describe("matching", function()
  local session

  -- Registers a fake source with these entries and opens the search bar.
  local function Given(entries)
    local ns = load_core()
    ns.api.RegisterSource({
      id = "Test.Bags",
      GetEntries = function()
        return entries
      end,
    })
    session = ns.NewSearchSession()
    session:Open()
  end

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
end)
