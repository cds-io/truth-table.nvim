-- Normal forms of an expression: disjunctive (an ∨ of ∧ terms, each a
-- product of literals) and conjunctive (an ∧ of ∨ clauses), the one built as
-- the dual of the other. A literal is an atom (a variable, a column
-- reference) or its negation. Three passes: →, ⊕ and ⇔ unfolded and every
-- ¬ pushed onto an atom; the chains distributed, as lists of terms; the
-- terms tidied. Tidying keeps the form a normal form and no more: a term
-- holding a literal and its negation goes, a repeated literal or term
-- collapses, a term whose literals include another's goes (absorption), and
-- constants fold. Minimising past that (reduction, consensus) is the
-- Karnaugh map's job, so a ∨ ¬a stays as it is in a DNF.
--
-- Terms come in the order distribution meets them, left to right, with
-- literals as met, so the form reads against its source. Pure: a tree in,
-- a fresh tree out; the atoms are the source's own nodes.
local fp = require("truth-table.fp")
local trees = require("truth-table.trees")
local M = {}

-- Distributing doubles the terms per clause crossed, so a form is refused
-- past this many before tidying.
local MAX_TERMS = 256

local DUAL = { ["and"] = "or", ["or"] = "and" }
-- The constant each operator leaves alone, and the one that takes over.
local IDENTITY = { ["and"] = 1, ["or"] = 0 }
local DOMINATOR = { ["and"] = 0, ["or"] = 1 }

-- `node` with →, ⊕ and ⇔ unfolded and every ¬ on an atom; `negated` says
-- whether the result is the negation of `node`.
local function nnf(node, negated)
    node = trees.unparen(node)
    if node.type == "not" then
        return nnf(node.operand, not negated)
    end
    local unfolded = trees.unfold(node)
    if unfolded then
        return nnf(unfolded, negated)
    end
    if DUAL[node.type] then
        local op = negated and DUAL[node.type] or node.type
        return trees.binary(op, nnf(node.left, negated), nnf(node.right, negated))
    end
    if node.type == "literal" then
        return negated and trees.literal(1 - node.value) or node
    end
    return negated and trees.negation(node) or node
end

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

-- The terms of `node` (in negation normal form) as an `outer` chain of
-- `inner` chains: a list of terms, where an empty list is the outer
-- operator's identity and an empty term its dominator. Nil and the reason
-- when distributing would pass the cap.
local function distribute(node, outer, inner)
    node = trees.unparen(node)
    if node.type == outer then
        local left, err = distribute(node.left, outer, inner)
        if not left then
            return nil, err
        end
        local right
        right, err = distribute(node.right, outer, inner)
        if not right then
            return nil, err
        end
        for _, item in ipairs(right) do
            left[#left + 1] = item
        end
        return left
    elseif node.type == inner then
        local left, err = distribute(node.left, outer, inner)
        if not left then
            return nil, err
        end
        local right
        right, err = distribute(node.right, outer, inner)
        if not right then
            return nil, err
        end
        if #left * #right > MAX_TERMS then
            return nil, "The form would have more than " .. MAX_TERMS .. " terms"
        end
        local crossed = {}
        for _, first in ipairs(left) do
            for _, second in ipairs(right) do
                local literals = fp.map(first.literals, function(item)
                    return item
                end)
                for _, item in ipairs(second.literals) do
                    literals[#literals + 1] = item
                end
                local merged = term(literals)
                if merged then
                    crossed[#crossed + 1] = merged
                end
            end
        end
        return crossed
    elseif node.type == "literal" then
        if node.value == IDENTITY[outer] then
            return {}
        end
        return { term({}) }
    end
    return { term({ literal(node) }) }
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

-- The tree of `terms` as an `outer` chain of `inner` chains.
local function render(terms, outer, inner)
    if #terms == 0 then
        return trees.literal(IDENTITY[outer])
    end
    if #terms[1].literals == 0 then
        return trees.literal(DOMINATOR[outer])
    end
    return trees.fold(
        outer,
        fp.map(terms, function(item)
            return trees.fold(
                inner,
                fp.map(item.literals, function(found)
                    return found.node
                end)
            )
        end)
    )
end

local function form(ast, outer, inner)
    local terms, err = distribute(nnf(ast, false), outer, inner)
    if not terms then
        return nil, err
    end
    return render(tidy(terms), outer, inner)
end

-- The disjunctive normal form of `ast`: an ∨ of ∧ terms of literals, or a
-- constant. Nil and the reason past the cap.
function M.dnf(ast)
    return form(ast, "or", "and")
end

-- The conjunctive normal form: an ∧ of ∨ clauses of literals, or a constant.
function M.cnf(ast)
    return form(ast, "and", "or")
end

return M
