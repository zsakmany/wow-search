-- The search session: the state behind the search bar. The search bar window
-- (a driving adapter) sends it open, close, the query, key presses, and the
-- result row under the mouse, and shows the view state that each of these
-- returns. See docs/adr/0003.
--
-- The combat rule: in combat, every use action is blocked. The action list
-- marks it, and picking it does nothing. Show actions are never blocked.
local _, ns = ...

local L = ns.L

-- The search bar shows as many results at a time as the visible results
-- setting says; the rest scroll.
local function VisibleRows()
  return ns.Setting("visibleResults")
end

local SearchSession = {}
SearchSession.__index = SearchSession

-- Whether combat blocks `action` now.
local function Blocked(action)
  return action.type == "use" and ns.InCombat()
end

-- The view state after a change. It also tells the action adapter which use
-- action Enter would run now, so that the adapter can get it ready (see
-- Actions.lua): the selected action of the open action list, when it is a
-- use action that combat does not block.
local function Changed(session)
  local list = session.actionList
  local action = list and list.actions[list.selection]
  if session.isOpen and action and action.type == "use" and not Blocked(action) then
    ns.PrepareAction(action, list.entry)
  else
    ns.PrepareAction(nil)
  end
  return session:View()
end

-- A new session starts closed with an empty query. When a source's entries
-- change, combat starts or ends, or a setting changes, while the search bar
-- is open, the session updates and calls `onViewChanged(view)` (optional),
-- so the window can show the new results, the blocked actions, the new
-- number of rows, and the tooltip on its new side.
function ns.NewSearchSession(onViewChanged)
  local session = setmetatable({
    isOpen = false,
    query = "",
    results = {},
    -- The positions of the matched letters in a result's name, by the
    -- result's entry; nil for a result with none (see View).
    matchedLetters = {},
    selection = 1, -- the selected result's position in all results
    scroll = 0,
    -- The open action list, or nil: the result it belongs to (`entry`),
    -- that result's actions, and the selected action's position.
    actionList = nil,
  }, SearchSession)
  local function Update()
    local view = Changed(session)
    if onViewChanged then
      onViewChanged(view)
    end
  end
  -- New entries, or a changed setting (the number of visible results, the
  -- tooltip side), take effect at once: search again, and keep the
  -- selected result in view.
  local function SearchAgain()
    if session.isOpen then
      session:Search(true)
      Update()
    end
  end
  ns.WatchEntries(SearchAgain)
  ns.WatchSettings(SearchAgain)
  ns.WatchCombat(function()
    if session.isOpen then
      Update()
    end
  end)
  return session
end

-- A name match always ranks above a long text match. Then best rank first:
-- the match score (long text matches all have the same score) plus the
-- boost from the player's picks (Picks.lua), so picks reorder results only
-- inside each of the two groups. Of equal ranks, the current character's
-- entries come before another character's; then they sort by name, then
-- kind, then the entry's fixed position, so the same query always gives
-- the same order.
local function Ranks(a, b)
  if a.byName ~= b.byName then
    return a.byName
  end
  if a.rank ~= b.rank then
    return a.rank > b.rank
  end
  if a.otherOwner ~= b.otherOwner then
    return b.otherOwner
  end
  local x, y = a.entry, b.entry
  if x.sortName ~= y.sortName then
    return x.sortName < y.sortName
  end
  if x.name ~= y.name then
    return x.name < y.name
  end
  if x.kind ~= y.kind then
    return x.kind < y.kind
  end
  return x.order < y.order
end

-- Whether an entry is another character's: it has an owner, and the owner
-- is not the current character.
local function IsOtherOwner(entry, current)
  return type(entry.owner) == "string" and entry.owner ~= current
end

-- Whether two entries are the same game thing. A source that is read again
-- gives new entries, so the tables differ.
local function SameThing(a, b)
  return a ~= nil and b ~= nil and a.kind == b.kind and a.gameID == b.gameID
    and a.owner == b.owner
end

-- Matches every entry against the query, by name or else by long text, and
-- ranks the results. A name match also keeps the name's matched letters.
-- With an empty query, the results are the recently picked things instead.
-- The best result is selected, unless `keepSelection` keeps the selected
-- position (when a source's entries change under the player's eyes).
--
-- The action list belongs to the selected result. A new query closes it.
-- When a source's entries change, it stays open only if the selected
-- result is still the same thing and still has actions, and then it shows
-- that thing's new entry.
function SearchSession:Search(keepSelection)
  local results, matchedLetters = {}, {}
  if self.query == "" then
    results = ns.RecentlyPicked(ns.Entries(), VisibleRows())
  else
    local matches = {}
    local query = ns.PrepareQuery(self.query)
    local boost = ns.PickBoosts(self.query)
    local current = ns.CurrentCharacter()
    for _, entry in ipairs(ns.Entries()) do
      local otherOwner = IsOtherOwner(entry, current)
      local score, letters = ns.Score(query, entry.match)
      if score then
        matches[#matches + 1] = {
          entry = entry, rank = score + boost(entry), byName = true, letters = letters, otherOwner = otherOwner,
        }
      elseif entry.longTextMatch and ns.MatchesLongText(query, entry.longTextMatch) then
        matches[#matches + 1] = { entry = entry, rank = boost(entry), byName = false, otherOwner = otherOwner }
      end
    end
    table.sort(matches, Ranks)
    for i, match in ipairs(matches) do
      results[i], matchedLetters[match.entry] = match.entry, match.letters
    end
  end
  self.results, self.matchedLetters = results, matchedLetters
  if not keepSelection then
    self.selection, self.scroll = 1, 0
  end
  self:MoveSelection(0)

  local list = self.actionList
  if list then
    local entry = results[self.selection]
    if keepSelection and SameThing(entry, list.entry) and ns.HasActions(entry) then
      list.entry, list.actions = entry, ns.EntryActions(entry)
      self:MoveInActionList(0)
    else
      self.actionList = nil
    end
  end
end

-- Moves the selection by `step` results, within the results, and scrolls
-- so that the selected result is in view.
function SearchSession:MoveSelection(step)
  local count, visible = #self.results, VisibleRows()
  self.selection = math.max(1, math.min(count, self.selection + step))
  if self.selection <= self.scroll then
    self.scroll = self.selection - 1
  elseif self.selection > self.scroll + visible then
    self.scroll = self.selection - visible
  end
  self.scroll = math.max(0, math.min(self.scroll, count - visible))
end

-- Which visible row shows its tooltip, and on which side (the tooltip side
-- setting), or nil for no tooltip: the selected row. (The mouse does not
-- show tooltips.) None while the search bar is closed, with no results, with
-- the setting off, or while the action list is open on the right side,
-- where the list shows too.
local function Tooltip(session, rows)
  local side = ns.Setting("tooltipSide")
  if not session.isOpen or #rows == 0 or side == "off"
    or (side == "right" and session.actionList) then
    return nil
  end
  return { row = session.selection - session.scroll, side = side }
end

-- An owner's name and realm, from its "Name-Realm". A character's name has
-- no hyphen; the realm follows the first one. Nil for an owner with no
-- realm.
local function SplitOwner(owner)
  return owner:match("^(.-)%-(.+)$")
end

-- The owner of another character's entry, as its row shows it: the name,
-- and the realm only when it is not the current character's ("Bob", or
-- "Bob-Stormrage"). Nil for the current character's entries, and for
-- entries with no owner.
local function OwnerText(entry, current)
  if not IsOtherOwner(entry, current) then
    return nil
  end
  local name, realm = SplitOwner(entry.owner)
  local _, currentRealm = SplitOwner(current or "")
  if realm and realm == currentRealm then
    return name
  end
  return entry.owner
end

-- The view state for the search bar. A new table on each call, so the
-- window can keep it without seeing later changes:
--   open       whether the search bar is open
--   query      the query
--   hint       the hint text while the query is empty and there are no
--              results (no recently picked things), else nil
--   noResults  the "no results" text when the query matches nothing, else nil
--   results    the visible results (at most as many as the visible
--              results setting says), top to bottom; each has
--              name, icon, kind, gameID (the game's ID for the thing, from
--              the entry), kindLabel (the kind, with the owner's name for
--              another character's result, see OwnerText: the row's kind
--              text), faded (true for a result with no actions:
--              the search bar draws it faded), selected (true on one row),
--              and matchedLetters: the positions of the name's letters that
--              matched the query, in order, counted in whole letters (nil
--              for a long text match and for the recently picked things;
--              the window must not change this list). The search bar shows
--              these letters in gold.
--   scroll     how many results are above the first visible row
--   total      how many results there are in all
--   actionList the open action list, else nil. It belongs to the selected
--              result. `rows` holds the actions, top to bottom; each has
--              id, label, type ("show" or "use"), selected (true on one
--              row), and blocked (true when combat blocks the action: the
--              row shows the "blocked in combat" sign)
--   tooltip    the result row that shows its WoW tooltip, else nil (see
--              Tooltip): `row` is its position in `results`, and `side`
--              ("right" or "left") the side of the search bar where the
--              tooltip shows
function SearchSession:View()
  local rows = {}
  local current = ns.CurrentCharacter()
  for i = self.scroll + 1, math.min(self.scroll + VisibleRows(), #self.results) do
    local entry = self.results[i]
    local owner = OwnerText(entry, current)
    local kindLabel = ns.kinds[entry.kind].label
    rows[#rows + 1] = {
      name = entry.name,
      icon = entry.icon,
      kind = entry.kind,
      gameID = entry.gameID,
      kindLabel = owner and L.KIND_WITH_OWNER:format(kindLabel, owner) or kindLabel,
      faded = not ns.HasActions(entry),
      selected = i == self.selection,
      matchedLetters = self.matchedLetters[entry],
    }
  end
  local actionList
  if self.actionList then
    local actionRows = {}
    for i, action in ipairs(self.actionList.actions) do
      actionRows[i] = {
        id = action.id,
        label = action.label,
        type = action.type,
        selected = i == self.actionList.selection,
        blocked = Blocked(action),
      }
    end
    actionList = { rows = actionRows }
  end
  return {
    open = self.isOpen,
    query = self.query,
    hint = self.query == "" and #self.results == 0 and L.HINT or nil,
    noResults = self.query ~= "" and #self.results == 0 and L.NO_RESULTS or nil,
    results = rows,
    scroll = self.scroll,
    total = #self.results,
    actionList = actionList,
    tooltip = Tooltip(self, rows),
  }
end

-- Each opening starts a new search with an empty query.
function SearchSession:Open()
  self.isOpen = true
  self.query = ""
  self:Search()
  return Changed(self)
end

function SearchSession:Close()
  self.isOpen = false
  self.actionList = nil
  return Changed(self)
end

-- The player changed the text in the search bar's text box.
function SearchSession:SetQuery(query)
  self.query = query
  self:Search()
  return Changed(self)
end

-- Opens a closed session and closes an open one (the key binding, /seek).
function SearchSession:Toggle()
  if self.isOpen then
    return self:Close()
  end
  return self:Open()
end

-- Runs the selected result's main action and closes the search bar, so the
-- player sees what the action shows. With no results, or when the result's
-- kind has no main action, nothing happens.
function SearchSession:RunMainAction()
  local entry = self.results[self.selection]
  if not entry or not ns.MainAction(entry) then
    return Changed(self)
  end
  self:Close()
  ns.RunAction(ns.MainAction(entry), entry)
  ns.RecordPick(entry, self.query)
  return self:View()
end

-- The position of the first use action in `actions`, or 1 (the main action)
-- when there is none.
local function FirstUseAction(actions)
  for i, action in ipairs(actions) do
    if action.type == "use" then
      return i
    end
  end
  return 1
end

-- Opens the action list of the selected result, with its first use action
-- selected, or its main action when it has no use action: Enter on the
-- results already runs the main action, so Tab, Enter uses the thing. With
-- no results, or for a faded result (no actions), nothing happens.
--
-- Why not a shortcut such as Shift+Enter that runs the use action from the
-- results: while the text box has keyboard focus, no key binding fires, and
-- a use action runs only from a key binding's real key press on the secure
-- button (adapters/wow/SearchBar.lua, "List keys"). The text box would have
-- to give up the keyboard on every Shift press, which breaks capital
-- letters and Shift-selection in it.
function SearchSession:OpenActionList()
  local entry = self.results[self.selection]
  if entry and ns.HasActions(entry) then
    local actions = ns.EntryActions(entry)
    self.actionList = { entry = entry, actions = actions, selection = FirstUseAction(actions) }
  end
end

-- Moves the action list's selection by `step` actions, within the list.
function SearchSession:MoveInActionList(step)
  local list = self.actionList
  list.selection = math.max(1, math.min(#list.actions, list.selection + step))
end

-- Runs the action list's selected action and closes the search bar, as the
-- main action does. A blocked action does nothing, and the search bar stays
-- open, so the player sees the sign.
function SearchSession:RunListAction()
  local list = self.actionList
  local action = list.actions[list.selection]
  if Blocked(action) then
    return Changed(self)
  end
  self:Close()
  ns.RunAction(action, list.entry)
  ns.RecordPick(list.entry, self.query)
  return self:View()
end

-- A key press while the action list is open. Escape closes only the list,
-- so the player is back at the results; Tab does nothing.
function SearchSession:PressKeyInActionList(key)
  if key == "ESCAPE" then
    self.actionList = nil
  elseif key == "ENTER" then
    return self:RunListAction()
  elseif key == "UP" then
    self:MoveInActionList(-1)
  elseif key == "DOWN" then
    self:MoveInActionList(1)
  end
  return Changed(self)
end

-- A key press in the search bar. `key` is the WoW key name, such as "ESCAPE"
-- or "DOWN". Up and Down move the selection, Enter runs the main action,
-- Tab opens the action list, and Escape closes the search bar; while the
-- action list is open, the keys work in the list instead.
function SearchSession:PressKey(key)
  if self.actionList then
    return self:PressKeyInActionList(key)
  end
  if key == "TAB" then
    self:OpenActionList()
  elseif key == "ESCAPE" then
    return self:Close()
  elseif key == "ENTER" then
    return self:RunMainAction()
  elseif key == "UP" then
    self:MoveSelection(-1)
  elseif key == "DOWN" then
    self:MoveSelection(1)
  end
  return Changed(self)
end
