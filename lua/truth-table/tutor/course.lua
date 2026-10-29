-- The course and the reader's place in it. The course is data, one file
-- per lesson under tutor/truth-table/, read in file-name order; the place
-- (the lesson and step the reader is on and the furthest they have
-- reached) outlives Neovim as one line of JSON in the state file init.lua
-- names, written on every move. Reads files and notifies; the windows are
-- init.lua's.
local page = require("truth-table.tutor.page")
local M = {}

local LESSONS = "tutor/truth-table"

-- The saved place as two indexes into `steps`: the file's lesson and step,
-- each brought within the course (a lesson past the last is the last, a
-- step past its lesson's last is that one), and the furthest reached, no
-- earlier than the place itself. The first step, for a file that is missing
-- or not the JSON remember() writes.
local function recall(state_file, course, index)
    local read, lines = pcall(vim.fn.readfile, state_file)
    local decoded, saved = false, nil
    if read then
        decoded, saved = pcall(vim.json.decode, table.concat(lines, "\n"))
    end
    if not (decoded and type(saved) == "table") then
        return 1, 1
    end
    local function within(value, last)
        local number = tonumber(value)
        return math.min(math.max(number and math.floor(number) or 1, 1), last)
    end
    local function position(place)
        if type(place) ~= "table" then
            return 1
        end
        local lesson = within(place.lesson, #course)
        return index[lesson][within(place.step, #course[lesson].steps)]
    end
    local at = position(saved.at)
    return at, math.max(at, position(saved.furthest))
end

-- The reader's place written for recall(). A place that cannot be written
-- is said once a session, and the tutor goes on without it.
local function remember(state_file, session)
    local at, furthest = session.steps[session.at], session.steps[session.furthest]
    local json = vim.json.encode({ at = at, furthest = furthest })
    local ok, err = pcall(function()
        vim.fn.mkdir(vim.fs.dirname(state_file), "p")
        vim.fn.writefile({ json }, state_file)
    end)
    if not ok and not session.unsaved then
        session.unsaved = true
        vim.notify("Tutorial place not saved to " .. state_file .. ": " .. tostring(err), vim.log.levels.WARN)
    end
end

-- The course from its files, at the saved place, or at the first step when
-- `fresh`.
local function load(state_file, fresh)
    local directory = vim.api.nvim_get_runtime_file(LESSONS, false)[1]
    local files = directory and vim.fn.glob(directory .. "/*.lua", true, true) or {}
    if #files == 0 then
        vim.notify("Tutorial lessons not found on the runtimepath: " .. LESSONS, vim.log.levels.WARN)
        return
    end
    table.sort(files)
    local course, steps, index = {}, {}, {}
    for lesson, file in ipairs(files) do
        course[lesson] = dofile(file)
        index[lesson] = {}
        for step in ipairs(course[lesson].steps) do
            steps[#steps + 1] = { lesson = lesson, step = step }
            index[lesson][step] = #steps
        end
    end
    local err = page.check(course)
    if err then
        vim.notify("Tutorial " .. err, vim.log.levels.WARN)
        return
    end
    local at, furthest = 1, 1
    if not fresh then
        at, furthest = recall(state_file, course, index)
    end
    return { course = course, steps = steps, index = index, at = at, furthest = furthest, scratch = {} }
end

M.load, M.remember = load, remember

return M
