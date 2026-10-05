-- The search session: the state behind the search bar. The search bar window
-- (a driving adapter) sends it open, close, the query, and key presses, and
-- shows the view state that each of these returns. See docs/adr/0003.
local _, ns = ...

local L = ns.L

-- The search bar shows this many results at a time; the rest scroll.
local VISIBLE_ROWS = 8

local SearchSession = {}
SearchSession.__index = SearchSession

-- A new session starts closed with an empty query. When a source's entries
-- change while the search bar is open, the session searches again and calls
-- `onViewChanged(view)` (optional), so the window can show the new results.
function ns.NewSearchSession(onViewChanged)
  local session = setmetatable({
    isOpen = false,
    query = "",
    results = {},
    selection = 1, -- the selected result's position in all results
    scroll = 0,
  }, SearchSession)
  ns.WatchEntries(function()
    if session.isOpen then
      session:Search(true)
      if onViewChanged then
        onViewChanged(session:View())
      end
    end
  end)
  return session
end

-- A name match always ranks above a long text match. Then best score first
-- (long text matches all have the same score). Equal scores sort by name,
-- then kind, then the entry's fixed position, so the same query always gives
-- the same order.
local function Ranks(a, b)
  if a.byName ~= b.byName then
    return a.byName
  end
  if a.score ~= b.score then
    return a.score > b.score
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

-- Matches every entry against the query, by name or else by long text, and
-- ranks the results. The best result is selected, unless `keepSelection`
-- keeps the selected position (when a source's entries change under the
-- player's eyes).
function SearchSession:Search(keepSelection)
  local matches = {}
  if self.query ~= "" then
    local query = ns.PrepareQuery(self.query)
    for _, entry in ipairs(ns.Entries()) do
      local score = ns.Score(query, entry.match)
      if score then
        matches[#matches + 1] = { entry = entry, score = score, byName = true }
      elseif entry.longTextMatch and ns.MatchesLongText(query, entry.longTextMatch) then
        matches[#matches + 1] = { entry = entry, score = 0, byName = false }
      end
    end
    table.sort(matches, Ranks)
  end
  local results = {}
  for i, match in ipairs(matches) do
    results[i] = match.entry
  end
  self.results = results
  if not keepSelection then
    self.selection, self.scroll = 1, 0
  end
  self:MoveSelection(0)
end

-- Moves the selection by `step` results, within the results, and scrolls
-- so that the selected result is in view.
function SearchSession:MoveSelection(step)
  local count = #self.results
  self.selection = math.max(1, math.min(count, self.selection + step))
  if self.selection <= self.scroll then
    self.scroll = self.selection - 1
  elseif self.selection > self.scroll + VISIBLE_ROWS then
    self.scroll = self.selection - VISIBLE_ROWS
  end
  self.scroll = math.max(0, math.min(self.scroll, count - VISIBLE_ROWS))
end

-- The view state for the search bar. A new table on each call, so the
-- window can keep it without seeing later changes:
--   open       whether the search bar is open
--   query      the query
--   hint       the hint text while the query is empty, else nil
--   noResults  the "no results" text when the query matches nothing, else nil
--   results    the visible results (at most 8), top to bottom; each has
--              name, icon, kind, kindLabel, and selected (true on one row)
--   scroll     how many results are above the first visible row
--   total      how many results there are in all
function SearchSession:View()
  local rows = {}
  for i = self.scroll + 1, math.min(self.scroll + VISIBLE_ROWS, #self.results) do
    local entry = self.results[i]
    rows[#rows + 1] = {
      name = entry.name,
      icon = entry.icon,
      kind = entry.kind,
      kindLabel = ns.kinds[entry.kind].label,
      selected = i == self.selection,
    }
  end
  return {
    open = self.isOpen,
    query = self.query,
    hint = self.query == "" and L.HINT or nil,
    noResults = self.query ~= "" and #self.results == 0 and L.NO_RESULTS or nil,
    results = rows,
    scroll = self.scroll,
    total = #self.results,
  }
end

-- Each opening starts a new search with an empty query.
function SearchSession:Open()
  self.isOpen = true
  self.query = ""
  self:Search()
  return self:View()
end

function SearchSession:Close()
  self.isOpen = false
  return self:View()
end

-- The player changed the text in the search bar's text box.
function SearchSession:SetQuery(query)
  self.query = query
  self:Search()
  return self:View()
end

-- Opens a closed session and closes an open one (the key binding, /seek).
function SearchSession:Toggle()
  if self.isOpen then
    return self:Close()
  end
  return self:Open()
end

-- Runs the selected result's main action and closes the search bar, so the
-- player sees what the action shows. With no results, nothing happens.
function SearchSession:RunMainAction()
  local entry = self.results[self.selection]
  if not entry then
    return self:View()
  end
  self:Close()
  ns.RunAction(ns.MainAction(entry), entry)
  return self:View()
end

-- A key press in the search bar. `key` is the WoW key name, such as "ESCAPE"
-- or "DOWN".
function SearchSession:PressKey(key)
  if key == "ESCAPE" then
    return self:Close()
  elseif key == "ENTER" then
    return self:RunMainAction()
  elseif key == "UP" then
    self:MoveSelection(-1)
  elseif key == "DOWN" then
    self:MoveSelection(1)
  end
  return self:View()
end
