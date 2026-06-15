-- truth-table.nvim entry point. Auto-sourced by Neovim on startup; registers the
-- :TruthTable* commands and keymaps via the module's setup().

if vim.g.loaded_truth_table then
    return
end
vim.g.loaded_truth_table = true

require("truth-table").setup()
