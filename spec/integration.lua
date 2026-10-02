vim.opt.rtp:append(vim.fn.getcwd())
require('truth-table').setup()
vim.cmd('TruthTable A B')
vim.api.nvim_win_set_cursor(0, {3, 3})
vim.cmd('TruthTableToggle')
vim.cmd('TruthTableExpand not A, A iff B')
local core = require('truth-table.core')
local lines = vim.api.nvim_buf_get_lines(0, 0, 6, false)
local tbl = assert(core.parse_table_lines(lines))
assert(tbl.rows[1][3] == 'T' and tbl.rows[2][4] == 'F')
vim.api.nvim_buf_set_lines(0, 0, -1, false, {'|A|B|', '|---|---|', '|1|0|1|'})
vim.api.nvim_win_set_cursor(0, {3, 1})
local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local notified = false
vim.notify = function() notified = true end
vim.cmd('TruthTableToggle')
assert(notified)
assert(vim.deep_equal(before, vim.api.nvim_buf_get_lines(0, 0, -1, false)))
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    '| B | A ∧ B |', '|---|---|', '|0|0|', '|1|1|',
})
vim.api.nvim_win_set_cursor(0, {3, 3})
vim.cmd('TruthTableExpand not `A ∧ B`')
local referenced = assert(core.parse_table_lines(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
assert(referenced.rows[1][3] == '1' and referenced.rows[2][3] == '0')
vim.api.nvim_win_set_cursor(0, {3, 2})
vim.cmd('TruthTableDropColumn')
vim.cmd('TruthTableDropRow')
local edited = assert(core.parse_table_lines(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
assert(#edited.headers == 2 and #edited.rows == 1)
assert(edited.headers[1] == 'A ∧ B' and edited.rows[1][1] == '1')
vim.cmd('TruthTableToggle')
local toggled_model = assert(core.parse_table_lines(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
assert(toggled_model.rows[1][1] == 'T')
vim.api.nvim_buf_set_lines(0, 0, -1, false, assert(core.format_table({ 'p | q', 'B' }, { { '0', '1' } })))
local heading = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
local q_pos = assert(heading:find('q', 1, true))
vim.api.nvim_win_set_cursor(0, {1, q_pos - 1})
vim.cmd('TruthTableDropColumn')
local escaped_edit = assert(core.parse_table_lines(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
assert(escaped_edit.headers[1] == 'B' and escaped_edit.rows[1][1] == '1')
-- Command paths use semantic operations, not string-cell compatibility APIs.
local legacy = {}
for _, name in ipairs({ 'build_truth_table', 'expand', 'toggle_table', 'drop_row', 'drop_column', 'parse_table_lines', 'format_table' }) do
    legacy[name] = core[name]
    core[name] = function() error('legacy adapter used by command: ' .. name) end
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'A and B', 'not A' })
vim.cmd('1,2TruthTable')
vim.api.nvim_win_set_cursor(0, {3, 3})
vim.cmd('TruthTableToggle')
vim.cmd('TruthTableExpand A iff B')
vim.cmd('TruthTableDropColumn')
vim.cmd('TruthTableDropRow')
local semantic = assert(core.parse_model(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
assert(semantic.encoding == 'tf' and #semantic.rows == 3 and #semantic.headers == 4)
local before_error = vim.api.nvim_buf_get_lines(0, 0, -1, false)
vim.cmd('TruthTableExpand missing')
assert(vim.deep_equal(before_error, vim.api.nvim_buf_get_lines(0, 0, -1, false)))
for name, fn in pairs(legacy) do core[name] = fn end
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '|A|', '|---|', '|1|discarded\\|' })
vim.api.nvim_win_set_cursor(0, {3, 1})
local malformed_before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
notified = false
vim.cmd('TruthTableToggle')
assert(notified and vim.deep_equal(malformed_before, vim.api.nvim_buf_get_lines(0, 0, -1, false)))
print('Neovim integration passed')
