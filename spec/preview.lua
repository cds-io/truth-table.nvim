vim.opt.rtp:append(vim.fn.getcwd())
require('truth-table').setup()
local core = require('truth-table.core')
local ns = vim.api.nvim_get_namespaces()['truth-table.preview']
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
assert(#marks() == 1 and marks()[1][4].virt_text[1][1] == ' ⇒ ¬A ∨ ¬B  | by De Morgan')
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
assert(marks()[1][4].virt_text[1][1] == ' [column 2] ⇒ ¬A ∨ ¬B  | by De Morgan')
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

-- Cursor-targeted rewrites. `on` puts the cursor on the first byte of `needle`.
local function on(needle, row)
    row = row or 1
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    vim.api.nvim_win_set_cursor(0, { row, assert(line:find(needle, 1, true)) - 1 })
end
local function text()
    return marks()[1] and marks()[1][4].virt_text[1][1]
end
-- A step with its justification's bar at a display column.
local function justified(step, column, law)
    return step .. string.rep(' ', column - vim.fn.strdisplaywidth(step)) .. '| by ' .. law
end

-- Factor previews, then applies in place, keeping indentation.
set({ '  S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)' })
on('¬C')
vim.cmd('TruthTableFactor')
assert(text() == ' ⇒ S ∨ (¬C ∧ (A ∨ G))  | by distributivity (factoring)')
assert(vim.api.nvim_get_current_line() == '  S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)')
vim.cmd('TruthTableApply')
assert(vim.api.nvim_get_current_line() == '  S ∨ (¬C ∧ (A ∨ G))' and #marks() == 0)

-- The same command dismisses; a different one replaces the pending preview.
on('S')
vim.cmd('TruthTableCommute')
assert(text() == ' ⇒ (¬C ∧ (A ∨ G)) ∨ S  | by commutativity')
vim.cmd('TruthTableCommute!')
assert(#marks() == 0)
vim.cmd('TruthTableCommute')
on('¬C')
vim.cmd('TruthTableDistribute')
assert(#marks() == 1 and text() == ' ⇒ S ∨ (¬C ∧ A) ∨ (¬C ∧ G)  | by distributivity (distributing)')
vim.cmd('TruthTableDistribute')
assert(#marks() == 0)

-- A refusal warns and leaves the buffer and the mark list alone.
on('∨')
notified = nil
vim.cmd('TruthTableFactor')
assert(#marks() == 0 and notified == 'Put the cursor on an operand')

-- Factor and Distribute are easy to reach for the wrong way round: a refusal
-- names the other when it applies at this cursor, and only then.
set({ '(Q ∧ ¬C) ∨ (Q ∧ ¬L)' })
on('Q')
vim.cmd('TruthTableDistribute')
assert(#marks() == 0)
assert(notified == 'No neighbouring group to distribute Q into; to pull it out of the terms that share it, use :TruthTableFactor')
set({ 'Q ∧ (¬C ∨ ¬L)' })
on('Q')
vim.cmd('TruthTableFactor')
assert(#marks() == 0)
assert(notified == 'Nothing to factor Q out of; to move it into the group beside it, use :TruthTableDistribute')
set({ 'Q ∧ R' })
on('Q')
vim.cmd('TruthTableDistribute')
assert(notified == 'No neighbouring group to distribute Q into')
vim.cmd('TruthTableFactor')
assert(notified == 'Nothing to factor Q out of')

-- Steps build a derivation under the Karnaugh line; the cursor follows. Each
-- step names its law, four columns clear of the wider line, and the next
-- step's bar sits under it.
local head = 'S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C) ≡ S ∨ A ∧ ¬C ∨ G ∧ ¬C'
local bar = vim.fn.strdisplaywidth(head) + 4
set({ head })
on('¬C ∨ G')
vim.cmd('TruthTableFactor')
vim.cmd('TruthTableApplyStep')
local pad = string.rep(' ', 24)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
    head,
    justified(pad .. '≡ S ∨ (¬C ∧ (A ∨ G))', bar, 'distributivity (factoring)'),
}))
local cursor = vim.api.nvim_win_get_cursor(0)
assert(cursor[1] == 2 and cursor[2] == #(pad .. '≡ '))
vim.cmd('TruthTableCommute')
vim.cmd('TruthTableApplyStep')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
    head,
    justified(pad .. '≡ S ∨ (¬C ∧ (A ∨ G))', bar, 'distributivity (factoring)'),
    justified(pad .. '≡ (¬C ∧ (A ∨ G)) ∨ S', bar, 'commutativity'),
}))
assert(vim.api.nvim_win_get_cursor(0)[1] == 3 and #marks() == 0)

-- A step lands under the line that was previewed, wherever the cursor went.
set({ 'A ∧ B', 'unrelated' })
vim.cmd('TruthTableCommute')
vim.api.nvim_win_set_cursor(0, { 2, 3 })
vim.cmd('TruthTableApplyStep')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { 'A ∧ B', '≡ B ∧ A    | by commutativity', 'unrelated' }))
assert(vim.api.nvim_win_get_cursor(0)[1] == 2)

-- A dangling separator has no expression to rewrite.
set({ 'F ≡ ' }, 1, 3)
notified = nil
vim.cmd('TruthTableDeMorgan')
assert(#marks() == 0 and notified == 'No expression under the cursor')

-- In-place apply on one side keeps the other side and the spacing.
set({ 'F  ≡  A ∧ B' })
on('A')
vim.cmd('TruthTableCommute')
vim.cmd('TruthTableApply')
assert(vim.api.nvim_get_current_line() == 'F  ≡  B ∧ A')

-- De Morgan works on the side under the cursor and can be stepped.
set({ '  ≡ ¬(A ∧ B)' })
vim.cmd('TruthTableDeMorgan')
vim.cmd('TruthTableApplyStep')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { '  ≡ ¬(A ∧ B)', '  ≡ ¬A ∨ ¬B     | by De Morgan' }))
set({ 'not (A and B)' })
vim.cmd('TruthTableDeMorgan')
vim.cmd('TruthTableDeMorganApply')
assert(vim.api.nvim_get_current_line() == '¬A ∨ ¬B')

-- A stale preview cannot be applied as a step either.
set({ 'A ∧ B' })
vim.cmd('TruthTableCommute')
set({ 'C ∧ D' })
notified = nil
vim.cmd('TruthTableApplyStep')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { 'C ∧ D' }))
assert(notified == 'No current preview; run a rewrite command first')
vim.wait(100, function() return #marks() == 0 end)

-- A heading rewrites from the heading row, cursor in the cell, in place only.
local heading_table = assert(core.format_table({ 'A', 'B', 'A ∧ B' }, { { '0', '0', '0' }, { '1', '1', '1' } }))
set(heading_table)
on('A ∧')
vim.cmd('TruthTableCommute')
assert(text() == ' [column 3] ⇒ B ∧ A  | by commutativity')
notified = nil
vim.cmd('TruthTableApplyStep')
assert(notified == 'Steps apply to expression lines; use :TruthTableApply for a heading')
assert(#marks() == 1 and vim.deep_equal(heading_table, vim.api.nvim_buf_get_lines(0, 0, -1, false)))
vim.cmd('TruthTableApply')
local renamed = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(core.split_row(renamed[1])[3] == 'B ∧ A')
for i = 2, #renamed do assert(renamed[i] == heading_table[i]) end

-- Padding inside the heading cell is not an operand.
set(heading_table)
vim.api.nvim_win_set_cursor(0, { 1, assert(heading_table[1]:find('A ∧', 1, true)) - 2 })
notified = nil
vim.cmd('TruthTableCommute')
assert(#marks() == 0 and notified == 'Put the cursor on an operand')

-- From a data row there is no operand to point at.
set(heading_table, 3, 14)
notified = nil
vim.cmd('TruthTableCommute')
assert(#marks() == 0 and notified == 'Put the cursor on the heading row to choose an operand')

-- A rewrite that would duplicate another heading is refused.
local clash = assert(core.format_table({ 'A ∧ B', 'B ∧ A' }, { { '1', '1' } }))
set(clash)
on('A ∧')
notified = nil
vim.cmd('TruthTableCommute')
assert(#marks() == 0 and notified:find('duplicate', 1, true))

-- Blank lines and trailing cursors refuse without touching the buffer.
set({ '' })
notified = nil
vim.cmd('TruthTableFactor')
assert(notified == 'No expression under the cursor')
set({ 'A ∧ B   ' }, 1, 7)
notified = nil
vim.cmd('TruthTableCommute')
assert(notified == 'Put the cursor on an operand' and vim.api.nvim_get_current_line() == 'A ∧ B   ')

-- Xor recognition closes a derivation; the cursor can be anywhere in either term.
set({ '(T ⊕ E) ∧ R ≡ R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))' })
on('¬T')
vim.cmd('TruthTableXor')
assert(text() == ' ⇒ R ∧ (T ⊕ E)  | by definition of ⊕')
vim.cmd('TruthTableApplyStep')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
    '(T ⊕ E) ∧ R ≡ R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))',
    justified('            ≡ R ∧ (T ⊕ E)', vim.fn.strdisplaywidth('(T ⊕ E) ∧ R ≡ R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))') + 4, 'definition of ⊕'),
}))

-- Simplify applies the collapsing law nearest the cursor and names it. A
-- derivation runs down justified lines: each step reads the expression and
-- leaves the justification alone.
set({ '(a and b) or (not a and b)' })
on('b')
vim.cmd('TruthTableFactor')
vim.cmd('TruthTableApplyStep')
vim.cmd('TruthTableSimplify')
assert(text() == ' ⇒ b ∧ 1  | by complement')
vim.cmd('TruthTableApplyStep')
vim.cmd('TruthTableSimplify')
assert(text() == ' ⇒ b  | by identity')
vim.cmd('TruthTableApplyStep')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
    '(a and b) or (not a and b)',
    '≡ b ∧ (a ∨ ¬a)                | by distributivity (factoring)',
    '≡ b ∧ 1                       | by complement',
    '≡ b                           | by identity',
}))
vim.cmd('TruthTableSimplify')
assert(#marks() == 0 and notified == 'No simplification applies to this expression')

-- One move does what the three steps did, and a cursor in the justification
-- still means the line's expression.
set({ '(a and b) or (not a and b)' })
vim.cmd('TruthTableSimplify')
assert(text() == ' ⇒ b  | by reduction')
vim.cmd('TruthTableSimplify')
assert(#marks() == 0)
set({ '≡ b ∧ (a ∨ ¬a)    | by distributivity' })
on('distributivity')
vim.cmd('TruthTableSimplify')
assert(text() == ' ⇒ b ∧ 1  | by complement')

-- Applied in place, a justified line gains the law: the line still says how
-- it follows from the one above.
vim.cmd('TruthTableApply')
assert(vim.api.nvim_get_current_line() == '≡ b ∧ 1    | by distributivity, complement')

-- In a heading, from a data row, Simplify reads the whole heading.
local constant = assert(core.format_table({ 'A', 'A ∨ ¬A' }, { { '0', '1' }, { '1', '1' } }))
set(constant, 3, 10)
vim.cmd('TruthTableSimplify')
assert(text() == ' [column 2] ⇒ 1  | by complement')
vim.cmd('TruthTableSimplify')

-- De Morgan reaches the nearest match around the cursor.
set({ 'R ∧ (T ∨ E) ∧ (¬T ∨ ¬E)' })
on('¬T')
vim.cmd('TruthTableDeMorgan')
assert(text() == ' ⇒ R ∧ (T ∨ E) ∧ ¬(T ∧ E)  | by De Morgan')
vim.cmd('TruthTableDeMorgan')
set({ 'A or not (B and C)' })
on('not')
vim.cmd('TruthTableDeMorgan')
assert(text() == ' ⇒ A ∨ ¬B ∨ ¬C  | by De Morgan')
vim.cmd('TruthTableApply')
assert(vim.api.nvim_get_current_line() == 'A ∨ ¬B ∨ ¬C')

-- In a heading the cursor picks a nested match from the heading row; from a
-- data row De Morgan still means the whole heading.
local nested = assert(core.format_table({ 'A', 'B', 'A ∧ ¬(A ∧ B)' }, { { '0', '0', '0' }, { '1', '0', '1' } }))
set(nested)
on('¬')
vim.cmd('TruthTableDeMorgan')
assert(text() == ' [column 3] ⇒ A ∧ (¬A ∨ ¬B)  | by De Morgan')
vim.cmd('TruthTableDeMorgan')
set(nested, 3, 14)
notified = nil
vim.cmd('TruthTableDeMorgan')
assert(#marks() == 0 and notified:find('whole expression', 1, true))

-- The Lua entry point keeps its no-argument form: a De Morgan preview.
set({ 'not (A and B)' })
require('truth-table.preview').toggle()
assert(text() == ' ⇒ ¬A ∨ ¬B  | by De Morgan')
require('truth-table.preview').toggle()
assert(#marks() == 0)

print('Rewrite preview integration passed')
