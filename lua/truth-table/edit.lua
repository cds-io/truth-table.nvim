-- Writes a rewrite's text and marks as one patch, and keeps the marks in
-- step with Neovim's undo tree: each undo sequence number has the marks that
-- went with it, so undo and redo restore them with the text, branches
-- included. The marks are truth-table.marks records.
local marks = require("truth-table.marks")
local M = {}
local namespace = vim.api.nvim_create_namespace("truth-table.changed")
local histories = {}

local function sequence(buf)
    return vim.api.nvim_buf_call(buf, function()
        return vim.fn.undotree().seq_cur
    end)
end

local function annotations(buf)
    return marks.read(buf, namespace)
end

local function restore(buf, state)
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    marks.paint(buf, namespace, state)
end

local function synchronize(buf, history)
    local seq = sequence(buf)
    local state = seq ~= history.current and history.states[seq] or nil
    -- Earlier entries predating the first patch have no plugin annotations.
    if seq < history.current and state == nil then
        state = {}
    end
    if state then
        restore(buf, state)
    else
        state = annotations(buf)
    end
    history.states[seq], history.current = state, seq
    return seq
end

local function watch(buf)
    if histories[buf] then
        return histories[buf]
    end
    local seq = sequence(buf)
    local history = { current = seq, states = { [seq] = annotations(buf) }, revision = 0 }
    histories[buf] = history
    vim.api.nvim_buf_attach(buf, false, {
        on_lines = function()
            history.revision = history.revision + 1
            local revision = history.revision
            -- seq_cur settles after on_lines; coalesce callbacks from one edit.
            vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(buf) or revision ~= history.revision then
                    return
                end
                synchronize(buf, history)
            end)
        end,
        on_detach = function() histories[buf] = nil end,
    })
    return history
end

-- The patch for writing `replacement` at `row` (from zero): in place of the
-- line there, or below it with `inserted`; with the marks `additions` on the
-- result. A patch holds the text and marks before and after: the marks
-- there already are shifted down for an insertion, or dropped from the line
-- written over.
function M.prepare(buf, write)
    local row, replacement, inserted, additions = write.row, write.replacement, write.inserted, write.additions or {}
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    local history = watch(buf)
    synchronize(buf, history)
    local before = annotations(buf)
    local after = {}
    for _, mark in ipairs(before) do
        if inserted or mark.row ~= row then
            local shift = inserted and mark.row > row and 1 or 0
            after[#after + 1] = {
                row = mark.row + shift, col = mark.col, end_col = mark.end_col,
                group = mark.group, priority = mark.priority,
            }
        end
    end
    for _, mark in ipairs(additions) do
        after[#after + 1] = mark
    end
    return {
        row = inserted and row + 1 or row,
        before = {
            lines = inserted and {} or vim.api.nvim_buf_get_lines(buf, row, row + 1, false),
            annotations = before,
        },
        after = { lines = { replacement }, annotations = after },
    }
end

function M.apply(buf, patch)
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    local history = watch(buf)
    -- Capture edits or an undo performed before a scheduled callback ran.
    local seq = synchronize(buf, history)
    history.states[seq] = patch.before.annotations
    -- Give this application its own native undo entry, even when invoked
    -- from a Lua callback in the same turn as another buffer modification.
    vim.api.nvim_buf_call(buf, function()
        vim.cmd("let &undolevels = &undolevels")
    end)
    vim.api.nvim_buf_set_lines(buf, patch.row, patch.row + #patch.before.lines, false, patch.after.lines)
    restore(buf, patch.after.annotations)
    history.revision = history.revision + 1
    history.current = sequence(buf)
    history.states[history.current] = patch.after.annotations
end

return M
