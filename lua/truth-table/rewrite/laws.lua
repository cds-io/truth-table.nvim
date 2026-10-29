-- The collapsing laws that shrink an ∧ or ∨ chain: complement, domination,
-- identity, idempotence, absorption, reduction, consensus. Each takes the
-- operands of one chain and the position of one of them, the focus, and
-- returns the operands that remain, one list per way the law applies to the
-- focus. simplify.lua tries them at each site. Pure.
local trees = require("truth-table.trees")
local walk = require("truth-table.rewrite.path")
local terms = require("truth-table.rewrite.terms")
local fp = require("cds.fp")
local M = {}

local fold = trees.fold
local DUAL = walk.DUAL
local complement, constant, without = terms.complement, terms.constant, terms.without
local factors, within, strip, merge = terms.factors, terms.within, terms.strip, terms.merge

-- Per chain operator: the constant that leaves the chain as it is, and the
-- one that decides it.
local IDENTITY = { ["and"] = 1, ["or"] = 0 }
local DOMINATOR = { ["and"] = 0, ["or"] = 1 }

-- In order of preference when several apply to one focus. A pairwise law
-- answers once per partner, in operand order.
local CHAIN_LAWS = {
    -- A ∨ ¬A is 1, and A ∧ ¬A is 0.
    {
        name = "complement",
        apply = function(items, at, op)
            local found = {}
            for other, item in ipairs(items) do
                if other ~= at and complement(items[at], item) then
                    local kept = without(items, math.max(at, other))
                    kept[math.min(at, other)] = trees.literal(DOMINATOR[op])
                    found[#found + 1] = kept
                end
            end
            return found
        end,
    },
    -- A ∨ 1 is 1, and A ∧ 0 is 0. The constant stays as it was typed.
    {
        name = "domination",
        apply = function(items, _, op)
            local item = fp.find(items, function(candidate)
                return constant(candidate) == DOMINATOR[op]
            end)
            return item and { { item } } or {}
        end,
    },
    -- A ∨ 0 and A ∧ 1 are A.
    {
        name = "identity",
        apply = function(items, at, op)
            if constant(items[at]) == IDENTITY[op] then
                return { without(items, at) }
            end
            return {}
        end,
    },
    -- A ∨ A is A. The first of the two stays.
    {
        name = "idempotence",
        apply = function(items, at, op)
            local found = {}
            for other, item in ipairs(items) do
                if other ~= at and within(items[at], item, DUAL[op]) and within(item, items[at], DUAL[op]) then
                    found[#found + 1] = without(items, math.max(at, other))
                end
            end
            return found
        end,
    },
    -- A ∨ A ∧ B is A: the focus absorbs every term that contains it, or is
    -- itself absorbed by a term it contains. A term with the focus's own
    -- factors is idempotence's.
    {
        name = "absorption",
        apply = function(items, at, op)
            local function absorbs(small, large)
                return within(small, large, DUAL[op]) and not within(large, small, DUAL[op])
            end
            local kept = fp.filter(items, function(item, other)
                return other == at or not absorbs(items[at], item)
            end)
            if #kept < #items then
                return { kept }
            end
            local absorbed = fp.any(items, function(item, other)
                return other ~= at and absorbs(item, items[at])
            end)
            return absorbed and { without(items, at) } or {}
        end,
    },
    -- A ∨ ¬A ∧ B is A ∨ B: every term holding the focus's complement loses
    -- it, or the focus loses the complement of another operand.
    {
        name = "absorption",
        apply = function(items, at, op)
            local kept, changed = {}, false
            for other, item in ipairs(items) do
                local stripped = other ~= at and strip(item, items[at], DUAL[op])
                kept[other] = stripped or item
                changed = changed or stripped ~= nil and stripped ~= false
            end
            if changed then
                return { kept }
            end
            local found = {}
            for other, item in ipairs(items) do
                local stripped = other ~= at and strip(items[at], item, DUAL[op])
                if stripped then
                    local result = {}
                    for index, operand in ipairs(items) do
                        result[index] = index == at and stripped or operand
                    end
                    found[#found + 1] = result
                end
            end
            return found
        end,
    },
    -- A ∧ B ∨ ¬A ∧ B is B.
    {
        name = "reduction",
        apply = function(items, at, op)
            local found = {}
            for other in ipairs(items) do
                if other ~= at then
                    local low, high = math.min(at, other), math.max(at, other)
                    local merged = merge(items[low], items[high], DUAL[op])
                    if merged then
                        local kept = without(items, high)
                        kept[low] = merged
                        found[#found + 1] = kept
                    end
                end
            end
            return found
        end,
    },
    -- A ∧ B ∨ ¬A ∧ C ∨ B ∧ C is A ∧ B ∨ ¬A ∧ C: the focus goes when two
    -- other terms split on an operand, one holding it and the other its
    -- complement, and the focus holds every other factor of both, of which
    -- there is at least one (a pair with none is complement's). Dually for
    -- an ∧ chain of ∨ terms.
    {
        name = "consensus",
        apply = function(items, at, op)
            local dual = DUAL[op]
            -- Does the focus hold every factor of `these` but the one at `split`?
            -- A lone factor leaves nothing to hold.
            local function covered(these, split)
                return #these == 1 or within(fold(dual, without(these, split)), items[at], dual)
            end
            for p = 1, #items do
                for q = p + 1, #items do
                    local left, right = factors(items[p], dual), factors(items[q], dual)
                    if p ~= at and q ~= at and #left + #right > 2 then
                        local split = fp.any(left, function(x, i)
                            return fp.any(right, function(y, j)
                                return complement(x, y) and covered(left, i) and covered(right, j)
                            end)
                        end)
                        if split then
                            return { without(items, at) }
                        end
                    end
                end
            end
            return {}
        end,
    },
}

M.LAWS = CHAIN_LAWS

return M
