-- A derivation's verdict shown in its buffer: the first failing step's
-- conclusion lit in the consumed group, its ≡ overlaid with ≢, and the
-- breaking assignment notified. With the proof, a truth table over the
-- chain's variables with one column per side goes in below the block, and
-- a failing conclusion's cell is lit at the breaking row. The derivation's
-- text is not touched; the marks go on the next change to the buffer, or
-- when the check runs again. check.lua judges; this paints.
local check = require("truth-table.check")
local core = require("truth-table.core")
local derivation = require("truth-table.derivation")
local markdown = require("truth-table.markdown")
local marks = require("truth-table.marks")
local model = require("truth-table.table_model")
local write = require("truth-table.write")
local SYMBOLS = require("truth-table.symbols")
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
    shown[buf] = shown[buf] or {}
    for _, id in ipairs(ids) do
        shown[buf][#shown[buf] + 1] = id
    end
end

-- The proof of `verdict`: a table over the chain's variables, in chain
-- order, with one computed column per side (a side that is a variable
-- names the column already there). Nil and the reason when a side refuses
-- to bind, which a judged chain's sides do not.
local function proof(verdict)
    local base = {
        headers = verdict.variables,
        rows = model.generate_rows(#verdict.variables),
        encoding = "bits",
    }
    return core.expand(base, verdict.texts)
end

local function column_of(tbl, heading)
    for index, header in ipairs(tbl.headers) do
        if header == heading then
            return index
        end
    end
end

-- The row of `tbl` (from one) on which the failing step's two columns
-- differ: the first one, as the check found it.
local function breaking_row(tbl, verdict)
    local premise = column_of(tbl, verdict.texts[verdict.step])
    local conclusion = column_of(tbl, verdict.texts[verdict.step + 1])
    for index, row in ipairs(tbl.rows) do
        if row[premise] ~= row[conclusion] then
            return index, conclusion
        end
    end
end

-- Insert the proof of `verdict` below row `last` (from one) of `buf`, at
-- `indent`, and light the failing cell. Returns the error when the table
-- cannot be built.
local function show_proof(buf, last, indent, verdict)
    local tbl, err = proof(verdict)
    if not tbl then
        return err
    end
    local lines = { "" }
    for _, line in ipairs(core.format(tbl)) do
        lines[#lines + 1] = indent .. line
    end
    vim.api.nvim_buf_set_lines(buf, last, last, false, lines)
    if verdict.ok then
        return
    end
    local row, column = breaking_row(tbl, verdict)
    if not row then
        return
    end
    -- The blank, the heading and the separator sit between the block and
    -- the first data row.
    local at = last + 2 + row
    local first, final = markdown.heading_cell(lines[3 + row], column)
    local cell = write.lit({ row = at, col = first - 1 }, { { 0, final - first + 1 } }, write.CONSUMED_GROUP)
    remember(buf, marks.paint(buf, namespace, cell))
end

-- Judge the derivation holding `row` (from one) in `buf` and show the
-- verdict; with `proof`, the table as well.
function M.show(buf, row, with_proof)
    -- The watch is kept by buffer number, so 0 (the current buffer) is
    -- resolved before anything is keyed by it.
    if buf == 0 then
        buf = vim.api.nvim_get_current_buf()
    end
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    shown[buf] = nil
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
    if verdict.ok and verdict.steps == 0 then
        vim.notify("No " .. SYMBOLS.EQUIV.unicode .. " step under the cursor", vim.log.levels.WARN)
        return
    end
    watch(buf)
    if with_proof then
        local refused = show_proof(buf, last, lines[first]:match("^%s*"), verdict)
        if refused then
            vim.notify(refused, vim.log.levels.WARN)
        end
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
    remember(buf, { vim.api.nvim_buf_set_extmark(buf, namespace, at, verdict.separator - 1, {
        virt_text = { { SYMBOLS.NOT_EQUIV.unicode, write.CONSUMED_GROUP } },
        virt_text_pos = "overlay",
    }) })
    vim.notify(check.message(verdict), vim.log.levels.WARN)
end

return M
