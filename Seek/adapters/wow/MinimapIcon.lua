-- Seek's minimap icon (see GLOSSARY.md): the magnifying glass at the edge
-- of the minimap, made with LibDBIcon-1.0 (libs/). A click on it does the
-- same as a click on the Seek entry in the addon button (Opening.lua). The
-- mouse on it shows the hover text.
--
-- The setting "Show minimap icon" (minimapIcon) is the only truth for
-- whether the icon shows, and a change shows or hides it at once.
-- LibDBIcon shows or hides the icon by its own `hide` field when the
-- player logs in, so Seek writes that field from the setting before then,
-- and again on each change. Its saved value is never read.
--
-- The icon's place on the minimap edge is in the account-wide saved
-- variable SeekMinimapIcon (see the TOC), the table where LibDBIcon keeps
-- it. It is not a setting: it is the same on every character, and the
-- settings store never sees it.
local addonName, ns = ...

local L = ns.L

local LibDBIcon = LibStub("LibDBIcon-1.0")

-- The same magnifying glass as the Seek entry in the addon button (the
-- TOC's IconAtlas), and the search box's magnifying glass if the game has
-- no such atlas.
local ICON_ATLAS = "common-search-magnifyingglass"
local FALLBACK_ICON = "Interface\\Common\\UI-Searchbox-Icon"

-- The icon's picture: a texture file, and the place of the picture in it
-- (left, right, top, bottom), or nil for the whole file. LibDBIcon takes a
-- file, not an atlas, so this asks the game where the atlas is.
local function Picture()
  local atlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ICON_ATLAS)
  local file = atlas and (atlas.file or atlas.filename)
  if not file then
    return FALLBACK_ICON, nil
  end
  return file, { atlas.leftTexCoord, atlas.rightTexCoord, atlas.topTexCoord, atlas.bottomTexCoord }
end

local icon, iconCoords = Picture()

-- When the mouse button last went down on the icon (see OnClick).
local mouseDownAt = 0

-- The icon's data for LibDBIcon: a LibDataBroker data object. Its type
-- "launcher" is LibDataBroker's word for a data object that only takes
-- clicks.
local iconData = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
  type = "launcher",
  icon = icon,
  iconCoords = iconCoords,
  -- A left click while the bar is open must close it. But the mouse button
  -- going down already took the text box's focus, which closed the bar;
  -- toggling now would open it again, so the click does nothing then.
  OnClick = function(_, button)
    if button == "LeftButton" and ns.SearchBarClosedByLostFocusSince(mouseDownAt) then
      return
    end
    ns.ClickAddonButtonOrMinimapIcon(button)
  end,
  -- LibDBIcon shows the hover text in its own GameTooltip frame.
  OnTooltipShow = function(frame)
    frame:AddLine(L.NAME)
    frame:AddLine(L.HOVER_TEXT_LEFT_CLICK, 1, 1, 1)
    frame:AddLine(L.HOVER_TEXT_RIGHT_CLICK, 1, 1, 1)
  end,
})

local registered = false

-- Shows or hides the icon as the setting says. Before the player logs in,
-- this only writes LibDBIcon's `hide` field: LibDBIcon places the icon and
-- shows or hides it by that field at login, once other addons have set
-- the minimap's shape.
local function Update()
  local shown = ns.Setting("minimapIcon")
  SeekMinimapIcon.hide = not shown
  if not IsLoggedIn() then
    return
  end
  if shown then
    LibDBIcon:Show(addonName)
  else
    LibDBIcon:Hide(addonName)
  end
end

ns.WatchSettings(function(name)
  if name == "minimapIcon" and registered then
    Update()
  end
end)

-- The icon needs its saved place, so it appears when the saved variables
-- are loaded. Settings.lua may load the settings just before or just after
-- this; until then the setting gives its default, and the watcher above
-- updates the icon when the loaded value differs. Both happen before the
-- player logs in, when LibDBIcon first shows its icons.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
  if name == addonName then
    self:UnregisterEvent("ADDON_LOADED")
    if type(SeekMinimapIcon) ~= "table" then
      SeekMinimapIcon = {}
    end
    LibDBIcon:Register(addonName, iconData, SeekMinimapIcon)
    -- The lost focus and the mouse button going down happen in the same
    -- frame, so they get the same GetTime(), in either order.
    LibDBIcon:GetMinimapButton(addonName):HookScript("OnMouseDown", function()
      mouseDownAt = GetTime()
    end)
    registered = true
    Update()
  end
end)
