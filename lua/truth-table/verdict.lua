-- A derivation's verdict shown in its buffer: the first failing step's
-- conclusion lit in the consumed group, its ≡ overlaid with ≢, and the
-- breaking assignment notified. The text is not touched; the marks go on
-- the next change to the buffer, or when the check runs again. check.lua
-- judges; this paints.
local check = require("truth-table.check")
local derivation = require("truth-table.derivation")
local marks = require("truth-table.marks")
local write = require("truth-table.write")
local SYMBOLS = require("truth-table.symbols")
local M = {}
local namespace = vim.api.nvim_create_namespace("truth-table.verdict")
local attached = {}

-- Clear the verdict's marks on the next change to `buf`. One attachment
-- per buffer; it stays for the buffer's life, as the preview's does.
local function watch(buf)
    if attached[buf] then
        return
    end
    attached[buf] = vim.api.nvim_buf_attach(buf, false, {
        on_lines = function()
            -- A fast context: the marks go once Neovim is ready.
            vim.schedule(function()
                if vim.api.nvim_buf_is_valid(buf) then
                    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
                end
            end)
        end,
        on_detach = function()
            attached[buf] = nil
        end,
    })
end

-- Judge the derivation holding `row` (from one) in `buf` and show the
-- verdict.
function M.show(buf, row)
    -- The watch is kept by buffer number, so 0 (the current buffer) is
    -- resolved before anything is keyed by it.
    if buf == 0 then
        buf = vim.api.nvim_get_current_buf()
    end
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local first, last = derivation.block(lines, row)
    local block = {}
    for i = first, last do
        block[#block + 1] = lines[i]
    end
    local verdict, err = check.check(block)
    if not verdict then
        vim.notify(err, vim.log.levels.WARN)
        return
    end
    if verdict.ok then
        if verdict.steps == 0 then
            vim.notify("No " .. SYMBOLS.EQUIV.unicode .. " step under the cursor", vim.log.levels.WARN)
        else
            local noun = verdict.steps == 1 and " step)" or " steps)"
            vim.notify("every step holds (" .. verdict.steps .. noun, vim.log.levels.INFO)
        end
        return
    end
    local at = first + verdict.row - 2
    local length = verdict.side[2] - verdict.side[1] + 1
    marks.paint(buf, namespace, write.lit({ row = at, col = verdict.side[1] - 1 }, { { 0, length } }, write.CONSUMED_GROUP))
    vim.api.nvim_buf_set_extmark(buf, namespace, at, verdict.separator - 1, {
        virt_text = { { SYMBOLS.NOT_EQUIV.unicode, write.CONSUMED_GROUP } },
        virt_text_pos = "overlay",
    })
    watch(buf)
    vim.notify(check.message(verdict), vim.log.levels.WARN)
end

return M
