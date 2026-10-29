-- The parser of the predicate language: tokens in, tree out, by recursive
-- descent with one left fold per precedence level. The second stage of the
-- pipeline in init.lua, on its own so the grammar reads apart from the
-- lexical rules. Pure.
local operators = require("truth-table.operators")
local trees = require("truth-table.trees")
local OPERATORS, CONSTANTS = operators.OPERATORS, operators.CONSTANTS
local M = {}

-- Tokenizer -> recursive-descent parser -> AST.
-- Precedence (loosest to tightest): iff, implies, xor, or, and, unary not, atom.

-- The tree of `tokens`, or nil and the reason at the byte of the token the
-- parser stopped on. `options.end_byte` is the byte after the source, for
-- a parser that runs out of tokens (the byte after the last token without
-- it); with `options.node_spans`, every node records the bytes it was read
-- from, first token through last, as `span`. Evaluation and rendering
-- ignore the field.
function M.parse_predicate(tokens, options)
    local pos = 1
    local last = tokens[#tokens]
    local end_byte = options and options.end_byte or (last and last.span.end_byte + 1 or 1)

    local function peek()
        return tokens[pos]
    end

    local function consume()
        local tok = tokens[pos]
        pos = pos + 1
        return tok
    end

    local function failure(message)
        local token = tokens[pos]
        return nil, message .. " at byte " .. (token and token.span.start_byte or end_byte)
    end

    local function expect(type, value)
        local tok = peek()
        if not tok or tok.type ~= type or (value and tok.value ~= value) then
            return failure("Expected " .. (value or type))
        end
        return consume()
    end

    local function located(node, first)
        if options and options.node_spans then
            node.span = {
                start_byte = tokens[first].span.start_byte,
                end_byte = tokens[pos - 1].span.end_byte,
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
            return located(trees.reference(tok.value), first)
        elseif tok.type == "ident" then
            consume()
            return located(trees.var(tok.value), first)
        elseif tok.type == "literal" then
            consume()
            -- A constant typed as a symbol keeps it, so the heading renders
            -- as written; a digit is its own rendering.
            local value = CONSTANTS[tok.value]
            local symbol = tok.value ~= tostring(value) and tok.value or nil
            return located(trees.literal(value, symbol), first)
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
            return located(trees.paren(node), first)
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
            return located(trees.negation(operand), first)
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
                left = located(trees.binary(operator, left, right), first)
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

return M
