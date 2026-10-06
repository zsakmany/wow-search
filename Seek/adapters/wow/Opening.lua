-- The ways to open and close the search bar: the key binding (Bindings.xml;
-- SuggestedKey.lua sets its first key), the /seek slash command, and a left
-- click on the Seek entry in the game's addon button at the minimap or on
-- Seek's minimap icon (MinimapIcon.lua). All of them toggle it. `/seek
-- settings` and a right click on the Seek entry or the minimap icon open
-- Seek's settings page instead (adapters/wow/Settings.lua).
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
SlashCmdList.SEEK = function(text)
  if text:lower():match("^%s*(.-)%s*$") == "settings" then
    ns.OpenSettings()
  else
    ns.ToggleSearchBar()
  end
end

-- A click on the Seek entry in the addon button or on the minimap icon,
-- with the mouse button: a right click opens the settings page, any other
-- click toggles the search bar.
function ns.ClickAddonButtonOrMinimapIcon(button)
  if button == "RightButton" then
    ns.OpenSettings()
  else
    ns.ToggleSearchBar()
  end
end

-- Called by the Seek entry in the addon button at the minimap (the addon
-- compartment), through the TOC's AddonCompartmentFunc, with the addon's
-- name and the mouse button. The game finds it by its global name.
function Seek_OnAddonCompartmentClick(_, button)
  ns.ClickAddonButtonOrMinimapIcon(button)
end
