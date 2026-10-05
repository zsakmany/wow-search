-- The tooltip, seen from the edge of the core: a fake source gives entries
-- through the public API, the test types a query, presses keys, and moves
-- the mouse over the result rows the way the search bar does, changes the
-- tooltip side setting through the fake settings port, and reads which row
-- shows its tooltip, and on which side, from the view state.

local FakeGame = require("tests.fake_game")

local function Item(name, itemID)
  return { name = name, icon = 134400, kind = "item", gameID = itemID, owner = "Tester" }
end

local function Spell(name, spellID)
  return { name = name, icon = 136243, kind = "spell", gameID = spellID, owner = "Tester" }
end

local function Quest(title, questID)
  return { name = title, icon = 133745, kind = "quest", gameID = questID, owner = "Tester" }
end

describe("the tooltip", function()
  local game, session

  before_each(function()
    game = FakeGame.Started()
    game.ns.SetActionAdapter({ Run = function() end })
    session = game.ns.NewSearchSession()
  end)

  -- Registers a fake source with these entries.
  local function GivenEntries(entries)
    game.Seek.RegisterSource({
      id = "Test.Things",
      GetEntries = function()
        return entries
      end,
    })
  end

  it("gets each result row's kind and game ID from the view", function()
    GivenEntries({ Item("Healing Potion", 118), Spell("Healing Touch", 5185), Quest("Healing Hands", 4021) })
    session:Open()
    local things = {}
    for _, result in ipairs(session:SetQuery("healing").results) do
      things[result.name] = { result.kind, result.gameID }
    end
    assert.are.same({
      ["Healing Potion"] = { "item", 118 },
      ["Healing Touch"] = { "spell", 5185 },
      ["Healing Hands"] = { "quest", 4021 },
    }, things)
  end)

  it("shows the selected row's tooltip on the right by default", function()
    GivenEntries({ Item("Potion 01", 1), Item("Potion 02", 2), Item("Potion 03", 3) })
    session:Open()
    session:SetQuery("potion")
    assert.are.same({ row = 1, side = "right" }, session:View().tooltip)
  end)

  it("moves with the selection on Up and Down, counted in visible rows", function()
    game:ChangeSetting("visibleResults", 3)
    GivenEntries({ Item("Potion 01", 1), Item("Potion 02", 2), Item("Potion 03", 3), Item("Potion 04", 4) })
    session:Open()
    session:SetQuery("potion")
    assert.are.equal(2, session:PressKey("DOWN").tooltip.row)
    -- The fourth result scrolls into the bottom row.
    session:PressKey("DOWN")
    assert.are.equal(3, session:PressKey("DOWN").tooltip.row)
    assert.are.equal(2, session:PressKey("UP").tooltip.row)
  end)

  describe("with the mouse over a result row", function()
    before_each(function()
      GivenEntries({ Item("Potion 01", 1), Item("Potion 02", 2), Item("Potion 03", 3) })
      session:Open()
      session:SetQuery("potion")
    end)

    it("shows that row's tooltip instead of the selected row's", function()
      local view = session:HoverResult(3)
      assert.are.same({ row = 3, side = "right" }, view.tooltip)
      assert.is_true(view.results[1].selected)
    end)

    it("keeps that row's tooltip when Up and Down move the selection", function()
      session:HoverResult(3)
      assert.are.equal(3, session:PressKey("DOWN").tooltip.row)
    end)

    it("goes back to the selected row's tooltip when the mouse leaves the rows", function()
      session:HoverResult(3)
      session:PressKey("DOWN")
      assert.are.equal(2, session:HoverResult(nil).tooltip.row)
    end)

    it("shows the selected row's tooltip when that row no longer shows a result", function()
      session:HoverResult(3)
      assert.are.same({ row = 1, side = "right" }, session:SetQuery("potion 02").tooltip)
    end)
  end)

  describe("the tooltip side setting", function()
    local shown

    before_each(function()
      shown = nil
      session = game.ns.NewSearchSession(function(view)
        shown = view
      end)
      GivenEntries({ Item("Potion 01", 1), Item("Potion 02", 2), Quest("The Defias Brotherhood", 65) })
      session:Open()
    end)

    it("is right by default, and hides the tooltip while the action list is open", function()
      session:SetQuery("potion")
      assert.are.equal("right", session:View().tooltip.side)
      assert.is_nil(session:PressKey("TAB").tooltip)
      session:HoverResult(2)
      assert.is_nil(session:View().tooltip)
      assert.are.same({ row = 2, side = "right" }, session:PressKey("ESCAPE").tooltip)
    end)

    it("left shows the tooltip on the left, also while the action list is open", function()
      game:ChangeSetting("tooltipSide", "left")
      session:SetQuery("potion")
      assert.are.same({ row = 1, side = "left" }, session:View().tooltip)
      assert.are.same({ row = 1, side = "left" }, session:PressKey("TAB").tooltip)
      assert.are.same({ row = 2, side = "left" }, session:HoverResult(2).tooltip)
    end)

    it("off shows no tooltip", function()
      game:ChangeSetting("tooltipSide", "off")
      assert.is_nil(session:SetQuery("potion").tooltip)
      assert.is_nil(session:HoverResult(2).tooltip)
    end)

    it("changes the tooltip at once while the search bar is open", function()
      session:SetQuery("defias")
      game:ChangeSetting("tooltipSide", "left")
      assert.are.same({ row = 1, side = "left" }, shown.tooltip)
      game:ChangeSetting("tooltipSide", "off")
      assert.is_nil(shown.tooltip)
      game:ChangeSetting("tooltipSide", nil)
      assert.are.same({ row = 1, side = "right" }, shown.tooltip)
    end)

    it("keeps the action list open when it changes", function()
      session:SetQuery("defias")
      session:PressKey("TAB")
      game:ChangeSetting("tooltipSide", "left")
      assert.is_not_nil(shown.actionList)
      assert.are.same({ row = 1, side = "left" }, shown.tooltip)
    end)
  end)

  it("forgets the row under the mouse when the search bar closes", function()
    GivenEntries({ Item("Potion 01", 1), Item("Potion 02", 2) })
    session:Open()
    session:SetQuery("potion")
    session:HoverResult(2)
    session:PressKey("ESCAPE")
    session:Open()
    assert.are.equal(1, session:SetQuery("potion").tooltip.row)
  end)

  it("shows none when there are no results", function()
    GivenEntries({ Item("Potion 01", 1) })
    session:Open()
    assert.is_nil(session:View().tooltip)
    assert.is_nil(session:SetQuery("sword").tooltip)
  end)

  it("hides when the search bar closes", function()
    GivenEntries({ Item("Potion 01", 1) })
    session:Open()
    session:SetQuery("potion")
    assert.is_nil(session:PressKey("ESCAPE").tooltip)
    assert.is_nil(session:View().tooltip)
  end)
end)
