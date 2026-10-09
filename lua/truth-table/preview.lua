-- Editor-only preview state. The source buffer remains unchanged until the
-- preview is applied. The terms a rewrite consumed are lit on its line
-- while the preview is pending, and what it put in is lit in the preview's
-- text at the end of the line. The expression under the cursor is
-- source.lua's, what a rewrite writes is write.lua's, and the keys that
-- apply a pending preview are held by transient.lua.
local derivation = require("truth-table.derivation")
local rewrite = require("truth-table.rewrite")
local marks = require("truth-table.marks")
local source = require("truth-table.source")
local write = require("truth-table.write")
local transient = require("truth-table.transient")
local M = {}
local namespace = vim.api.nvim_create_namespace("truth-table.preview")
-- The consumed terms of a pending preview, cleared with it. They sit above
-- whatever an earlier step lit on their line.
local TARGET = vim.api.nvim_create_namespace("truth-table.target")
local PENDING = 4098
local pending, attached = {}, {}

-- Each rewrite maps a located tree and a cursor byte to a new tree and the
-- name of the law that justifies it. `whole` marks a rewrite that also
-- works without a cursor in the expression, on the whole of it. `opposite` names the rewrite a
-- reader is likely to have meant when this one refuses, with the words that
-- point to it.
local REWRITES = {
    de_morgan = { whole = true, run = rewrite.de_morgan },
    simplify = { whole = true, run = rewrite.simplify },
    factor = {
        run = rewrite.factor,
        opposite = { name = "distribute", hint = "to move it into the group beside it, use :TruthTableDistribute" },
    },
    distribute = {
        run = rewrite.distribute,
        opposite = { name = "factor", hint = "to pull it out of the terms that share it, use :TruthTableFactor" },
    },
    xor = { run = rewrite.xor },
    commute = {
        run = function(ast, byte)
            return rewrite.commute(ast, byte, false)
        end,
    },
    commute_back = {
        run = function(ast, byte)
            return rewrite.commute(ast, byte, true)
        end,
    },
}

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

-- The preview of `kind` at the cursor in `buf`: the plan of the write; or
-- nil and the reason.
local function resolve(buf, kind)
    local selected, ast = source.at(buf)
    if not selected then
        return nil, ast
    end
    if not kind.whole and not selected.offset then
        return nil, "Put the cursor on the heading row to choose an operand"
    end
    -- A rewrite carries its law and both sides of the change.
    local rewritten, reason = kind.run(ast, selected.offset)
    if not rewritten then
        -- Factor and Distribute are one law used from either side, and easy
        -- to reach for the wrong way round: say so when the other applies.
        local opposite = kind.opposite
        if opposite and REWRITES[opposite.name].run(ast, selected.offset) then
            return nil, reason .. "; " .. opposite.hint
        end
        return nil, reason
    end
    local preview, err = write.prepare(buf, selected, write.rendered(rewritten))
    if not preview then
        return nil, err
    end
    return preview
end

-- The preview's text at the end of its line: the heading with what the
-- rewrite produced lit, and its law as a justification, in the comment
-- colour otherwise.
local function chunks(preview)
    local label = preview.column and (" [column " .. preview.column .. "] ⇒ ") or " ⇒ "
    local tail = "  " .. derivation.justification(preview.law)
    if #preview.changed == 0 then
        return { { label .. preview.heading .. tail, "Comment" } }
    end
    local out = {}
    local cursor, prefix = 0, label
    for _, region in ipairs(preview.changed) do
        out[#out + 1] = { prefix .. preview.heading:sub(cursor + 1, region[1]), "Comment" }
        out[#out + 1] = { preview.heading:sub(region[1] + 1, region[2]), write.CHANGED_GROUP }
        cursor, prefix = region[2], ""
    end
    out[#out + 1] = { preview.heading:sub(cursor + 1) .. tail, "Comment" }
    return out
end

-- A rewrite command resolves its preview at the cursor first. The same
-- preview as the pending one (the same text on the same line) dismisses
-- it; any other replaces it. A refusal leaves the pending preview as it
-- was.
function M.toggle(name)
    -- Without a name this is the De Morgan toggle it was before rewrites had names.
    local kind = REWRITES[name or "de_morgan"]
    local buf = vim.api.nvim_get_current_buf()
    local preview, err = resolve(buf, kind)
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
        virt_text = chunks(preview), virt_text_pos = "eol",
    })
    local targets = write.lit({ row = preview.row, col = preview.source }, preview.consumed, write.CONSUMED_GROUP)
    for _, mark in ipairs(targets) do
        mark.priority = PENDING
    end
    preview.targets = marks.paint(buf, TARGET, targets)
    pending[buf] = preview
    transient.engage(buf, KEYS)
    if preview.column then
        vim.notify("Applying renames the heading; update explicit references to its old label if needed", vim.log.levels.INFO)
    end
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
