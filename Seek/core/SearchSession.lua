-- The search session: the state behind the search bar. The search bar window
-- (a driving adapter) sends it open, close, the query, and key presses, and
-- shows the view state that each of these returns. See docs/adr/0003.
local _, ns = ...

local L = ns.L

local SearchSession = {}
SearchSession.__index = SearchSession

-- A new session starts closed with an empty query.
function ns.NewSearchSession()
  return setmetatable({ isOpen = false, query = "" }, SearchSession)
end

-- The view state for the search bar. A new table on each call, so the
-- window can keep it without seeing later changes.
function SearchSession:View()
  return {
    open = self.isOpen,
    query = self.query,
    hint = self.query == "" and L.HINT or nil,
    results = {},
  }
end

-- Each opening starts a new search with an empty query.
function SearchSession:Open()
  self.isOpen = true
  self.query = ""
  return self:View()
end

function SearchSession:Close()
  self.isOpen = false
  return self:View()
end

-- The player changed the text in the search bar's text box.
function SearchSession:SetQuery(query)
  self.query = query
  return self:View()
end

-- Opens a closed session and closes an open one (the key binding, /seek).
function SearchSession:Toggle()
  if self.isOpen then
    return self:Close()
  end
  return self:Open()
end

-- A key press in the search bar. `key` is the WoW key name, such as "ESCAPE".
function SearchSession:PressKey(key)
  if key == "ESCAPE" then
    return self:Close()
  end
  return self:View()
end
