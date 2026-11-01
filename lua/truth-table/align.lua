-- The justification bars of a derivation in one column, the way a new step
-- places its own: run on the derivation a rewrite wrote to, through the
-- TruthTableRewrite autocommand, and on demand (:TruthTableAlign) for one
-- typed by hand. derivation.lua measures and says what to write; this
-- writes the padding before each bar and nothing else, so the marks on the
-- expressions stay where they are.
local derivation = require("truth-table.derivation")
local list = require("truth-table.list")
local M = {}

-- Align the derivation holding `row` (from one) in `buf`. With `join`, the
-- edit joins the undo entry before it, so a rewrite and its realignment undo
-- together. Returns the block's first and last rows.
function M.derivation(buf, row, join)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local first, last = derivation.block(lines, row)
    local block = list.slice(lines, first, last)
    local joined = not join
    for _, edit in ipairs(derivation.alignment(block, vim.fn.strdisplaywidth)) do
        if not joined then
            -- Once, before the first edit: Neovim syncs undo between commands
            -- and keystrokes, never between the API calls of one Lua turn,
            -- so every edit of this loop lands in the entry the first one
            -- joined. Refused after an undo, when there is no entry to join.
            pcall(vim.cmd, "undojoin")
            joined = true
        end
        local at = first + edit.index - 2
        vim.api.nvim_buf_set_text(buf, at, edit.start, at, edit.finish, { edit.replacement })
    end
    return first, last
end

return M
