-- Fuzzy matching on names: the query's letters must appear in the name in
-- order, with gaps allowed. Case is ignored. A letter at a word start, and a
-- letter right after the previous matched letter, score higher; gaps cost a
-- little. Of all the ways the query fits the name, the best one counts.
local _, ns = ...

local MATCH = 16 -- each matched letter
local WORD_START = 12 -- extra for a letter that starts a word
local ADJACENT = 8 -- extra for a letter right after the previous match
local GAP_START = 3 -- cost of a gap between two matched letters
local GAP_EXTEND = 1 -- cost of each further letter in that gap

-- Splits text into UTF-8 characters (names from non-English game clients
-- have letters such as "ß" that take more than one byte). Only ASCII
-- letters get lower case; other letters must match exactly.
local function Characters(text)
  local chars = {}
  for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    chars[#chars + 1] = #char == 1 and char:lower() or char
  end
  return chars
end

-- A letter or digit, ASCII or not; anything else (space, hyphen, colon)
-- separates words.
local function IsWordCharacter(char)
  return #char > 1 or char:find("^%w") ~= nil
end

-- Prepares a name once, so that each query matches it fast.
function ns.PrepareName(name)
  local chars = Characters(name)
  local starts = {}
  for i, char in ipairs(chars) do
    starts[i] = IsWordCharacter(char) and (i == 1 or not IsWordCharacter(chars[i - 1]))
  end
  return { chars = chars, starts = starts }
end

-- Prepares the query once for all names.
function ns.PrepareQuery(query)
  return { chars = Characters(query) }
end

-- The score of a name for a query (higher is better), or nil when the name
-- does not match.
function ns.Score(query, name)
  local q, n = query.chars, name.chars
  if #q == 0 then
    return nil
  end
  -- Most names do not match at all: find that out cheaply first.
  local at = 0
  for i = 1, #q do
    repeat
      at = at + 1
    until n[at] == q[i] or at > #n
    if at > #n then
      return nil
    end
  end
  -- best[j]: the best score with the previous query letter matched at
  -- name letter j (nil when it cannot be matched there).
  local best
  for i = 1, #q do
    local current = {}
    -- The best score of an earlier match at least 2 letters back, with the
    -- cost of the gap up to letter j already taken off.
    local gapped
    for j = 1, #n do
      if i > 1 then
        if gapped then
          gapped = gapped - GAP_EXTEND
        end
        local before = best[j - 2]
        if before and (not gapped or before - GAP_START > gapped) then
          gapped = before - GAP_START
        end
      end
      if n[j] == q[i] then
        local score = MATCH + (name.starts[j] and WORD_START or 0)
        if i == 1 then
          current[j] = score
        else
          local previous = best[j - 1] and best[j - 1] + ADJACENT
          if gapped and (not previous or gapped > previous) then
            previous = gapped
          end
          current[j] = previous and previous + score
        end
      end
    end
    best = current
  end
  local top
  for j = 1, #n do
    if best[j] and (not top or best[j] > top) then
      top = best[j]
    end
  end
  return top
end
