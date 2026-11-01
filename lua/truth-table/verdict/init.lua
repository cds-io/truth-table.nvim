-- A derivation's verdict shown in its buffer: the first failing step's
-- conclusion lit in the consumed group, its ≡ overlaid with ≢, and the
-- breaking assignment notified. With the proof, a truth table over the
-- chain's variables with one column per side goes in below the block, and
-- a failing conclusion's cell is lit at the breaking row. The same verdict
-- and proof serve a list of expressions given as an argument or as
-- selected lines (equiv). The derivation's text is not touched; the marks
-- go on the next change to the buffer, or when the check runs again.
-- check.lua judges; this paints. The proof table is proof.lua's; this
-- keeps the marks and takes them down.
local check = require("truth-table.check")
local derivation = require("truth-table.derivation")
local list = require("truth-table.list")
local marks = require("truth-table.marks")
local write = require("truth-table.write")
local SYMBOLS = require("truth-table.symbols")
local proof = require("truth-table.verdict.proof")
local M = {}
local namespace = vim.api.nvim_create_namespace("truth-table.verdict")
local attached, shown = {}, {}

-- Take the verdict's marks down on the next change to `buf`: the ids
-- painted by then, so marks painted after the change (the proof's, which
-- follows its own insertion) stay. One attachment per buffer; it stays for
-- the buffer's life, as the preview's does.
local function watch(buf)
    if attached[buf] then
        return
    end
    attached[buf] = vim.api.nvim_buf_attach(buf, false, {
        on_lines = function()
            local ids = shown[buf]
            shown[buf] = nil
            if ids then
                -- A fast context: the marks go once Neovim is ready.
                vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(buf) then
                        for _, id in ipairs(ids) do
                            pcall(vim.api.nvim_buf_del_extmark, buf, namespace, id)
                        end
                    end
                end)
            end
        end,
        on_detach = function()
            attached[buf], shown[buf] = nil, nil
        end,
    })
end

local function remember(buf, ids)
    shown[buf] = list.concat(shown[buf] or {}, ids)
end

-- The proof of `verdict` inserted below row `last` of `buf`, its failing
-- cell lit; or the reason it could not be built, notified.
local function show_proof(buf, last, indent, verdict)
    local cell, refused = proof.show(buf, last, indent, verdict)
    if not cell then
        vim.notify(refused, vim.log.levels.WARN)
        return
    end
    remember(buf, marks.paint(buf, namespace, cell))
end

-- Judge `exprs`, two or more expression texts, as a chain, each against
-- the one before it, and notify the verdict: equivalent, or the first pair
-- that differs with the assignment. With `with_proof`, the table goes in
-- below row `below` (from one) of `buf`, at `indent`, its differing cell
-- lit. The expressions are an argument or plain lines, so nothing else is
-- marked.
function M.equiv(buf, exprs, below, indent, with_proof)
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    if #exprs < 2 then
        vim.notify("Give two or more expressions to compare", vim.log.levels.WARN)
        return
    end
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    shown[buf] = nil
    local verdict, err = check.check(exprs)
    if not verdict then
        vim.notify(err, vim.log.levels.WARN)
        return
    end
    watch(buf)
    if with_proof then
        show_proof(buf, below, indent, verdict)
    end
    if verdict.ok then
        vim.notify("equivalent (" .. #exprs .. " expressions)", vim.log.levels.INFO)
        return
    end
    local assignment = check.assignment(verdict)
    local where = assignment ~= "" and (" at " .. assignment) or ""
    local pair = "expressions " .. verdict.step .. " and " .. (verdict.step + 1)
    vim.notify(pair .. " differ" .. where .. ": " .. check.values(verdict), vim.log.levels.WARN)
end

-- Judge the derivation holding `row` (from one) in `buf` and show the
-- verdict; with `proof`, the table as well.
function M.show(buf, row, with_proof)
    -- The watch is kept by buffer number, so 0 (the current buffer) is
    -- resolved before anything is keyed by it.
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    shown[buf] = nil
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local first, last = derivation.block(lines, row)
    local verdict, err = check.check(list.slice(lines, first, last))
    if not verdict then
        vim.notify(err, vim.log.levels.WARN)
        return
    end
    if verdict.ok and verdict.steps == 0 then
        vim.notify("No " .. SYMBOLS.EQUIV.unicode .. " step under the cursor", vim.log.levels.WARN)
        return
    end
    watch(buf)
    if with_proof then
        show_proof(buf, last, lines[first]:match("^%s*"), verdict)
    end
    if verdict.ok then
        local noun = verdict.steps == 1 and " step)" or " steps)"
        vim.notify("every step holds (" .. verdict.steps .. noun, vim.log.levels.INFO)
        return
    end
    local at = first + verdict.row - 2
    local length = verdict.side[2] - verdict.side[1] + 1
    local lit = write.lit({ row = at, col = verdict.side[1] - 1 }, { { 0, length } }, write.CONSUMED_GROUP)
    remember(buf, marks.paint(buf, namespace, lit))
    remember(buf, {
        vim.api.nvim_buf_set_extmark(buf, namespace, at, verdict.separator - 1, {
            virt_text = { { SYMBOLS.NOT_EQUIV.unicode, write.CONSUMED_GROUP } },
            virt_text_pos = "overlay",
        }),
    })
    vim.notify(check.message(verdict), vim.log.levels.WARN)
end

return M
