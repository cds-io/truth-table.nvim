-- Syntax trees of the predicate language: taking one apart and putting one
-- together, copying one through a transformation, its canonical form and its
-- text. Pure: trees in, trees out, and no input tree is changed. The parser
-- that makes them is truth-table.predicate; this module never reads source.
--
-- A tree is a table with a `type`: "var" (name), "reference" (index, from
-- :hN), "column" (index, with name or variable; what binding makes of the
-- two before it), "literal" (value, and the symbol it was typed as), "paren"
-- (expr), "not" (operand), or a binary operator's name (left, right).
local fp = require("truth-table.fp")
local result = require("truth-table.result")
local operators = require("truth-table.operators")
local BINARY, SYMBOLS = operators.BINARY, operators.SYMBOLS
local M = {}

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
            return fn(copy)
        end)
    elseif BINARY[node.type] then
        local left, err = M.transform(node.left, fn)
        return result.bind(left, err, function(mapped_left)
            local right, right_err = M.transform(node.right, fn)
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
    return M.transform(node, function(copy)
        if copy.type == "paren" then
            return copy.expr
        elseif copy.type == "not" then
            return { type = "not", operand = grouped(copy.operand) }
        elseif FLAT[copy.type] then
            return M.fold(copy.type, fp.map(M.operands(copy, copy.type), grouped))
        elseif BINARY[copy.type] then
            return { type = copy.type, left = grouped(copy.left), right = grouped(copy.right) }
        end
        return copy
    end)
end

-- Print a tree as it stands: parentheses come from its paren nodes alone. A
-- column bound from a reference prints as its label in quotes.
local function render(node)
    if node.type == "paren" then
        return "(" .. render(node.expr) .. ")"
    elseif node.type == "reference" then
        return ":h" .. node.index
    elseif node.type == "column" then
        return node.variable or ("“" .. node.name .. "”")
    elseif node.type == "var" then
        return node.name
    elseif node.type == "literal" then
        return node.symbol or tostring(node.value)
    elseif node.type == "not" then
        return SYMBOLS["not"] .. render(node.operand)
    elseif BINARY[node.type] then
        return render(node.left) .. " " .. SYMBOLS[node.type] .. " " .. render(node.right)
    end
end

-- The text of a tree, as a column heading: rendered from its canonical form,
-- so one expression has one text however its source grouped it.
function M.heading(node)
    return render(assert(M.canonical(node)))
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

return M
