-- The WoW storage adapter (core/Storage.lua). The saved data (the saved
-- copy of the entries, and the picks) is the per-character saved variable
-- SeekSavedCopy (see the TOC); WoW writes it to a file at logout and
-- /reload.
--
-- WoW's load order: first all of Seek's files run (and Seek's own sources
-- register); then WoW sets SeekSavedCopy from the file and sends
-- ADDON_LOADED for Seek. Only then does the core start: it loads the saved
-- copy and the picks, and starts reading sources. So the core never reads
-- (or saves) before the saved data is loaded, and the older saved copy
-- never replaces a newer read.
local addonName, ns = ...

ns.SetStorage({
  Load = function()
    return SeekSavedCopy
  end,
  Save = function(_, data)
    SeekSavedCopy = data
  end,
})

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
  if name == addonName then
    self:UnregisterEvent("ADDON_LOADED")
    ns.Start()
  end
end)
