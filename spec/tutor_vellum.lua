-- The lesson pane is styled through vellum.nvim when that is installed, and
-- shows the step's Markdown when it is absent or cannot do the job. Three
-- vellums take turns: none, the installed one when TRUTH_TABLE_TEST_VELLUM
-- names its directory, and a stand-in whose behaviour the checks choose.
vim.opt.rtp:append(vim.fn.getcwd())
vim.o.columns = 160
vim.o.number = true
require('truth-table').setup()
local page = require('truth-table.tutor_page')
local styled = require('truth-table.tutor_vellum')

local warnings = {}
vim.notify = function(message, level)
    if level == vim.log.levels.WARN then
        warnings[#warnings + 1] = message
    end
end

local files = vim.fn.glob(vim.fn.getcwd() .. '/tutor/truth-table/*.lua', true, true)
table.sort(files)
local course = vim.tbl_map(dofile, files)

-- No vellum: nothing to show, and nothing to say about it.
assert(styled.render({ '# A heading' }, 80) == nil and #warnings == 0)

-- The installed vellum renders every step at three widths. Each mark is
-- checked against its line as it is read, and at the widest no letter or
-- digit of a step goes missing.
local installed = vim.env.TRUTH_TABLE_TEST_VELLUM
if installed then
    vim.opt.rtp:append(vim.fn.expand(installed))
    vim.o.termguicolors = true
    local function alnum(lines)
        return (table.concat(lines, '\n'):gsub('[^%w]', ''))
    end
    for _, width in ipairs({ 104, 70, 50 }) do
        for number, lesson in ipairs(course) do
            for index in ipairs(lesson.steps) do
                local label = ('lesson %d step %d at width %d'):format(number, index, width)
                local markdown = page.render(course, number, index)
                local lines, marks = styled.render(markdown, width)
                assert(lines and #marks > 0, label .. ': ' .. table.concat(warnings, '; '))
                assert(width < 104 or alnum(lines) == alnum(markdown), label .. ': text went missing')
            end
        end
    end
    assert(#warnings == 0)
    package.loaded['vellum.render'], package.loaded['vellum.theme'] = nil, nil
    styled.restyle()
    print('Tutor with the installed vellum passed')
end

-- The stand-in: a page that names the width it was asked for, then the
-- step's first line with its opening word marked. `behaviour` picks a
-- renderer that works, one that raises, and one whose mark runs past its line.
local behaviour = 'works'
local calls = { apply = 0, reset = 0 }
package.loaded['vellum.theme'] = {
    apply = function()
        calls.apply = calls.apply + 1
    end,
}
package.loaded['vellum.render'] = {
    reset = function()
        calls.reset = calls.reset + 1
    end,
    render = function(buf, width, max_width)
        assert(behaviour ~= 'raises', 'the renderer changed')
        local title = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
        local lines = { '', ('  width %d of %d'):format(width, max_width), '  ' .. title }
        local rows = { {}, {}, { { 0, behaviour == 'astray' and 999 or 4, 'Title', 100 } } }
        return lines, rows, 2, {}
    end,
}

local function pane(role)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.w[win].truth_table_tutor == role then
            return win, vim.api.nvim_win_get_buf(win)
        end
    end
end

local function marks()
    local _, buf = pane('lesson')
    local namespace = vim.api.nvim_get_namespaces().truth_table_tutor
    return vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
end

-- The lesson pane holds the stand-in's page for this step, wrapped to the
-- pane's width and marked, with no gutter; the scratch pane keeps the
-- reader's line numbers.
local function styled_at(lesson, step)
    local win, buf = pane('lesson')
    local width = vim.api.nvim_win_get_width(win)
    local expected = { '', ('  width %d of 100'):format(width), '  ' .. page.render(course, lesson, step)[1] }
    assert(vim.deep_equal(expected, vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
    local found = marks()
    assert(#found == 1 and found[1][2] == 2 and found[1][3] == 2)
    assert(found[1][4].end_col == 6 and found[1][4].hl_group == 'Title' and found[1][4].priority == 100)
    assert(vim.bo[buf].filetype == 'truth-table-tutor' and not vim.bo[buf].modifiable)
    assert(not vim.wo[win].wrap and not vim.wo[win].number and vim.wo[win].signcolumn == 'no')
    assert(vim.wo[(pane('scratch'))].number)
    return true
end

-- The lesson pane holds the step's Markdown, as it does with no vellum.
local function markdown_at(lesson, step)
    local win, buf = pane('lesson')
    assert(vim.deep_equal(page.render(course, lesson, step), vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
    assert(#marks() == 0)
    assert(vim.bo[buf].filetype == 'markdown' and not vim.bo[buf].modifiable)
    assert(vim.wo[win].wrap and vim.wo[win].linebreak)
    return true
end

vim.cmd('TruthTableTutor')
assert(styled_at(1, 1) and calls.apply == 1 and calls.reset == 1)
assert(vim.bo[select(2, pane('scratch'))].filetype == 'markdown')

-- The keys work from the styled pane, and a step change reuses the theme.
vim.api.nvim_set_current_win((pane('lesson')))
vim.cmd('normal ]]')
assert(styled_at(2, 1) and calls.apply == 1)
vim.cmd('TruthTableTutor 5')
assert(styled_at(5, 1))

-- A new width wraps the page again and keeps the reader's place in it; the
-- same width leaves the pane alone.
local lesson_win = pane('lesson')
vim.api.nvim_win_set_cursor(lesson_win, { 3, 0 })
vim.api.nvim_win_set_width(lesson_win, 40)
vim.api.nvim_exec_autocmds('WinResized', {})
assert(styled_at(5, 1) and vim.api.nvim_win_get_width(lesson_win) == 40)
assert(vim.api.nvim_win_get_cursor(lesson_win)[1] == 3)
local tick = vim.api.nvim_buf_get_changedtick(select(2, pane('lesson')))
vim.api.nvim_exec_autocmds('WinResized', {})
assert(tick == vim.api.nvim_buf_get_changedtick(select(2, pane('lesson'))))

-- A colorscheme has the groups defined again.
vim.api.nvim_exec_autocmds('ColorScheme', {})
assert(styled_at(5, 1) and calls.apply == 2 and calls.reset == 2)

-- A renderer that raises: the pane shows Markdown, and says why once.
behaviour = 'raises'
vim.cmd('TruthTableTutorNext')
assert(markdown_at(5, 2) and #warnings == 1)
assert(warnings[1]:find('vellum.nvim could not render', 1, true) and warnings[1]:find('the renderer changed', 1, true))
vim.cmd('TruthTableTutorPrev')
assert(markdown_at(5, 1) and #warnings == 1)
vim.cmd('normal ]]')
assert(markdown_at(5, 2))

-- A width change has nothing to redo while the pane shows Markdown.
tick = vim.api.nvim_buf_get_changedtick(select(2, pane('lesson')))
vim.api.nvim_win_set_width((pane('lesson')), 60)
vim.api.nvim_exec_autocmds('WinResized', {})
assert(tick == vim.api.nvim_buf_get_changedtick(select(2, pane('lesson'))))

-- A mark that runs past its line is refused whole, and a renderer that
-- works again is used again.
behaviour = 'astray'
vim.cmd('TruthTableTutorNext')
assert(markdown_at(5, 3))
behaviour = 'works'
vim.cmd('TruthTableTutorNext')
assert(styled_at(5, 4))

-- Starting over leaves no watcher behind.
vim.cmd('TruthTableTutor!')
assert(styled_at(1, 1) and #vim.api.nvim_get_autocmds({ group = 'truth_table_tutor' }) == 2)

print('Tutor with vellum passed')
