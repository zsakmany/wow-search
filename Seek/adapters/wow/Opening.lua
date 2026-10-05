-- The ways to open and close the search bar: the key binding (Bindings.xml;
-- SuggestedKey.lua sets its first key), the /seek slash command, and the
-- Seek entry in the game's addon button at the minimap. All of them toggle
-- it.
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

-- Called by the Seek entry in the addon button at the minimap (the addon
-- compartment), through the TOC's AddonCompartmentFunc. The game finds it
-- by its global name.
function Seek_OnAddonCompartmentClick()
  ns.ToggleSearchBar()
end
