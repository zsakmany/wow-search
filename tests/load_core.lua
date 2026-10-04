-- Loads Seek's core the way WoW does: each core file listed in the TOC, in
-- TOC order, gets ("Seek", ns) as its `...`, and all files share one ns table.
-- Returns that ns. Call it once per test so that each test starts fresh.

local TOC = "Seek/Seek_Camelot.toc"

return function()
  local ns = {}
  local toc = assert(io.open(TOC, "r"))
  for line in toc:lines() do
    -- TOC paths use backslashes; only the core runs outside the game.
    local path = line:match("^%s*(core\\[^%s]+%.lua)%s*$")
    if path then
      local chunk = assert(loadfile("Seek/" .. path:gsub("\\", "/")))
      chunk("Seek", ns)
    end
  end
  toc:close()
  return ns
end
