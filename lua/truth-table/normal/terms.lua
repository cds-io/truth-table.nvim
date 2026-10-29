-- The terms of a normal form as data: a literal (an atom or its negation,
-- keyed by the atom's text), a term (its literals in order, each key's
-- sense), and the tidying that keeps a list of terms a normal form and no
-- more. Separate from the passes in init.lua so the term arithmetic reads
-- on its own. Pure.
local fp = require("cds.fp")
local trees = require("truth-table.trees")
local M = {}

-- A literal of a negation normal form, as { key, negated, node }: the key
-- is the atom's text, so two spellings of one atom meet.
local function literal(node)
    local atom, negated = trees.unparen(node), false
    if atom.type == "not" then
        atom, negated = trees.unparen(atom.operand), true
    end
    return { key = trees.heading(atom), negated = negated, node = node }
end

-- A term: its literals in order, and each key's sense.
local function term(literals)
    local out = { literals = {}, sense = {} }
    for _, item in ipairs(literals) do
        local seen = out.sense[item.key]
        if seen == nil then
            out.sense[item.key] = item.negated
            out.literals[#out.literals + 1] = item
        elseif seen ~= item.negated then
            -- A literal and its negation: the term is the inner operator's
            -- dominator, and goes.
            return nil
        end
    end
    return out
end

-- The text that identifies a term's set of literals, whatever their order.
local function signature(item)
    local keys = fp.map(item.literals, function(found)
        return found.key .. (found.negated and "-" or "+")
    end)
    table.sort(keys)
    return table.concat(keys, "\0")
end

-- Does every literal of `small` appear in `large`, with the same sense?
local function within(small, large)
    return fp.all(small.literals, function(item)
        return large.sense[item.key] == item.negated
    end)
end

-- The terms with repeats collapsed and absorbed terms gone: an empty term
-- takes the whole form, as the outer operator's dominator.
local function tidy(terms)
    if fp.any(terms, function(item)
        return #item.literals == 0
    end) then
        return { term({}) }
    end
    local distinct = fp.unique(terms, signature)
    return fp.filter(distinct, function(item, index)
        return not fp.any(distinct, function(other, position)
            return position ~= index and within(other, item)
        end)
    end)
end

M.literal, M.term, M.tidy = literal, term, tidy

return M
