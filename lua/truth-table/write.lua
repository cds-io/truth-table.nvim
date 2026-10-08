-- Writing a rewrite where its source is: in place of the expression, or
-- below its line as a ≡ step, with the terms the law consumed lit on the
-- source line and what it produced lit in the text written, so a derivation
-- reads from the part a law acted on to the part it produced. `prepare`
-- plans one write, which a preview shows before it happens; `in_place` and
-- `step` carry a plan out through edit.lua, and tell whoever follows the
-- TruthTableRewrite event.
local edit = require("truth-table.edit")
local M = {}

-- The lit regions of written rewrites stay with their lines. The consumed
-- terms sit above whatever an earlier step lit on their line.
M.CHANGED_GROUP, M.CONSUMED_GROUP = "TruthTableChanged", "TruthTableConsumed"
local PRIORITY = { [M.CHANGED_GROUP] = 4096, [M.CONSUMED_GROUP] = 4097 }

-- A rewrite as the source will write it: the consumed ranges lie in the
-- source expression's text, the produced ones in the text written.
function M.rendered(rewritten)
    local change = rewritten.change
    return {
        text = change.text, law = change.law,
        produced = change.produced_ranges, consumed = change.consumed_ranges,
    }
end

-- The plan for writing `rewritten` (see rendered) where `source` is: the
-- `row` from zero, the `replacement` line, `written`, the byte from zero
-- where the text starts in it, `source`, where the expression starts in
-- the line it is in, the `heading` and `law`, the `changed` and `consumed`
-- ranges, the heading's `column` when the source is one, the buffer's
-- `tick` at the time, and for an expression line the `step` to insert
-- below with its `step_column`. Nil and the reason when the source refuses
-- the text.
function M.prepare(buf, source, rewritten)
    local replacement, written = source.replace(rewritten)
    if not replacement then
        return nil, written
    end
    local plan = {
        row = source.row - 1,
        replacement = replacement,
        written = written,
        source = source.start,
        heading = rewritten.text,
        law = rewritten.law,
        changed = rewritten.produced or {},
        consumed = rewritten.consumed or {},
        column = source.column,
        tick = vim.api.nvim_buf_get_changedtick(buf),
    }
    if source.step then
        plan.step, plan.step_column = source.step(rewritten)
    end
    return plan
end

-- The marks for `ranges` of an expression whose text starts at `at`,
-- { row, col }, in `group`; none when the text has no start (it is escaped
-- there, and does not map byte for byte).
function M.lit(at, ranges, group)
    if at.col == nil then
        return {}
    end
    local out = {}
    for _, range in ipairs(ranges) do
        out[#out + 1] = {
            row = at.row, col = at.col + range[1], end_col = at.col + range[2],
            group = group, priority = PRIORITY[group],
        }
    end
    return out
end

-- Anything that wants to follow a written rewrite: the buffer, the row it
-- was written to (from one) and whether it is a step below its source or
-- in its place. The plugin's own listener aligns the derivation's bars.
local function written(buf, row, kind)
    vim.api.nvim_exec_autocmds("User", {
        pattern = "TruthTableRewrite",
        data = { buf = buf, row = row, kind = kind },
    })
end

function M.in_place(buf, plan)
    local additions = M.lit({ row = plan.row, col = plan.written }, plan.changed, M.CHANGED_GROUP)
    edit.apply(buf, edit.prepare(buf, { row = plan.row, replacement = plan.replacement, additions = additions }))
    written(buf, plan.row + 1, "in_place")
end

-- Insert the step below the source line in `win`'s buffer and leave the
-- cursor on it, ready for the next rewrite.
function M.step(win, plan)
    local buf = vim.api.nvim_win_get_buf(win)
    local additions = M.lit({ row = plan.row, col = plan.source }, plan.consumed, M.CONSUMED_GROUP)
    for _, mark in ipairs(M.lit({ row = plan.row + 1, col = plan.step_column }, plan.changed, M.CHANGED_GROUP)) do
        additions[#additions + 1] = mark
    end
    edit.apply(buf, edit.prepare(buf, { row = plan.row, replacement = plan.step, inserted = true, additions = additions }))
    written(buf, plan.row + 2, "step")
    vim.api.nvim_win_set_cursor(win, { plan.row + 2, plan.step_column })
end

return M
