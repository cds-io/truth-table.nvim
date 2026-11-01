-- The laws a tree is rewritten by whole: each connective's definition in
-- ∧, ∨ and ¬ (unfold), and De Morgan over the root. Both answer a fresh
-- tree over the operands' own nodes, and neither reads a cursor; the
-- cursor-targeted rewrites under rewrite/ call these at a site. Pure.
local fp = require("cds.fp")
local node_ = require("truth-table.trees.node")
local render = require("truth-table.trees.render")
local M = {}

local binary, negate, unparen, operands, fold = node_.binary, node_.negation, node_.unparen, node_.operands, node_.fold
local negated, canonical = node_.negated, render.canonical

-- Root-only De Morgan rewrite, returning an independent tree. No automatic
-- double-negation simplification: that is a separate refactoring operation.
-- Each connective's definition in ∧, ∨ and ¬, over its two operands.
local DEFINITIONS = {
    implies = function(a, b)
        return binary("or", negate(a), b)
    end,
    iff = function(a, b)
        return binary("or", binary("and", a, b), binary("and", negate(a), negate(b)))
    end,
    xor = function(a, b)
        return binary("or", binary("and", a, negate(b)), binary("and", negate(a), b))
    end,
}

-- `node` (parentheses around it ignored) replaced by its definition when it
-- is a →, ⊕ or ⇔, its operands going in as they are; nil otherwise. The
-- result is a fresh tree over the operands' own nodes.
function M.unfold(node)
    local inner = unparen(node)
    local define = DEFINITIONS[inner.type]
    return define and define(inner.left, inner.right)
end

-- The other operator of a De Morgan pair.
local DUAL = require("truth-table.operators").DUAL

-- De Morgan over the whole of `node`, in either direction, reading a run of
-- one operator as a flat list whatever its parentheses: ¬ over an ∧ or ∨
-- chain negates every operand and flips the operator; a chain whose
-- operands are all negations becomes one negation of the dual chain. The
-- result is in canonical form.
function M.de_morgan(node)
    local root = unparen(node)
    local rewritten
    if root.type == "not" then
        local operand = unparen(root.operand)
        if DUAL[operand.type] then
            rewritten = fold(DUAL[operand.type], fp.map(operands(operand, operand.type), negate))
        end
    elseif DUAL[root.type] then
        local items = operands(root, root.type)
        if fp.all(items, negated) then
            local inner = fp.map(items, function(item)
                return unparen(item).operand
            end)
            rewritten = negate(fold(DUAL[root.type], inner))
        end
    end
    if not rewritten then
        return nil, "No De Morgan rewrite applies to the whole expression"
    end
    return canonical(rewritten)
end

return M
