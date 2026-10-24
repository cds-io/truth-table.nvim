-- The busted helper, loaded before every spec in both tiers: the cds modules
-- truth-table.needs declares, behind proxies that refuse any other name, so a
-- spec that reaches an undeclared cds function fails and the declaration
-- stays what the code uses.
require("cds.needs").strict("truth-table.nvim", require("truth-table.needs"))
