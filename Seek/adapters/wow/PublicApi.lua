-- Publishes the core's public API as the global `Seek`, so that other addons
-- (and Seek's own sources) can register a source:
--   Seek.RegisterSource({ id = "MyAddon.Things", GetEntries = function(self) ... end })
--   Seek.NotifyChanged("MyAddon.Things")
-- See core/Sources.lua for the source and entry contract.
local _, ns = ...

Seek = ns.api
