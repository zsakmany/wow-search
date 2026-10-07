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

-- Spells whose description was empty at the last read (spell ID -> true).
-- The game may still be loading it.
local waiting = {}

-- The game has loaded a spell's data or text: if Seek waits for it, read the
-- talents again. (Many spells can load in one frame; Seek reads the talents
-- once for all of their notices.)
local function TextLoaded(spellID)
  if waiting[spellID] then
    waiting[spellID] = nil
    Seek.NotifyChanged(SOURCE_ID)
  end
end

-- The talent's spell's description, or nil. As in the spell source
-- (SpellSource.lua): the description is empty until the game has loaded
-- the spell's data; then wait for it, and read again when it comes
-- (SPELL_TEXT_UPDATE below, or the spell data load).
local function SpellDescription(spellID)
  local description = C_Spell.GetSpellDescription(spellID)
  if description and description ~= "" then
    waiting[spellID] = nil
    return ns.LongText({ description })
  end
  if not waiting[spellID] then
    waiting[spellID] = true
    local spell = Spell:CreateFromSpellID(spellID)
    if not spell:IsSpellDataCached() then
      spell:ContinueOnSpellLoad(function()
        TextLoaded(spellID)
      end)
    end
  end
  return nil
end

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

local function TalentIcon(definition)
  if definition.overrideIcon then
    return definition.overrideIcon
  end
  -- The spell's own icon, not one that another spell puts over it.
  return definition.spellID and select(2, C_Spell.GetSpellTexture(definition.spellID))
end

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
local function IsShown(node)
  return node.isVisible and (not node.subTreeID or node.subTreeActive)
end

-- The talent's points: the points spent in its node, when it is the node's
-- active option (always, for a node with one talent), and the most its
-- option can take. For a choice node: 1/1 on the chosen option, 0/1 on the
-- others.
local function Points(node, entryID, entryInfo)
  local active = node.activeEntry and node.activeEntry.entryID == entryID
  return active and node.ranksPurchased or 0, entryInfo.maxRanks
end

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
    if node and IsShown(node) then
      for _, entryID in ipairs(node.entryIDs) do
        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
        -- An option that picks a sub-tree has no definition: it is not a
        -- talent itself.
        local definition = entryInfo and entryInfo.definitionID
          and C_Traits.GetDefinitionInfo(entryInfo.definitionID)
        local name = definition and TalentName(definition)
        if name and name ~= "" then
          local spentPoints, possiblePoints = Points(node, entryID, entryInfo)
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
-- reads. PLAYER_ENTERING_WORLD reads them once the talent data is ready at
-- login. SPELL_TEXT_UPDATE comes when a spell's description is ready. Seek
-- decides when to read: in combat, it waits for the end (ADR 0002), so this
-- file must not read the talents itself.
local events = CreateFrame("Frame")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("TRAIT_NODE_CHANGED")
events:RegisterEvent("TRAIT_TREE_CHANGED")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELL_TEXT_UPDATE")
events:SetScript("OnEvent", function(_, event, spellID)
  if event == "SPELL_TEXT_UPDATE" then
    TextLoaded(spellID)
  else
    Seek.NotifyChanged(SOURCE_ID)
  end
end)
