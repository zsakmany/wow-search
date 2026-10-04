-- A fake game for the tests: loads Seek's core the way WoW does and plugs
-- fake adapters into its ports:
--   combat     a fake combat state that the test turns on and off
--   storage    an in-memory storage; a reload keeps it, as WoW keeps saved
--              variables
--   scheduler  runs work all at once, or, with `stepByStep`, one step each
--              time the test asks
-- The test acts as the game: it registers fake sources through `game.Seek`
-- (the public API), starts the core (as WoW does when the saved variables
-- are loaded), enters and leaves combat, and reloads.

local load_core = require("tests.load_core")

-- A deep copy. The in-memory storage keeps copies, so that what the core
-- saved cannot change later, as in WoW, where saved variables go to a file.
local function Copy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for key, field in pairs(value) do
    copy[key] = Copy(field)
  end
  return copy
end

local function NewStorage()
  local storage = {}
  function storage:Load()
    return Copy(self.data)
  end
  function storage:Save(data)
    self.data = Copy(data)
  end
  return storage
end

local function NewCombatState(inCombat)
  local combat = { inCombat = inCombat or false }
  function combat:IsInCombat()
    return self.inCombat
  end
  return combat
end

-- Runs the steps of each piece of work in the order the work came. Without
-- `stepByStep`, all work runs at once, as soon as it comes.
local function NewScheduler(stepByStep)
  local scheduler = { queue = {}, stepByStep = stepByStep, running = false }

  function scheduler:Run(step)
    self.queue[#self.queue + 1] = step
    if not self.stepByStep then
      self:RunAll()
    end
  end

  -- Runs one step of the oldest work. Returns false when there was no work.
  function scheduler:Step()
    local step = self.queue[1]
    if not step then
      return false
    end
    self.running = true
    local more = step()
    self.running = false
    if not more then
      table.remove(self.queue, 1)
    end
    return true
  end

  -- Runs all steps of all work. Work that comes while a step runs is run by
  -- the loop that is already running.
  function scheduler:RunAll()
    if not self.running then
      while self:Step() do
      end
    end
  end

  return scheduler
end

local FakeGame = {}
FakeGame.__index = FakeGame

local M = {}

-- A new game with the core loaded and the fakes plugged in, not started
-- yet: sources that register now are read only after `game:Start()`.
-- options (all optional):
--   inCombat    the player is in combat
--   stepByStep  the scheduler runs one step each time the test asks
--   storage     the storage to use (a reload passes the old game's)
function M.New(options)
  options = options or {}
  local ns = load_core()
  local game = setmetatable({
    ns = ns,
    Seek = ns.api,
    combat = NewCombatState(options.inCombat),
    storage = options.storage or NewStorage(),
    scheduler = NewScheduler(options.stepByStep),
  }, FakeGame)
  ns.SetCombatState(game.combat)
  ns.SetStorage(game.storage)
  ns.SetScheduler(game.scheduler)
  return game
end

-- A new game, started.
function M.Started(options)
  local game = M.New(options)
  game:Start()
  return game
end

-- The saved variables are loaded: the core loads the saved copy and starts
-- reading sources.
function FakeGame:Start()
  self.ns.Start()
end

function FakeGame:EnterCombat()
  self.combat.inCombat = true
  self.ns.CombatStarted()
end

function FakeGame:LeaveCombat()
  self.combat.inCombat = false
  self.ns.CombatEnded()
end

-- Runs one step of the scheduler's work. Returns false when there was none.
function FakeGame:Step()
  return self.scheduler:Step()
end

-- Whether the scheduler has no work left.
function FakeGame:IsIdle()
  return self.scheduler.queue[1] == nil
end

-- Runs all of the scheduler's work.
function FakeGame:RunSteps()
  self.scheduler:RunAll()
end

-- A /reload: a new game with a freshly loaded core and the same storage,
-- not started yet. The player stays in or out of combat, unless
-- `options.inCombat` says otherwise.
function FakeGame:Reload(options)
  options = options or {}
  local inCombat = options.inCombat
  if inCombat == nil then
    inCombat = self.combat.inCombat
  end
  return M.New({ inCombat = inCombat, stepByStep = options.stepByStep, storage = self.storage })
end

return M
