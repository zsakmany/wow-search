-- The WoW action adapter: runs the actions that the core asks for through
-- the Actions port (core/Actions.lua). Show actions only change what the
-- player sees, so they also work in combat.
--
-- Show in bag works with the default Blizzard bags. With a bag addon that
-- replaces them (such as Bagnon), the bag addon's own window opens if it
-- takes over OpenBag, and nothing is highlighted: Seek finds no shown
-- Blizzard bag button to light.
local _, ns = ...

local FIRST_BAG = Enum.BagIndex.Backpack
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS

local HIGHLIGHT_SECONDS = 4

-- The bag slots to highlight ({ bag, slot, itemID } each) and when to stop.
local targets = {}
local highlightEnds = 0

-- Seek's glow texture on each bag button that has had one (button -> glow).
-- Kept here, not as a field on Blizzard's button, so Seek writes nothing
-- into Blizzard's tables (that would taint them).
local glows = setmetatable({}, { __mode = "k" })

-- A pulsing glow like the game's own "new item" glow, on top of the icon.
local function GlowOn(button)
  local glow = glows[button]
  if not glow then
    glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetAtlas("bags-glow-white", true)
    glow:SetPoint("CENTER")
    glow:SetBlendMode("ADD")
    glow.pulse = glow:CreateAnimationGroup()
    glow.pulse:SetLooping("BOUNCE")
    local fade = glow.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.2)
    fade:SetDuration(0.5)
    -- A new texture starts shown; hide it so the check below starts the pulse.
    glow:Hide()
    glows[button] = glow
  end
  if not glow:IsShown() then
    glow:Show()
    glow.pulse:Play()
  end
end

local function GlowOff(glow)
  glow.pulse:Stop()
  glow:Hide()
end

-- Blizzard's bags reuse their item buttons (for example when the player
-- switches between one combined bag and separate bags), so a button can
-- show another slot later. Each frame while the highlight lasts, find the
-- buttons that show the target slots now, and light only those. The glow
-- goes off after a few seconds, or as soon as the bags close or the item
-- leaves its slot.
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
  local lit = {}
  if GetTime() < highlightEnds then
    for _, target in ipairs(targets) do
      local button = ContainerFrameUtil_GetItemButtonAndContainer(target.bag, target.slot)
      if button and button:IsVisible()
          and C_Container.GetContainerItemID(target.bag, target.slot) == target.itemID then
        lit[button] = true
      end
    end
  else
    self:Hide()
  end
  -- Light the buttons first: a button gets its glow the first time here.
  for button in pairs(lit) do
    GlowOn(button)
  end
  for button, glow in pairs(glows) do
    if not lit[button] and glow:IsShown() then
      GlowOff(glow)
    end
  end
end)

-- Opens the bags and highlights every slot that holds the item.
local function ShowInBag(entry)
  targets = {}
  for bag = FIRST_BAG, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      if C_Container.GetContainerItemID(bag, slot) == entry.gameID then
        targets[#targets + 1] = { bag = bag, slot = slot, itemID = entry.gameID }
      end
    end
  end

  -- Open only the bags that hold the item. With the game's "Combine bags"
  -- option on, OpenBag opens the combined bag instead.
  for _, target in ipairs(targets) do
    if not IsBagOpen(target.bag) then
      OpenBag(target.bag)
    end
  end

  -- Without Blizzard's bag code there is nothing to highlight.
  if ContainerFrameUtil_GetItemButtonAndContainer and #targets > 0 then
    highlightEnds = GetTime() + HIGHLIGHT_SECONDS
    driver:Show()
  end
end

-- Each action id from the kind registry (core/Kinds.lua) and how to run it.
local run = {
  showInBag = ShowInBag,
}

ns.SetActionAdapter({
  Run = function(_, actionID, entry)
    local action = run[actionID]
    if not action then
      error("Seek: the WoW action adapter cannot run the action " .. tostring(actionID))
    end
    action(entry)
  end,
})
