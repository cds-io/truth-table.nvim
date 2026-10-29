-- The nodes of a syntax tree: the constructors that make every node, and
-- the traversals that take a tree apart (unparen, children, the operands of
-- a chain) or copy one through a transformation. The canonical form and the
-- text are render.lua's, which is written over these; the laws over a tree
-- are laws.lua's. Pure: no input tree is changed.
local result = require("cds.result")
local operators = require("truth-table.operators")
local BINARY = operators.BINARY
local M = {}

function M.var(name)
    return { type = "var", name = name }
end

function M.reference(index)
    return { type = "reference", index = index }
end

-- A column is a bound variable or reference: `name` when a reference was
-- bound to a heading, `variable` when a variable was.
function M.column(index, name, variable)
    return { type = "column", index = index, name = name, variable = variable }
end

-- `symbol` is the constant as it was typed, when it was typed.
function M.literal(value, symbol)
    return { type = "literal", value = value, symbol = symbol }
end

function M.paren(expr)
    return { type = "paren", expr = expr }
end

function M.negation(operand)
    return { type = "not", operand = operand }
end

function M.binary(op, left, right)
    assert(BINARY[op], "Unknown binary operator: " .. tostring(op))
    return { type = op, left = left, right = right }
end

function M.unparen(node)
    while node.type == "paren" do
        node = node.expr
    end
    return node
end

-- A node's children, left to right: the one under a parenthesis or a
-- negation, the two of a binary operator, none for a leaf.
function M.children(node)
    if node.type == "paren" then
        return { node.expr }
    elseif node.type == "not" then
        return { node.operand }
    elseif BINARY[node.type] then
        return { node.left, node.right }
    end
    return {}
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
        chain = M.binary(op, chain, flat[i])
    end
    return chain
end

-- Post-order traversal that copies every node before applying a
-- result-producing transformation. Binding, variable discovery and the
-- canonical form are all written over it; inputs stay intact.
function M.transform(node, fn)
    local copy = { type = node.type }
    if node.type == "paren" or node.type == "not" then
        local key = node.type == "paren" and "expr" or "operand"
        local child, err = M.transform(node[key], fn)
        return result.bind(child, err, function(mapped)
            copy[key] = mapped
            return fn(copy, node)
        end)
    elseif BINARY[node.type] then
        local left, err = M.transform(node.left, fn)
        return result.bind(left, err, function(mapped_left)
            local right, right_err = M.transform(node.right, fn)
            return result.bind(right, right_err, function(mapped_right)
                copy.left, copy.right = mapped_left, mapped_right
                return fn(copy, node)
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
    return fn(copy, node)
end

return M
