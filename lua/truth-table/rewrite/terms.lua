-- How the rewrites compare terms: identity with parentheses ignored, the
-- complement of a term, a constant's value, and the factor relations the
-- collapsing laws test (one term's factors within another's, a term
-- stripped of a complement, two terms merged over the one factor they
-- differ in). Shared by the operand rules, the recognition of ⊕ and ⇔ and
-- the laws, so it holds none of them. Pure.
local trees = require("truth-table.trees")
local list = require("truth-table.list")
local fp = require("cds.fp")
local M = {}

local unparen, operands, fold = trees.unparen, trees.operands, trees.fold

-- Tree identity with every parenthesis ignored; operand order counts.
local function shape(node)
    node = unparen(node)
    if node.type == "var" then
        return node.name
    elseif node.type == "literal" then
        return tostring(node.value)
    elseif node.type == "reference" then
        return ":h" .. node.index
    elseif node.type == "not" then
        return "not(" .. shape(node.operand) .. ")"
    end
    return node.type .. "(" .. shape(node.left) .. "," .. shape(node.right) .. ")"
end

-- When one of the two operands is the negation of the other (parentheses
-- ignored): the un-negated one, and whether `a` was the negated one.
local function complement(a, b)
    local x, y = unparen(a), unparen(b)
    if y.type == "not" and shape(y.operand) == shape(x) then
        return a, false
    elseif x.type == "not" and shape(x.operand) == shape(y) then
        return b, true
    end
end

local function constant(node)
    local inner = unparen(node)
    return inner.type == "literal" and inner.value or nil
end

-- The items with the pair at `a` and `b` collapsed to `value`, standing
-- where the first of the two stood.
local function collapse(items, a, b, value)
    local low, high = math.min(a, b), math.max(a, b)
    return list.with(list.without(items, high), low, value)
end

-- A term's factors: its operands when it is a chain of `op`, else itself.
local function factors(term, op)
    return unparen(term).type == op and operands(term, op) or { term }
end

-- Does every factor of `small` appear among those of `large`? Then, in an ∨
-- chain of ∧ terms, `large` is true only where `small` already is (dually
-- for ∧ over ∨), which is what lets `small` absorb it.
local function within(small, large, op)
    local theirs = fp.set(factors(large, op), shape)
    return fp.all(factors(small, op), function(factor)
        return theirs[shape(factor)]
    end)
end

-- `term` without its factor that is the complement of `operand`, or nil when
-- it has none.
local function strip(term, operand, op)
    if unparen(term).type ~= op then
        return nil
    end
    local rest, found = {}, false
    for _, factor in ipairs(operands(term, op)) do
        if not found and complement(operand, factor) then
            found = true
        else
            rest[#rest + 1] = factor
        end
    end
    if not found then
        return nil
    end
    return fold(op, rest)
end

-- Two terms with the same factors but for one, plain in one term and negated
-- in the other: the factors they share, in the first term's order.
local function merge(first, second, op)
    local left, right = factors(first, op), factors(second, op)
    if #left < 2 or #left ~= #right then
        return nil
    end
    local used, shared, differing = {}, {}, 0
    for _, factor in ipairs(left) do
        local same, opposite
        for index, candidate in ipairs(right) do
            if not used[index] then
                if not same and shape(candidate) == shape(factor) then
                    same = index
                elseif not opposite and complement(factor, candidate) then
                    opposite = index
                end
            end
        end
        if same then
            used[same] = true
            shared[#shared + 1] = factor
        elseif opposite then
            used[opposite] = true
            differing = differing + 1
        else
            return nil
        end
    end
    if differing ~= 1 then
        return nil
    end
    return fold(op, shared)
end

M.shape, M.complement, M.constant, M.collapse = shape, complement, constant, collapse
M.factors, M.within, M.strip, M.merge = factors, within, strip, merge

return M
