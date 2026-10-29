-- The tutor's buffers and windows: a scratch buffer with undo stopped at
-- its starting text, a buffer dressed with its filetype and the keys that
-- move, and the two panes side by side, found again by the role each
-- window carries. Nothing here knows the course; init.lua puts the step in.
local fp = require("cds.fp")
local M = {}

local ROLE = "truth_table_tutor"
local KEYS = { ["]]"] = "TruthTableTutorNext", ["[["] = "TruthTableTutorPrev" }

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
    local found = fp.find(vim.api.nvim_list_wins(), function(win)
        return vim.w[win][ROLE] == role
    end)
    return found
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

M.ROLE, M.live, M.buffer, M.dress, M.window, M.panes = ROLE, live, buffer, dress, window, panes

return M
