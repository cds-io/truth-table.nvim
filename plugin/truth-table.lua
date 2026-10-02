-- truth-table.nvim entry point. Auto-sourced by Neovim on startup; registers the
-- :TruthTable* commands and keymaps via the module's setup().

if vim.g.loaded_truth_table then
    return
end
vim.g.loaded_truth_table = true

local truth_table = require("truth-table")
if not truth_table.configured then
    truth_table.setup()
end
