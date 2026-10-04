# Hexagonal architecture: a plain-Lua core behind ports

Seek's core (matching, ranking, sources, kinds, actions) is plain Lua 5.1 and never touches the WoW API. It talks to the game only through ports. WoW adapters plug into the ports in the game; fake adapters plug into them in unit and integration tests, which run outside the game. This is rare for WoW addons, which usually call the game API from everywhere. We chose it on purpose: the WoW API cannot run outside the game, so without this split the core could only be tested by hand. Do not "simplify" by calling the WoW API from core code.
