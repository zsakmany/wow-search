# Read and save game data outside combat; search only the saved copy in combat

WoW Forever and Retail (Midnight 12.x) hide some data from addons in combat ("secret values"), for example tooltip text. Seek therefore reads its sources' data outside combat and keeps a saved copy. In combat, Seek searches only that copy and does not read live game data. A reader may want to "simplify" this by reading live data when the search bar opens. Do not: it breaks in combat.

One exception: cooldowns (#52). A cooldown changes every second and is only shown, never searched, so the search bar window reads it live for its visible rows, also in combat. It never goes into an entry, the saved copy, or a source read. For spells in combat it uses only the game's secret-safe path: a duration object, which the cooldown sweep and the game's time formatter take as it is.
