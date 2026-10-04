-- :TruthTableTutor shows the course in two panes, the lesson beside a scratch
-- buffer per step, and every exercise produces what its lesson says it will.
-- The second half is what keeps the course true as the plugin changes: each
-- step's `solution` is replayed in its scratch buffer, and the result must be
-- the step's own `expect` block.
vim.opt.rtp:append(vim.fn.getcwd())
vim.o.wrap = false
require('truth-table').setup()
local page = require('truth-table.tutor_page')
local predicate = require('truth-table.predicate')

local warnings = {}
vim.notify = function(message, level)
    if level == vim.log.levels.WARN then
        warnings[#warnings + 1] = message
    end
end

local files = vim.fn.glob(vim.fn.getcwd() .. '/tutor/truth-table/*.lua', true, true)
table.sort(files)
local course = vim.tbl_map(dofile, files)
assert(#course >= 10)

-- Every lesson has a title, an aim and steps; a step that shows an
-- expectation says how to reach it, and the other way round.
local exercises = 0
for number, lesson in ipairs(course) do
    local label = 'lesson ' .. number
    assert(type(lesson.title) == 'string' and type(lesson.aim) == 'string', label)
    assert(#lesson.steps > 0, label)
    for index, step in ipairs(lesson.steps) do
        assert(type(step.text) == 'string', label .. ' step ' .. index)
        assert((step.expect ~= nil) == (step.solution ~= nil), label .. ' step ' .. index)
        exercises = exercises + (step.solution and 1 or 0)
    end
end
assert(exercises >= 20)

-- Every law a lesson states holds. A law is `left ≡ right` on a line of a
-- fenced block in a step's text; a line may hold several, two or more spaces
-- apart (the reference lists each law beside its dual, after its name).
local function equivalent(left, right)
    local sides = { assert(predicate.parse_expression(left)), assert(predicate.parse_expression(right)) }
    local names = {}
    for _, side in ipairs(sides) do
        for _, name in ipairs(assert(predicate.variables(side))) do
            if not vim.tbl_contains(names, name) then
                names[#names + 1] = name
            end
        end
    end
    for row = 0, 2 ^ #names - 1 do
        local values = {}
        for index, name in ipairs(names) do
            values[name] = math.floor(row / 2 ^ (index - 1)) % 2
        end
        if predicate.eval_ast(sides[1], values) ~= predicate.eval_ast(sides[2], values) then
            return false
        end
    end
    return true
end

local laws = 0
for number, lesson in ipairs(course) do
    for index, step in ipairs(lesson.steps) do
        local fenced = false
        for _, line in ipairs(page.lines(step.text)) do
            if line:match('^```') then
                fenced = not fenced
            elseif fenced and line:find('≡', 1, true) then
                for _, law in ipairs(vim.split((line:gsub('%s+≡%s+', ' ≡ ')), '%s%s+')) do
                    local left, right = law:match('^(.-) ≡ (.+)$')
                    if left then
                        assert(equivalent(left, right), ('lesson %d step %d: %s'):format(number, index, law))
                        laws = laws + 1
                    end
                end
            end
        end
    end
end
assert(laws >= 40)

local function pane(role)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.w[win].truth_table_tutor == role then
            return win, vim.api.nvim_win_get_buf(win)
        end
    end
end

local function text(role)
    local _, buf = pane(role)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

-- The reader is at this lesson and step: the lesson pane shows it, on the
-- left, and the cursor is in the scratch pane.
local function at(lesson, step)
    local lesson_win, lesson_buf = pane('lesson')
    local scratch_win, scratch_buf = pane('scratch')
    assert(lesson_win and scratch_win and lesson_buf ~= scratch_buf)
    local tab = vim.api.nvim_get_current_tabpage()
    assert(vim.deep_equal({ lesson_win, scratch_win }, vim.api.nvim_tabpage_list_wins(tab)))
    assert(vim.api.nvim_win_get_position(lesson_win)[2] < vim.api.nvim_win_get_position(scratch_win)[2])
    assert(vim.api.nvim_get_current_win() == scratch_win)
    assert(vim.deep_equal(page.render(course, lesson, step), text('lesson')))
    assert(vim.bo[lesson_buf].buftype == 'nofile' and not vim.bo[lesson_buf].modifiable)
    assert(vim.bo[scratch_buf].buftype == 'nofile' and vim.bo[scratch_buf].modifiable)
    assert(vim.bo[lesson_buf].filetype == 'markdown' and vim.bo[scratch_buf].filetype == 'markdown')
    assert(vim.wo[lesson_win].wrap and vim.wo[lesson_win].linebreak and not vim.wo[scratch_win].wrap)
    return true
end

local function starting_text(lesson, step)
    local template = page.lines(course[lesson].steps[step].template)
    return #template > 0 and template or { '' }
end

-- A new tab holds the two panes, on the first step, with its starting text
-- in the scratch pane.
vim.cmd('edit ' .. vim.fn.fnameescape(vim.fn.getcwd() .. '/README.md'))
local tabs = #vim.api.nvim_list_tabpages()
vim.cmd('TruthTableTutor')
assert(#vim.api.nvim_list_tabpages() == tabs + 1)
assert(at(1, 1))
assert(vim.deep_equal(starting_text(1, 1), text('scratch')))
assert(vim.api.nvim_win_get_cursor(0)[1] == 1)
assert(table.concat(text('lesson'), '\n'):find('**Aim:** ' .. course[1].aim, 1, true))

-- Undo has nothing to take back: the scratch never existed as an empty buffer.
vim.cmd('silent! undo')
assert(vim.deep_equal(starting_text(1, 1), text('scratch')))

-- Next and Prev move one step, across lesson boundaries, and stop at the ends.
vim.cmd('TruthTableTutorPrev')
assert(at(1, 1) and #warnings == 1 and warnings[1]:find('first step', 1, true))
vim.cmd('TruthTableTutorNext')
assert(at(2, 1))
assert(vim.deep_equal({ 'p q' }, text('scratch')))
vim.cmd('normal ]]')
assert(at(2, 2))
vim.api.nvim_set_current_win((pane('lesson')))
vim.cmd('normal [[')
assert(at(2, 1))

-- Work stays in its step's scratch.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'scribble' })
vim.cmd('TruthTableTutorNext')
assert(at(2, 2) and vim.deep_equal({ '' }, text('scratch')))
vim.cmd('TruthTableTutorPrev')
assert(at(2, 1) and vim.deep_equal({ 'scribble' }, text('scratch')))

-- From another tab the command returns to the reader's place.
vim.cmd('tabfirst')
assert(vim.api.nvim_get_current_win() ~= pane('scratch'))
vim.cmd('TruthTableTutor')
assert(at(2, 1) and #vim.api.nvim_list_tabpages() == tabs + 1)

-- A closed pane opens again beside the other, and closed panes in a tab of
-- their own. The scratch pane keeps the reader's wrapping in each case.
vim.api.nvim_win_close(pane('lesson'), false)
vim.cmd('TruthTableTutor')
assert(at(2, 1) and #vim.api.nvim_list_tabpages() == tabs + 1)
vim.api.nvim_win_close(pane('scratch'), false)
vim.cmd('TruthTableTutorNext')
assert(at(2, 2) and #vim.api.nvim_list_tabpages() == tabs + 1)
vim.cmd('tabclose')
assert(#vim.api.nvim_list_tabpages() == tabs and not pane('lesson') and not pane('scratch'))
vim.cmd('TruthTableTutorPrev')
assert(at(2, 1) and #vim.api.nvim_list_tabpages() == tabs + 1)
assert(vim.deep_equal({ 'scribble' }, text('scratch')))

-- :bdelete leaves valid but unloaded buffers. Reopening recreates the deleted
-- pane with its starting text and tutor options, and preserves the other pane.
local deleted_scratch = vim.api.nvim_get_current_buf()
vim.cmd('bdelete!')
assert(vim.api.nvim_buf_is_valid(deleted_scratch) and not vim.api.nvim_buf_is_loaded(deleted_scratch))
vim.cmd('TruthTableTutor')
assert(at(2, 1) and vim.deep_equal(starting_text(2, 1), text('scratch')))
assert(not vim.api.nvim_buf_is_valid(deleted_scratch))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'kept scratch' })
local lesson_win, deleted_lesson = pane('lesson')
vim.api.nvim_set_current_win(lesson_win)
vim.cmd('bdelete')
assert(vim.api.nvim_buf_is_valid(deleted_lesson) and not vim.api.nvim_buf_is_loaded(deleted_lesson))
vim.cmd('TruthTableTutor')
assert(at(2, 1) and vim.deep_equal({ 'kept scratch' }, text('scratch')))
assert(not vim.api.nvim_buf_is_valid(deleted_lesson))
vim.cmd('TruthTableTutorNext')
vim.cmd('TruthTableTutorPrev')
assert(at(2, 1) and vim.deep_equal({ 'kept scratch' }, text('scratch')))

-- A number jumps to that lesson's first step; anything else is refused.
vim.cmd('TruthTableTutor 6')
assert(at(6, 1))
warnings = {}
vim.cmd('TruthTableTutor ' .. #course + 1)
vim.cmd('TruthTableTutor six')
assert(at(6, 1) and #warnings == 2 and warnings[2]:find('lessons 1 to ' .. #course, 1, true))

-- With ! the course starts over and the work is gone.
vim.cmd('TruthTableTutor!')
assert(at(1, 1) and #vim.api.nvim_list_tabpages() == tabs + 1)
vim.cmd('TruthTableTutor 2')
assert(at(2, 1) and vim.deep_equal({ 'p q' }, text('scratch')))
vim.cmd('TruthTableTutor!')

-- Work through the course in order, as a reader would. Each move of a step's
-- solution names the line to put the cursor on (the first line when absent),
-- the text on it the cursor sits on (the start of the line when absent), and
-- the commands to run. The scratch pane must end up as the step's `expect`.
local function trimmed(lines)
    while lines[#lines] == '' do
        lines[#lines] = nil
    end
    return lines
end

local function row_of(line)
    for row, candidate in ipairs(text('scratch')) do
        if candidate == line then
            return row
        end
    end
end

for number, lesson in ipairs(course) do
    for index, step in ipairs(lesson.steps) do
        local label = ('lesson %d step %d'):format(number, index)
        assert(at(number, index), label)
        assert(vim.deep_equal(starting_text(number, index), text('scratch')), label)
        for _, move in ipairs(step.solution or {}) do
            local row = move.on and assert(row_of(move.on), label .. ': no line ' .. move.on) or 1
            local column = 0
            if move.at then
                column = assert(text('scratch')[row]:find(move.at, 1, true), label .. ': no ' .. move.at) - 1
            end
            vim.api.nvim_win_set_cursor(0, { row, column })
            warnings = {}
            for _, command in ipairs(move.run) do
                vim.cmd(command)
            end
            assert(#warnings == 0, label .. ': ' .. table.concat(warnings, '; '))
        end
        if step.expect then
            local result = trimmed(text('scratch'))
            assert(
                vim.deep_equal(page.lines(step.expect), result),
                label .. ': the lesson does not show this result:\n' .. table.concat(result, '\n')
            )
        end
        warnings = {}
        vim.cmd('TruthTableTutorNext')
    end
end
assert(at(#course, #course[#course].steps) and #warnings == 1 and warnings[1]:find('last step', 1, true))

print('Tutor passed')
