-- A fake game for the tests: loads Seek's core the way WoW does and plugs
-- fake adapters into its ports:
--   combat     a fake combat state that the test turns on and off
--   character  the current character, "Tester" unless the test names one
--   storage    an in-memory storage: the character's own saved data and the
--              account's, which all of the account's characters share; a
--              reload keeps both, as WoW keeps saved variables
--   scheduler  runs work all at once, or, with `stepByStep`, one step each
--              time the test asks
--   clock      a fake clock that stands still until the test moves it on; a
--              reload keeps it, as the game's time goes on
--   settings   fake settings that the test changes, as the player does on
--              Seek's settings page; a reload keeps them
-- The test acts as the game: it registers fake sources through `game.Seek`
-- (the public API), starts the core (as WoW does when the saved variables
-- are loaded), enters and leaves combat, lets days pass, reloads, and logs
-- in as another character of the same account.

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

-- The saved data of one account: the account-wide data (`data`), and each
-- character's storage, by name.
local function NewAccount()
  return { characters = {} }
end

-- One character's storage on `account`. Its own data is `storage.data`.
local function NewStorage(account)
  local storage = {}
  function storage:Load()
    return Copy(self.data)
  end
  function storage:Save(data)
    self.data = Copy(data)
  end
  function storage.LoadAccount()
    return Copy(account.data)
  end
  function storage.SaveAccount(_, data)
    account.data = Copy(data)
  end
  return storage
end

local function NewCharacter(name)
  local character = { name = name }
  function character:Name()
    return self.name
  end
  return character
end

local function NewCombatState(inCombat)
  local combat = { inCombat = inCombat or false }
  function combat:IsInCombat()
    return self.inCombat
  end
  return combat
end

local DAY = 24 * 60 * 60

-- Settings by name. A setting that the test has not changed gives nil, and
-- the core uses its default.
local function NewSettings()
  local settings = { values = {} }
  function settings:Get(name)
    return self.values[name]
  end
  return settings
end

-- The time is in seconds. It starts on a fixed day, so that every run of the
-- tests sees the same times.
local function NewClock()
  local clock = { now = 1700000000 }
  function clock:Now()
    return self.now
  end
  return clock
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
--   character   the current character's name, as "Name-Realm"
--   account     the account's saved data (a reload and a login pass the old
--               game's)
--   storage     the character's storage (a reload passes the old game's)
--   clock       the clock to use (a reload passes the old game's)
--   settings    the settings to use (a reload passes the old game's)
function M.New(options)
  options = options or {}
  local ns = load_core()
  local account = options.account or NewAccount()
  local character = options.character or "Tester"
  account.characters[character] = options.storage or account.characters[character] or NewStorage(account)
  local game = setmetatable({
    ns = ns,
    Seek = ns.api,
    combat = NewCombatState(options.inCombat),
    character = NewCharacter(character),
    account = account,
    storage = account.characters[character],
    scheduler = NewScheduler(options.stepByStep),
    clock = options.clock or NewClock(),
    settings = options.settings or NewSettings(),
  }, FakeGame)
  ns.SetCombatState(game.combat)
  ns.SetCharacter(game.character)
  ns.SetStorage(game.storage)
  ns.SetScheduler(game.scheduler)
  ns.SetClock(game.clock)
  ns.SetSettings(game.settings)
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

-- Moves the clock on by `days` days (a fraction of a day works too).
function FakeGame:PassDays(days)
  self.clock.now = self.clock.now + days * DAY
end

-- The player changes a setting on Seek's settings page; nil puts it back to
-- its default.
function FakeGame:ChangeSetting(name, value)
  self.settings.values[name] = value
  self.ns.SettingChanged(name)
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

-- A /reload: a new game with a freshly loaded core, the same storage, the
-- same clock, and the same settings, not started yet. The player stays in
-- or out of combat, unless `options.inCombat` says otherwise.
function FakeGame:Reload(options)
  options = options or {}
  local inCombat = options.inCombat
  if inCombat == nil then
    inCombat = self.combat.inCombat
  end
  return M.New({ inCombat = inCombat, stepByStep = options.stepByStep, character = self.character.name,
    account = self.account, storage = self.storage, clock = self.clock, settings = self.settings })
end

-- The player logs out and logs in as `character` on the same account: a new
-- game with a freshly loaded core, that character's own saved data (none on
-- its first login), the account's saved data, the same clock, and the same
-- settings, not started yet. `options` as for a reload.
function FakeGame:LogIn(character, options)
  options = options or {}
  return M.New({ inCombat = options.inCombat, stepByStep = options.stepByStep, character = character,
    account = self.account, clock = self.clock, settings = self.settings })
end

return M
