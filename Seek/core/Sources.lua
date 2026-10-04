-- Sources and their entries (the Sources port), and the public API that lets
-- an addon register a source. Seek's own sources use the same API.
--
-- A source is a table:
--   id          a unique, stable name, such as "Seek.Bags"
--   GetEntries  a function; Seek calls source:GetEntries() and gets a list
--               of entries
-- An entry is a table:
--   name    (required) the name that the query matches
--   kind    (required) one of the kinds in Kinds.lua, such as "item"
--   icon    a texture file ID or path
--   gameID  the game's ID for the thing, such as the item ID
--   owner   the character that owns it
-- Seek rejects (leaves out) an entry with no name or an unknown kind.
--
-- When its data changes, a source calls NotifyChanged(id). Seek then reads
-- it again and replaces all of its old entries.
local _, ns = ...

local kinds = ns.kinds

local sources = {} -- registered sources, in the order they registered
local byId = {}
local entriesById = {} -- source id -> its accepted entries
local allEntries = {} -- every source's entries in one list
local watchers = {}

-- Copies an entry from a source, or returns nil to reject it. Seek keeps
-- its own copy, so a source can change or reuse its tables later.
local function Accept(entry)
  if type(entry) ~= "table" or type(entry.name) ~= "string" or entry.name == ""
      or not kinds[entry.kind] then
    return nil
  end
  return {
    name = entry.name,
    kind = entry.kind,
    icon = entry.icon,
    gameID = entry.gameID,
    owner = entry.owner,
    match = ns.PrepareName(entry.name),
    sortName = entry.name:lower(),
  }
end

local function Rebuild()
  allEntries = {}
  for _, source in ipairs(sources) do
    for _, entry in ipairs(entriesById[source.id]) do
      entry.order = #allEntries + 1
      allEntries[#allEntries + 1] = entry
    end
  end
  for _, watcher in ipairs(watchers) do
    watcher()
  end
end

-- Reads a source and replaces its old entries as a whole. This is the only
-- place where the core reads a source.
local function Read(source)
  local entries = {}
  for _, entry in ipairs(source:GetEntries() or {}) do
    entries[#entries + 1] = Accept(entry)
  end
  entriesById[source.id] = entries
  Rebuild()
end

-- Every source's current entries, in one list. Each has the fields above,
-- plus `match` (the prepared name), `sortName`, and `order` (a fixed
-- position), for matching and a stable tie-break.
function ns.Entries()
  return allEntries
end

-- Calls `watcher()` each time the entries change.
function ns.WatchEntries(watcher)
  watchers[#watchers + 1] = watcher
end

-- The public API. A WoW adapter publishes it as the global `Seek`.
ns.api = {}

-- Registers a source and reads it at once.
function ns.api.RegisterSource(source)
  if type(source) ~= "table" or type(source.id) ~= "string"
      or type(source.GetEntries) ~= "function" then
    error("Seek.RegisterSource: the source needs an id (string) and a GetEntries function", 2)
  end
  if byId[source.id] then
    error("Seek.RegisterSource: a source with the id " .. source.id .. " is already registered", 2)
  end
  sources[#sources + 1] = source
  byId[source.id] = source
  Read(source)
end

-- A source tells Seek that its data changed.
function ns.api.NotifyChanged(id)
  local source = byId[id]
  if not source then
    error("Seek.NotifyChanged: no source with the id " .. tostring(id), 2)
  end
  Read(source)
end
