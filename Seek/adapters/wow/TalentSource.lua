-- Seek's talent source: one entry per talent in the talent trees of the
-- character's class, for the spec group that the character uses now, with
-- points or without (ADR 0001). Each has the talent's description as its
-- long text, and its spent and possible points. It registers through the
-- public `Seek` table, like any other addon's source.
--
-- On Forever the class has one talent tree, split into talent groups (the
-- school columns), for each of its two spec groups (dual spec). Seek reads
-- the tree the way the talent window does (Blizzard_PlayerSpells, with its
-- Camelot overrides). For a choice node, each option is its own talent.
-- Left out: nodes that the talent window hides (such as those of another
-- specialization), the talents of the other spec group, and the nodes of a
-- sub-tree that is not active, if the game has any.
local _, ns = ...

local SOURCE_ID = "Seek.Talents"

-- A spell's description as long text, or nil while the game loads it;
-- TextLoaded reads the talents again when it comes (SpellText.lua).
local SpellDescription, TextLoaded = ns.SpellDescriptions(SOURCE_ID)

-- The talent's name, icon, and description, as the talent window shows them
-- (TalentUtil.GetTalentName, TalentUtil.GetTalentDescription, and
-- TalentButtonUtil.CalculateIconTexture in Blizzard_SharedTalentUI/
-- Blizzard_SharedTalentUtil.lua): the definition's own, when it has them,
-- else those of its spell. The name is "" when there is none.
local function TalentName(definition)
  if definition.overrideName and definition.overrideName ~= "" then
    return definition.overrideName
  end
  return definition.spellID and C_Spell.GetSpellName(definition.spellID) or ""
end

-- The talent's icon (see TalentName).
local function TalentIcon(definition)
  if definition.overrideIcon then
    return definition.overrideIcon
  end
  -- The spell's own icon, not one that another spell puts over it.
  return definition.spellID and select(2, C_Spell.GetSpellTexture(definition.spellID))
end

-- The talent's description as long text, or nil (see TalentName).
local function TalentDescription(definition)
  if definition.overrideDescription and definition.overrideDescription ~= "" then
    return ns.LongText({ definition.overrideDescription })
  end
  return definition.spellID and SpellDescription(definition.spellID)
end

-- The ID of the talent config of the spec group that the character uses
-- now, or nil. The talent window uses this one for the spec group's tab;
-- the game's active config is the same, and is the fallback.
local function ConfigID()
  local specGroup = C_SpecializationInfo.GetActiveSpecGroup()
  return specGroup and C_SpecializationInfo.GetCombatConfigIDForSpecGroup(specGroup)
    or C_ClassTalents.GetActiveConfigID()
end

-- Whether the talent window shows the node: a visible node, and, for a node
-- of a sub-tree, only when that sub-tree is active.
local function IsNodeVisible(node)
  return node.isVisible and (not node.subTreeID or node.subTreeActive)
end

-- The talent's spent and possible points, as the talent window shows them:
-- its node's current rank, when it is the node's active option (always, for
-- a node with one talent), and the most its option can take. The current
-- rank counts the ranks that the game gives for free too, not only the
-- bought ones, so a free talent shows 1/1, as in the talent window. For a
-- choice node: 1/1 on the chosen option, 0/1 on the others.
local function SpentAndPossiblePoints(node, entryID, entryInfo)
  local active = node.activeEntry and node.activeEntry.entryID == entryID
  local possible = entryInfo.maxRanks
  return active and math.min(node.currentRank, possible) or 0, possible
end

-- One entry per talent of the active spec group's tree (see the top of
-- this file). None before the game has the talent data (at login).
local function GetEntries()
  local entries = {}
  local configID = ConfigID()
  local config = configID and C_Traits.GetConfigInfo(configID)
  local treeID = config and config.treeIDs[1]
  if not treeID then
    return entries
  end
  local owner = ns.CurrentCharacter()
  for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
    local node = C_Traits.GetNodeInfo(configID, nodeID)
    if node and IsNodeVisible(node) then
      for _, entryID in ipairs(node.entryIDs) do
        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
        -- An option that picks a sub-tree has no definition: it is not a
        -- talent itself.
        local definition = entryInfo and entryInfo.definitionID
          and C_Traits.GetDefinitionInfo(entryInfo.definitionID)
        local name = definition and TalentName(definition)
        if name and name ~= "" then
          local spentPoints, possiblePoints = SpentAndPossiblePoints(node, entryID, entryInfo)
          entries[#entries + 1] = {
            name = name,
            icon = TalentIcon(definition),
            kind = "talent",
            gameID = entryID,
            owner = owner,
            longText = TalentDescription(definition),
            spentPoints = spentPoints,
            possiblePoints = possiblePoints,
          }
        end
      end
    end
  end
  return entries
end

Seek.RegisterSource({ id = SOURCE_ID, GetEntries = GetEntries })

-- The talents change when the player changes a talent or applies the
-- changes (TRAIT_NODE_CHANGED, TRAIT_CONFIG_UPDATED, TRAIT_TREE_CHANGED),
-- or switches spec group (PLAYER_TALENT_UPDATE,
-- ACTIVE_COMBAT_CONFIG_CHANGED). Several come at once, one per node; Seek
-- reads the talents once for all of the notices that come before it
-- reads. At login, PLAYER_ENTERING_WORLD and TRAIT_CONFIG_LIST_UPDATED
-- (the talent configs are ready; the talent window waits for it too) read
-- them once the talent data is ready. SPELL_TEXT_UPDATE comes when a
-- spell's description is ready. Seek decides when to read: in combat, it
-- waits for the end (ADR 0002), so this file must not read the talents
-- itself.
local events = CreateFrame("Frame")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("TRAIT_NODE_CHANGED")
events:RegisterEvent("TRAIT_TREE_CHANGED")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
events:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELL_TEXT_UPDATE")
events:SetScript("OnEvent", function(_, event, spellID)
  if event == "SPELL_TEXT_UPDATE" then
    TextLoaded(spellID)
  else
    Seek.NotifyChanged(SOURCE_ID)
  end
end)
