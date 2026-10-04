-- Seek's quest source: one entry per quest in the character's quest log. It
-- registers through the public `Seek` table, like any other addon's source.
--
-- It leaves out what the quest log itself does not list as a quest: header
-- rows, hidden quests, and tasks (bonus objectives, which show only in the
-- objective tracker). Quests under a collapsed header are still read.

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

-- Calls `visit(questID, title)` for each quest that the quest log lists.
local function EachQuest(visit)
  for index = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(index)
    if info and not info.isHeader and not info.isHidden and not info.isTask then
      visit(info.questID, info.title)
    end
  end
end

local function GetEntries()
  local entries = {}
  local owner = CurrentCharacter()
  EachQuest(function(questID, title)
    entries[#entries + 1] = {
      name = title,
      icon = QUEST_ICON,
      kind = "quest",
      gameID = questID,
      owner = owner,
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
