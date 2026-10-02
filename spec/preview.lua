vim.opt.rtp:append(vim.fn.getcwd())
require('truth-table').setup()
local core = require('truth-table.core')
local ns = vim.api.nvim_get_namespaces()['truth-table.de-morgan']
local function marks()
    return vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
end
local function set(lines, row, col)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { row or 1, col or 0 })
end
local notified
vim.notify = function(message) notified = message end
set({ '  not (A and B)' })
vim.cmd('TruthTableDeMorgan')
assert(vim.api.nvim_get_current_line() == '  not (A and B)')
assert(#marks() == 1 and marks()[1][4].virt_text[1][1] == ' ⇒ ¬A ∨ ¬B')
vim.cmd('TruthTableDeMorgan')
assert(#marks() == 0)
vim.cmd('TruthTableDeMorgan')
vim.cmd('TruthTableDeMorganApply')
assert(vim.api.nvim_get_current_line() == '  ¬A ∨ ¬B' and #marks() == 0)
-- Changed source cannot be overwritten by a stale preview.
set({ 'not (A or B)' })
vim.cmd('TruthTableDeMorgan')
set({ 'A and B' })
vim.cmd('TruthTableDeMorganApply')
assert(vim.api.nvim_get_current_line() == 'A and B')
vim.wait(100, function() return #marks() == 0 end)
assert(#marks() == 0)
-- Select from a data row; only the selected heading changes.
local table_lines = assert(core.format_table({ 'A', '¬(A ∧ B)' }, { { '0', '1' }, { '1', '0' } }))
for i, line in ipairs(table_lines) do table_lines[i] = '  ' .. line end
set(table_lines, 3, 12)
vim.cmd('TruthTableDeMorgan')
assert(#marks() == 1 and marks()[1][2] == 0)
assert(marks()[1][4].virt_text[1][1] == ' [column 2] ⇒ ¬A ∨ ¬B')
vim.cmd('TruthTableDeMorganApply')
local updated = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(core.split_row(updated[1])[2] == '¬A ∨ ¬B')
assert(updated[1]:sub(1, 2) == '  ')
for i = 2, #updated do assert(updated[i] == table_lines[i]) end
-- Duplicate headings refuse the preview, with no text edits.
local duplicate = assert(core.format_table({ '¬(A ∧ B)', '¬A ∨ ¬B' }, { { '1', '1' } }))
set(duplicate)
vim.cmd('TruthTableDeMorgan')
assert(#marks() == 0 and notified:find('duplicate', 1, true))
assert(vim.deep_equal(duplicate, vim.api.nvim_buf_get_lines(0, 0, -1, false)))
set({ 'A or not (B and C)' })
vim.cmd('TruthTableDeMorgan')
assert(#marks() == 0 and notified:find('whole expression', 1, true))
print('De Morgan preview integration passed')
