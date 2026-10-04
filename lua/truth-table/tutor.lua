-- :TruthTableTutor. Two panes in a tab of their own: the lesson on the left,
-- one step at a time, and on the right a scratch buffer holding that step's
-- starting text for the reader to run commands on. The course is data, one
-- file per lesson under tutor/truth-table/, read in file-name order;
-- tutor_page.lua turns a step into the lesson pane's text.
local page = require("truth-table.tutor_page")

local M = {}

local LESSONS = "tutor/truth-table"
local ROLE = "truth_table_tutor"
local KEYS = { ["]]"] = "TruthTableTutorNext", ["[["] = "TruthTableTutorPrev" }
-- The lesson pane wraps its prose to whatever width the window has.
local LESSON_PANE = { wrap = true, linebreak = true, breakindent = true, breakindentopt = "list:-1" }

-- The course, the reader's place in it (an index into `steps`, every step of
-- every lesson in order), the lesson pane's buffer, and a scratch buffer per
-- step visited, so the work in one survives moving to another.
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
    return { course = course, steps = steps, at = 1, scratch = {} }
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
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_name(buf, name)
    -- Set after the filetype, whose plugin maps the same keys to headings.
    for keys, command in pairs(KEYS) do
        vim.keymap.set("n", keys, "<cmd>" .. command .. "<CR>", { buffer = buf, desc = command })
    end
    return buf
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

local function show()
    local at = session.steps[session.at]
    if not live(session.lesson) then
        session.lesson = buffer("truth-table-tutor://lesson", {}, session.lesson)
    end
    vim.bo[session.lesson].modifiable = true
    vim.api.nvim_buf_set_lines(session.lesson, 0, -1, false, page.render(session.course, at.lesson, at.step))
    vim.bo[session.lesson].modifiable = false

    local scratch = session.scratch[session.at]
    if not live(scratch) then
        local name = ("truth-table-tutor://scratch/%d.%d"):format(at.lesson, at.step)
        scratch = buffer(name, page.lines(session.course[at.lesson].steps[at.step].template), scratch)
        session.scratch[session.at] = scratch
    end

    local lesson_win, scratch_win = panes()
    vim.api.nvim_win_set_buf(lesson_win, session.lesson)
    -- Set after the buffer is in the window, and local to it. A window takes
    -- fresh options when it first shows a buffer: set any earlier, these are
    -- lost, and the scratch pane, split off this one, keeps the reader's own.
    for name, value in pairs(LESSON_PANE) do
        vim.api.nvim_set_option_value(name, value, { win = lesson_win, scope = "local" })
    end
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
    session = session or load()
    if not session then
        return
    end
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
