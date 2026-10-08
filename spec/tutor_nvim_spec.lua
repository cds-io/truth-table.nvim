-- :TruthTableTutor shows the course in two panes, the lesson beside a scratch
-- buffer per step, and every exercise produces what its lesson says it will.
-- The replay at the end is what keeps the course true as the plugin changes:
-- each step's `solution` is replayed in its scratch buffer, and the result must
-- be the step's own `expect` block.
-- Runs inside Neovim (make test-nvim): busted with nlua as its interpreter.
vim.opt.rtp:append(vim.fn.getcwd())
-- The reader's own setting: the scratch pane must keep it while the lesson
-- pane wraps.
vim.o.wrap = false
require("truth-table").setup()

local page = require("truth-table.tutor_page")
local predicate = require("truth-table.predicate")
local spans = require("truth-table.tutor_spans")
local tutor = require("truth-table.tutor")

-- The place is saved to a file of this run's own, never the reader's.
tutor.state_file = vim.fn.tempname() .. "/truth-table/tutor.json"

local warnings = {}
vim.notify = function(message, level)
    if level == vim.log.levels.WARN then
        warnings[#warnings + 1] = message
    end
end

-- Loaded here, before any case runs, so the replay can name one case per lesson.
local files = vim.fn.glob(vim.fn.getcwd() .. "/tutor/truth-table/*.lua", true, true)
table.sort(files)
local course = vim.tbl_map(dofile, files)

-- Both sides have the same value under every assignment of their variables.
local function equivalent(left, right, label)
    local sides = {}
    for _, source in ipairs({ left, right }) do
        local tree, err = predicate.parse_expression(source)
        assert.is_truthy(tree, ("%s: %s: %s"):format(label, source, tostring(err)))
        sides[#sides + 1] = tree
    end
    local names = {}
    for _, side in ipairs(sides) do
        local variables, err = predicate.variables(side)
        assert.is_truthy(variables, label .. ": " .. tostring(err))
        for _, name in ipairs(variables) do
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

-- The tutor's extmarks in `buf`, each as its row, columns, group and
-- priority, in buffer order.
local function extmarks(buf)
    local namespace = vim.api.nvim_get_namespaces().truth_table_tutor
    local found = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })) do
        found[#found + 1] = {
            row = mark[2], col = mark[3], end_col = mark[4].end_col,
            hl_group = mark[4].hl_group, priority = mark[4].priority,
        }
    end
    return found
end

-- The marks a lesson's spans should become, in the same shape.
local function expected_marks(marked)
    local marks = {}
    for i, span in ipairs(marked) do
        marks[i] = { row = span.row - 1, col = span.col, end_col = span.end_col, hl_group = span.group, priority = spans.PRIORITY }
    end
    return marks
end

-- The reader is at this lesson and step: the lesson pane shows it, on the
-- left, with the lessons up to `furthest` (this one, unless the reader has
-- been further) visited in its winbar, and the cursor is in the scratch
-- pane, which has no winbar.
local function at(lesson, step, furthest)
    local label = ("lesson %d step %d"):format(lesson, step)
    local lesson_win, lesson_buf = pane("lesson")
    local scratch_win, scratch_buf = pane("scratch")
    assert.is_truthy(lesson_win, label .. ": no lesson pane")
    assert.is_truthy(scratch_win, label .. ": no scratch pane")
    assert.are_not.equal(lesson_buf, scratch_buf, label .. ": the panes share a buffer")
    local tab = vim.api.nvim_get_current_tabpage()
    assert.are.same({ lesson_win, scratch_win }, vim.api.nvim_tabpage_list_wins(tab), label .. ": windows in the tab")
    local lesson_column = vim.api.nvim_win_get_position(lesson_win)[2]
    local scratch_column = vim.api.nvim_win_get_position(scratch_win)[2]
    assert.is_true(
        lesson_column < scratch_column,
        ("%s: lesson pane at column %d, scratch pane at column %d"):format(label, lesson_column, scratch_column)
    )
    assert.are.equal(scratch_win, vim.api.nvim_get_current_win(), label .. ": current window")
    local markdown, marked = page.render(course, { lesson = lesson, step = step })
    assert.are.same(markdown, text("lesson"), label .. ": lesson pane text")
    local place = { lesson = lesson, step = step, furthest = furthest or lesson }
    assert.are.equal(page.progress(course, place), vim.wo[lesson_win].winbar, label .. ": lesson winbar")
    assert.are.equal("", vim.wo[scratch_win].winbar, label .. ": scratch winbar")
    assert.are.same(expected_marks(marked), extmarks(lesson_buf), label .. ": lesson pane marks")
    assert.are.equal("nofile", vim.bo[lesson_buf].buftype, label .. ": lesson buftype")
    assert.is_false(vim.bo[lesson_buf].modifiable, label .. ": lesson modifiable")
    assert.are.equal("nofile", vim.bo[scratch_buf].buftype, label .. ": scratch buftype")
    assert.is_true(vim.bo[scratch_buf].modifiable, label .. ": scratch modifiable")
    assert.are.equal("markdown", vim.bo[lesson_buf].filetype, label .. ": lesson filetype")
    assert.are.equal("markdown", vim.bo[scratch_buf].filetype, label .. ": scratch filetype")
    assert.is_true(vim.wo[lesson_win].wrap, label .. ": lesson wrap")
    assert.is_true(vim.wo[lesson_win].linebreak, label .. ": lesson linebreak")
    assert.is_false(vim.wo[scratch_win].wrap, label .. ": scratch wrap")
end

local function starting_text(lesson, step)
    local template = assert(page.template(course[lesson].steps[step].template))
    return #template > 0 and template or { "" }
end

local function starting_marks(lesson, step)
    return expected_marks(select(2, page.template(course[lesson].steps[step].template)))
end

local function tab_count()
    return #vim.api.nvim_list_tabpages()
end

describe("the course", function()
    -- The files say how many lessons there are: each name opens with its
    -- number, so one that went missing leaves a gap.
    it("is every lesson file, numbered from 1 with no gap", function()
        assert.is_true(#files > 0, "no lesson files in tutor/truth-table/")
        local numbers = vim.iter(files)
            :map(function(file)
                return tonumber(vim.fs.basename(file):match("^(%d+)%-"))
            end)
            :totable()
        assert.are.same(vim.fn.range(1, #files), numbers)
    end)

    it("gives every lesson a title, an aim and steps, and every step its text", function()
        for number, lesson in ipairs(course) do
            local label = "lesson " .. number
            assert.are.equal("string", type(lesson.title), label .. ": title")
            assert.are.equal("string", type(lesson.aim), label .. ": aim")
            assert.is_true(#lesson.steps > 0, label .. ": no steps")
            for index, step in ipairs(lesson.steps) do
                assert.are.equal("string", type(step.text), label .. " step " .. index)
            end
        end
    end)

    it("says how to reach every expectation a step shows, and the other way round", function()
        for number, lesson in ipairs(course) do
            for index, step in ipairs(lesson.steps) do
                assert.are.equal(
                    step.expect ~= nil,
                    step.solution ~= nil,
                    ("lesson %d step %d: has an expect, has a solution"):format(number, index)
                )
            end
        end
    end)

    -- The welcome lesson lists the parts with their lessons, so the parts
    -- the files open are checked against it.
    it("opens the parts the welcome lesson lists, at the lessons it says", function()
        local opened = {}
        for number, lesson in ipairs(course) do
            if lesson.part then
                opened[#opened + 1] = { name = lesson.part, first = number }
            end
        end
        assert.are.equal("string", type(course[1].part), "lesson 1 opens no part")
        local listed = {}
        for _, step in ipairs(course[1].steps) do
            for name, first in step.text:gmatch("\n%- ([%w ]+), lessons? (%d+)") do
                listed[#listed + 1] = { name = name, first = tonumber(first) }
            end
        end
        assert.are.same(opened, listed)
    end)

    -- A colour span belongs in a ```logic block or a template, and its
    -- markers have to be well formed, or the tutor refuses to open.
    it("has every colour span where one may be, and well formed", function()
        assert.is_nil(page.check(course))
    end)

    -- The first lesson shows the reader around and the last is the reference;
    -- every lesson between them is there to be worked through.
    it("has an exercise in every lesson between the first and the last", function()
        for number = 2, #course - 1 do
            local exercises = vim.iter(course[number].steps)
                :filter(function(step)
                    return step.solution ~= nil
                end)
                :totable()
            assert.is_true(#exercises > 0, ("lesson %d (%s) has no exercise"):format(number, course[number].title))
        end
    end)

    -- A law is `left ≡ right` on a line of a fenced block in a step's text; a
    -- line may hold several, two or more spaces apart (the reference lists each
    -- law beside its dual, after its name). The ≡ signs on a line say how many
    -- laws it holds, so a line the reader below stops recognising (after a
    -- reformat, say) fails here where it would otherwise go unchecked.
    it("reads every ≡ in a fenced block as a law, and each law holds under every assignment", function()
        local laws = 0
        for number, lesson in ipairs(course) do
            for index, step in ipairs(lesson.steps) do
                local fenced = false
                for _, line in ipairs((assert(page.body(step.text)))) do
                    if line:match("^```") then
                        fenced = not fenced
                    elseif fenced and line:find("≡", 1, true) then
                        local read = 0
                        for _, law in ipairs(vim.split((line:gsub("%s+≡%s+", " ≡ ")), "%s%s+")) do
                            local left, right = law:match("^(.-) ≡ (.+)$")
                            if left then
                                local label = ("lesson %d step %d: %s"):format(number, index, law)
                                assert.is_true(equivalent(left, right, label), label)
                                read = read + 1
                            end
                        end
                        local _, written = line:gsub("≡", "")
                        assert.are.equal(written, read, ("lesson %d step %d: laws read from: %s"):format(number, index, line))
                        laws = laws + read
                    end
                end
            end
        end
        assert.is_true(laws > 0, "no laws found in any lesson")
    end)
end)

-- Each navigation case starts a fresh session, then visits the place it needs.
describe(":TruthTableTutor", function()
    local tabs

    before_each(function()
        -- Keep a reader tab, closing any tutor tab left by an earlier case.
        vim.cmd("tabnew")
        vim.cmd("silent tabonly!")
        vim.cmd("enew!")
        vim.wo.wrap = false
        tabs = tab_count()
        vim.cmd("TruthTableTutor!")
        warnings = {}
    end)

    it("opens a new tab holding the two panes, on the first step, with its starting text in the scratch pane", function()
        vim.cmd("tabclose")
        vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.getcwd() .. "/README.md"))
        tabs = tab_count()
        vim.cmd("TruthTableTutor")
        assert.are.equal(tabs + 1, tab_count())
        at(1, 1)
        assert.are.same(starting_text(1, 1), text("scratch"))
        assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
        local shown = table.concat(text("lesson"), "\n")
        assert.is_truthy(shown:find("**Aim:** " .. course[1].aim, 1, true), shown)
    end)

    -- The scratch never existed as an empty buffer.
    it("leaves undo nothing to take back", function()
        vim.cmd("silent! undo")
        assert.are.same(starting_text(1, 1), text("scratch"))
    end)

    it("stops Prev at the first step, with a warning", function()
        vim.cmd("TruthTableTutorPrev")
        at(1, 1)
        assert.are.equal(1, #warnings, vim.inspect(warnings))
        assert.is_truthy(warnings[1]:find("first step", 1, true), warnings[1])
    end)

    it("moves Next one step, across a lesson boundary", function()
        for _ = 2, #course[1].steps do
            vim.cmd("TruthTableTutorNext")
        end
        at(1, #course[1].steps)
        vim.cmd("TruthTableTutorNext")
        at(2, 1)
        assert.are.same({ "p q" }, text("scratch"))
    end)

    it("moves one step with ]] and, from the lesson pane, back with [[", function()
        vim.cmd("TruthTableTutor 2")
        vim.cmd("normal ]]")
        at(2, 2)
        vim.api.nvim_set_current_win((pane("lesson")))
        vim.cmd("normal [[")
        at(2, 1)
    end)

    it("keeps work in its step's scratch", function()
        vim.cmd("TruthTableTutor 2")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "scribble" })
        vim.cmd("TruthTableTutorNext")
        at(2, 2)
        assert.are.same({ "" }, text("scratch"))
        vim.cmd("TruthTableTutorPrev")
        at(2, 1)
        assert.are.same({ "scribble" }, text("scratch"))
    end)

    it("returns to the reader's place from another tab", function()
        vim.cmd("TruthTableTutor 2")
        vim.cmd("tabfirst")
        assert.are_not.equal((pane("scratch")), vim.api.nvim_get_current_win())
        vim.cmd("TruthTableTutor")
        at(2, 1)
        assert.are.equal(tabs + 1, tab_count())
    end)

    it("opens a closed lesson pane again beside the scratch pane", function()
        vim.cmd("TruthTableTutor 2")
        vim.api.nvim_win_close(pane("lesson"), false)
        vim.cmd("TruthTableTutor")
        at(2, 1)
        assert.are.equal(tabs + 1, tab_count())
    end)

    it("opens a closed scratch pane again beside the lesson pane, on Next", function()
        vim.cmd("TruthTableTutor 2")
        vim.api.nvim_win_close(pane("scratch"), false)
        vim.cmd("TruthTableTutorNext")
        at(2, 2)
        assert.are.equal(tabs + 1, tab_count())
    end)

    it("opens both panes in a tab of their own once their tab is closed, on Prev", function()
        vim.cmd("TruthTableTutor 2")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "scribble" })
        vim.cmd("TruthTableTutorNext")
        vim.cmd("tabclose")
        assert.are.equal(tabs, tab_count())
        assert.is_nil((pane("lesson")))
        assert.is_nil((pane("scratch")))
        vim.cmd("TruthTableTutorPrev")
        at(2, 1)
        assert.are.equal(tabs + 1, tab_count())
        assert.are.same({ "scribble" }, text("scratch"))
    end)

    -- :bdelete leaves a valid but unloaded buffer, which is what makes it a
    -- different case from a closed window.
    it("recreates a scratch pane deleted with :bdelete, with its starting text and tutor options", function()
        vim.cmd("TruthTableTutor 2")
        local deleted_scratch = vim.api.nvim_get_current_buf()
        vim.cmd("bdelete!")
        assert.is_true(vim.api.nvim_buf_is_valid(deleted_scratch))
        assert.is_false(vim.api.nvim_buf_is_loaded(deleted_scratch))
        vim.cmd("TruthTableTutor")
        at(2, 1)
        assert.are.same(starting_text(2, 1), text("scratch"))
        assert.is_false(vim.api.nvim_buf_is_valid(deleted_scratch))
    end)

    it("recreates a lesson pane deleted with :bdelete, and preserves the scratch pane's work", function()
        vim.cmd("TruthTableTutor 2")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "kept scratch" })
        local lesson_win, deleted_lesson = pane("lesson")
        vim.api.nvim_set_current_win(lesson_win)
        vim.cmd("bdelete")
        assert.is_true(vim.api.nvim_buf_is_valid(deleted_lesson))
        assert.is_false(vim.api.nvim_buf_is_loaded(deleted_lesson))
        vim.cmd("TruthTableTutor")
        at(2, 1)
        assert.are.same({ "kept scratch" }, text("scratch"))
        assert.is_false(vim.api.nvim_buf_is_valid(deleted_lesson))
        vim.cmd("TruthTableTutorNext")
        vim.cmd("TruthTableTutorPrev")
        at(2, 1)
        assert.are.same({ "kept scratch" }, text("scratch"))
    end)

    it("jumps to a lesson's first step when given its number", function()
        vim.cmd("TruthTableTutor 6")
        at(6, 1)
    end)

    it("refuses a number past the last lesson, and anything that is not a number", function()
        vim.cmd("TruthTableTutor 6")
        warnings = {}
        vim.cmd("TruthTableTutor " .. #course + 1)
        vim.cmd("TruthTableTutor six")
        at(6, 1)
        assert.are.equal(2, #warnings, vim.inspect(warnings))
        assert.is_truthy(warnings[2]:find("lessons 1 to " .. #course, 1, true), warnings[2])
    end)

    it("starts the course over with !, and the work is gone", function()
        vim.cmd("TruthTableTutor 2")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "scribble" })
        vim.cmd("TruthTableTutor!")
        at(1, 1)
        assert.are.equal(tabs + 1, tab_count())
        vim.cmd("TruthTableTutor 2")
        at(2, 1)
        assert.are.same({ "p q" }, text("scratch"))
    end)
end)

-- A course of one lesson, written to a directory put first on the runtimepath,
-- so :TruthTableTutor! reads it in place of the real one. Each case writes the
-- lesson it needs and starts from a reader tab with no tutor pane.
describe("a lesson with colour spans", function()
    local directory, tabs
    local red, blue = "TruthTableTutorRed", "TruthTableTutorBlue"

    local function lesson(body, template)
        local file = directory .. "/tutor/truth-table/01-spans.lua"
        vim.fn.writefile(vim.split(([[
return {
    part = "Spans",
    title = "Spans",
    aim = "See a part.",
    steps = {
        {
            text = "Look at the group:\n\n```logic\n%s\n```\n",
            template = "%s\n",
        },
    },
}]]):format(body, template), "\n"), file)
    end

    before_each(function()
        directory = vim.fn.tempname()
        vim.fn.mkdir(directory .. "/tutor/truth-table", "p")
        vim.opt.rtp:prepend(directory)
        lesson("A ∨ [:red ¬(B] ∧ ¬C)", "[:blue p] and q")
        vim.cmd("tabnew")
        vim.cmd("silent tabonly!")
        vim.cmd("enew!")
        tabs = tab_count()
        warnings = {}
    end)

    after_each(function()
        vim.opt.rtp:remove(directory)
        vim.fn.delete(directory, "rf")
    end)

    it("paints the span in the lesson pane where its line landed, and the template's in the scratch", function()
        vim.cmd("TruthTableTutor!")
        assert.are.same({}, warnings)
        local _, lesson_buf = pane("lesson")
        local _, scratch_buf = pane("scratch")
        assert.are.equal("A ∨ ¬(B ∧ ¬C)", vim.api.nvim_buf_get_lines(lesson_buf, 7, 8, false)[1])
        assert.are.same({ { row = 7, col = 6, end_col = 10, hl_group = red, priority = 200 } }, extmarks(lesson_buf))
        assert.are.same({ "p and q" }, vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false))
        assert.are.same({ { row = 0, col = 0, end_col = 1, hl_group = blue, priority = 200 } }, extmarks(scratch_buf))
    end)

    it("lets the scratch mark follow the reader's edits", function()
        vim.cmd("TruthTableTutor!")
        local _, scratch_buf = pane("scratch")
        vim.api.nvim_buf_set_text(scratch_buf, 0, 0, 0, 0, { "xx" })
        assert.are.same({ { row = 0, col = 2, end_col = 3, hl_group = blue, priority = 200 } }, extmarks(scratch_buf))
    end)

    it("refuses to open on a wrong marker, naming the lesson, step, field and byte", function()
        lesson("A ∨ [:purple ¬(B] ∧ ¬C)", "p and q")
        vim.cmd("TruthTableTutor!")
        assert.are.same(
            { 'Tutorial lesson 1 step 1: text: unknown colour "purple" at byte 7: A ∨ [:purple ¬(B] ∧ ¬C)' },
            warnings
        )
        assert.is_nil((pane("lesson")))
        assert.are.equal(tabs, tab_count())
    end)

    it("defines the palette as default links, and leaves a group the reader set alone", function()
        vim.api.nvim_set_hl(0, red, { fg = "#ff0000" })
        finally(function()
            vim.cmd("highlight clear " .. red)
            vim.api.nvim_set_hl(0, red, { default = true, link = "DiagnosticError" })
            assert.are.equal("DiagnosticError", vim.api.nvim_get_hl(0, { name = red }).link)
        end)
        vim.cmd("TruthTableTutor!")
        local groups = vim.list_extend(vim.deepcopy(spans.PALETTE), vim.tbl_values(page.STATES))
        assert.are.equal(#spans.PALETTE + 3, #groups)
        for _, entry in ipairs(groups) do
            local hl = vim.api.nvim_get_hl(0, { name = entry.group })
            if entry.group == red then
                assert.are.equal(0xff0000, hl.fg)
            else
                assert.are.equal(entry.link, hl.link, entry.group)
                assert.is_true(hl.default, entry.group)
            end
        end
    end)
end)

-- One case per lesson, with a fresh session so any lesson can run on its own.
describe("working through the course", function()
    local function trimmed(lines)
        while lines[#lines] == "" do
            lines[#lines] = nil
        end
        return lines
    end

    local function row_of(line)
        for row, candidate in ipairs(text("scratch")) do
            if candidate == line then
                return row
            end
        end
    end

    before_each(function()
        vim.cmd("TruthTableTutor!")
        warnings = {}
    end)

    for number, lesson in ipairs(course) do
        -- Each move of a step's solution names the line to put the cursor on
        -- (the first line when absent), the text on it the cursor sits on (the
        -- start of the line when absent), and the commands to run.
        it(("lesson %d: %s"):format(number, lesson.title), function()
            vim.cmd("TruthTableTutor " .. number)
            for index, step in ipairs(lesson.steps) do
                local label = ("lesson %d step %d"):format(number, index)
                at(number, index)
                assert.are.same(starting_text(number, index), text("scratch"), label)
                assert.are.same(starting_marks(number, index), extmarks(select(2, pane("scratch"))), label .. ": scratch marks")
                for _, move in ipairs(step.solution or {}) do
                    local row = 1
                    if move.on then
                        row = row_of(move.on)
                        assert.is_truthy(row, label .. ": no line " .. move.on)
                    end
                    local column = 0
                    if move.at then
                        local found = text("scratch")[row]:find(move.at, 1, true)
                        assert.is_truthy(found, label .. ": no " .. move.at)
                        column = found - 1
                    end
                    vim.api.nvim_win_set_cursor(0, { row, column })
                    warnings = {}
                    for _, command in ipairs(move.run) do
                        vim.cmd(command)
                    end
                    assert.are.same({}, warnings, label)
                end
                if step.expect then
                    local result = trimmed(text("scratch"))
                    assert.are.same(page.lines(step.expect), result, label .. ": the lesson does not show this result")
                end
                warnings = {}
                vim.cmd("TruthTableTutorNext")
            end
        end)
    end

    it("ends on the last step, where Next warns that there is no further", function()
        vim.cmd("TruthTableTutor " .. #course)
        for _ = 1, #course[#course].steps do
            vim.cmd("TruthTableTutorNext")
        end
        at(#course, #course[#course].steps)
        assert.are.equal(1, #warnings, vim.inspect(warnings))
        assert.is_truthy(warnings[1]:find("last step", 1, true), warnings[1])
    end)
end)

-- The reader's place, and the furthest step they have reached, outlive the
-- Neovim they were made in. A restart here is the tutor's module and buffers
-- gone, with the state file left where it is.
describe("the reader's place", function()
    local function restart()
        vim.cmd("tabnew")
        vim.cmd("silent tabonly!")
        vim.cmd("enew!")
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_get_name(buf):find("truth-table-tutor://", 1, true) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
        package.loaded["truth-table.tutor"] = nil
        require("truth-table.tutor").state_file = tutor.state_file
    end

    local function saved()
        return vim.json.decode(table.concat(vim.fn.readfile(tutor.state_file), "\n"))
    end

    before_each(function()
        restart()
        vim.fn.delete(tutor.state_file)
        warnings = {}
    end)

    it("is saved on every move, as the lesson and step, with the furthest reached", function()
        vim.cmd("TruthTableTutor 6")
        assert.are.same({ at = { lesson = 6, step = 1 }, furthest = { lesson = 6, step = 1 } }, saved())
        vim.cmd("TruthTableTutorNext")
        vim.cmd("TruthTableTutorPrev")
        vim.cmd("TruthTableTutorPrev")
        assert.are.same({ at = { lesson = 5, step = #course[5].steps }, furthest = { lesson = 6, step = 2 } }, saved())
        at(5, #course[5].steps, 6)
    end)

    it("is where the reader left off, after a restart", function()
        vim.cmd("TruthTableTutor 6")
        vim.cmd("TruthTableTutorNext")
        vim.cmd("TruthTableTutorPrev")
        vim.cmd("TruthTableTutorPrev")
        restart()
        vim.cmd("TruthTableTutor")
        at(5, #course[5].steps, 6)
        assert.are.same(starting_text(5, #course[5].steps), text("scratch"))
        vim.cmd("TruthTableTutorNext")
        at(6, 1)
    end)

    it("is the first step, with nothing visited, after ! and after a restart from that", function()
        vim.cmd("TruthTableTutor 6")
        restart()
        vim.cmd("TruthTableTutor!")
        at(1, 1)
        restart()
        vim.cmd("TruthTableTutor")
        at(1, 1)
    end)

    it("is the first step when there is no file, or one that cannot be read", function()
        vim.cmd("TruthTableTutor")
        at(1, 1)
        restart()
        vim.fn.writefile({ "{ not json" }, tutor.state_file)
        vim.cmd("TruthTableTutor")
        at(1, 1)
        assert.are.same({}, warnings)
    end)

    it("falls to the nearest step the course has, for a place it no longer has", function()
        vim.fn.mkdir(vim.fs.dirname(tutor.state_file), "p")
        vim.fn.writefile({ vim.json.encode({ at = { lesson = 3, step = 9 }, furthest = { lesson = 99, step = 1 } }) }, tutor.state_file)
        vim.cmd("TruthTableTutor")
        at(3, #course[3].steps, #course)
    end)
end)
