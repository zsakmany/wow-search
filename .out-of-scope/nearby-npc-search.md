# Search nearby NPCs

Seek does not search the NPCs near the player, friendly or hostile, and does not target them from the search bar.

## Why this is out of scope

Addons cannot list the units around the player. The game gives an addon a unit only through a unit token: `target`, `mouseover`, and the nameplates (`nameplate1`, `nameplate2`, ...). For "every NPC near me", only the nameplates come close, and in the game they see far too little to make a useful source.

A proof of concept in the WoW Forever beta (Interface 16001) found this:

- **Nameplates follow the player's options.** Names (the plain text above a model's head) are not nameplates (the health bars), and addons cannot see names. Friendly NPCs have a nameplate only when "Friendly NPC Nameplates" is on (`nameplateShowFriendlyNpcs`). That option was off on the test character, and most players never turn it on. So the main example, typing `innk` to find the innkeeper, finds nothing for most players.
- **With "Always Show Nameplates" off, almost nothing is left.** Out of combat, the addon saw exactly one enemy: the one the player faced, through its soft target nameplate (`SoftTargetNameplateEnemy`).
- **Nameplates exist only on screen.** Even with every option on, a nameplate exists only for a unit in the camera view and in range (`nameplateMaxDistance`, 45 yards). It goes away as soon as the player turns their back. "Show Offscreen Nameplates" does not change this. An NPC that Seek can see is one the player can usually click.
- **Targeting itself works.** A secure button with `/targetexact <name>` (the same machinery as the use key) targeted an NPC behind the player's back. The limit is finding the NPC, not targeting it.

A version that works only after the player changes their nameplate options, and that shows only what is on screen, does not earn a new kind, a widened ADR 0001, and a source whose entries change every second.

Other addons that find NPCs, such as RareScanner, use the same unit tokens, plus minimap vignettes (only for rares, treasures, and events that the game marks) and their own shipped NPC database. A game-wide NPC list is a data pack's job (ADR 0001), not a source of Seek's own.

## What would change this

A game API that lists nearby units without nameplates. Or a data pack with NPC names and places, together with a way to target by name (`/targetexact`, which the proof of concept showed works).

## Prior requests

- #24: "Search nearby NPCs and target them"
