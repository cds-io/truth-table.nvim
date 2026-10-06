-- The init file of the Neovim that spec/startup_nvim_spec.lua starts: after
-- evaluating it, that Neovim loads plugin/ itself, as it does for a reader.
-- Once it is up it tries the plugin and writes what it found to stdout as
-- JSON, for the spec to judge.
vim.opt.rtp:append(vim.fn.getcwd())
vim.opt.swapfile = false
if vim.env.TRUTH_TABLE_TEST_CUSTOM == "1" then
    require("truth-table").setup({ abbreviations = false })
end
package.preload["which-key"] = function() error("which-key intentionally absent") end
vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
        local found = {}
        local ok, err = pcall(function()
            found.loaded = vim.g.loaded_truth_table
            found.command = vim.fn.exists(":TruthTable")
            found.abbreviation = vim.fn.maparg("and@", "i", true)
            vim.cmd("TruthTable A")
            vim.api.nvim_win_set_cursor(0, { 3, 1 })
            vim.cmd("TruthTableToggle")
            local tbl = assert(require("truth-table.core").parse(vim.api.nvim_buf_get_lines(0, 0, 4, false)))
            found.rows, found.encoding = tbl.rows, tbl.encoding
            vim.cmd("help truth-table-predicates")
            found.help_filetype = vim.bo.filetype
            found.help_file = vim.api.nvim_buf_get_name(0)
        end)
        if not ok then
            found.error = tostring(err)
        end
        io.stdout:write(vim.json.encode(found))
        vim.cmd("qa!")
    end,
})
