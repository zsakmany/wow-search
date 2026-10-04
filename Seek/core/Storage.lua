-- The Storage port: keeps the saved copy of the entries, per character, so
-- that search works at once after a reload, also in combat (ADR 0002). The
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
local _, ns = ...

local adapter

function ns.SetStorage(storage)
  adapter = storage
end

-- The saved data, or nil when there is none or no adapter is plugged in.
function ns.LoadSaved()
  return adapter and adapter:Load()
end

-- Saves `data`. Does nothing when no adapter is plugged in.
function ns.Save(data)
  if adapter then
    adapter:Save(data)
  end
end
