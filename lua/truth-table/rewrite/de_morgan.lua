-- De Morgan at a site: a negation pushes in over the chain it negates, and
-- a chain contracts a run of two or more adjacent negated operands into one
-- negation. The command finds the nearest site from the cursor outward;
-- `de_morgan_at` and `runs` are what `moves` calls at every site. Pure.
local trees = require("truth-table.trees")
local walk = require("truth-table.rewrite.path")
local drafting = require("truth-table.rewrite.draft")
local fp = require("cds.fp")
local M = {}

local unparen, operands, fold = trees.unparen, trees.operands, trees.fold
local DUAL, path_to, chain_internal = walk.DUAL, walk.path_to, walk.chain_internal
local operation, substitute = drafting.operation, drafting.substitute

local DE_MORGAN = "De Morgan"

local function negated(item)
    return unparen(item).type == "not"
end

-- The run of adjacent negated operands of `items` holding the one at
-- `focus`: its first and last indices, or nil when that operand is no
-- negation. Without a focus the run is every operand, when all are negated.
local function run_around(items, focus)
    if not focus then
        if not fp.all(items, negated) then
            return nil
        end
        return 1, #items
    end
    if not negated(items[focus]) then
        return nil
    end
    local first, last = focus, focus
    while first > 1 and negated(items[first - 1]) do
        first = first - 1
    end
    while last < #items and negated(items[last + 1]) do
        last = last + 1
    end
    return first, last
end

-- De Morgan at one site. A negation pushes in over the chain it negates. A
-- chain contracts a run of two or more adjacent negated operands into one
-- negation: the run holding the operand at `focus`, or every operand when
-- there is no focus. Nil when neither applies.
local function de_morgan_at(ast, node, focus)
    local inner = unparen(node)
    if inner.type == "not" or not DUAL[inner.type] then
        local rewritten = trees.de_morgan(node)
        if rewritten then
            return {
                tree = substitute(ast, node, rewritten),
                law = DE_MORGAN,
                consumed = { node },
                produced = { rewritten },
            }
        end
        return nil
    end
    local items = operands(node, inner.type)
    local first, last = run_around(items, focus)
    if not first or last == first then
        return nil
    end
    if first == 1 and last == #items then
        local rewritten = trees.de_morgan(node)
        return {
            tree = substitute(ast, node, rewritten),
            law = DE_MORGAN,
            consumed = { node },
            produced = { rewritten },
        }
    end
    local run = fp.filter(items, function(_, index)
        return index >= first and index <= last
    end)
    local kept = {}
    local contracted = trees.de_morgan(fold(inner.type, run))
    for index, item in ipairs(items) do
        if index == first then
            kept[#kept + 1] = contracted
        elseif index < first or index > last then
            kept[#kept + 1] = item
        end
    end
    return {
        tree = substitute(ast, node, fold(inner.type, kept)),
        law = DE_MORGAN,
        consumed = run,
        produced = { contracted },
    }
end

-- The index among `items` of the operand the path passes through below
-- `index`, or nil when the path ends at the chain itself.
local function focus_below(path, index, items)
    local positions = {}
    for position, item in ipairs(items) do
        positions[item] = position
    end
    for below = index + 1, #path do
        if positions[path[below]] then
            return positions[path[below]]
        end
    end
end

-- The runs of two or more adjacent negated operands of `items`, each as
-- the index of its first operand.
local function runs(items)
    local found, index = {}, 1
    while index <= #items do
        local first, last = run_around(items, index)
        if first and last > first then
            found[#found + 1] = first
            index = last + 1
        else
            index = index + 1
        end
    end
    return found
end

-- De Morgan at the nearest site, from the cursor outward, where it applies:
-- every negation and every chain root is a site, and the operand under the
-- cursor picks the run a chain contracts. ¬(A ∧ B ∧ C) becomes
-- ¬A ∨ ¬B ∨ ¬C, and ¬A ∨ ¬B ∨ C becomes ¬(A ∧ B) ∨ C (dually for ∨).
-- Without a cursor inside the expression, only the whole expression is
-- tried.
local function de_morgan(ast, byte)
    local path = byte and path_to(ast, byte) or {}
    for index = #path, 1, -1 do
        if not chain_internal(path, index) then
            local node = path[index]
            local focus
            if DUAL[unparen(node).type] then
                focus = focus_below(path, index, operands(node, unparen(node).type))
            end
            local draft = de_morgan_at(ast, node, focus)
            if draft then
                return { draft }
            end
        end
    end
    return { de_morgan_at(ast, ast) }, "No De Morgan rewrite applies under the cursor or to the whole expression"
end

M.de_morgan = operation(de_morgan)

M.de_morgan_at, M.runs = de_morgan_at, runs

return M
