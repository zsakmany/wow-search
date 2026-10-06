# Seek

Seek is a World of Warcraft addon that opens a search bar on a hotkey and finds the player's own things (bag items, spells, quests) and, when the query starts with `>`, the game options in the game's Options window as they type; Enter on a game option opens the Options window at it. It also finds the items in the bags of the player's other characters on the account, as faded results: each character shows after it has logged in once with Seek, and the setting "Show other characters' bags" turns this off. Domain words: [GLOSSARY.md](GLOSSARY.md). Decisions: [docs/adr/](docs/adr/).

## Tests and checks

The tests run outside the game on Lua 5.1, the Lua version of WoW. Two commands, run from the project root:

```sh
make setup   # install the test tools (once)
make check   # run luacheck and the busted tests
```

`make setup` needs Python 3, `make`, and a C compiler (on a Mac: the Xcode Command Line Tools). It installs Lua 5.1, LuaRocks, busted, and luacheck into `.tools/` inside the project, with [hererocks](https://github.com/luarocks/hererocks). Nothing is installed into the system, and git ignores `.tools/`. To start over, delete `.tools/` and run `make setup` again.

The project path must not contain a space: LuaRocks cannot be installed there, and `make setup` stops with an error.

`make check` fails when a test fails or when luacheck finds a problem. GitHub Actions runs the same two commands on every push.

## Running the addon in WoW

```sh
make link    # symlink Seek/ into WoW's AddOns folder (once)
```

WoW then reads the addon straight from this project: change the code, type `/reload` in the game, and see the change. By default `make link` uses the WoW Forever beta folder. For another install, give its AddOns folder:

```sh
make link WOW_ADDONS="/Applications/World of Warcraft/_forever_/Interface/AddOns"
```

In the game, `/seek` opens and closes the search bar, and so does a left click on Seek's minimap icon (the magnifying glass at the edge of the minimap) or on the Seek entry in the addon button at the minimap. Seek's settings are on the Seek page under the AddOns tab of the game's Options window; `/seek settings` or a right click on the minimap icon or the Seek entry opens it. The setting "Show minimap icon" there hides the minimap icon. The icon can be dragged along the minimap edge, and keeps its place on every character. On the first login, Seek sets Cmd+K (Mac) or Ctrl+K (Windows) as its key, if that key is free. The key can be changed in the game's Keybindings menu, in the Seek section.

`make link` never replaces an existing `Seek` folder. To undo the link, delete the `Seek` link in the AddOns folder.

## Folders

- `Seek/`: the addon itself. Only this folder is linked into WoW.
  - `Seek/core/`: plain Lua 5.1 that never touches the WoW API ([ADR 0003](docs/adr/0003-hexagonal-core.md)). luacheck fails on any WoW global here.
  - `Seek/adapters/wow/`: the WoW adapters. WoW globals are allowed here.
  - `Seek/libs/`: copies of other authors' libraries (LibDBIcon-1.0 for the minimap icon, and what it needs), with their sources and versions in `Seek/libs/README.md`. luacheck skips them.
- `tests/`: busted tests (`*_spec.lua`). They run outside the game. `tests/load_core.lua` loads the core files the way WoW does: in TOC order, each with the shared `ns` table. `tests/fake_game.lua` plugs fake adapters into the core's ports (combat state, the current character, in-memory storage for the character and the account, a scheduler that the test runs step by step, a clock that the test moves on, settings that the test changes) and simulates a `/reload` and a login as another character of the same account.
