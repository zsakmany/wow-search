-- The ways to open and close the search bar: the key binding (Bindings.xml)
-- and the /seek slash command. Both toggle it.
local _, ns = ...

local L = ns.L

-- Label in the game's Keybindings menu for the binding in Bindings.xml.
BINDING_NAME_SEEK_TOGGLE = L.BINDING_TOGGLE

-- Called by the SEEK_TOGGLE binding. Bindings.xml runs in the global
-- environment, so it can only reach a global function.
function Seek_ToggleSearchBar()
  ns.ToggleSearchBar()
end

SLASH_SEEK1 = "/seek"
SlashCmdList.SEEK = function()
  ns.ToggleSearchBar()
end
