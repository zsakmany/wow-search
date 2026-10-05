-- The Storage port: keeps Seek's saved data, per character, between game
-- sessions: the saved copy of the entries, so that search works at once
-- after a reload, also in combat (ADR 0002), and the player's picks. The
-- WoW storage adapter plugs in when the addon loads; tests plug in an
-- in-memory storage.
--
-- A storage adapter is a table with two methods:
--   Load()      the data that Save got last time (maybe in an earlier game
--               session), or nil when there is none
--   Save(data)  keeps `data` (a table of plain tables, strings, and
--               numbers) for the next Load. The core may change `data` after
--               this call and save it again.
-- The core loads once, in ns.Start(), which the adapter calls when the
-- saved data is ready.
--
-- The saved data is one table. Each part of the core keeps its own fields
-- in it, with its own version, so that a change in one part does not throw
-- away the other's data:
--   version, sources  the saved copy of the entries (Sources.lua)
--   picks             the picks (Picks.lua); saved data from before picks
--                     has none
local _, ns = ...

local adapter

-- The saved data as a whole: what Load gave, with the fields that the core
-- has saved since.
local data = {}

function ns.SetStorage(storage)
  adapter = storage
end

-- Loads the saved data: a table, or nil when there is none or no adapter is
-- plugged in. The core calls it once, in ns.Start().
function ns.LoadSaved()
  local loaded = adapter and adapter:Load()
  if type(loaded) ~= "table" then
    return nil
  end
  data = loaded
  return loaded
end

-- Saves the fields in `fields`, and keeps the other fields of the saved
-- data as they are. Does nothing when no adapter is plugged in.
function ns.Save(fields)
  for key, value in pairs(fields) do
    data[key] = value
  end
  if adapter then
    adapter:Save(data)
  end
end
