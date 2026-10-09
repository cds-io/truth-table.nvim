-- :TruthTableRewrites, the menu of every rewrite of the expression the
-- cursor selects. The one picked is written at once: below, as the next
-- step of a derivation, or over a heading, which has no steps. A pending
-- preview in the buffer is dismissed first.
local rewrite = require("truth-table.rewrite")
local derivation = require("truth-table.derivation")
local source = require("truth-table.source")
local write = require("truth-table.write")
local preview = require("truth-table.preview")
local M = {}

-- The menu lists each result with its law, the bars in one column, as the
-- steps of a derivation read.
function M.choose()
    local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
    preview.dismiss(buf)
    local selected, ast = source.at(buf)
    if not selected then
        vim.notify(ast, vim.log.levels.WARN)
        return
    end
    local moves = rewrite.moves(ast)
    if #moves == 0 then
        vim.notify("No rewrite applies to " .. selected.expression, vim.log.levels.WARN)
        return
    end
    local widest = 0
    for _, move in ipairs(moves) do
        widest = math.max(widest, vim.fn.strdisplaywidth(move.text))
    end
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    vim.ui.select(moves, {
        prompt = "Rewrites of " .. selected.expression,
        kind = "truth-table.rewrite",
        format_item = function(move)
            local pad = widest - vim.fn.strdisplaywidth(move.text) + 2
            return move.text .. string.rep(" ", pad) .. derivation.justification(move.law)
        end,
    }, function(move)
        if not move then
            return
        end
        -- A select UI may call back long after the menu opened.
        local shown = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf
        if not shown or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
            vim.notify("The buffer changed while the menu was open; nothing was written", vim.log.levels.WARN)
            return
        end
        local plan, err = write.prepare(buf, selected, write.rendered(move.rewritten))
        if not plan then
            vim.notify(err, vim.log.levels.WARN)
        elseif plan.step then
            write.step(win, plan)
        else
            write.in_place(buf, plan)
            vim.notify(
                "Renamed the heading; update explicit references to its old label if needed",
                vim.log.levels.INFO
            )
        end
    end)
end

return M
