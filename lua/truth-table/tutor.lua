-- :TruthTableTutor. The tutorial is worked through by running commands on its
-- own lines, so it opens as a scratch copy: the reader edits freely and the
-- shipped file stays as written.
local M = {}

local SOURCE = "tutor/truth-table-tutor.md"
local NAME = "truth-table-tutor"

local function copy()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].truth_table_tutor then
            return buf
        end
    end
end

local function create(path)
    local buf = vim.api.nvim_create_buf(true, true)
    -- Filled with undo off, so the first `u` cannot take the text away.
    local undolevels = vim.bo[buf].undolevels
    vim.bo[buf].undolevels = -1
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(path))
    vim.bo[buf].undolevels = undolevels
    vim.bo[buf].modified = false
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_name(buf, NAME)
    vim.b[buf].truth_table_tutor = true
    return buf
end

-- Show the reader's copy, keeping the work in it; `fresh` starts over.
function M.open(fresh)
    local path = vim.api.nvim_get_runtime_file(SOURCE, false)[1]
    if not path then
        vim.notify("Tutorial not found on the runtimepath: " .. SOURCE, vim.log.levels.WARN)
        return
    end
    local buf = copy()
    if buf and fresh then
        vim.api.nvim_buf_delete(buf, { force = true })
        buf = nil
    end
    local window = buf and vim.fn.win_findbuf(buf)[1]
    if window then
        vim.api.nvim_set_current_win(window)
        return
    end
    vim.cmd("tab sbuffer " .. (buf or create(path)))
    if not buf then
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end
end

return M
