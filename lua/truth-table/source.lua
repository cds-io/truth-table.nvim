-- The expression the cursor selects, as a source: one side of a derivation
-- line, or a table heading, read from anywhere in its column. A source is
-- the `expression`, the byte from zero where it `start`s in its line (nil
-- when it is escaped there), `offset`, the cursor's byte within the
-- expression when it has one, and the ways to write a rendered rewrite,
-- { text, law, produced, consumed }, back: `replace(rewritten)` gives the
-- edited line and the byte, from zero, where the text starts in it (nil
-- when the text is escaped there), and `step(rewritten)`, for expression
-- lines only, gives the line to insert below and that byte. A heading
-- source carries its `column` too. Rows are from one.
local predicate = require("truth-table.predicate")
local markdown = require("truth-table.markdown")
local derivation = require("truth-table.derivation")
local M = {}

-- A heading is one expression, read from anywhere in its column. Only the
-- heading row itself puts the cursor on a byte of the expression.
local function heading_source(lines, bounds, at)
    local selected = {}
    for i = bounds.start_line, bounds.end_line do
        selected[#selected + 1] = lines[i]
    end
    local tbl, err = markdown.parse_table_lines(selected)
    if not tbl then
        return nil, err
    end
    local heading_line = lines[bounds.start_line]
    local column = math.min(markdown.column_index(lines[at.row], at.byte - 1), #tbl.headers)
    local expression = tbl.headers[column]
    local first, last = markdown.heading_cell(heading_line, column)
    -- An escaped heading does not map byte for byte (nor does it parse).
    local start = first and heading_line:sub(first, last) == expression and first - 1 or nil
    local offset
    if start and at.row == bounds.start_line then
        offset = at.byte - start
    end
    return {
        row = bounds.start_line,
        column = column,
        expression = expression,
        start = start,
        offset = offset,
        replace = function(rewritten)
            local replaced, reason = markdown.replace_heading(heading_line, column, rewritten.text)
            if not replaced then
                return nil, reason
            end
            local cell_first, cell_last = markdown.heading_cell(replaced, column)
            local written = cell_first and replaced:sub(cell_first, cell_last) == rewritten.text and cell_first - 1
                or nil
            return replaced, written
        end,
    }
end

local function line_source(line, at)
    if markdown.is_table_line(line) then
        return nil, "Cursor is not inside a supported truth table"
    end
    local side, err = derivation.working_side(line, at.byte)
    if not side then
        return nil, err
    end
    return {
        row = at.row,
        expression = side.text,
        start = side.first - 1,
        offset = at.byte - side.first + 1,
        replace = function(rewritten)
            return derivation.replace(line, side, rewritten), side.first - 1
        end,
        step = function(rewritten)
            return derivation.step(line, rewritten, vim.fn.strdisplaywidth)
        end,
    }
end

-- The source the cursor selects in `buf` and its located tree, or nil and
-- the reason there is none.
function M.at(buf)
    local position = vim.api.nvim_win_get_cursor(0)
    local at = { row = position[1], byte = position[2] + 1 }
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local bounds = markdown.find_table(lines, at.row)
    local source, err
    if bounds then
        source, err = heading_source(lines, bounds, at)
    else
        source, err = line_source(lines[at.row], at)
    end
    if not source then
        return nil, err
    end
    local ast, parse_err = predicate.parse_located(source.expression)
    if not ast then
        return nil, parse_err
    end
    return source, ast
end

return M
