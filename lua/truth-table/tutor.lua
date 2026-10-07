-- :TruthTableTutor. Two panes in a tab of their own: the lesson on the left,
-- one step at a time, and on the right a scratch buffer holding that step's
-- starting text for the reader to run commands on. The course is data, one
-- file per lesson under tutor/truth-table/, read in file-name order;
-- tutor_page.lua turns a step into the lesson pane's Markdown, and
-- tutor_vellum.lua styles that when vellum.nvim is installed. A lesson's
-- colour spans (tutor_spans.lua) are painted in both panes.
local page = require("truth-table.tutor_page")
local styled = require("truth-table.tutor_vellum")
local spans = require("truth-table.tutor_spans")

local M = {}

local LESSONS = "tutor/truth-table"
local ROLE = "truth_table_tutor"
local KEYS = { ["]]"] = "TruthTableTutorNext", ["[["] = "TruthTableTutorPrev" }
local MARKS = vim.api.nvim_create_namespace(ROLE)
-- The lesson pane by what it shows. Markdown is one line per paragraph, for
-- the window to wrap at whatever width it has. Styled text arrives wrapped to
-- the window's full width, so the window gives up its gutter and leaves the
-- lines alone.
local LESSON_PANE = {
    markdown = {
        filetype = "markdown",
        options = { wrap = true, linebreak = true, breakindent = true, breakindentopt = "list:-1" },
    },
    styled = {
        filetype = "truth-table-tutor",
        options = {
            wrap = false,
            list = false,
            spell = false,
            colorcolumn = "",
            number = false,
            relativenumber = false,
            signcolumn = "no",
            foldcolumn = "0",
            statuscolumn = "",
        },
    },
}

-- The course, the reader's place in it (an index into `steps`, every step of
-- every lesson in order), the lesson pane's buffer, the width its text was
-- wrapped to (nil while it shows Markdown), and a scratch buffer per step
-- visited, so the work in one survives moving to another.
local session

local function load()
    local directory = vim.api.nvim_get_runtime_file(LESSONS, false)[1]
    local files = directory and vim.fn.glob(directory .. "/*.lua", true, true) or {}
    if #files == 0 then
        vim.notify("Tutorial lessons not found on the runtimepath: " .. LESSONS, vim.log.levels.WARN)
        return
    end
    table.sort(files)
    local course, steps = {}, {}
    for lesson, file in ipairs(files) do
        course[lesson] = dofile(file)
        for step in ipairs(course[lesson].steps) do
            steps[#steps + 1] = { lesson = lesson, step = step }
        end
    end
    local err = page.check(course)
    if err then
        vim.notify("Tutorial " .. err, vim.log.levels.WARN)
        return
    end
    return { course = course, steps = steps, at = 1, scratch = {} }
end

-- The colour spans' highlight groups, as defaults: one the reader defines
-- stands.
local function palette()
    for _, entry in ipairs(spans.PALETTE) do
        vim.api.nvim_set_hl(0, entry.group, { default = true, link = entry.link })
    end
end

-- A lesson's spans as marks on the lines they were found in.
local function marks_of(marked)
    local marks = {}
    for i, span in ipairs(marked) do
        marks[i] = { row = span.row - 1, col = span.col, end_col = span.end_col, group = span.group, priority = spans.PRIORITY }
    end
    return marks
end

local function paint(buf, marks)
    for _, mark in ipairs(marks) do
        vim.api.nvim_buf_set_extmark(buf, MARKS, mark.row, mark.col, {
            end_col = mark.end_col,
            hl_group = mark.group,
            priority = mark.priority,
        })
    end
end

local function live(buf)
    return buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
end

local function buffer(name, lines, previous)
    -- :bdelete leaves an unloaded buffer with its name but resets its options.
    -- Wipe that shell before creating a fresh scratch with the same name.
    if previous and vim.api.nvim_buf_is_valid(previous) then
        vim.api.nvim_buf_delete(previous, { force = true })
    end
    local buf = vim.api.nvim_create_buf(false, true)
    -- Filled with undo off, so undo stops at the starting text.
    local undolevels = vim.bo[buf].undolevels
    vim.bo[buf].undolevels = -1
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].undolevels = undolevels
    vim.api.nvim_buf_set_name(buf, name)
    return buf
end

-- A buffer's filetype and the tutor's keys. The keys go on after the
-- filetype, whose plugin maps the same ones to headings, and again each time:
-- a filetype plugin that is replaced takes those mappings with it.
local function dress(buf, filetype)
    if vim.bo[buf].filetype ~= filetype then
        vim.bo[buf].filetype = filetype
    end
    for keys, command in pairs(KEYS) do
        vim.keymap.set("n", keys, "<cmd>" .. command .. "<CR>", { buffer = buf, desc = command })
    end
end

local function window(role)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.w[win][ROLE] == role then
            return win
        end
    end
end

-- Both panes, side by side. A pane the reader closed opens again beside the
-- other; with neither left, a new tab holds the pair.
local function panes()
    local lesson, scratch = window("lesson"), window("scratch")
    if not lesson then
        if scratch then
            vim.api.nvim_set_current_win(scratch)
            vim.cmd("leftabove vsplit")
        else
            vim.cmd("tab split")
        end
        lesson = vim.api.nvim_get_current_win()
        vim.w[lesson][ROLE] = "lesson"
    end
    if not scratch then
        vim.api.nvim_set_current_win(lesson)
        vim.cmd("rightbelow vsplit")
        scratch = vim.api.nvim_get_current_win()
        vim.w[scratch][ROLE] = "scratch"
    end
    return lesson, scratch
end

-- The reader's step in the lesson pane `win`, which shows the lesson buffer:
-- styled for the width the pane has now, or as Markdown when that fails. The
-- lesson's colour spans are painted either way; load() checked every step
-- renders.
local function draw(win)
    local at = session.steps[session.at]
    local markdown, marked = page.render(session.course, at.lesson, at.step)
    assert(markdown, marked)
    local width = vim.api.nvim_win_get_width(win)
    local lines, marks = styled.render(markdown, width, marked)
    local pane = lines and LESSON_PANE.styled or LESSON_PANE.markdown
    session.width = lines and width

    local buf = session.lesson
    local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_clear_namespace(buf, MARKS, 0, -1)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or markdown)
    vim.bo[buf].modifiable = false
    paint(buf, lines and marks or marks_of(marked))
    dress(buf, pane.filetype)
    -- Set after the buffer is in the window, and local to it. A window takes
    -- fresh options when it first shows a buffer: set any earlier, these are
    -- lost, and the scratch pane, split off this one, keeps the reader's own.
    for name, value in pairs(pane.options) do
        vim.api.nvim_set_option_value(name, value, { win = win, scope = "local" })
    end
    vim.api.nvim_win_call(win, function()
        vim.fn.winrestview(view)
    end)
end

-- Styled text is wrapped to one width and coloured for one colorscheme, so
-- it is drawn again when either changes.
local function watch()
    local group = vim.api.nvim_create_augroup(ROLE, { clear = true })
    local function redraw(event)
        if event.event == "ColorScheme" then
            styled.restyle()
            palette()
        end
        local win = window("lesson")
        if not (win and session.width and vim.api.nvim_win_get_buf(win) == session.lesson) then
            return
        end
        if event.event == "ColorScheme" or vim.api.nvim_win_get_width(win) ~= session.width then
            draw(win)
        end
    end
    vim.api.nvim_create_autocmd({ "WinResized", "ColorScheme" }, { group = group, callback = redraw })
end

local function show()
    local at = session.steps[session.at]
    if not live(session.lesson) then
        session.lesson = buffer("truth-table-tutor://lesson", {}, session.lesson)
    end

    local scratch = session.scratch[session.at]
    if not live(scratch) then
        local name = ("truth-table-tutor://scratch/%d.%d"):format(at.lesson, at.step)
        local lines, marked = page.template(session.course[at.lesson].steps[at.step].template)
        scratch = buffer(name, assert(lines, marked), scratch)
        -- Painted once the text is in, so undo has nothing of it; from here
        -- the marks move with the reader's edits.
        paint(scratch, marks_of(marked))
        dress(scratch, "markdown")
        session.scratch[session.at] = scratch
    end

    local lesson_win, scratch_win = panes()
    vim.api.nvim_win_set_buf(lesson_win, session.lesson)
    draw(lesson_win)
    vim.api.nvim_win_set_cursor(lesson_win, { 1, 0 })
    vim.api.nvim_win_set_buf(scratch_win, scratch)
    vim.api.nvim_set_current_win(scratch_win)
end

local function discard()
    local buffers = vim.tbl_values(session.scratch)
    buffers[#buffers + 1] = session.lesson
    for _, buf in ipairs(buffers) do
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
    vim.api.nvim_del_augroup_by_name(ROLE)
    styled.forget()
    session = nil
end

-- Show the reader's place with the work in it. `fresh` starts the course
-- over, rereading the lesson files; `lesson` moves to that lesson's first
-- step.
function M.open(opts)
    opts = opts or {}
    if opts.fresh and session then
        discard()
    end
    if not session then
        session = load()
        if not session then
            return
        end
        watch()
    end
    palette()
    if opts.lesson then
        local target
        for index, at in ipairs(session.steps) do
            if at.lesson == tonumber(opts.lesson) then
                target = index
                break
            end
        end
        if not target then
            local message = "No lesson %s: the tutorial has lessons 1 to %d"
            vim.notify(message:format(opts.lesson, #session.course), vim.log.levels.WARN)
            return
        end
        session.at = target
    end
    show()
end

-- Move `delta` steps through the course, across lesson boundaries.
function M.step(delta)
    if not session then
        M.open()
        return
    end
    if not session.steps[session.at + delta] then
        local edge = delta > 0 and "last" or "first"
        vim.notify("This is the " .. edge .. " step of the tutorial", vim.log.levels.WARN)
        return
    end
    session.at = session.at + delta
    show()
end

return M
