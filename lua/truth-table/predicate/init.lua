-- Predicate language: source -> AST -> bound AST -> Boolean value. The
-- tokenizer, the parser, the evaluator and the binding of names to row
-- positions, with the helpers that read a :TruthTable argument. The operators
-- themselves are truth-table.operators; a tree once made is the business of
-- truth-table.trees. No table rendering or editor dependencies. Fallible
-- operations use value, error.
-- The tokenizer is tokenize.lua and the parser parse.lua; this composes the
-- two into the parse pipeline and holds the evaluator, the binding, and the
-- argument helpers.
local result = require("cds.result")
local operators = require("truth-table.operators")
local trees = require("truth-table.trees")
local tokenize = require("truth-table.predicate.tokenize")
local parse = require("truth-table.predicate.parse")
local KEYWORDS, BY_NAME, CONSTANT_WORDS = operators.KEYWORDS, operators.BY_NAME, operators.CONSTANT_WORDS
local trim = require("truth-table.text").trim
local M = {}

M.tokenize = tokenize.tokenize
M.parse_predicate = parse.parse_predicate

function M.eval_ast(node, ctx)
    if node.type == "paren" then
        return M.eval_ast(node.expr, ctx)
    elseif node.type == "column" then
        return ctx[node.index]
    elseif node.type == "reference" then
        return ctx[node.index]
    elseif node.type == "var" then
        return ctx[node.name]
    elseif node.type == "literal" then
        return node.value
    elseif BY_NAME[node.type] then
        local operator = BY_NAME[node.type]
        local left = M.eval_ast(operator.unary and node.operand or node.left, ctx)
        local right
        if not operator.unary then
            right = M.eval_ast(node.right, ctx)
        end
        return operator.apply(left, right) and 1 or 0
    end
end

-- Parse source through the tokenizer/parser Result pipeline.
local function parse_source(input, node_spans)
    local tokens, err = M.tokenize(input)
    local ast, parse_err = result.bind(tokens, err, function(values)
        return M.parse_predicate(values, { node_spans = node_spans, end_byte = #input + 1 })
    end)
    return result.context(ast, parse_err, 'Parse error in "' .. input .. '": ')
end

function M.parse_expression(input)
    return parse_source(input, false)
end

-- The same tree, each node carrying span = { start_byte, end_byte }: the
-- one-based, inclusive bytes of `input` it was read from. Cursor-targeted
-- rewrites use the spans to find the node under the cursor.
function M.parse_located(input)
    return parse_source(input, true)
end

-- Resolve surface names once; evaluation uses row positions, never labels.
function M.bind_columns(node, columns, headers)
    return trees.transform(node, function(copy)
        if copy.type == "reference" then
            if not headers or not headers[copy.index] then
                return nil, "Column reference out of range: :h" .. copy.index
            end
            return trees.column(copy.index, headers[copy.index])
        elseif copy.type == "var" then
            local index = columns[copy.name]
            if not index then
                return nil, "Unknown column: " .. copy.name
            end
            return trees.column(index, nil, copy.name)
        end
        return copy
    end)
end

-- Positional references contain no expression delimiters.
function M.split_expressions(input, delimiters)
    local parts, start, pos = {}, 1, 1
    while pos <= #input do
        local ch = input:sub(pos, pos)
        if delimiters:find(ch, 1, true) then
            local part = trim(input:sub(start, pos - 1))
            if part == "" then
                return nil, "Empty expression at position " .. start
            end
            parts[#parts + 1] = part
            pos = pos + 1
            start = pos
        else
            pos = pos + 1
        end
    end
    local last = trim(input:sub(start))
    if last == "" then
        return nil, "Empty expression at position " .. start
    end
    parts[#parts + 1] = last
    return parts
end

-- Variables in order of first appearance. Local accumulators never escape;
-- the observable operation is pure and reference errors short-circuit traversal.
function M.variables(node)
    local vars, seen = {}, {}
    local mapped, err = trees.transform(node, function(copy)
        if copy.type == "reference" then
            return nil, "Column references require an existing table"
        elseif copy.type == "var" and not seen[copy.name] then
            seen[copy.name] = true
            vars[#vars + 1] = copy.name
        end
        return copy
    end)
    return result.map(mapped, err, function()
        return vars
    end)
end

-- Does the :TruthTable argument use the expression form? The classic forms (an
-- integer, or a list of names) consist of word characters and spaces only, so
-- any other character, or an operator keyword or constant word among the
-- names, means expressions. N.B. this reserves those words: `:TruthTable p or q`
-- is the expression p ∨ q, where it used to be three variables.
function M.is_expression_input(args)
    if args:match("[^%w_%s]") then
        return true
    end
    for word in args:gmatch("%S+") do
        if KEYWORDS[word] or CONSTANT_WORDS[word] then
            return true
        end
    end
    return false
end

return M
