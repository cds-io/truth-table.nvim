-- :TruthTableTutor. Two panes in a tab of their own: the lesson on the left,
-- one step at a time, and on the right a scratch buffer holding that step's
-- starting text for the reader to run commands on. The course is data, one
-- file per lesson under tutor/truth-table/, read in file-name order;
-- page.lua turns a step into the lesson pane's Markdown, and vellum.lua
-- styles that when vellum.nvim is installed. A lesson's colour spans
-- (spans.lua) are painted in both panes. course.lua reads the lessons and
-- keeps the reader's place, panes.lua owns the buffers and windows, and
-- lesson.lua draws the lesson pane; this holds the session and moves it.
local fp = require("cds.fp")
local list = require("truth-table.list")
local page = require("truth-table.tutor.page")
local styled = require("truth-table.tutor.vellum")
local course = require("truth-table.tutor.course")
local panes = require("truth-table.tutor.panes")
local lesson = require("truth-table.tutor.lesson")

local M = {}

local ROLE = panes.ROLE
local live, buffer, dress, window = panes.live, panes.buffer, panes.dress, panes.window
local palette, marks_of, paint = lesson.palette, lesson.marks_of, lesson.paint
-- Where the reader's place outlives Neovim: the lesson and step they are on
-- and the furthest they have reached, as one line of JSON, written on every
-- move. A spec points this at a file of its own.
M.state_file = vim.fs.joinpath(vim.fn.stdpath("state"), "truth-table", "tutor.json")

-- The course, the reader's place in it (`at`, an index into `steps`, every
-- step of every lesson in order, and `furthest`, the highest `at` has been;
-- `index[lesson][step]` is the other way round), the lesson pane's buffer,
-- the width its text was wrapped to (nil while it shows Markdown), and a
-- scratch buffer per step visited, so the work in one survives moving to
-- another.
local session

local function draw(win)
    session.width = lesson.draw(session, win)
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
    session.furthest = math.max(session.furthest, session.at)
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

    local lesson_win, scratch_win = panes.panes()
    vim.api.nvim_win_set_buf(lesson_win, session.lesson)
    draw(lesson_win)
    vim.api.nvim_win_set_cursor(lesson_win, { 1, 0 })
    vim.api.nvim_win_set_buf(scratch_win, scratch)
    vim.api.nvim_set_current_win(scratch_win)
    course.remember(M.state_file, session)
end

local function discard()
    for _, buf in ipairs(list.concat(vim.tbl_values(session.scratch), { session.lesson })) do
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
    vim.api.nvim_del_augroup_by_name(ROLE)
    styled.forget()
    session = nil
end

-- Show the reader's place with the work in it: the saved place, in a Neovim
-- the tutor has not run in. `fresh` starts the course over, rereading the
-- lesson files; `lesson` moves to that lesson's first step.
function M.open(opts)
    opts = opts or {}
    if opts.fresh and session then
        discard()
    end
    if not session then
        session = course.load(M.state_file, opts.fresh)
        if not session then
            return
        end
        watch()
    end
    palette()
    if opts.lesson then
        local _, target = fp.find(session.steps, function(at)
            return at.lesson == tonumber(opts.lesson)
        end)
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
