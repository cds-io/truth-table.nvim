-- Cursor-targeted rewrites of a predicate AST: factor, distribute, commute,
-- exclusive-or recognition, De Morgan, and the collapsing laws (simplify).
-- Pure: trees in, trees out. Inputs come from predicate.parse_located, whose
-- node spans say where the cursor is; outputs are fresh trees without spans,
-- in canonical form (predicate.canonical), which is where their grouping and
-- parentheses are decided. A rewrite returns the new tree and the name of the
-- law it applied, or nil and the reason it does not apply.
local predicate = require("truth-table.predicate")
local SYMBOLS = require("truth-table.symbols")
local M = {}

-- A chain is a maximal run of one of these operators, read as a flat operand
-- list. They are the associative, commutative ones, which is what makes the
-- flat reading sound; implication is neither, so it is always one operand.
local CHAIN = { ["and"] = true, ["or"] = true, xor = true, iff = true }
local DUAL = { ["and"] = "or", ["or"] = "and" }

local NO_TARGET = "Put the cursor on an operand"
-- Distributing moves an operand into a group and factoring moves a shared
-- one out: the one law, used from either side.
local DISTRIBUTIVITY = "distributivity"
local DE_MORGAN = "De Morgan"

local unparen, operands, fold = predicate.unparen, predicate.operands, predicate.fold
-- A fresh tree without spans, in the form every grouping of it shares.
local canonical = predicate.canonical

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

local function contains(node, byte)
    return node.span.start_byte <= byte and byte <= node.span.end_byte
end

-- Nodes from the root down to the smallest one whose span holds `byte`.
local function path_to(root, byte)
    local path, node = {}, root
    while node and contains(node, byte) do
        path[#path + 1] = node
        local children = node.type == "paren" and { node.expr }
            or node.type == "not" and { node.operand }
            or node.left and { node.left, node.right }
            or {}
        node = nil
        for _, child in ipairs(children) do
            if contains(child, byte) then
                node = child
            end
        end
    end
    return path
end

local function is_operand(path, index)
    local parent = path[index - 1]
    return parent ~= nil and CHAIN[parent.type] and unparen(path[index]).type ~= parent.type
end

-- The target: the deepest node on the path that is an operand of a chain.
-- Returns the path and the target's index in it, or nil and a message.
local function locate(ast, byte)
    local path = path_to(ast, byte)
    for index = #path, 2, -1 do
        if is_operand(path, index) then
            return path, index
        end
    end
    return nil, NO_TARGET
end

-- The chain that path[index] is an operand of, or nil. `top` is the chain's
-- root and `slot` is that root with any parentheses around it, the node its
-- own parent sees; both are path indices. `index` is the operand's position
-- in the flat list.
local function chain_at(path, index)
    if not is_operand(path, index) then
        return nil
    end
    local op, top = path[index - 1].type, index - 1
    while true do
        local above = top - 1
        while path[above] and path[above].type == "paren" do
            above = above - 1
        end
        if not path[above] or path[above].type ~= op then
            break
        end
        top = above
    end
    local slot = top
    while path[slot - 1] and path[slot - 1].type == "paren" do
        slot = slot - 1
    end
    local members = operands(path[top], op)
    for position, member in ipairs(members) do
        if member == path[index] then
            return { op = op, top = top, slot = slot, operands = members, index = position }
        end
    end
end

-- A copy of the tree with `old` (matched by identity) replaced by `new`.
local function substitute(node, old, new)
    if node == old then
        return new
    elseif node.type == "paren" then
        return { type = "paren", expr = substitute(node.expr, old, new) }
    elseif node.type == "not" then
        return { type = "not", operand = substitute(node.operand, old, new) }
    elseif node.left then
        return {
            type = node.type,
            left = substitute(node.left, old, new),
            right = substitute(node.right, old, new),
        }
    end
    return node
end

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
function M.commute(ast, byte, backward)
    local path, index = locate(ast, byte)
    if not path then
        return nil, index
    end
    local chain = chain_at(path, index)
    local items, from = chain.operands, chain.index
    local to = backward and from - 1 or from + 1
    if to < 1 or to > #items then
        to = backward and from + 1 or from - 1
    end
    items[from], items[to] = items[to], items[from]
    return canonical(substitute(ast, path[chain.top], fold(chain.op, items))), "commutativity"
end

-- Pull the target out of every term of the enclosing dual chain that has it:
-- A ∧ T ∨ G ∧ T becomes T ∧ (A ∨ G), and dually for ∨ over ∧.
function M.factor(ast, byte)
    local path, index = locate(ast, byte)
    if not path then
        return nil, index
    end
    local target = path[index]
    local label = predicate.ast_to_heading(target)
    local inner = chain_at(path, index)
    local outer = DUAL[inner.op] and chain_at(path, inner.slot)
    if not outer or outer.op ~= DUAL[inner.op] then
        return nil, "Nothing to factor " .. label .. " out of"
    end

    local wanted = shape(target)
    local terms, remainders, position = {}, {}, nil
    for _, term in ipairs(outer.operands) do
        local parts = unparen(term).type == inner.op and operands(term, inner.op) or {}
        local rest, found = {}, false
        for _, part in ipairs(parts) do
            -- Only the first occurrence leaves: A ∧ A ∧ B keeps one A.
            if not found and shape(part) == wanted then
                found = true
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
        return nil, "Fewer than two terms share " .. label
    end

    local factored = { type = inner.op, left = target, right = fold(outer.op, remainders) }
    table.insert(terms, position, factored)
    return canonical(substitute(ast, path[outer.top], fold(outer.op, terms))), DISTRIBUTIVITY
end

-- Multiply the target into the dual group next to it (right neighbour first):
-- T ∧ (A ∨ G) becomes T ∧ A ∨ T ∧ G, and dually for ∨ over ∧.
function M.distribute(ast, byte)
    local path, index = locate(ast, byte)
    if not path then
        return nil, index
    end
    local target = path[index]
    local chain = chain_at(path, index)
    local dual = DUAL[chain.op]
    local at, group_at = chain.index, nil
    for _, candidate in ipairs({ at + 1, at - 1 }) do
        local operand = chain.operands[candidate]
        if not group_at and dual and operand and unparen(operand).type == dual then
            group_at = candidate
        end
    end
    if not group_at then
        return nil, "No neighbouring group to distribute " .. predicate.ast_to_heading(target) .. " into"
    end

    local products = {}
    for _, member in ipairs(operands(chain.operands[group_at], dual)) do
        -- The target stays on the side of the group it started on.
        products[#products + 1] = fold(chain.op, group_at > at and { target, member } or { member, target })
    end

    if #chain.operands > 2 then
        local items, first = chain.operands, math.min(at, group_at)
        items[first] = fold(dual, products)
        table.remove(items, first + 1)
        return canonical(substitute(ast, path[chain.top], fold(chain.op, items))), DISTRIBUTIVITY
    end

    -- The products take the chain's place.
    return canonical(substitute(ast, path[chain.top], fold(dual, products))), DISTRIBUTIVITY
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

-- Two two-operand terms whose operands are complements pair by pair: the
-- un-negated operands in the first term's order, and how many of the first
-- term's operands were the negated ones.
local function complementary(first, second)
    for _, order in ipairs({ { 1, 2 }, { 2, 1 } }) do
        local a, a_negated = complement(first[1], second[order[1]])
        local b, b_negated = complement(first[2], second[order[2]])
        if a and b then
            return a, b, (a_negated and 1 or 0) + (b_negated and 1 or 0)
        end
    end
end

-- Recognise two terms of an outer and/or chain, without changing either tree.
local function recognise_pair(first, second, op)
    local inner = DUAL[op]
    if not inner or unparen(first).type ~= inner or unparen(second).type ~= inner then
        return nil
    end
    local left, right = operands(first, inner), operands(second, inner)
    if #left ~= 2 or #right ~= 2 then
        return nil
    end
    local a, b, negated = complementary(left, right)
    if not a then
        return nil
    end
    -- p ∧ q ∨ ¬p ∧ ¬q is p ⇔ q; each negation among the first term's
    -- operands flips it. The dual starts from ⊕.
    local odd = negated % 2 == 1
    local kind = (odd == (op == "or")) and "xor" or "iff"
    return { type = kind, left = a, right = b }
end

-- Recognise an exclusive or (or an equivalence) spelled out as two terms:
-- ¬A ∧ B ∨ A ∧ ¬B becomes A ⊕ B, and A ∧ B ∨ ¬A ∧ ¬B becomes A ⇔ B. The
-- product-of-sums spellings work the same way with the result flipped:
-- (A ∨ B) ∧ (¬A ∨ ¬B) is A ⊕ B. The cursor can be anywhere in either term.
function M.xor(ast, byte)
    local path, index = locate(ast, byte)
    if not path then
        return nil, index
    end
    -- From the target outward, the first two-operand term of a dual chain
    -- that has a complementary partner in that chain.
    for at = index, 2, -1 do
        local chain = chain_at(path, at)
        local inner = chain and DUAL[chain.op]
        if inner and unparen(path[at]).type == inner then
            for partner in ipairs(chain.operands) do
                if partner ~= chain.index then
                    local low, high = math.min(chain.index, partner), math.max(chain.index, partner)
                    local recognised = recognise_pair(chain.operands[low], chain.operands[high], chain.op)
                    if recognised then
                        local items = chain.operands
                        items[low] = recognised
                        table.remove(items, high)
                        local law = "definition of " .. predicate.SYMBOLS[recognised.type]
                        return canonical(substitute(ast, path[chain.top], fold(chain.op, items))), law
                    end
                end
            end
        end
    end
    return nil, "No pair of terms under the cursor forms ⊕ or ⇔"
end

-- De Morgan at the nearest node, from the cursor outward, where it applies:
-- ¬(A ∧ B) becomes ¬A ∨ ¬B, and ¬A ∨ ¬B becomes ¬(A ∧ B) (dually for ∨).
-- Without a cursor inside the expression, only the whole expression is tried.
function M.de_morgan(ast, byte)
    local path = byte and path_to(ast, byte) or {}
    for index = #path, 1, -1 do
        local rewritten = predicate.de_morgan(path[index])
        if rewritten then
            return canonical(substitute(ast, path[index], rewritten)), DE_MORGAN
        end
    end
    local rewritten = predicate.de_morgan(ast)
    if not rewritten then
        return nil, "No De Morgan rewrite applies under the cursor or to the whole expression"
    end
    return rewritten, DE_MORGAN
end

-- ---------------------------------------------------------------------------
-- Simplify: the laws that shrink an expression. Each takes the operands of
-- one ∧ or ∨ chain and the position of one of them, the focus, and returns
-- the operands that remain when the law applies to the focus, else nil.
-- ---------------------------------------------------------------------------

-- Per chain operator: the constant that leaves the chain as it is, and the
-- one that decides it.
local IDENTITY = { ["and"] = 1, ["or"] = 0 }
local DOMINATOR = { ["and"] = 0, ["or"] = 1 }

local function constant(node)
    local inner = unparen(node)
    return inner.type == "literal" and inner.value or nil
end

local function without(items, dropped)
    local kept = {}
    for index, item in ipairs(items) do
        if index ~= dropped then
            kept[#kept + 1] = item
        end
    end
    return kept
end

-- A term's factors: its operands when it is a chain of `op`, else itself.
local function factors(term, op)
    return unparen(term).type == op and operands(term, op) or { term }
end

-- Does every factor of `small` appear among those of `large`? Then, in an ∨
-- chain of ∧ terms, `large` is true only where `small` already is (dually
-- for ∧ over ∨), which is what lets `small` absorb it.
local function within(small, large, op)
    local theirs = {}
    for _, factor in ipairs(factors(large, op)) do
        theirs[shape(factor)] = true
    end
    for _, factor in ipairs(factors(small, op)) do
        if not theirs[shape(factor)] then
            return false
        end
    end
    return true
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

-- In order of preference when several apply to one focus.
local CHAIN_LAWS = {
    -- A ∨ ¬A is 1, and A ∧ ¬A is 0.
    { name = "complement", apply = function(items, at, op)
        for other, item in ipairs(items) do
            if other ~= at and complement(items[at], item) then
                local kept = without(items, math.max(at, other))
                kept[math.min(at, other)] = { type = "literal", value = DOMINATOR[op] }
                return kept
            end
        end
    end },
    -- A ∨ 1 is 1, and A ∧ 0 is 0. The constant stays as it was typed.
    { name = "domination", apply = function(items, _, op)
        for _, item in ipairs(items) do
            if constant(item) == DOMINATOR[op] then
                return { item }
            end
        end
    end },
    -- A ∨ 0 and A ∧ 1 are A.
    { name = "identity", apply = function(items, at, op)
        if constant(items[at]) == IDENTITY[op] then
            return without(items, at)
        end
    end },
    -- A ∨ A is A. The first of the two stays.
    { name = "idempotence", apply = function(items, at, op)
        for other, item in ipairs(items) do
            if other ~= at and within(items[at], item, DUAL[op]) and within(item, items[at], DUAL[op]) then
                return without(items, math.max(at, other))
            end
        end
    end },
    -- A ∨ A ∧ B is A: the focus absorbs every term that contains it, or is
    -- itself absorbed by a term it contains.
    { name = "absorption", apply = function(items, at, op)
        local kept = {}
        for other, item in ipairs(items) do
            if other == at or not within(items[at], item, DUAL[op]) then
                kept[#kept + 1] = item
            end
        end
        if #kept < #items then
            return kept
        end
        for other, item in ipairs(items) do
            if other ~= at and within(item, items[at], DUAL[op]) then
                return without(items, at)
            end
        end
    end },
    -- A ∨ ¬A ∧ B is A ∨ B: every term holding the focus's complement loses
    -- it, or the focus loses the complement of another operand.
    { name = "absorption", apply = function(items, at, op)
        local kept, changed = {}, false
        for other, item in ipairs(items) do
            local stripped = other ~= at and strip(item, items[at], DUAL[op])
            kept[other] = stripped or item
            changed = changed or stripped ~= nil and stripped ~= false
        end
        if changed then
            return kept
        end
        for other, item in ipairs(items) do
            local stripped = other ~= at and strip(items[at], item, DUAL[op])
            if stripped then
                kept[at] = stripped
                return kept
            end
        end
    end },
    -- A ∧ B ∨ ¬A ∧ B is B.
    { name = "reduction", apply = function(items, at, op)
        for other in ipairs(items) do
            if other ~= at then
                local low, high = math.min(at, other), math.max(at, other)
                local merged = merge(items[low], items[high], DUAL[op])
                if merged then
                    local kept = without(items, high)
                    kept[low] = merged
                    return kept
                end
            end
        end
    end },
}

-- Where a collapsing law can apply: every ¬, and the root of every ∧ or ∨
-- chain, innermost first.
local function sites(node, parent_op, out)
    if node.type == "paren" then
        return sites(node.expr, parent_op, out)
    elseif node.type == "not" then
        sites(node.operand, nil, out)
        out[#out + 1] = node
    elseif node.left then
        sites(node.left, node.type, out)
        sites(node.right, node.type, out)
        if DUAL[node.type] and parent_op ~= node.type then
            out[#out + 1] = node
        end
    end
    return out
end

-- Apply the first law that fits at a site: the node to replace, its
-- replacement, and the law's name. With `on_path` (the nodes over the
-- cursor) a chain is tried only with its operand under the cursor as the
-- focus; without it, with each operand in turn.
local function collapse(node, on_path)
    if node.type == "not" then
        local inner = unparen(node.operand)
        if inner.type == "literal" then
            -- A constant typed as a symbol flips to the other symbol.
            local flipped = inner.value == 1 and SYMBOLS.BOTTOM or SYMBOLS.TOP
            local symbol = inner.symbol and flipped.unicode or nil
            return node, { type = "literal", value = 1 - inner.value, symbol = symbol }, "negation"
        elseif inner.type == "not" then
            return node, inner.operand, "double negation"
        end
        return nil
    end

    local items = operands(node, node.type)
    local first, last = 1, #items
    if on_path then
        first = nil
        for index, item in ipairs(items) do
            if on_path[item] then
                first, last = index, index
            end
        end
        if not first then
            return nil
        end
    end
    for at = first, last do
        for _, law in ipairs(CHAIN_LAWS) do
            local kept = law.apply(items, at, node.type)
            if kept then
                return node, fold(node.type, kept), law.name
            end
        end
    end
end

-- Apply one collapsing law (complement, domination, identity, idempotence,
-- absorption, reduction, or the removal of a negated constant or a double
-- negation) and say which. The nearest match wins: a law involving the
-- operand under the cursor, then one inside whatever the cursor selects,
-- then one in a chain around the cursor, then one anywhere. Without a cursor
-- in the expression only the last applies. ⊕, ⇔ and → are left as they are.
function M.simplify(ast, byte)
    local path = byte and path_to(ast, byte) or {}
    local on_path, target = {}, path[#path]
    for _, node in ipairs(path) do
        on_path[node] = true
    end
    local function around(site)
        return on_path[site]
    end
    local function inside(site)
        return target and target.span.start_byte <= site.span.start_byte and site.span.end_byte <= target.span.end_byte
    end
    local function anywhere()
        return true
    end

    local all = sites(ast, nil, {})
    local passes = {
        { within = around, focus = on_path },
        { within = inside },
        { within = around },
        { within = anywhere },
    }
    for _, pass in ipairs(passes) do
        for _, site in ipairs(all) do
            if pass.within(site) then
                local old, new, law = collapse(site, pass.focus)
                if old then
                    return canonical(substitute(ast, old, new)), law
                end
            end
        end
    end
    return nil, "No simplification applies to this expression"
end

return M
