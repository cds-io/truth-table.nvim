-- :TruthTableTutor opens the tutorial as a scratch copy, and every exercise
-- in it produces what the tutorial says it will. The second half is what
-- keeps the tutorial true as the plugin changes: the tutorial's own fenced
-- "you should see" blocks are the expected output.
vim.opt.rtp:append(vim.fn.getcwd())
require('truth-table').setup()
local source = vim.fn.getcwd() .. '/tutor/truth-table-tutor.md'
local original = vim.fn.readfile(source)
local function lines()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end
local warnings = {}
vim.notify = function(message, level)
    if level == vim.log.levels.WARN then
        warnings[#warnings + 1] = message
    end
end

-- A new tab holds a Markdown scratch buffer with the tutorial's text.
vim.cmd('edit ' .. vim.fn.fnameescape(vim.fn.getcwd() .. '/README.md'))
local tabs = #vim.api.nvim_list_tabpages()
vim.cmd('TruthTableTutor')
local tutor = vim.api.nvim_get_current_buf()
assert(#vim.api.nvim_list_tabpages() == tabs + 1)
assert(vim.bo.filetype == 'markdown' and vim.bo.buftype == 'nofile')
assert(vim.api.nvim_buf_get_name(tutor) ~= source)
assert(vim.deep_equal(original, lines()))
assert(vim.api.nvim_win_get_cursor(0)[1] == 1 and not vim.bo.modified)

-- Undo has nothing to take back: the copy never existed as an empty buffer.
vim.cmd('silent! undo')
assert(vim.deep_equal(original, lines()))

-- Edits stay in the copy, and running the command again returns to it.
vim.api.nvim_buf_set_lines(tutor, 0, 1, false, { 'scribble' })
vim.cmd('tabfirst')
assert(vim.api.nvim_get_current_buf() ~= tutor)
vim.cmd('TruthTableTutor')
assert(vim.api.nvim_get_current_buf() == tutor and lines()[1] == 'scribble')
assert(#vim.api.nvim_list_tabpages() == tabs + 1)

-- A hidden copy comes back in a tab of its own.
vim.cmd('tabclose')
assert(#vim.api.nvim_list_tabpages() == tabs and vim.api.nvim_buf_is_valid(tutor))
vim.cmd('TruthTableTutor')
assert(vim.api.nvim_get_current_buf() == tutor and #vim.api.nvim_list_tabpages() == tabs + 1)

-- With ! the copy is replaced by a fresh one. The shipped file is untouched.
vim.cmd('TruthTableTutor!')
assert(vim.api.nvim_get_current_buf() ~= tutor and not vim.api.nvim_buf_is_valid(tutor))
assert(#vim.api.nvim_list_tabpages() == tabs + 1)
assert(vim.deep_equal(original, lines()))
assert(vim.deep_equal(original, vim.fn.readfile(source)))

-- Work through the exercises in order, as a reader would. Each step names the
-- line to put the cursor on (found outside the fenced blocks, since those hold
-- the expected results), where on it, and the commands to run. Whatever the
-- commands change or insert must appear, as one block, in the tutorial as
-- shipped.
local function exercise_row(text)
    local fenced = false
    for row, line in ipairs(lines()) do
        if line:match('^%s*```') then
            fenced = not fenced
        elseif not fenced and line == text then
            return row
        end
    end
end

local function changed(before, after)
    local first = 1
    while before[first] and before[first] == after[first] do
        first = first + 1
    end
    local last_before, last_after = #before, #after
    while last_before >= first and last_after >= first and before[last_before] == after[last_after] do
        last_before, last_after = last_before - 1, last_after - 1
    end
    while after[first] == '' and first <= last_after do
        first = first + 1
    end
    while after[last_after] == '' and last_after >= first do
        last_after = last_after - 1
    end
    return vim.list_slice(after, first, last_after)
end

local function shipped(block)
    for start = 1, #original - #block + 1 do
        local matches = true
        for offset, line in ipairs(block) do
            if original[start + offset - 1] ~= line then
                matches = false
                break
            end
        end
        if matches then
            return true
        end
    end
    return false
end

local steps = dofile(vim.fn.getcwd() .. '/spec/tutor_steps.lua')
for number, step in ipairs(steps) do
    local label = 'step ' .. number .. ' (' .. step.line .. ')'
    local row = assert(exercise_row(step.line), label .. ': line not in the tutorial')
    local column = step.at and assert(step.line:find(step.at, 1, true), label .. ': no ' .. step.at) - 1 or 0
    vim.api.nvim_win_set_cursor(0, { row, column })
    local before = lines()
    warnings = {}
    for _, command in ipairs(step.run) do
        vim.cmd(command)
    end
    local result = changed(before, lines())
    assert(#result > 0, label .. ': nothing changed; ' .. table.concat(warnings, '; '))
    assert(shipped(result), label .. ': the tutorial does not show this result:\n' .. table.concat(result, '\n'))
end
assert(#steps >= 20)

print('Tutor passed')
