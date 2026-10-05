-- When Seek reads its sources, seen from the edge of the core (ADR 0002):
-- only outside combat, in small steps, and with a saved copy that search
-- uses after a reload and in combat. The fake game plugs in a fake combat
-- state, an in-memory storage, and a scheduler that the test runs.

local FakeGame = require("tests.fake_game")

local function Item(name, itemID)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester", inBags = true }
end

local function Spell(name, spellID)
  return { name = name, icon = 135812, kind = "spell", gameID = spellID, owner = "Tester" }
end

local function Names(view)
  local names = {}
  for i, result in ipairs(view.results) do
    names[i] = result.name
  end
  return names
end

-- A fake source that gives `entries` and writes down each read, and
-- whether the player was in combat then.
local function Source(game, id, entries)
  local source = { id = id, entries = entries or {}, reads = 0, readsInCombat = 0 }
  function source:GetEntries()
    self.reads = self.reads + 1
    if game.combat:IsInCombat() then
      self.readsInCombat = self.readsInCombat + 1
    end
    return self.entries
  end
  return source
end

-- What the search bar shows for this query.
local function Search(game, query)
  local session = game.ns.NewSearchSession()
  session:Open()
  return Names(session:SetQuery(query))
end

describe("in combat", function()
  local game, bags

  before_each(function()
    game = FakeGame.Started()
    bags = Source(game, "Test.Bags", { Item("Hearthstone", 6948) })
    game.Seek.RegisterSource(bags)
  end)

  it("a change notice does not read the source; it is read after combat ends", function()
    game:EnterCombat()
    bags.entries = { Item("Hearthstone", 6948), Item("Wool Cloth", 2592) }
    game.Seek.NotifyChanged("Test.Bags")
    assert.are.same({}, Search(game, "wool"))

    game:LeaveCombat()
    assert.are.same({ "Wool Cloth" }, Search(game, "wool"))
    assert.are.equal(0, bags.readsInCombat)
  end)

  it("a source that registers is not read; it is read after combat ends", function()
    game:EnterCombat()
    local spells = Source(game, "Test.Spells", { Spell("Fireball", 133) })
    game.Seek.RegisterSource(spells)
    assert.are.same({}, Search(game, "fireb"))

    game:LeaveCombat()
    assert.are.same({ "Fireball" }, Search(game, "fireb"))
    assert.are.equal(0, spells.readsInCombat)
  end)

  it("a read that was scheduled before combat started waits for its end", function()
    game = FakeGame.Started({ stepByStep = true })
    bags = Source(game, "Test.Bags", { Item("Hearthstone", 6948) })
    game.Seek.RegisterSource(bags)
    game:EnterCombat()
    game:RunSteps()
    assert.are.equal(0, bags.reads)

    game:LeaveCombat()
    game:RunSteps()
    assert.are.same({ "Hearthstone" }, Search(game, "hearth"))
    assert.are.equal(0, bags.readsInCombat)
  end)

  it("a source that changes several times is read once after combat ends", function()
    local readsBefore = bags.reads
    game:EnterCombat()
    for _ = 1, 3 do
      game.Seek.NotifyChanged("Test.Bags")
    end
    game:LeaveCombat()
    assert.are.equal(readsBefore + 1, bags.reads)
  end)

  it("search still finds what was read before combat", function()
    game:EnterCombat()
    game.Seek.NotifyChanged("Test.Bags")
    assert.are.same({ "Hearthstone" }, Search(game, "hearth"))
  end)
end)

describe("after a reload", function()
  local game

  -- A game in which the bags held a Hearthstone and the player knew
  -- Fireball, both read before the reload.
  before_each(function()
    game = FakeGame.Started()
    game.Seek.RegisterSource(Source(game, "Test.Bags", { Item("Hearthstone", 6948) }))
    game.Seek.RegisterSource(Source(game, "Test.Spells", { Spell("Fireball", 133) }))
  end)

  -- Reloads; the sources register again (as Seek's own sources do while the
  -- addon's files run), and the core starts. Returns the new game and its
  -- sources, which give `bagEntries` from now on.
  local function Reload(options, bagEntries)
    local after = game:Reload(options)
    local bags = Source(after, "Test.Bags", bagEntries or { Item("Hearthstone", 6948) })
    local spells = Source(after, "Test.Spells", { Spell("Fireball", 133) })
    after.Seek.RegisterSource(bags)
    after.Seek.RegisterSource(spells)
    after:Start()
    return after, bags, spells
  end

  it("search gives the same results before any source is read", function()
    local after, bags, spells = Reload({ stepByStep = true })
    assert.are.same({ "Hearthstone" }, Search(after, "hearth"))
    assert.are.same({ "Fireball" }, Search(after, "fireb"))
    assert.are.equal(0, bags.reads + spells.reads)
  end)

  it("in combat, search works and the sources are read only after combat ends", function()
    local after, bags = Reload({ inCombat = true }, { Item("Hearthstone", 6948), Item("Wool Cloth", 2592) })
    assert.are.same({ "Hearthstone" }, Search(after, "hearth"))
    assert.are.same({}, Search(after, "wool"))
    assert.are.equal(0, bags.reads)

    after:LeaveCombat()
    assert.are.same({ "Wool Cloth" }, Search(after, "wool"))
  end)

  it("a new read replaces the saved copy, and the next reload keeps the new entries", function()
    local after = Reload({}, { Item("Wool Cloth", 2592) })
    assert.are.same({}, Search(after, "hearth"))
    assert.are.same({ "Wool Cloth" }, Search(after, "wool"))

    local again = after:Reload({ inCombat = true })
    again.Seek.RegisterSource(Source(again, "Test.Bags", {}))
    again:Start()
    assert.are.same({ "Wool Cloth" }, Search(again, "wool"))
    assert.are.same({}, Search(again, "hearth"))
  end)

  it("a source that registers after the start gets its saved entries at once", function()
    local after = game:Reload({ inCombat = true })
    after:Start()
    assert.are.same({}, Search(after, "fireb"))
    after.Seek.RegisterSource(Source(after, "Test.Spells", { Spell("Fireball", 133) }))
    assert.are.same({ "Fireball" }, Search(after, "fireb"))
  end)

  it("search finds nothing from a source that has not registered", function()
    local after = game:Reload({ inCombat = true })
    after.Seek.RegisterSource(Source(after, "Test.Bags", {}))
    after:Start()
    assert.are.same({ "Hearthstone" }, Search(after, "hearth"))
    assert.are.same({}, Search(after, "fireb"))
  end)
end)

describe("a large source", function()
  -- "Potion 001" to "Potion <count>"
  local function Potions(count)
    local entries = {}
    for i = 1, count do
      entries[i] = Item(("Potion %03d"):format(i), i)
    end
    return entries
  end

  it("is read over several steps, and search keeps the old entries until all are ready", function()
    local game = FakeGame.Started({ stepByStep = true })
    local bags = Source(game, "Test.Bags", { Item("Hearthstone", 6948) })
    game.Seek.RegisterSource(bags)
    game:RunSteps()

    bags.entries = Potions(500)
    game.Seek.NotifyChanged("Test.Bags")
    local steps = 0
    repeat
      assert.are.same({ "Hearthstone" }, Search(game, "hearth"))
      assert.are.same({}, Search(game, "potion"))
      game:Step()
      steps = steps + 1
    until game:IsIdle()
    assert.is_true(steps > 2)
    assert.are.same({}, Search(game, "hearth"))
    assert.are.same({ "Potion 001" }, Search(game, "potion 001"))
    assert.are.same({ "Potion 500" }, Search(game, "potion 500"))
  end)

  it("finishes its steps when combat starts after it was read", function()
    local game = FakeGame.Started({ stepByStep = true })
    -- The reads of the start (Seek's own source of other characters' bags).
    game:RunSteps()
    local bags = Source(game, "Test.Bags", Potions(500))
    game.Seek.RegisterSource(bags)
    game:Step()
    game:EnterCombat()
    game:RunSteps()
    assert.are.same({ "Potion 250" }, Search(game, "potion 250"))
    assert.are.equal(1, bags.reads)
    assert.are.equal(0, bags.readsInCombat)
  end)
end)

describe("before the start", function()
  it("a source is not read, also after a change notice; it is read at the start", function()
    -- In WoW, the sources register while the addon's files run, before the
    -- saved variables are loaded.
    local game = FakeGame.New()
    local bags = Source(game, "Test.Bags", { Item("Hearthstone", 6948) })
    game.Seek.RegisterSource(bags)
    game.Seek.NotifyChanged("Test.Bags")
    assert.are.equal(0, bags.reads)

    game:Start()
    assert.are.equal(1, bags.reads)
    assert.are.same({ "Hearthstone" }, Search(game, "hearth"))
  end)
end)
