-- Makes an entry's long text (see core/Sources.lua) from pieces of game
-- text, such as tooltip lines, for Seek's own sources. Seek keeps long text
-- in the saved copy, so only plain text goes in: color codes, links,
-- textures, and atlases are stripped, and line breaks become spaces.
--
-- Call it only while Seek reads a source, which is only outside combat: in
-- combat, game text such as tooltip text can be a secret value (ADR 0002).
local _, ns = ...

-- The pieces (a list of strings) joined with spaces, as plain text, or nil
-- when no text is left.
function ns.LongText(pieces)
  local text = C_StringUtil.StripHyperlinks(table.concat(pieces, " "))
  text = text:gsub("|n", " "):gsub("%s+", " "):match("^ ?(.-) ?$")
  if text == "" then
    return nil
  end
  return text
end
