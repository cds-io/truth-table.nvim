-- truth-table core: the table pipeline, with no Neovim dependency.
--
-- Everything here is a plain function over strings and tables: no `vim.*`, no
-- buffers, no side effects. The predicate language lives in
-- truth-table.predicate, the table model in truth-table.table_model and the
-- Markdown codec in truth-table.markdown; this module composes them into the
-- table pipeline used by init.lua. Cells are the integers 0 and 1 throughout
-- and a table carries its encoding ("bits" or "tf") as a field; the codec is
-- the one place that spells them. The one thing that wants Neovim
-- (display-width measurement) is injectable: M.display_width has a pure
-- default, and setup() swaps in vim.fn.strdisplaywidth.

local M = {}
local fp = require("truth-table.fp")
local result = require("truth-table.result")
local model = require("truth-table.table_model")
local predicate = require("truth-table.predicate")
local trees = require("truth-table.trees")
local markdown = require("truth-table.markdown")
local karnaugh = require("truth-table.karnaugh")

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Every fallible operation returns one table, or nil and an error.
M.parse = markdown.parse_table_lines
M.find_table = markdown.find_table
M.column_index = markdown.column_index
M.split_expressions = predicate.split_expressions
M.drop_row = model.drop_row
M.drop_column = model.drop_column
M.toggle = model.toggle

-- The codecs take the width measurer as an argument; these close over the
-- injected one.
M.display_width = markdown.display_width
function M.format(tbl)
    return markdown.format(tbl, M.display_width)
end

-- Karnaugh analysis of one column (see truth-table.karnaugh for the fields)
-- and its rendering as Markdown lines: the map, when the column has two to
-- four inputs, followed by `heading ≡ formula`.
M.derive_karnaugh = karnaugh.derive
function M.format_karnaugh(analysis)
    return karnaugh.render(analysis, M.display_width)
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

local function expand_asts(tbl, asts)
    local normalized, err = model.normalize(tbl)
    return result.bind(normalized, err, function(valid)
        local indices = {}
        for i, heading in ipairs(valid.headers) do
            indices[heading] = i
        end
        local columns, column_err = result.traverse(asts, function(ast)
            local bound, bind_err = predicate.bind_columns(ast, indices, valid.headers)
            return result.bind(bound, bind_err, function(expression)
                return {
                    heading = trees.heading(expression),
                    values = result.traverse(valid.rows, function(row)
                        return predicate.eval_ast(expression, row)
                    end),
                }
            end)
        end)
        return result.bind(columns, column_err, function(computed)
            return model.append_columns(valid, computed)
        end)
    end)
end

function M.expand(tbl, predicate_strings)
    local asts, err = result.traverse(predicate_strings, predicate.parse_expression)
    if not asts then
        return nil, err
    end
    return expand_asts(tbl, asts)
end

-- Build a whole table from expressions separated by `|` or `,`. The variables
-- are whatever names the expressions mention, in order of first appearance;
-- each compound expression becomes a computed column. A bare variable adds no
-- column of its own, which makes it a way to pin the variable order
-- (`b | a | a -> b`). Returns the table, or nil + an error message.
local function table_from_expressions(input)
    local parts, split_err = predicate.split_expressions(input, "|,")
    local asts, parse_err = result.bind(parts, split_err, function(expressions)
        return result.traverse(expressions, predicate.parse_expression)
    end)
    if not asts then
        return nil, parse_err
    end
    local vars, seen = {}, {}
    local discovered, discover_err = result.traverse(asts, predicate.variables)
    if not discovered then
        return nil, discover_err
    end
    for _, names in ipairs(discovered) do
        for _, name in ipairs(names) do
            if not seen[name] then
                seen[name] = true
                vars[#vars + 1] = name
            end
        end
    end
    local compound = fp.filter(asts, function(ast)
        return ast.type ~= "var"
    end)

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
    local parts = fp.filter(fp.map(lines, trim), function(line)
        return line ~= ""
    end)
    return table.concat(parts, " | ")
end

-- The table for any :TruthTable argument: an integer N, a list of names, or
-- expressions (see predicate.is_expression_input). Returns nil + an error
-- message on failure.
function M.build(args)
    if predicate.is_expression_input(args) then
        return table_from_expressions(args)
    end

    local headers, err = M.parse_truth_table_args(args)
    if not headers then
        return nil, err
    end
    return { headers = headers, rows = model.generate_rows(#headers), encoding = "bits" }
end

return M
