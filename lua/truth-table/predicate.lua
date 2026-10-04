-- Predicate language: source -> AST -> bound AST -> Boolean value.
-- No table rendering or editor dependencies. Fallible operations use value, error.
local result = require("truth-table.result")
local M = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ---------------------------------------------------------------------------
-- Predicate language: tokenizer -> recursive-descent parser -> AST.
-- Precedence (loosest to tightest): iff, implies, xor, or, and, unary not, atom.
-- ---------------------------------------------------------------------------

-- Ordered from tightest to loosest. Every binary operator associates left.
local SYMBOLS = require("truth-table.symbols")

-- Token aliases, rendering, binding power, and Boolean semantics live together.
-- The keyword and rendered symbol come from truth-table.symbols so the
-- abbreviations stay in step; the aliases are extra spellings the tokenizer
-- accepts, and each one includes the rendered symbol so headings round-trip.
local OPERATORS = {
    { name = SYMBOLS.NOT.ascii, symbol = SYMBOLS.NOT.unicode, aliases = { SYMBOLS.NOT.unicode, "!" }, unary = true,
        apply = function(a) return a == 0 end },
    { name = SYMBOLS.AND.ascii, symbol = SYMBOLS.AND.unicode, aliases = { SYMBOLS.AND.unicode },
        apply = function(a, b) return a == 1 and b == 1 end },
    { name = SYMBOLS.OR.ascii, symbol = SYMBOLS.OR.unicode, aliases = { SYMBOLS.OR.unicode },
        apply = function(a, b) return a == 1 or b == 1 end },
    { name = SYMBOLS.XOR.ascii, symbol = SYMBOLS.XOR.unicode, aliases = { SYMBOLS.XOR.unicode },
        apply = function(a, b) return a ~= b end },
    { name = SYMBOLS.IMPLIES.ascii, symbol = SYMBOLS.IMPLIES.unicode,
        aliases = { SYMBOLS.IMPLIES.unicode, "⇒", "->", "=>" },
        apply = function(a, b) return a == 0 or b == 1 end },
    { name = SYMBOLS.IFF.ascii, symbol = SYMBOLS.IFF.unicode,
        aliases = { SYMBOLS.IFF.unicode, "=", "↔", "<->", "<=>" },
        apply = function(a, b) return a == b end },
}
local KEYWORDS, BINARY, SYMBOL_OPS, BY_NAME = {}, {}, {}, {}
M.SYMBOLS = {}
for index, operator in ipairs(OPERATORS) do
    KEYWORDS[operator.name] = true
    BY_NAME[operator.name] = operator
    operator.precedence = #OPERATORS - index + 1
    M.SYMBOLS[operator.name] = operator.symbol
    if not operator.unary then
        BINARY[operator.name] = true
    end
    for _, alias in ipairs(operator.aliases) do
        -- Preserve the existing tokenizer's public spelling for !.
        SYMBOL_OPS[#SYMBOL_OPS + 1] = { alias, alias == "!" and "!" or operator.name }
    end
end
M.SYMBOLS["!"] = M.SYMBOLS["not"]
-- Longest match handles overlapping spellings without order-sensitive aliases.
table.sort(SYMBOL_OPS, function(a, b)
    return #a[1] > #b[1]
end)

-- The constants: the digits, with ⊤ and ⊥ as further spellings of 1 and 0.
-- The words `true` and `false` are read as ⊤ and ⊥, the way `and` is read as
-- ∧, which reserves them: neither can name a column.
local CONSTANTS = { ["0"] = 0, ["1"] = 1, [SYMBOLS.TOP.unicode] = 1, [SYMBOLS.BOTTOM.unicode] = 0 }
local CONSTANT_WORDS = {
    [SYMBOLS.TOP.ascii] = SYMBOLS.TOP.unicode,
    [SYMBOLS.BOTTOM.ascii] = SYMBOLS.BOTTOM.unicode,
}

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

-- Compatibility adapter: binding owns name validation.
function M.validate_vars(node, header_set)
    local _, err = M.bind_columns(node, header_set)
    return err
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

-- ---------------------------------------------------------------------------
-- Taking trees apart and putting them together, for every module that does.
-- ---------------------------------------------------------------------------

function M.unparen(node)
    while node.type == "paren" do
        node = node.expr
    end
    return node
end

local function collect(node, op, out)
    local inner = M.unparen(node)
    if inner.type == op then
        collect(inner.left, op, out)
        collect(inner.right, op, out)
    else
        out[#out + 1] = node
    end
    return out
end

-- Operands of the `op` chain rooted at `node`, left to right. Parentheses
-- around a run of the same operator are transparent; any other operand is
-- kept whole, parentheses included.
function M.operands(node, op)
    return collect(node, op, {})
end

-- Left-nested chain of `op` over `operands`, splicing in any operand that is
-- itself an `op` chain so the result reads flat.
function M.fold(op, operands)
    local flat = {}
    for _, operand in ipairs(operands) do
        collect(operand, op, flat)
    end
    local chain = flat[1]
    for i = 2, #flat do
        chain = { type = op, left = chain, right = flat[i] }
    end
    return chain
end

-- Print a tree as it stands: parentheses come from its paren nodes alone.
local function render_ast(node, reference_text)
    if node.type == "paren" then
        return "(" .. render_ast(node.expr, reference_text) .. ")"
    elseif node.type == "reference" then
        return ":h" .. node.index
    elseif node.type == "column" then
        return node.variable or reference_text(node.name)
    elseif node.type == "var" then
        return node.name
    elseif node.type == "literal" then
        return node.symbol or tostring(node.value)
    elseif node.type == "not" then
        return M.SYMBOLS["not"] .. render_ast(node.operand, reference_text)
    elseif BINARY[node.type] then
        local left, right = render_ast(node.left, reference_text), render_ast(node.right, reference_text)
        return left .. " " .. M.SYMBOLS[node.type] .. " " .. right
    end
end

-- Headings and expressions are rendered from the canonical tree, so one
-- expression has one text however its source grouped it.
local function render(node, reference_text)
    return render_ast(assert(M.canonical(node)), reference_text)
end

function M.ast_to_heading(node)
    return render(node, function(name)
        return "“" .. name .. "”"
    end)
end

local function ast_to_expression(node)
    return render(node, function(name)
        return "[" .. name .. "]"
    end)
end

-- Parse source through the tokenizer/parser Result pipeline.
local function parse_source(input, node_spans)
    local tokens, err, locations = M.tokenize(input)
    local ast, parse_err = result.bind(tokens, err, function(values)
        locations.node_spans = node_spans
        return M.parse_predicate(values, locations)
    end)
    if not ast then
        return nil, 'Parse error in "' .. input .. '": ' .. parse_err
    end
    return ast
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

-- Post-order traversal copies every node before applying a result-producing
-- transformation. Shared by binding and variable discovery; inputs stay intact.
function M.transform_ast(node, fn)
    local copy = { type = node.type }
    if node.type == "paren" or node.type == "not" then
        local key = node.type == "paren" and "expr" or "operand"
        local child, err = M.transform_ast(node[key], fn)
        return result.bind(child, err, function(mapped)
            copy[key] = mapped
            return fn(copy)
        end)
    elseif BINARY[node.type] then
        local left, err = M.transform_ast(node.left, fn)
        return result.bind(left, err, function(mapped_left)
            local right, right_err = M.transform_ast(node.right, fn)
            return result.bind(right, right_err, function(mapped_right)
                copy.left, copy.right = mapped_left, mapped_right
                return fn(copy)
            end)
        end)
    elseif node.type == "var" then
        copy.name = node.name
    elseif node.type == "reference" then
        copy.index = node.index
    elseif node.type == "literal" then
        copy.value, copy.symbol = node.value, node.symbol
    elseif node.type == "column" then
        copy.index, copy.name, copy.variable = node.index, node.name, node.variable
    else
        return nil, "Unknown AST node: " .. tostring(node.type)
    end
    return fn(copy)
end

-- A run of ∧ or of ∨ means the same however it is grouped, and reads
-- correctly flat. ⊕ and ⇔ are associative too, but a flat run of either
-- misreads (A ⇔ B ⇔ C is true when A is true and B and C are false), so
-- their grouping stays visible, like that of →.
local FLAT = { ["and"] = true, ["or"] = true }

local function grouped(operand)
    return BINARY[operand.type] and { type = "paren", expr = operand } or operand
end

-- The canonical form of a tree: one tree, and so one text, for every way of
-- grouping and parenthesising the same expression. The source's parentheses
-- are dropped; a run of ∧ or of ∨ becomes one left-nested chain; and an
-- operand that is itself a binary expression is parenthesised, so a mix of
-- operators reads without recalling the binding order: (A ∧ B) ∨ C.
function M.canonical(node)
    -- The traversal is post-order, so a node's operands are canonical before
    -- the node is: any parentheses they had are gone, and a run among them
    -- is already one chain.
    return M.transform_ast(node, function(copy)
        if copy.type == "paren" then
            return copy.expr
        elseif copy.type == "not" then
            return { type = "not", operand = grouped(copy.operand) }
        elseif FLAT[copy.type] then
            local operands = {}
            for i, operand in ipairs(M.operands(copy, copy.type)) do
                operands[i] = grouped(operand)
            end
            return M.fold(copy.type, operands)
        elseif BINARY[copy.type] then
            return { type = copy.type, left = grouped(copy.left), right = grouped(copy.right) }
        end
        return copy
    end)
end

-- Resolve surface names once; evaluation uses row positions, never labels.
function M.bind_columns(node, columns, headers)
    return M.transform_ast(node, function(copy)
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
    local mapped, err = M.transform_ast(node, function(copy)
        if copy.type == "reference" then
            return nil, "Column references require an existing table"
        elseif copy.type == "var" and not seen[copy.name] then
            seen[copy.name] = true
            vars[#vars + 1] = copy.name
        end
        return copy
    end)
    return result.bind(mapped, err, function()
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

-- Root-only De Morgan rewrite, returning an independent tree. No automatic
-- double-negation simplification: that is a separate refactoring operation.
function M.de_morgan(node)
    local root = M.unparen(node)
    local rewritten
    if root.type == "not" then
        local operand = M.unparen(root.operand)
        if operand.type == "and" or operand.type == "or" then
            rewritten = {
                type = operand.type == "and" and "or" or "and",
                left = { type = "not", operand = operand.left },
                right = { type = "not", operand = operand.right },
            }
        end
    elseif root.type == "and" or root.type == "or" then
        local left, right = M.unparen(root.left), M.unparen(root.right)
        if left.type == "not" and right.type == "not" then
            rewritten = { type = "not", operand = {
                type = root.type == "and" and "or" or "and",
                left = left.operand, right = right.operand,
            } }
        end
    end
    if not rewritten then
        return nil, "No De Morgan rewrite applies to the whole expression"
    end
    return M.canonical(rewritten)
end

function M.de_morgan_expression(input)
    local ast, err = M.parse_expression(input)
    local rewritten, rewrite_err = result.bind(ast, err, M.de_morgan)
    return result.bind(rewritten, rewrite_err, ast_to_expression)
end

return M
