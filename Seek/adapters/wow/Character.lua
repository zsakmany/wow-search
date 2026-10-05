-- The WoW character adapter (core/Character.lua): the current character as
-- "Name-Realm". Seek's own sources name the owner of their entries with
-- it, and the core keeps the character's bags under it, so it must give
-- the same name each time, from the start of the login.
--
-- UnitName and GetRealmName work from the start, also while the addon's
-- files run; UnitFullName's realm and GetNormalizedRealmName can be missing
-- early in the login. The realm is written as WoW's normalized realm name
-- writes it: without spaces and hyphens ("Argent Dawn" -> "ArgentDawn").
local _, ns = ...

ns.SetCharacter({
  Name = function()
    local realm = GetRealmName():gsub("[%s%-]", "")
    return UnitName("player") .. "-" .. realm
  end,
})
