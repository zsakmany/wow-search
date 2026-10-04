-- luacheck config. See docs/adr/0003-hexagonal-core.md.
std = "lua51"
exclude_files = { ".tools/" }

-- Core: plain Lua 5.1 that never touches the WoW API. Every WoW global is an
-- undefined global here, so luacheck fails on it. Also ban the Lua 5.1 globals
-- that the game does not have.
files["Seek/core/"] = {
  not_globals = { "io", "require", "dofile", "loadfile", "module", "package" },
}

-- WoW adapters: may read and change WoW globals (the WoW API is too large to
-- list). Creating a new global is still flagged; add the addon's own globals
-- (saved variables, slash commands) to `globals` here when they appear.
files["Seek/adapters/wow/"] = {
  ignore = { "112", "113" }, -- mutating / accessing an undefined global
  globals = {
    -- The public API that other addons use
    "Seek",
    -- Key binding labels and the function that Bindings.xml calls
    "BINDING_NAME_SEEK_TOGGLE", "Seek_ToggleSearchBar",
    -- The /seek slash command
    "SLASH_SEEK1",
  },
}

files["tests/"] = {
  std = "+busted",
}
