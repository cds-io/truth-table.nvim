-- truth-table.nvim entry point. Auto-sourced by Neovim on startup; registers the
-- :TruthTable* commands and keymaps via the module's setup(), once the cds-lua
-- on the runtimepath is seen to provide what the plugin uses.

if vim.g.loaded_truth_table then
    return
end

-- the one check kept here: a cds-lua too old to carry cds.needs fails this
-- require, which is the answer
local ok, needs = pcall(require, "cds.needs")
local problem
if ok then
    problem = needs.check("truth-table.nvim", require("truth-table.needs"))
else
    problem =
        "truth-table.nvim needs cds-lua with cds.needs: install cds-io/cds-lua at the commit lazy.lua pins, or update it"
end
if problem then
    vim.notify(problem, vim.log.levels.ERROR)
    return
end
vim.g.loaded_truth_table = true

local truth_table = require("truth-table")
if not truth_table.configured then
    truth_table.setup()
end
