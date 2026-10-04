-- The source contract, seen from the edge of the core: a fake source
-- registers through the public API and sends change notices, and the test
-- reads the results the way the search bar does.

local load_core = require("tests.load_core")

local function Item(name, itemID)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester" }
end

local function Quest(title, questID)
  return { name = title, icon = 133745, kind = "quest", gameID = questID, owner = "Tester" }
end

local function Names(view)
  local names = {}
  for i, result in ipairs(view.results) do
    names[i] = result.name
  end
  return names
end

describe("a source", function()
  local ns, Seek, bags

  before_each(function()
    ns = load_core()
    Seek = ns.api
    -- A fake bag source: the test changes `bags.entries` and sends a notice.
    bags = { id = "Test.Bags", entries = {} }
    function bags:GetEntries()
      return self.entries
    end
  end)

  it("is read again after a change notice, and its old entries are replaced", function()
    bags.entries = { Item("Hearthstone", 6948), Item("Linen Cloth", 2589) }
    Seek.RegisterSource(bags)
    local session = ns.NewSearchSession()
    session:Open()
    assert.are.same({ "Linen Cloth" }, Names(session:SetQuery("linen")))

    -- The player sells the cloth and loots some wool.
    bags.entries = { Item("Hearthstone", 6948), Item("Wool Cloth", 2592) }
    Seek.NotifyChanged("Test.Bags")

    assert.are.same({}, Names(session:SetQuery("linen")))
    assert.are.same({ "Wool Cloth" }, Names(session:SetQuery("cloth")))
  end)

  it("updates the open search bar after a change notice", function()
    Seek.RegisterSource(bags)
    local shown
    local session = ns.NewSearchSession(function(view)
      shown = view
    end)
    session:Open()
    session:SetQuery("hearth")

    bags.entries = { Item("Hearthstone", 6948) }
    Seek.NotifyChanged("Test.Bags")

    assert.are.same({ "Hearthstone" }, Names(shown))
  end)

  it("has its entries with an unknown kind rejected", function()
    bags.entries = {
      Item("Hearthstone", 6948),
      { name = "Swift Brown Steed", icon = 132261, kind = "mount", gameID = 6, owner = "Tester" },
    }
    Seek.RegisterSource(bags)
    local session = ns.NewSearchSession()
    session:Open()
    assert.are.same({}, Names(session:SetQuery("steed")))
    assert.are.same({ "Hearthstone" }, Names(session:SetQuery("hearth")))
  end)

  it("mixes its entries with other sources' entries in one list", function()
    bags.entries = { Item("Minor Healing Potion", 118) }
    local bank = { id = "Test.Bank" }
    function bank.GetEntries()
      return { Item("Healing Potion", 929) }
    end
    Seek.RegisterSource(bags)
    Seek.RegisterSource(bank)
    local session = ns.NewSearchSession()
    session:Open()
    assert.are.same({ "Healing Potion", "Minor Healing Potion" }, Names(session:SetQuery("heal")))
  end)

  it("can give quests, which rank in the same list as items", function()
    bags.entries = { Item("Wolf Meat", 750) }
    local quests = { id = "Test.Quests" }
    function quests.GetEntries()
      return { Quest("Wolves Across the Border", 33), Quest("Kobold Camp Cleanup", 7) }
    end
    Seek.RegisterSource(bags)
    Seek.RegisterSource(quests)
    local session = ns.NewSearchSession()
    session:Open()
    local view = session:SetQuery("wol")
    assert.are.same({ "Wolf Meat", "Wolves Across the Border" }, Names(view))
    assert.are.equal("Item", view.results[1].kindLabel)
    assert.are.equal("Quest", view.results[2].kindLabel)
    assert.are.equal("quest", view.results[2].kind)
  end)

  it("must have an id and a GetEntries function", function()
    assert.has_error(function()
      Seek.RegisterSource({ id = "Test.NoEntries" })
    end)
    assert.has_error(function()
      Seek.RegisterSource({ GetEntries = function() return {} end })
    end)
  end)
end)
