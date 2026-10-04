-- The kinds that Seek knows. An entry must have one of these kinds, or Seek
-- rejects it. To add a kind, add a row here with its label from the locale
-- table.
local _, ns = ...

local L = ns.L

ns.kinds = {
  item = { label = L.KIND_ITEM },
}
