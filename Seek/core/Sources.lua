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
--
-- When Seek reads (ADR 0002): only outside combat, and only after
-- ns.Start(). A change notice (or a registration) outside combat schedules a
-- read through the Scheduler port; in combat, or before the start, it marks
-- the source as stale, and Seek reads it when combat ends (or at the
-- start). Seek never calls GetEntries in combat. A read runs in steps; until
-- it is done, search keeps using the source's old entries.
--
-- The saved copy: after each read, Seek saves every source's entries through
-- the Storage port. ns.Start() loads them, so search works at once after a
-- reload, also in combat, before any source is read.
local _, ns = ...

local kinds = ns.kinds

-- Change this when the saved copy's shape changes; Seek then ignores an
-- older saved copy and reads every source again.
local SAVED_VERSION = 1

-- How many entries one step prepares. The scheduler runs as many steps per
-- frame as its time budget allows.
local STEP_SIZE = 50

-- Registered sources, in the order they registered. Each is a table:
--   source  the source
--   stale   its data changed (or it was never read) and it waits for a read
--   queued  a read is scheduled and has not called GetEntries yet
local sources = {}
local byId = {}
local entriesById = {} -- source id -> its prepared entries
local allEntries = {} -- every source's entries in one list
local watchers = {}
local started = false

-- The saved copy, as the Storage port keeps it. `sources` maps a source id
-- to its entries, with only the fields that a source gives. It also keeps
-- the entries of sources that have not registered (yet) in this session.
local saved = { version = SAVED_VERSION, sources = {} }

-- Copies an entry from a source, or returns nil to reject it. Seek keeps
-- its own copy, so a source can change or reuse its tables later. The copy
-- has only what the saved copy needs.
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
  }
end

-- The entry that search uses: an accepted copy with its name prepared for
-- matching. This is the slow part of a read.
local function Prepare(copy)
  return {
    name = copy.name,
    kind = copy.kind,
    icon = copy.icon,
    gameID = copy.gameID,
    owner = copy.owner,
    match = ns.PrepareName(copy.name),
    sortName = copy.name:lower(),
  }
end

local function Rebuild()
  allEntries = {}
  for _, state in ipairs(sources) do
    for _, entry in ipairs(entriesById[state.source.id] or {}) do
      entry.order = #allEntries + 1
      allEntries[#allEntries + 1] = entry
    end
  end
  for _, watcher in ipairs(watchers) do
    watcher()
  end
end

-- Swaps in a source's new entries at once, and saves them.
local function Replace(id, copies, entries)
  saved.sources[id] = copies
  entriesById[id] = entries
  Rebuild()
  ns.Save(saved)
end

-- The steps of one read. The first step reads the source (only outside
-- combat) and accepts its entries; the next steps prepare them, STEP_SIZE at
-- a time, and the last one swaps them in. Combat may start during the
-- steps: they touch only Seek's own copies, not the game.
local function ReadSteps(state)
  local copies, entries
  return function()
    if not copies then
      state.queued = false
      if ns.InCombat() then
        state.stale = true
        return false
      end
      copies, entries = {}, {}
      -- The only place where the core reads a source.
      for _, entry in ipairs(state.source:GetEntries() or {}) do
        copies[#copies + 1] = Accept(entry)
      end
    else
      for i = #entries + 1, math.min(#entries + STEP_SIZE, #copies) do
        entries[i] = Prepare(copies[i])
      end
    end
    if #entries < #copies then
      return true
    end
    Replace(state.source.id, copies, entries)
    return false
  end
end

-- Reads a source when Seek may read: outside combat and after the start.
-- Otherwise the source stays stale until then.
local function Request(state)
  if not started or ns.InCombat() then
    state.stale = true
    return
  end
  state.stale = false
  if not state.queued then
    state.queued = true
    ns.Schedule(ReadSteps(state))
  end
end

local function RequestStale()
  for _, state in ipairs(sources) do
    if state.stale then
      Request(state)
    end
  end
end

-- Gives a source its entries from the saved copy, when it has none yet (so
-- the saved copy never replaces a newer read). Returns true when it did.
local function UseSavedCopy(id)
  local copies = saved.sources[id]
  if not copies or entriesById[id] then
    return false
  end
  local entries = {}
  for i, copy in ipairs(copies) do
    entries[i] = Prepare(copy)
  end
  entriesById[id] = entries
  return true
end

-- Takes the saved data from the Storage port, if it has the right shape.
-- Each entry is accepted again, as if a source gave it.
local function LoadSavedCopy()
  local data = ns.LoadSaved()
  if type(data) ~= "table" or data.version ~= SAVED_VERSION or type(data.sources) ~= "table" then
    return
  end
  for id, list in pairs(data.sources) do
    if type(id) == "string" and type(list) == "table" then
      local copies = {}
      for _, entry in ipairs(list) do
        copies[#copies + 1] = Accept(entry)
      end
      saved.sources[id] = copies
    end
  end
end

-- Starts Seek when the storage is ready (in WoW, when the saved variables
-- are loaded, after all of the addon's files have run): loads the saved
-- copy, so search works at once, and reads the stale sources (all of them
-- after a reload) when Seek may read. Later calls do nothing.
function ns.Start()
  if started then
    return
  end
  started = true
  LoadSavedCopy()
  for _, state in ipairs(sources) do
    UseSavedCopy(state.source.id)
  end
  Rebuild()
  RequestStale()
end

-- When combat ends, read what changed in combat.
ns.WatchCombat(function(inCombat)
  if not inCombat then
    RequestStale()
  end
end)

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

-- Registers a source. Search gets its entries from the saved copy at once,
-- and Seek reads it as soon as it may (see above).
function ns.api.RegisterSource(source)
  if type(source) ~= "table" or type(source.id) ~= "string"
      or type(source.GetEntries) ~= "function" then
    error("Seek.RegisterSource: the source needs an id (string) and a GetEntries function", 2)
  end
  if byId[source.id] then
    error("Seek.RegisterSource: a source with the id " .. source.id .. " is already registered", 2)
  end
  local state = { source = source, stale = true, queued = false }
  sources[#sources + 1] = state
  byId[source.id] = state
  if started then
    if UseSavedCopy(source.id) then
      Rebuild()
    end
    Request(state)
  end
end

-- A source tells Seek that its data changed.
function ns.api.NotifyChanged(id)
  local state = byId[id]
  if not state then
    error("Seek.NotifyChanged: no source with the id " .. tostring(id), 2)
  end
  Request(state)
end
