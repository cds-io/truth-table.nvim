-- Predicate language: source -> AST -> bound AST -> Boolean value. The
-- tokenizer, the parser, the evaluator and the binding of names to row
-- positions, with the helpers that read a :TruthTable argument. The operators
-- themselves are truth-table.operators; a tree once made is the business of
-- truth-table.trees. No table rendering or editor dependencies. Fallible
-- operations use value, error.
local result = require("truth-table.result")
local operators = require("truth-table.operators")
local trees = require("truth-table.trees")
local OPERATORS, KEYWORDS, BY_NAME = operators.OPERATORS, operators.KEYWORDS, operators.BY_NAME
local SYMBOL_OPS, CONSTANTS, CONSTANT_WORDS = operators.SYMBOL_OPS, operators.CONSTANTS, operators.CONSTANT_WORDS
local M = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Tokenizer -> recursive-descent parser -> AST.
-- Precedence (loosest to tightest): iff, implies, xor, or, and, unary not, atom.

local function symbol_op_at(input, pos)
    for _, entry in ipairs(SYMBOL_OPS) do
        local symbol = entry[1]
        if input:sub(pos, pos + #symbol - 1) == symbol then
            return entry[2], #symbol
        end
    end
end

function M.tokenize(input)
    local tokens, spans = {}, {}
    local pos = 1
    local len = #input

    while pos <= len do
        local ws = input:match("^%s+", pos)
        if ws then
            pos = pos + #ws
        end
        if pos > len then
            break
        end

        local token_start = pos
        local ch = input:sub(pos, pos)
        local symbol_op, symbol_len = symbol_op_at(input, pos)

        if ch == ":" then
            local reference = input:match("^:h%d+", pos)
            if not reference or input:sub(pos + #reference, pos + #reference):match("[%w_:]") then
                return nil, "Invalid column reference at byte " .. pos .. "; expected :hN"
            end
            local index = tonumber(reference:sub(3))
            if index < 1 or index == math.huge then
                return nil, "Column reference must have a positive index at byte " .. pos
            end
            tokens[#tokens + 1] = { type = "reference", value = index }
            pos = pos + #reference
        elseif symbol_op then
            tokens[#tokens + 1] = { type = "op", value = symbol_op }
            pos = pos + symbol_len
        elseif ch == "(" or ch == ")" then
            tokens[#tokens + 1] = { type = "paren", value = ch }
            pos = pos + 1
        elseif ch:match("[A-Za-z_]") then
            local ident = input:match("^[A-Za-z_][A-Za-z0-9_]*", pos)
            if KEYWORDS[ident] then
                tokens[#tokens + 1] = { type = "op", value = ident }
            elseif CONSTANT_WORDS[ident] then
                tokens[#tokens + 1] = { type = "literal", value = CONSTANT_WORDS[ident] }
            else
                tokens[#tokens + 1] = { type = "ident", value = ident }
            end
            pos = pos + #ident
        else
            local character = input:match("^[^\128-\191][\128-\191]*", pos) or ch
            if not CONSTANTS[character] then
                return nil, "Unexpected character: " .. character .. " at byte " .. pos
            end
            tokens[#tokens + 1] = { type = "literal", value = character }
            pos = pos + #character
        end
        spans[#tokens] = { start_byte = token_start, end_byte = pos - 1 }
    end

    -- Optional third return keeps token records and value/error callers intact.
    return tokens, nil, { spans = spans, end_byte = len + 1 }
end

function M.parse_predicate(tokens, locations)
    local pos = 1

    local function peek()
        return tokens[pos]
    end

    local function consume()
        local tok = tokens[pos]
        pos = pos + 1
        return tok
    end

    local function failure(message)
        if locations then
            local span = locations.spans[pos]
            local byte = span and span.start_byte or locations.end_byte
            return nil, message .. " at byte " .. byte
        end
        return nil, message .. " at token " .. pos
    end

    local function expect(type, value)
        local tok = peek()
        if not tok or tok.type ~= type or (value and tok.value ~= value) then
            return failure("Expected " .. (value or type))
        end
        return consume()
    end

    -- When the locations ask for it (node_spans), every node records the bytes
    -- it was read from: first token through last. Evaluation and rendering
    -- ignore the field.
    local function located(node, first)
        if locations and locations.node_spans then
            node.span = {
                start_byte = locations.spans[first].start_byte,
                end_byte = locations.spans[pos - 1].end_byte,
            }
        end
        return node
    end

    local parse_expr

    local function parse_atom()
        local tok = peek()
        if not tok then
            return failure("Unexpected end of expression")
        end

        local first = pos
        if tok.type == "reference" then
            consume()
            return located({ type = "reference", index = tok.value }, first)
        elseif tok.type == "ident" then
            consume()
            return located({ type = "var", name = tok.value }, first)
        elseif tok.type == "literal" then
            consume()
            -- A constant typed as a symbol keeps it, so the heading renders
            -- as written; a digit is its own rendering.
            local value = CONSTANTS[tok.value]
            local symbol = tok.value ~= tostring(value) and tok.value or nil
            return located({ type = "literal", value = value, symbol = symbol }, first)
        elseif tok.type == "paren" and tok.value == "(" then
            consume()
            local node, err = parse_expr()
            if not node then
                return nil, err
            end
            local ok, err2 = expect("paren", ")")
            if not ok then
                return nil, err2 or "Expected closing parenthesis"
            end
            return located({ type = "paren", expr = node }, first)
        else
            return failure("Unexpected token: " .. tok.value)
        end
    end

    local function parse_unary()
        local tok = peek()
        if tok and tok.type == "op" and (tok.value == "not" or tok.value == "!") then
            local first = pos
            consume()
            local operand, err = parse_unary()
            if not operand then
                return nil, err
            end
            return located({ type = "not", operand = operand }, first)
        end
        return parse_atom()
    end

    -- Each precedence level is a left fold over the next tighter parser.
    local function chain(operand, operator)
        return function()
            local first = pos
            local left, err = operand()
            if not left then
                return nil, err
            end
            while peek() and peek().type == "op" and peek().value == operator do
                consume()
                local right, right_err = operand()
                if not right then
                    return nil, right_err
                end
                left = located({ type = operator, left = left, right = right }, first)
            end
            return left
        end
    end

    parse_expr = parse_unary
    for _, operator in ipairs(OPERATORS) do
        if not operator.unary then
            parse_expr = chain(parse_expr, operator.name)
        end
    end

    local ast, err = parse_expr()
    if not ast then
        return nil, err
    end

    if pos <= #tokens then
        return failure("Unexpected token after expression: " .. tokens[pos].value)
    end

    return ast
end

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
    local tokens, err, locations = M.tokenize(input)
    local ast, parse_err = result.bind(tokens, err, function(values)
        locations.node_spans = node_spans
        return M.parse_predicate(values, locations)
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
            return { type = "column", index = copy.index, name = headers[copy.index] }
        elseif copy.type == "var" then
            local index = columns[copy.name]
            if not index then
                return nil, "Unknown column: " .. copy.name
            end
            return { type = "column", index = index, variable = copy.name }
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
