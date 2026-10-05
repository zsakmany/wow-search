-- Seek's quest source: one entry per quest in the character's quest log,
-- with the quest's description and objectives as its long text. It
-- registers through the public `Seek` table, like any other addon's source.
--
-- It leaves out what the quest log itself does not list as a quest: header
-- rows, hidden quests, and tasks (bonus objectives, which show only in the
-- objective tracker). Quests under a collapsed header are still read.
local _, ns = ...

local SOURCE_ID = "Seek.Quests"

-- The quest log API gives no icon for a quest; all quests share this one.
local QUEST_ICON = "Interface\\Icons\\INV_Misc_Book_08"

-- "Name-Realm" of the current character (the realm can be missing early in
-- the login).
local function CurrentCharacter()
  local name, realm = UnitFullName("player")
  if realm and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

-- Calls `visit(index, questID, title)` for each quest that the quest log
-- lists, with its index in the quest log.
local function EachQuest(visit)
  for index = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(index)
    if info and not info.isHeader and not info.isHidden and not info.isTask then
      visit(index, info.questID, info.title)
    end
  end
end

-- The quest's text: its description, the objectives text under it, and
-- each objective line (such as "Wolf Meat: 3/8"). GetQuestLogQuestText
-- takes the quest's index, so Seek never selects the quest: the selected
-- quest is UI state that the quest log and the map use, and changing it from
-- addon code risks taint (issues #27 and #29). Blizzard's own quest log
-- search reads the text the same way. Text that the game has not loaded yet
-- comes with a later QUEST_LOG_UPDATE, which reads the log again.
local function QuestText(index, questID)
  local description, objectives = GetQuestLogQuestText(index)
  local pieces = {}
  pieces[#pieces + 1] = description
  pieces[#pieces + 1] = objectives
  for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
    pieces[#pieces + 1] = objective.text
  end
  return ns.LongText(pieces)
end

local function GetEntries()
  local entries = {}
  local owner = CurrentCharacter()
  EachQuest(function(index, questID, title)
    entries[#entries + 1] = {
      name = title,
      icon = QUEST_ICON,
      kind = "quest",
      gameID = questID,
      owner = owner,
      longText = QuestText(index, questID),
    }
  end)
  return entries
end

Seek.RegisterSource({ id = SOURCE_ID, GetEntries = GetEntries })

-- QUEST_LOG_UPDATE comes often (objective progress, quest data loading,
-- several times in one frame); Seek reads the log once for all of the
-- notices that come before it reads. PLAYER_ENTERING_WORLD reads the log
-- once it is ready at login. Seek decides when to read: in combat, it waits
-- for the end (ADR 0002), so this file must not read the log itself.
local events = CreateFrame("Frame")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
  Seek.NotifyChanged(SOURCE_ID)
end)
