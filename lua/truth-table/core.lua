-- truth-table core: pure logic with no Neovim dependency.
--
-- Everything here is a plain function over strings and tables: no `vim.*`, no
-- buffers, no side effects. That boundary keeps the parser, evaluator, and
-- formatter unit-testable under a bare Lua interpreter (busted). The one place
-- that wants Neovim (display-width measurement) is injectable: M.display_width
-- has a pure default, and the vim layer swaps in vim.fn.strdisplaywidth.

local M = {}
local result = require("truth-table.result")
local model = require("truth-table.table_model")
local predicate = require("truth-table.predicate")
local markdown = require("truth-table.markdown")

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Compatibility facade; standalone codecs receive width measurement explicitly.
M.display_width = markdown.display_width
function M.center_pad(str, width)
    return markdown.center_pad(str, width, M.display_width)
end

function M.format_table(headers, rows)
    return markdown.format({ headers = headers, rows = rows }, M.display_width)
end

-- Legacy string-cell generation is an adapter over semantic row generation.
function M.generate_rows(n)
    return model.render_rows({ rows = model.generate_rows(n), encoding = "bits" })
end

-- Semantic API: every fallible operation returns one table, or nil and an error.
M.parse_model = markdown.parse_table_lines
M.drop_model_row = model.drop_row
M.drop_model_column = model.drop_column
M.toggle_model = model.toggle
function M.format_model(tbl)
    return markdown.format(tbl, M.display_width)
end

local function legacy_parts(tbl, err)
    if not tbl then
        return nil, err
    end
    return tbl.headers, model.render_rows(tbl)
end

-- Parse the :TruthTable argument: either an integer N (-> headers A, B, C, ...)
-- or a list of variable names. Returns headers, or nil + an error message.
function M.parse_truth_table_args(args)
    local input = trim(args)
    if input == "" then
        return nil, "Usage: :TruthTable N or :TruthTable name1 name2 ..."
    end

    local n = tonumber(input)
    if n then
        if n < 1 or n > 10 or n ~= math.floor(n) then
            return nil, "N must be an integer between 1 and 10"
        end
        local headers = {}
        for i = 1, n do
            headers[i] = string.char(64 + i)
        end
        return headers
    end

    local headers = {}
    local seen = {}
    for name in input:gmatch("%S+") do
        if not name:match("^[A-Za-z_][A-Za-z0-9_]*$") then
            return nil, "Invalid variable name: " .. name
        end
        if seen[name] then
            return nil, "Duplicate variable name: " .. name
        end
        seen[name] = true
        headers[#headers + 1] = name
    end

    if #headers > 10 then
        return nil, "Too many variables (max 10)"
    end

    return headers
end

M.is_table_line = markdown.is_table_line
M.is_separator = markdown.is_separator
M.split_row = markdown.split_row
M.column_index = markdown.column_index
function M.parse_table_lines(lines)
    local parsed, err = markdown.parse_table_lines(lines)
    return result.bind(parsed, err, function(tbl)
        return { headers = tbl.headers, rows = model.render_rows(tbl), encoding = tbl.encoding }
    end)
end

-- Compatibility facade for the standalone predicate language.
M.tokenize = predicate.tokenize
M.parse_predicate = predicate.parse_predicate
M.validate_vars = predicate.validate_vars
M.eval_ast = predicate.eval_ast
M.ast_to_heading = predicate.ast_to_heading
M.parse_expression = predicate.parse_expression
M.bind_columns = predicate.bind_columns
M.split_expressions = predicate.split_expressions
M.is_expression_input = predicate.is_expression_input
M.SYMBOLS = predicate.SYMBOLS

local function expand_asts(tbl, asts)
    local normalized, err = model.normalize(tbl)
    return result.bind(normalized, err, function(valid)
        local indices = {}
        for i, heading in ipairs(valid.headers) do
            indices[heading] = i
        end
        local columns, column_err = result.traverse(asts, function(ast)
            local bound, bind_err = M.bind_columns(ast, indices)
            return result.bind(bound, bind_err, function(expression)
                return {
                    heading = M.ast_to_heading(ast),
                    values = result.traverse(valid.rows, function(row)
                        return M.eval_ast(expression, row)
                    end),
                }
            end)
        end)
        return result.bind(columns, column_err, function(computed)
            return model.append_columns(valid, computed)
        end)
    end)
end

function M.expand_model(tbl, predicate_strings)
    local asts, err = result.traverse(predicate_strings, M.parse_expression)
    if not asts then
        return nil, err
    end
    return expand_asts(tbl, asts)
end

function M.expand(tbl, predicate_strings)
    return legacy_parts(M.expand_model(tbl, predicate_strings))
end

-- Build a whole table from expressions separated by `|` or `,`. The variables
-- are whatever names the expressions mention, in order of first appearance;
-- each compound expression becomes a computed column. A bare variable adds no
-- column of its own, which makes it a way to pin the variable order
-- (`b | a | a -> b`). Returns headers, rows, or nil + an error message.
local function table_from_expressions(input)
    local parts, split_err = M.split_expressions(input, "|,")
    local asts, parse_err = result.bind(parts, split_err, function(expressions)
        return result.traverse(expressions, M.parse_expression)
    end)
    if not asts then
        return nil, parse_err
    end
    local vars, seen, compound = {}, {}, {}
    local discovered, discover_err = result.traverse(asts, predicate.variables)
    if not discovered then
        return nil, discover_err
    end
    for i, names in ipairs(discovered) do
        for _, name in ipairs(names) do
            if not seen[name] then
                seen[name] = true
                vars[#vars + 1] = name
            end
        end
        if asts[i].type ~= "var" then
            compound[#compound + 1] = asts[i]
        end
    end

    if #vars == 0 then
        return nil, "No variables in: " .. trim(input)
    end
    if #vars > 10 then
        return nil, "Too many variables (max 10)"
    end

    return expand_asts({ headers = vars, rows = model.generate_rows(#vars) }, compound)
end

-- The :TruthTable argument spelled out over several lines (a visual selection):
-- a line break is one more column delimiter. Blank lines are skipped.
function M.args_from_lines(lines)
    local parts = {}
    for _, line in ipairs(lines) do
        line = trim(line)
        if line ~= "" then
            parts[#parts + 1] = line
        end
    end
    return table.concat(parts, " | ")
end

-- Headers + rows for any :TruthTable argument: an integer N, a list of names,
-- or expressions (see M.is_expression_input). Returns nil + an error message
-- on failure.
function M.build_model(args)
    if M.is_expression_input(args) then
        return table_from_expressions(args)
    end

    local headers, err = M.parse_truth_table_args(args)
    if not headers then
        return nil, err
    end
    return { headers = headers, rows = model.generate_rows(#headers), encoding = "bits" }
end

function M.build_truth_table(args)
    return legacy_parts(M.build_model(args))
end

-- The compatibility adapters are the only edit paths that encode string cells.
local function edit_table(transform, tbl, index)
    return legacy_parts(transform(tbl, index))
end

function M.drop_row(tbl, index)
    return edit_table(model.drop_row, tbl, index)
end

function M.drop_column(tbl, index)
    return edit_table(model.drop_column, tbl, index)
end

function M.toggle_table(tbl)
    return edit_table(model.toggle, tbl)
end

-- Toggle every cell between 0/1 and F/T, returning fresh rows. The direction is decided by
-- the first data cell: T/F -> 0/1, otherwise 0/1 -> T/F. Returns the rows.
function M.toggle_cells(rows)
    local uses_tf = false
    if #rows > 0 and #rows[1] > 0 then
        local first = rows[1][1]
        uses_tf = (first == "T" or first == "F")
    end

    local replacements = uses_tf and { T = "1", F = "0" } or { ["1"] = "T", ["0"] = "F" }
    return result.traverse(rows, function(row)
        return result.traverse(row, function(cell)
            return replacements[cell] or cell
        end)
    end)
end

return M
