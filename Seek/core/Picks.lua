-- Picks: each time the player runs an action on a result, Seek remembers
-- that thing, so that it ranks higher later (see GLOSSARY.md). The forget
-- action is not a pick: it removes all picks of a thing. The button
-- "Forget all picks" on Seek's settings page removes all picks of this
-- character, of every thing; it is not a pick either. A pick is
-- the thing's kind and game ID (not its source: the same item from the
-- bags or the bank is one thing), the query that the player had typed, and
-- the time (from the Clock port). An entry without a game ID is never
-- picked: Seek cannot tell such things apart.
--
-- Ranking uses picks in two ways, and they fade with age:
--   strong  picks made with a query that shares a start with the current
--           query (one starts with the other): a pick made with "hea"
--           lifts the thing for "h" and for "hearth". A pick made from the
--           empty search bar has no query, and gives no strong boost.
--   weak    all picks of the thing, for any query that matches it.
--
-- Seek saves the picks per character through the Storage port, next to the
-- saved copy, and keeps the picks of things that the player no longer has:
-- they count again when the thing comes back.
local _, ns = ...

-- Change this when the saved picks' shape changes; Seek then ignores older
-- saved picks.
local SAVED_VERSION = 1

-- Seek keeps at most this many picks, the most recent ones, and none older
-- than this many seconds (90 days).
local MAX_PICKS = 200
local MAX_AGE = 90 * 24 * 60 * 60

-- How much picks lift a result at most, in match score points: together
-- less than 24. A letter at a word start gets 12 extra (WORD_START in
-- Matcher.lua; change these with it), so
-- picks can lift a result above one that matches slightly better, but not
-- above one that matches much better (24 points or more).
local STRONG_BOOST = 18
local WEAK_BOOST = 6

-- A pick fades with age: it counts half after this many seconds (14 days),
-- a quarter after twice as long, and so on.
local HALF_LIFE = 14 * 24 * 60 * 60

-- Every pick, oldest first. Each is a table:
--   kind, gameID  the thing
--   query         the query that the player had typed
--   time          when (ns.Now(), in seconds)
local picks = {}

-- The key of a thing (a pick or an entry): its kind and game ID. Nil
-- without a game ID.
local function Key(thing)
  return thing.gameID ~= nil and thing.kind .. ":" .. tostring(thing.gameID) or nil
end

-- A query as ShareStart compares it: lower case, without spaces at the
-- ends.
local function Normalize(query)
  return query:lower():match("^%s*(.-)%s*$")
end

-- Whether a pick made with `picked` typed gives the strong boost for
-- `query`: one starts with the other, ignoring case and spaces at the ends.
-- Never for a pick made with the query empty.
local function ShareStart(picked, query)
  picked, query = Normalize(picked), Normalize(query)
  if picked == "" then
    return false
  end
  return picked:sub(1, #query) == query or query:sub(1, #picked) == picked
end

-- How much a pick counts at the time `now`: 1 when new, fading with age.
-- A pick from the future (the clock went back) counts as new.
local function Weight(pick, now)
  local age = math.max(0, now - pick.time)
  return 0.5 ^ (age / HALF_LIFE)
end

-- How much picks that count `weight` in all lift a result, up to `boost`:
-- the first pick counts most, and each further one less.
local function Lift(boost, weight)
  return boost * weight / (weight + 1)
end

-- Whether a pick is older than MAX_AGE at the time `now`.
local function Expired(pick, now)
  return now - pick.time > MAX_AGE
end

-- Drops the picks older than MAX_AGE, and then all but the MAX_PICKS most
-- recent ones.
local function DropOld(now)
  local kept = {}
  for _, pick in ipairs(picks) do
    if not Expired(pick, now) then
      kept[#kept + 1] = pick
    end
  end
  while #kept > MAX_PICKS do
    table.remove(kept, 1)
  end
  picks = kept
end

-- Saves the picks through the Storage port.
local function SavePicks()
  ns.Save({ picks = { version = SAVED_VERSION, list = picks } })
end

-- Takes the picks from the saved data (see Storage.lua), if they have the
-- right shape. ns.Start() calls it.
function ns.LoadPicks(data)
  local saved = type(data) == "table" and data.picks
  if type(saved) ~= "table" or saved.version ~= SAVED_VERSION or type(saved.list) ~= "table" then
    return
  end
  local loaded = {}
  for _, pick in ipairs(saved.list) do
    if type(pick) == "table" and type(pick.kind) == "string" and pick.gameID ~= nil
        and type(pick.query) == "string" and type(pick.time) == "number" then
      loaded[#loaded + 1] = { kind = pick.kind, gameID = pick.gameID, query = pick.query, time = pick.time }
    end
  end
  picks = loaded
  DropOld(ns.Now())
end

-- Remembers that the player ran an action on `entry` with `query` typed,
-- and saves the picks.
function ns.RecordPick(entry, query)
  if entry.gameID == nil then
    return
  end
  local now = ns.Now()
  picks[#picks + 1] = { kind = entry.kind, gameID = entry.gameID, query = query, time = now }
  DropOld(now)
  SavePicks()
end

-- Removes all picks of the thing of `entry` (its kind and game ID),
-- whatever query each was made with, and saves the picks: the forget
-- action (see GLOSSARY.md).
function ns.ForgetPicks(entry)
  local key = Key(entry)
  local kept = {}
  for _, pick in ipairs(picks) do
    if Key(pick) ~= key then
      kept[#kept + 1] = pick
    end
  end
  picks = kept
  SavePicks()
end

-- The functions to call when all picks are forgotten (see
-- ns.WatchForgottenPicks).
local forgottenWatchers = {}

-- Calls `watcher()` each time all picks are forgotten, so that an open
-- search bar can show it at once. (The forget action needs no notice: the
-- search session runs it itself.)
function ns.WatchForgottenPicks(watcher)
  forgottenWatchers[#forgottenWatchers + 1] = watcher
end

-- Removes all picks of this character, of every thing, and saves the
-- picks: the button "Forget all picks" on Seek's settings page.
function ns.ForgetAllPicks()
  picks = {}
  SavePicks()
  for _, watcher in ipairs(forgottenWatchers) do
    watcher()
  end
end

-- How much the picks lift each result of `query`: a function that takes an
-- entry and gives its boost (0 for a thing that was never picked).
function ns.PickBoosts(query)
  local now = ns.Now()
  local strong, weak = {}, {}
  for _, pick in ipairs(picks) do
    if not Expired(pick, now) then
      local key = Key(pick)
      local weight = Weight(pick, now)
      weak[key] = (weak[key] or 0) + weight
      if ShareStart(pick.query, query) then
        strong[key] = (strong[key] or 0) + weight
      end
    end
  end
  return function(entry)
    local key = Key(entry)
    if not key or not weak[key] then
      return 0
    end
    return Lift(STRONG_BOOST, strong[key] or 0) + Lift(WEAK_BOOST, weak[key])
  end
end

-- Up to `count` of `entries`, one for each recently picked thing, the most
-- recent pick first. A thing with no entry in `entries` is left out (the
-- player no longer has it); its picks stay and count again when it comes
-- back. An entry with no actions (a faded result, such as an item in
-- another character's bags) is never a pick, so it is left out too. Of two
-- entries of the same thing, the first in `entries` is used.
function ns.RecentlyPicked(entries, count)
  local now = ns.Now()
  local byKey = {}
  for _, entry in ipairs(entries) do
    local key = Key(entry)
    if key and not byKey[key] and ns.HasActions(entry) then
      byKey[key] = entry
    end
  end
  local recent, seen = {}, {}
  for i = #picks, 1, -1 do
    local key = Key(picks[i])
    if byKey[key] and not seen[key] and not Expired(picks[i], now) then
      seen[key] = true
      recent[#recent + 1] = byKey[key]
      if #recent == count then
        break
      end
    end
  end
  return recent
end
