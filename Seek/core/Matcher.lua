-- Fuzzy matching on names: the query's letters must appear in the name in
-- order, with gaps allowed. Case is ignored. A letter at a word start, and a
-- letter right after the previous matched letter, score higher; gaps cost a
-- little. Of all the ways the query fits the name, the best one counts.
--
-- Word-start matching on long text (no fuzzy matching there, so that long
-- text does not fill the results with noise): each query word must match the
-- start of a word in the text. Case is ignored here too.
local _, ns = ...

local MATCH = 16 -- each matched letter
local WORD_START = 12 -- extra for a letter that starts a word (Picks.lua relies on it)
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

-- The words of a text, in lower case (ASCII letters only, as for names),
-- with one space before each word. A word is a run of letters and digits,
-- ASCII or not. Typographic punctuation (U+2000 to U+206F: quotes such as
-- „“ and ’, dashes, "…") and the no-break space (U+00A0) also separate
-- words; other non-ASCII characters count as letters.
local function Words(text)
  text = text:gsub("[A-Z]", string.lower)
    :gsub("\226\128[\128-\191]", " ")
    :gsub("\226\129[\128-\175]", " ")
    :gsub("\194\160", " ")
  local words = {}
  for word in text:gmatch("[%w\128-\255]+") do
    words[#words + 1] = " " .. word
  end
  return words
end

-- Prepares a long text once, so that each query matches it fast: its words,
-- each after one space, in one string. A query word then starts a word in
-- the text exactly where " " .. word is found. Returns nil for a text with
-- no words.
function ns.PrepareLongText(text)
  local words = Words(text)
  if #words == 0 then
    return nil
  end
  return table.concat(words)
end

-- Prepares the query once for all names and long texts.
function ns.PrepareQuery(query)
  return { chars = Characters(query), words = Words(query) }
end

-- Whether each query word starts a word in the prepared long text. A query
-- with no words matches no long text.
function ns.MatchesLongText(query, longText)
  if #query.words == 0 then
    return false
  end
  for _, word in ipairs(query.words) do
    if not longText:find(word, 1, true) then
      return false
    end
  end
  return true
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
