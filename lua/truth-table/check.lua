-- The verdict on a derivation: each side judged against the side before it
-- over every assignment of their variables, and the first step that is not
-- an equivalence, with the assignment that breaks it. Pure: the block's
-- lines in, a record out. derivation.lua splits the lines into sides,
-- predicate.lua parses and evaluates them, table_model.lua lists the rows.
--
-- A step is judged over the union of both sides' variables, so a side that
-- drops one still ranges over it. The justification after the bar is the
-- writer's note and is not read. A column reference has a meaning inside a
-- table only, so a side that holds one is refused.
local derivation = require("truth-table.derivation")
local predicate = require("truth-table.predicate")
local model = require("truth-table.table_model")
local trees = require("truth-table.trees")
local SYMBOLS = require("truth-table.symbols")
local M = {}

-- The table commands take ten variables at most, and a step over more
-- would take longer than a table does, so the same cap applies.
local MAX_VARIABLES = 10

-- The first column reference in a tree, as it is written, or nil.
local function reference(node)
    if node.type == "reference" then
        return ":h" .. node.index
    end
    for _, child in ipairs(trees.children(node)) do
        local found = reference(child)
        if found then
            return found
        end
    end
end

-- Every side of `lines` in order, each with the row (from one) it is on,
-- its bytes, its tree and its variables; or nil and the reason a side
-- cannot be judged.
local function chain(lines)
    local sides = {}
    for row, line in ipairs(lines) do
        for _, side in ipairs(derivation.sides(line)) do
            local ast, err = predicate.parse_expression(side.text)
            if not ast then
                return nil, err
            end
            local found = reference(ast)
            if found then
                return nil, found .. " has no meaning outside a table"
            end
            sides[#sides + 1] = {
                row = row, first = side.first, last = side.last, separator = side.separator,
                ast = ast, variables = assert(predicate.variables(ast)),
            }
        end
    end
    return sides
end

-- The variables of both sides, in order of first appearance.
local function union(first, second)
    local names, seen = {}, {}
    for _, list in ipairs({ first, second }) do
        for _, name in ipairs(list) do
            if not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end
    return names
end

-- The first row of `names` under which the two trees differ, as the
-- assignment and the two values, or nil when none does.
local function differ(premise, conclusion, names)
    for _, row in ipairs(model.generate_rows(#names)) do
        local ctx = {}
        for i, name in ipairs(names) do
            ctx[name] = row[i]
        end
        local left, right = predicate.eval_ast(premise, ctx), predicate.eval_ast(conclusion, ctx)
        if left ~= right then
            local assignment = {}
            for i, name in ipairs(names) do
                assignment[i] = { name = name, value = row[i] }
            end
            return { assignment = assignment, premise = left, conclusion = right }
        end
    end
end

-- The verdict on the derivation `lines`, in order: { ok = true, steps = n }
-- when every step holds, or for the first step that fails { ok = false,
-- step, row, side = { first, last }, separator, assignment, premise,
-- conclusion }, with `row` the index into `lines` of the line holding the
-- conclusion, `side` and `separator` one-based bytes in it, `assignment` a
-- list of { name, value } and the two values the sides take under it. Nil
-- and a reason when a side cannot be judged.
function M.check(lines)
    local sides, err = chain(lines)
    if not sides then
        return nil, err
    end
    for k = 2, #sides do
        local premise, conclusion = sides[k - 1], sides[k]
        local names = union(premise.variables, conclusion.variables)
        if #names > MAX_VARIABLES then
            return nil, "Too many variables (max " .. MAX_VARIABLES .. ")"
        end
        local found = differ(premise.ast, conclusion.ast, names)
        if found then
            return {
                ok = false, step = k - 1, row = conclusion.row,
                side = { conclusion.first, conclusion.last }, separator = conclusion.separator,
                assignment = found.assignment, premise = found.premise, conclusion = found.conclusion,
            }
        end
    end
    return { ok = true, steps = math.max(#sides - 1, 0) }
end

-- A failing verdict as one line: the step, the assignment in order of
-- appearance, and the two values.
function M.message(verdict)
    local parts = {}
    for i, bound in ipairs(verdict.assignment) do
        parts[i] = bound.name .. "=" .. bound.value
    end
    local values = verdict.premise .. " " .. SYMBOLS.NOT_EQUIV.unicode .. " " .. verdict.conclusion
    if #parts == 0 then
        return "step " .. verdict.step .. ": " .. values
    end
    return "step " .. verdict.step .. ": " .. table.concat(parts, ", ") .. " gives " .. values
end

return M
