-- Editor-only preview state. The source buffer remains unchanged until the
-- preview is applied. The terms a rewrite consumed are lit on its line
-- while the preview is pending, and what it put in is lit in the preview's
-- text at the end of the line. The expression under the cursor is
-- source.lua's, what a rewrite writes is write.lua's, and the keys that
-- apply a pending preview are held by transient.lua.
-- The rewrites by name, and the plan of one at the cursor, are plan.lua's;
-- this is the state: the pending preview per buffer, its marks, its keys,
-- and the changedtick that says whether the buffer is still as it left it.
local marks = require("truth-table.marks")
local plan = require("truth-table.preview.plan")
local write = require("truth-table.write")
local transient = require("truth-table.transient")
local M = {}
local namespace = vim.api.nvim_create_namespace("truth-table.preview")
-- The consumed terms of a pending preview, cleared with it. They sit above
-- whatever an earlier step lit on their line.
local TARGET = vim.api.nvim_create_namespace("truth-table.target")
local PENDING = 4098
local pending, attached = {}, {}

-- While a preview is pending, <Space> and <CR> apply it: <Space> in place,
-- <CR> as a ≡ step.
local KEYS = {
    {
        lhs = "<Space>",
        run = function()
            M.apply()
        end,
        desc = "Truth table: apply preview in place",
    },
    {
        lhs = "<CR>",
        run = function()
            M.apply_step()
        end,
        desc = "Truth table: apply preview as a ≡ step",
    },
}

-- Take the pending preview in `buf` down, with its marks and its keys.
function M.dismiss(buf)
    pending[buf] = nil
    transient.release(buf)
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    vim.api.nvim_buf_clear_namespace(buf, TARGET, 0, -1)
end

local function watch(buf)
    if attached[buf] then
        return
    end
    attached[buf] = vim.api.nvim_buf_attach(buf, false, {
        on_lines = function()
            local preview = pending[buf]
            pending[buf] = nil
            if preview then
                -- A fast context: the extmark and the transient keymaps go
                -- once Neovim is ready. A preview engaged again by then owns
                -- the keymaps, so they stay.
                vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(buf) then
                        pcall(vim.api.nvim_buf_del_extmark, buf, namespace, preview.mark)
                        for _, mark in ipairs(preview.targets or {}) do
                            pcall(vim.api.nvim_buf_del_extmark, buf, TARGET, mark)
                        end
                    end
                    if not pending[buf] then
                        transient.release(buf)
                    end
                end)
            end
        end,
        on_detach = function()
            attached[buf], pending[buf] = nil, nil
            transient.forget(buf)
        end,
    })
end

-- A rewrite command resolves its preview at the cursor first. The same
-- preview as the pending one (the same text on the same line) dismisses
-- it; any other replaces it. A refusal leaves the pending preview as it
-- was.
function M.toggle(name)
    -- Without a name this is the De Morgan toggle it was before rewrites had names.
    local buf = vim.api.nvim_get_current_buf()
    local preview, err = plan.resolve(buf, name or "de_morgan")
    if not preview then
        vim.notify(err, vim.log.levels.WARN)
        return
    end
    local shown = pending[buf]
    if shown then
        M.dismiss(buf)
        if shown.row == preview.row and shown.replacement == preview.replacement then
            return
        end
    end
    watch(buf)
    preview.mark = vim.api.nvim_buf_set_extmark(buf, namespace, preview.row, 0, {
        virt_text = plan.chunks(preview),
        virt_text_pos = "eol",
    })
    local targets = write.lit({ row = preview.row, col = preview.source }, preview.consumed, write.CONSUMED_GROUP)
    for _, mark in ipairs(targets) do
        mark.priority = PENDING
    end
    preview.targets = marks.paint(buf, TARGET, targets)
    pending[buf] = preview
    transient.engage(buf, KEYS)
    if preview.column then
        vim.notify(
            "Applying renames the heading; update explicit references to its old label if needed",
            vim.log.levels.INFO
        )
    end
end

-- The pending preview in `buf` while the buffer is as the preview left it,
-- or nil: a probe with no side effects, where `current` clears stale state
-- and complains.
function M.active(buf)
    local preview = pending[buf]
    if preview and preview.tick == vim.api.nvim_buf_get_changedtick(buf) then
        return preview
    end
    return nil
end

-- The pending preview, provided the buffer is as it was when the preview was
-- made. Otherwise the stale state is cleared and the user is told.
local function current(buf)
    local preview = pending[buf]
    if not preview or preview.tick ~= vim.api.nvim_buf_get_changedtick(buf) then
        M.dismiss(buf)
        vim.notify("No current preview; run a rewrite command first", vim.log.levels.WARN)
        return nil
    end
    return preview
end

function M.apply()
    local buf = vim.api.nvim_get_current_buf()
    local preview = current(buf)
    if not preview then
        return
    end
    -- Clear state before editing so the attachment cannot invalidate a new mark.
    M.dismiss(buf)
    write.in_place(buf, preview)
end

-- Insert the rewritten expression as the next line of a derivation and leave
-- the cursor on it, ready for the next rewrite.
function M.apply_step()
    local buf = vim.api.nvim_get_current_buf()
    local preview = current(buf)
    if not preview then
        return
    end
    if not preview.step then
        vim.notify("Steps apply to expression lines; use :TruthTableApply for a heading", vim.log.levels.WARN)
        return
    end
    M.dismiss(buf)
    write.step(0, preview)
end

return M
