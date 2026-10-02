-- Real startup: Neovim loads plugin/ itself after evaluating this init file.
vim.opt.rtp:append(vim.fn.getcwd())
vim.opt.swapfile = false
package.preload['which-key'] = function() error('which-key intentionally absent') end
vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
        local ok, err = pcall(function()
            assert(vim.g.loaded_truth_table)
            assert(vim.fn.exists(':TruthTable') == 2)
            vim.cmd('TruthTable A')
            vim.api.nvim_win_set_cursor(0, {3, 1})
            vim.cmd('TruthTableToggle')
            local core = require('truth-table.core')
            local tbl = assert(core.parse_model(vim.api.nvim_buf_get_lines(0, 0, 4, false)))
            assert(vim.deep_equal(tbl.rows, { { 0 }, { 1 } }))
            assert(tbl.encoding == 'tf')
        end)
        if not ok then
            io.stderr:write(tostring(err) .. '\n')
            vim.cmd('cquit 1')
            return
        end
        print('Automatic Neovim startup passed')
        vim.cmd('qa!')
    end,
})
