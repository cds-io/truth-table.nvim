-- The proof of a verdict: a truth table over the chain's variables with
-- one column per side, written in below the block, and the cell where the
-- failing step's two columns first differ, as the mark to light. init.lua
-- paints the mark and keeps it; this builds and inserts the table.
local core = require("truth-table.core")
local fp = require("cds.fp")
local list = require("truth-table.list")
local text = require("truth-table.text")
local markdown = require("truth-table.markdown")
local model = require("truth-table.table_model")
local write = require("truth-table.write")
local M = {}

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
    local _, index = fp.find(tbl.headers, function(header)
        return header == heading
    end)
    return index
end

-- The row of `tbl` (from one) on which the failing step's two columns
-- differ: the first one, as the check found it.
local function breaking_row(tbl, verdict)
    local premise = column_of(tbl, verdict.texts[verdict.step])
    local conclusion = column_of(tbl, verdict.texts[verdict.step + 1])
    local _, index = fp.find(tbl.rows, function(row)
        return row[premise] ~= row[conclusion]
    end)
    if index then
        return index, conclusion
    end
end

-- Insert the proof of `verdict` below row `last` (from one) of `buf`, at
-- `indent`. Returns the marks that light the failing cell (none when every
-- step holds), or nil and the error when the table cannot be built.
function M.show(buf, last, indent, verdict)
    local tbl, err = proof(verdict)
    if not tbl then
        return nil, err
    end
    local lines = list.concat({ "" }, text.indented(core.format(tbl), indent))
    vim.api.nvim_buf_set_lines(buf, last, last, false, lines)
    if verdict.ok then
        return {}
    end
    local row, column = breaking_row(tbl, verdict)
    if not row then
        return {}
    end
    -- The blank, the heading and the separator sit between the block and
    -- the first data row.
    local at = last + 2 + row
    local first, final = markdown.heading_cell(lines[3 + row], column)
    return write.lit({ row = at, col = first - 1 }, { { 0, final - first + 1 } }, write.CONSUMED_GROUP)
end

return M
