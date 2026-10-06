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
--   longText  plain text that the query matches at word starts, such as an
--             item's tooltip text (optional; no color codes or links: Seek
--             keeps it in the saved copy)
--   inBags  (items) true when the item is in the current character's bags;
--           only then does it get its actions, "show in bag" and "use"
--           (Kinds.lua). An item in another character's bags has none.
--   usable  (items) true when the player can use the item, such as a
--           Hearthstone; only then does it get the "use" action (Kinds.lua)
--   tracked (quests) true when the quest is a tracked quest; it then gets
--           "untrack" in place of "track" (Kinds.lua)
--   focused (quests) true when the quest has the focus; it then gets
--           "remove focus" in place of "focus" (Kinds.lua)
--   page    (game options) the name of the game option page that holds the
--           game option, such as "Controls"; nil for a game option page
--   count   (items) the item count: how many of the item the owner has, all
--           stacks together, a whole number of at least 1. The result's row
--           shows it after the name when it is more than 1; the query never
--           matches it.
-- Seek rejects (leaves out) an entry with no name or an unknown kind, and
-- leaves out long text and a page that are not strings, and a count that is
-- not a whole number of at least 1. Any `inBags`, `usable`, `tracked`, or
-- `focused` other than true counts as false.
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
-- older saved copy and reads every source again. Version 2: bag items have
-- inBags (without it they would have no actions), and owners are named the
-- same way for every source.
local SAVED_VERSION = 2

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

-- The saved copy: its fields in the saved data that the Storage port keeps.
-- `sources` maps a source id to its entries, with only the fields that a
-- source gives. It also keeps the entries of sources that have not
-- registered (yet) in this session.
local saved = { version = SAVED_VERSION, sources = {} }

-- Whether `count` is an item count that Seek keeps: a whole number of at
-- least 1.
local function IsCount(count)
  return type(count) == "number" and count >= 1 and count < math.huge and count == math.floor(count)
end

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
    longText = type(entry.longText) == "string" and entry.longText or nil,
    inBags = entry.inBags == true or nil,
    usable = entry.usable == true or nil,
    tracked = entry.tracked == true or nil,
    focused = entry.focused == true or nil,
    page = type(entry.page) == "string" and entry.page or nil,
    count = IsCount(entry.count) and entry.count or nil,
  }
end

-- The entry that search uses: an accepted copy with its name and long text
-- prepared for matching. This is the slow part of a read.
local function Prepare(copy)
  return {
    name = copy.name,
    kind = copy.kind,
    icon = copy.icon,
    gameID = copy.gameID,
    owner = copy.owner,
    inBags = copy.inBags,
    usable = copy.usable,
    tracked = copy.tracked,
    focused = copy.focused,
    page = copy.page,
    count = copy.count,
    match = ns.PrepareName(copy.name),
    longTextMatch = copy.longText and ns.PrepareLongText(copy.longText),
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

-- Swaps in a source's new entries at once, and saves them. The bag
-- source's entries are also kept as the current character's bags
-- (CharacterBags.lua).
local function Replace(id, copies, entries)
  saved.sources[id] = copies
  entriesById[id] = entries
  Rebuild()
  ns.Save(saved)
  ns.KeepCharacterBags(id, copies)
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

-- Takes the saved copy from the saved data, if it has the right shape.
-- Each entry is accepted again, as if a source gave it.
local function LoadSavedCopy(data)
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
-- copy, so search works at once, the picks (Picks.lua), and each
-- character's bags (CharacterBags.lua), and reads the stale sources (all of
-- them after a reload) when Seek may read. Later calls do nothing.
function ns.Start()
  if started then
    return
  end
  started = true
  local data = ns.LoadSaved()
  LoadSavedCopy(data)
  ns.LoadPicks(data)
  ns.LoadCharacterBags(ns.LoadAccountSaved())
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

-- Every source's current entries, in one list. Each has the fields above
-- (but not the long text itself), plus `match` (the prepared name),
-- `longTextMatch` (the prepared long text, or nil), `sortName`, and `order`
-- (a fixed position), for matching and a stable tie-break.
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
