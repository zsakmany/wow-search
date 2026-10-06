-- Seek's game option source: one entry per game option and game option page
-- in the game's Options window, in the player's game language. A game
-- option's long text is its hover explanation in the window (its tooltip in
-- the Settings API). It registers through the public `Seek` table, like any
-- other addon's source.
--
-- It lists Blizzard's pages (the window's Game tab) and their subpages, and
-- Seek's own page. Left out: the pages of other addons on the AddOns tab,
-- section headers (rows with a name but no setting and no action), game
-- options that are hidden now (ShouldShow), rows that are a copy of a game
-- option on another page (search ignores them in Blizzard's search too),
-- the hidden key binding pages (those with a redirectCategory, such as
-- "NoDisplayKB"), and the rows of the key binding page: key bindings are a
-- later issue. Rows with no name (some buttons) are left out too.
--
-- Seek only reads the window's lists. It never writes into SettingsPanel or
-- its pages: writing there from addon code taints the window (issue #25).
local _, ns = ...

local SOURCE_ID = "Seek.GameOptions"

-- The Settings API gives no icon for a game option; all share this one.
local GAME_OPTION_ICON = "Interface\\Icons\\INV_Misc_Gear_01"

-- The text of a name or a tooltip, which can be a string or a function that
-- gives one. Nil when there is no text, or when the function fails.
local function Text(value)
  if type(value) == "function" then
    local ok, text = pcall(value)
    value = ok and text or nil
  end
  if type(value) == "string" and value ~= "" then
    return value
  end
  return nil
end

-- Calls `visit(page, name)` for each game option page that Seek lists,
-- with the page's qualified name (a subpage's name comes with its parent
-- page's name): Blizzard's pages and their subpages, and Seek's own page,
-- but no hidden key binding page.
local function EachPage(visit)
  local function Visit(page)
    local name = not page.redirectCategory and Text(page:GetQualifiedName())
    if name then
      visit(page, name)
    end
  end
  for _, category in ipairs(SettingsPanel:GetAllCategories()) do
    if category:GetCategorySet() == Settings.CategorySet.Game or category == ns.SettingsPage() then
      Visit(category)
      for _, subpage in ipairs(category:GetSubcategories()) do
        Visit(subpage)
      end
    end
  end
end

-- Whether the row is shown now. A failing check counts as hidden.
local function IsShown(initializer)
  local ok, shown = pcall(initializer.ShouldShow, initializer)
  return ok and shown
end

-- Calls `visit(name, tooltip)` for each game option on the page: each row
-- of a vertical layout that has a setting or an action (a button), is
-- shown now, and is not a copy of a row on another page. The name is the
-- one that Settings.OpenToCategory scrolls to: the row's `data.name` (for a
-- setting, the setting's name), else its GetName(). A page with a canvas
-- layout, and the key binding page, have none.
local function EachGameOption(page, visit)
  local layout = SettingsPanel:GetLayout(page)
  if not layout or not layout:IsVerticalLayout() or page:GetID() == Settings.KEYBINDINGS_CATEGORY_ID then
    return
  end
  for _, initializer in ipairs(layout:GetInitializers()) do
    local data = initializer.data
    if type(data) == "table" and (data.setting or data.buttonClick)
        and not (initializer.IsSearchIgnoredInLayout and initializer:IsSearchIgnoredInLayout(layout))
        and IsShown(initializer) then
      local name = Text(data.name) or (initializer.GetName and Text(initializer:GetName()))
      if name then
        visit(name, Text(initializer.GetTooltip and initializer:GetTooltip() or data.tooltip))
      end
    end
  end
end

-- The entries. A page's ID (category:GetID()) is only a counter that can
-- change between sessions, so the game ID is made of names instead: the
-- page's qualified name for a page, and the page's name and the game
-- option's name for a game option. The action adapter looks the page up
-- again by its name (ns.GameOptionPageID).
local function GetEntries()
  local entries, seen = {}, {}
  local function Add(entry)
    if not seen[entry.gameID] then
      seen[entry.gameID] = true
      entries[#entries + 1] = entry
    end
  end
  EachPage(function(page, pageName)
    Add({ name = pageName, icon = GAME_OPTION_ICON, kind = "gameOption", gameID = pageName })
    EachGameOption(page, function(name, tooltip)
      Add({
        name = name,
        icon = GAME_OPTION_ICON,
        kind = "gameOption",
        gameID = pageName .. "\n" .. name,
        page = pageName,
        longText = tooltip and ns.LongText({ tooltip }),
      })
    end)
  end)
  return entries
end

-- The ID of the game option page that Seek lists with this qualified name
-- now, or nil when there is none.
function ns.GameOptionPageID(name)
  local found
  EachPage(function(page, pageName)
    if not found and pageName == name then
      found = page:GetID()
    end
  end)
  return found
end

-- Blizzard builds its pages only after both VARIABLES_LOADED and
-- PLAYER_ENTERING_WORLD, and then sends SETTINGS_LOADED. A read before that
-- would find only some pages and replace the saved copy with them. So the
-- source registers then: until that moment the game is still on the loading
-- screen. Seek decides when to read: in combat, it waits for the end, and
-- search uses the saved copy meanwhile (ADR 0002).
local registered = false

local events = CreateFrame("Frame")
events:RegisterEvent("SETTINGS_LOADED")
events:SetScript("OnEvent", function(self)
  self:UnregisterEvent("SETTINGS_LOADED")
  registered = true
  Seek.RegisterSource({ id = SOURCE_ID, GetEntries = GetEntries })
end)

-- Seek's own page was added to the Options window (adapters/wow/Settings.lua):
-- read the pages again, if they have been read before.
function ns.GameOptionPageAdded()
  if registered then
    Seek.NotifyChanged(SOURCE_ID)
  end
end
