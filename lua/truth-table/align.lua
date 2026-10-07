-- The justification bars of a derivation in one column, the way a new step
-- places its own: run on the derivation a rewrite wrote to, through the
-- TruthTableRewrite autocommand, and on demand (:TruthTableAlign) for one
-- typed by hand. derivation.lua measures; this writes the padding before
-- each bar and nothing else, so the marks on the expressions stay where they
-- are.
local derivation = require("truth-table.derivation")
local M = {}

-- Align the derivation holding `row` (from one) in `buf`. With `join`, the
-- edit joins the undo entry before it, so a rewrite and its realignment undo
-- together. Returns the block's first and last rows.
function M.derivation(buf, row, join)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local first, last = derivation.block(lines, row)
    local block = {}
    for i = first, last do
        block[#block + 1] = lines[i]
    end
    local aligned = derivation.aligned(block, vim.fn.strdisplaywidth)
    local joined = not join
    for i, line in ipairs(aligned) do
        local old = block[i]
        if line ~= old then
            local bar, new_bar = old:find("|", 1, true), line:find("|", 1, true)
            local kept = #(old:sub(1, bar - 1):gsub("%s+$", ""))
            if not joined then
                -- Refused after an undo, when there is no entry to join.
                pcall(vim.cmd, "undojoin")
                joined = true
            end
            local at = first + i - 2
            vim.api.nvim_buf_set_text(buf, at, kept, at, bar - 1, { line:sub(kept + 1, new_bar - 1) })
        end
    end
    return first, last
end

return M
