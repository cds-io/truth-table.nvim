-- The operand rewrites: commute, factor and distribute, each of the
-- operand under the cursor within its chain. Distributing moves an operand
-- into a group and factoring moves a shared one out: the one law, used
-- from either side. Each rule is written over a path and the target's
-- index in it (the `_at` form, which `moves` calls from every position),
-- and `at_cursor` makes the command of it. Pure.
local trees = require("truth-table.trees")
local walk = require("truth-table.rewrite.path")
local drafting = require("truth-table.rewrite.draft")
local shape = require("truth-table.rewrite.terms").shape
local collapse = require("truth-table.rewrite.terms").collapse
local M = {}

local unparen, operands, fold = trees.unparen, trees.operands, trees.fold
local DUAL, locate, chain_at = walk.DUAL, walk.locate, walk.chain_at
local at_cursor, operation, substitute = drafting.at_cursor, drafting.operation, drafting.substitute

-- Distributing moves an operand into a group and factoring moves a shared
-- one out: the one law, used from either side. The justification names the
-- side, so a step says which command wrote it.
local DISTRIBUTING = "distributivity (distributing)"
local FACTORING = "distributivity (factoring)"

-- The operand under the cursor, as a node of `ast`.
function M.target(ast, byte)
    local path, index = locate(ast, byte)
    if not path then
        return nil, index
    end
    return path[index]
end

-- Swap the target with the operand on its right (left when `backward`). At
-- the end of the chain the direction flips, so a target always has a partner.
local function commute_at(path, index, backward)
    local chain = chain_at(path, index)
    local items, from = chain.operands, chain.index
    local to = backward and from - 1 or from + 1
    if to < 1 or to > #items then
        to = backward and from + 1 or from - 1
    end
    local moved = { items[math.min(from, to)], items[math.max(from, to)] }
    items[from], items[to] = items[to], items[from]
    return {
        {
            tree = substitute(path[1], path[chain.top], fold(chain.op, items)),
            law = "commutativity",
            consumed = moved,
            produced = moved,
        },
    }
end
M.commute = operation(at_cursor(commute_at))

-- Pull the target out of every term of the enclosing dual chain that has it:
-- A ∧ T ∨ G ∧ T becomes T ∧ (A ∨ G), and dually for ∨ over ∧.
local function factor_at(path, index)
    local target = path[index]
    local label = trees.heading(target)
    local inner = chain_at(path, index)
    local outer = DUAL[inner.op] and chain_at(path, inner.slot)
    if not outer or outer.op ~= DUAL[inner.op] then
        return {}, "Nothing to factor " .. label .. " out of"
    end

    local wanted = shape(target)
    local terms, remainders, position, pulled = {}, {}, nil, {}
    for _, term in ipairs(outer.operands) do
        local parts = unparen(term).type == inner.op and operands(term, inner.op) or {}
        local rest, found = {}, false
        for _, part in ipairs(parts) do
            -- Only the first occurrence leaves: A ∧ A ∧ B keeps one A.
            if not found and shape(part) == wanted then
                found = true
                pulled[#pulled + 1] = part
            else
                rest[#rest + 1] = part
            end
        end
        if found then
            remainders[#remainders + 1] = fold(inner.op, rest)
            position = position or #terms + 1
        else
            terms[#terms + 1] = term
        end
    end
    if #remainders < 2 then
        return {}, "Fewer than two terms share " .. label
    end

    local factored = { type = inner.op, left = target, right = fold(outer.op, remainders) }
    table.insert(terms, position, factored)
    return {
        {
            tree = substitute(path[1], path[outer.top], fold(outer.op, terms)),
            law = FACTORING,
            consumed = pulled,
            produced = { factored },
        },
    }
end
M.factor = operation(at_cursor(factor_at))

-- Multiply the target into the dual group next to it (right neighbour first):
-- T ∧ (A ∨ G) becomes T ∧ A ∨ T ∧ G, and dually for ∨ over ∧.
local function distribute_at(path, index)
    local target = path[index]
    local chain = chain_at(path, index)
    local dual = DUAL[chain.op]
    local at, found = chain.index, {}
    for _, group_at in ipairs({ at + 1, at - 1 }) do
        local group = chain.operands[group_at]
        if dual and group and unparen(group).type == dual then
            local products = {}
            for _, member in ipairs(operands(group, dual)) do
                -- The target stays on the side of the group it started on.
                products[#products + 1] = fold(chain.op, group_at > at and { target, member } or { member, target })
            end

            local product = fold(dual, products)
            local items = collapse(operands(path[chain.top], chain.op), at, group_at, product)
            found[#found + 1] = {
                tree = substitute(path[1], path[chain.top], fold(chain.op, items)),
                law = DISTRIBUTING,
                consumed = group_at > at and { target, group } or { group, target },
                produced = { product },
            }
        end
    end
    return found, "No neighbouring group to distribute " .. trees.heading(target) .. " into"
end
M.distribute = operation(at_cursor(distribute_at))

M.commute_at, M.factor_at, M.distribute_at = commute_at, factor_at, distribute_at

return M
