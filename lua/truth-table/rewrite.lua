-- Cursor-targeted rewrites of a predicate AST: factor, distribute, commute,
-- exclusive-or recognition, De Morgan, and the collapsing laws (simplify);
-- and `moves`, every one of them the expression allows, wherever it applies.
-- Pure: trees in, trees out. Inputs come from predicate.parse_located, whose
-- node spans say where the cursor is; outputs are fresh trees without spans,
-- in canonical form (trees.canonical), which is where their grouping and
-- parentheses are decided. A rewrite returns { value, change }: the new tree
-- and the record of the change that made it, the law, the trees before and
-- after, the text of the one after, and the terms it consumed and produced
-- as nodes and as byte ranges in each tree's text; or nil and the reason it
-- does not apply. Which terms those are is data beside the trees, never a
-- flag inside them. Inside, every rewrite drafts what it finds as
-- { tree, law, consumed, produced }, each draft in order of preference, with
-- the reason when there are none; `completed` makes the record of a draft.
-- The command takes the first draft, and `moves` takes them all.
local trees = require("truth-table.trees")
local operators = require("truth-table.operators")
local SYMBOLS = require("truth-table.symbols")
local fp = require("truth-table.fp")
local M = {}

-- A chain is a maximal run of one of these operators, read as a flat operand
-- list. They are the associative, commutative ones, which is what makes the
-- flat reading sound; implication is neither, so it is always one operand.
local CHAIN = { ["and"] = true, ["or"] = true, xor = true, iff = true }
local DUAL = { ["and"] = "or", ["or"] = "and" }

local NO_TARGET = "Put the cursor on an operand"
-- Distributing moves an operand into a group and factoring moves a shared
-- one out: the one law, used from either side. The justification names the
-- side, so a step says which command wrote it.
local DISTRIBUTING = "distributivity (distributing)"
local FACTORING = "distributivity (factoring)"
local DE_MORGAN = "De Morgan"

local unparen, operands, fold, children = trees.unparen, trees.operands, trees.fold, trees.children

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

local function contains(node, byte, positions)
    local span = node.span or positions[node]
    return span.start_byte <= byte and byte <= span.end_byte
end

-- Nodes from the root down to the smallest one whose span holds `byte`.
local function path_to(root, byte)
    local positions = root.span and {} or trees.positions(root)
    local path, node = {}, root
    while node and contains(node, byte, positions) do
        path[#path + 1] = node
        local below = children(node)
        node = nil
        for _, child in ipairs(below) do
            if contains(child, byte, positions) then
                node = child
            end
        end
    end
    return path
end

-- The path from the root down to every node, outermost first and left to
-- right.
local function paths(root)
    local found, path = {}, {}
    local function visit(node)
        path[#path + 1] = node
        local copy = {}
        for depth, step in ipairs(path) do
            copy[depth] = step
        end
        found[#found + 1] = copy
        for _, child in ipairs(children(node)) do
            visit(child)
        end
        path[#path] = nil
    end
    visit(root)
    return found
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

-- The operand rewrites take their target as a path and the target's index in
-- it; the tree is path[1]. This makes one the rewrite of the operand under
-- the cursor.
local function at_cursor(rewrite_at)
    return function(ast, byte, ...)
        local path, index = locate(ast, byte)
        if not path then
            return {}, index
        end
        return rewrite_at(path, index, ...)
    end
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

-- The record of one rewrite, from its draft: the draft's tree in canonical
-- form with its text, the consumed terms as byte ranges in the input's
-- text, the produced ones in the result's. The produced nodes ride through
-- the canonical form by identity, outside the tree.
local function completed(ast, draft)
    local text, output, value, mapped = trees.rendered(draft.tree, draft.produced)
    local positions, input = ast.span and {} or trees.positions(ast), {}
    for _, node in ipairs(draft.consumed) do
        local span = node.span or positions[node]
        input[#input + 1] = { span.start_byte - 1, span.end_byte }
    end
    return {
        value = value,
        change = {
            law = draft.law, before = ast, after = value, text = text,
            consumed = draft.consumed, produced = mapped,
            consumed_ranges = input, produced_ranges = output,
        },
    }
end

-- The command of a rewrite: the record of its first draft, or nil and the
-- reason it found none.
local function operation(find)
    return function(ast, ...)
        local drafts, reason = find(ast, ...)
        if drafts[1] then
            return completed(ast, drafts[1])
        end
        return nil, reason
    end
end

-- A copy of the tree with `old` (matched by identity) replaced by `new`,
-- which goes in as it is, so the nodes inside it keep their identity.
local function substitute(node, old, new)
    return (trees.transform(node, function(copy, original)
        return original == old and new or copy
    end))
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
local function commute_at(path, index, backward)
    local chain = chain_at(path, index)
    local items, from = chain.operands, chain.index
    local to = backward and from - 1 or from + 1
    if to < 1 or to > #items then
        to = backward and from + 1 or from - 1
    end
    local moved = { items[math.min(from, to)], items[math.max(from, to)] }
    items[from], items[to] = items[to], items[from]
    return { {
        tree = substitute(path[1], path[chain.top], fold(chain.op, items)),
        law = "commutativity", consumed = moved, produced = moved,
    } }
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
    return { {
        tree = substitute(path[1], path[outer.top], fold(outer.op, terms)),
        law = FACTORING, consumed = pulled, produced = { factored },
    } }
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

            -- Each neighbour starts from a fresh list of the chain's operands.
            local items, first = operands(path[chain.top], chain.op), math.min(at, group_at)
            items[first] = fold(dual, products)
            local produced = { items[first] }
            table.remove(items, first + 1)
            found[#found + 1] = {
                tree = substitute(path[1], path[chain.top], fold(chain.op, items)),
                law = DISTRIBUTING,
                consumed = group_at > at and { target, group } or { group, target },
                produced = produced,
            }
        end
    end
    return found, "No neighbouring group to distribute " .. trees.heading(target) .. " into"
end
M.distribute = operation(at_cursor(distribute_at))

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
    return trees.binary(kind, a, b)
end

-- Recognise an exclusive or (or an equivalence) spelled out as two terms:
-- ¬A ∧ B ∨ A ∧ ¬B becomes A ⊕ B, and A ∧ B ∨ ¬A ∧ ¬B becomes A ⇔ B. The
-- product-of-sums spellings work the same way with the result flipped:
-- (A ∨ B) ∧ (¬A ∨ ¬B) is A ⊕ B. The cursor can be anywhere in either term.
local function xor_at(path, index)
    local found = {}
    -- From the target outward, every two-operand term of a dual chain that
    -- has a complementary partner in that chain, the nearest first.
    for at = index, 2, -1 do
        local chain = chain_at(path, at)
        local inner = chain and DUAL[chain.op]
        if inner and unparen(path[at]).type == inner then
            for partner in ipairs(chain.operands) do
                if partner ~= chain.index then
                    local low, high = math.min(chain.index, partner), math.max(chain.index, partner)
                    local recognised = recognise_pair(chain.operands[low], chain.operands[high], chain.op)
                    if recognised then
                        local items = operands(path[chain.top], chain.op)
                        items[low] = recognised
                        table.remove(items, high)
                        found[#found + 1] = {
                            tree = substitute(path[1], path[chain.top], fold(chain.op, items)),
                            law = "definition of " .. operators.SYMBOLS[recognised.type],
                            consumed = { chain.operands[low], chain.operands[high] },
                            produced = { recognised },
                        }
                    end
                end
            end
        end
    end
    return found, "No pair of terms under the cursor forms ⊕ or ⇔"
end
M.xor = operation(at_cursor(xor_at))

-- The draft of De Morgan at `node` of `ast`, or nil where it does not apply.
local function de_morgan_at(ast, node)
    local rewritten = trees.de_morgan(node)
    if rewritten then
        return { tree = substitute(ast, node, rewritten), law = DE_MORGAN, consumed = { node }, produced = { rewritten } }
    end
end

-- De Morgan at the nearest node, from the cursor outward, where it applies:
-- ¬(A ∧ B) becomes ¬A ∨ ¬B, and ¬A ∨ ¬B becomes ¬(A ∧ B) (dually for ∨).
-- Without a cursor inside the expression, only the whole expression is tried.
local function de_morgan(ast, byte)
    local path = byte and path_to(ast, byte) or {}
    for index = #path, 1, -1 do
        local draft = de_morgan_at(ast, path[index])
        if draft then
            return { draft }
        end
    end
    return { de_morgan_at(ast, ast) }, "No De Morgan rewrite applies under the cursor or to the whole expression"
end

M.de_morgan = operation(de_morgan)

-- ---------------------------------------------------------------------------
-- Simplify: the laws that shrink an expression. Each takes the operands of
-- one ∧ or ∨ chain and the position of one of them, the focus, and returns
-- the operands that remain, one list per way the law applies to the focus.
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
    return fp.filter(items, function(_, index)
        return index ~= dropped
    end)
end

-- The operands of `site` that a collapsing law made disappear: those its
-- result `new` does not keep (the laws keep an operand by identity). A site
-- that is no chain, a negation, goes whole.
local function gone(site, new)
    if site.type ~= "and" and site.type ~= "or" then
        return { site }
    end
    local kept = {}
    for _, item in ipairs(operands(new, site.type)) do
        kept[item] = true
    end
    local out = {}
    for _, item in ipairs(operands(site, site.type)) do
        if not kept[item] then
            out[#out + 1] = item
        end
    end
    return #out > 0 and out or { site }
end

-- A collapsing law may put a term in while leaving the other operands as
-- they were (a ∨ ¬a ∨ b becomes 1 ∨ b): what it produced is that term. One
-- that only removes terms produced what remains at the site.
local function replacement_terms(site, new)
    if not DUAL[site.type] then return { new } end
    local original, introduced = {}, {}
    for _, item in ipairs(operands(site, site.type)) do
        original[item] = true
    end
    for _, item in ipairs(operands(new, site.type)) do
        if not original[item] then
            introduced[#introduced + 1] = item
        end
    end
    return #introduced > 0 and introduced or { new }
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

-- In order of preference when several apply to one focus. A pairwise law
-- answers once per partner, in operand order.
local CHAIN_LAWS = {
    -- A ∨ ¬A is 1, and A ∧ ¬A is 0.
    { name = "complement", apply = function(items, at, op)
        local found = {}
        for other, item in ipairs(items) do
            if other ~= at and complement(items[at], item) then
                local kept = without(items, math.max(at, other))
                kept[math.min(at, other)] = trees.literal(DOMINATOR[op])
                found[#found + 1] = kept
            end
        end
        return found
    end },
    -- A ∨ 1 is 1, and A ∧ 0 is 0. The constant stays as it was typed.
    { name = "domination", apply = function(items, _, op)
        for _, item in ipairs(items) do
            if constant(item) == DOMINATOR[op] then
                return { { item } }
            end
        end
        return {}
    end },
    -- A ∨ 0 and A ∧ 1 are A.
    { name = "identity", apply = function(items, at, op)
        if constant(items[at]) == IDENTITY[op] then
            return { without(items, at) }
        end
        return {}
    end },
    -- A ∨ A is A. The first of the two stays.
    { name = "idempotence", apply = function(items, at, op)
        local found = {}
        for other, item in ipairs(items) do
            if other ~= at and within(items[at], item, DUAL[op]) and within(item, items[at], DUAL[op]) then
                found[#found + 1] = without(items, math.max(at, other))
            end
        end
        return found
    end },
    -- A ∨ A ∧ B is A: the focus absorbs every term that contains it, or is
    -- itself absorbed by a term it contains. A term with the focus's own
    -- factors is idempotence's.
    { name = "absorption", apply = function(items, at, op)
        local function absorbs(small, large)
            return within(small, large, DUAL[op]) and not within(large, small, DUAL[op])
        end
        local kept = {}
        for other, item in ipairs(items) do
            if other == at or not absorbs(items[at], item) then
                kept[#kept + 1] = item
            end
        end
        if #kept < #items then
            return { kept }
        end
        for other, item in ipairs(items) do
            if other ~= at and absorbs(item, items[at]) then
                return { without(items, at) }
            end
        end
        return {}
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
    end },
    -- A ∧ B ∨ ¬A ∧ B is B.
    { name = "reduction", apply = function(items, at, op)
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
    end },
}

-- Where a collapsing law can apply: every ¬, and the root of every ∧ or ∨
-- chain, innermost first. The nodes are the tree's own, so a caller can
-- match them by identity.
local function sites(ast)
    local out = {}
    local function visit(node, parent_op)
        if node.type == "paren" then
            visit(node.expr, parent_op)
        elseif node.type == "not" then
            visit(node.operand, nil)
            out[#out + 1] = node
        elseif node.left then
            visit(node.left, node.type)
            visit(node.right, node.type)
            if DUAL[node.type] and parent_op ~= node.type then
                out[#out + 1] = node
            end
        end
    end
    visit(ast, nil)
    return out
end

-- Every way a law collapses a site, as { new, law } with `new` the site's
-- replacement, in order of preference. A chain is tried with each of its
-- operands from `first` to `last` as the focus: all of them by default.
local function collapses(node, first, last)
    if node.type == "not" then
        local inner = unparen(node.operand)
        if inner.type == "literal" then
            -- A constant typed as a symbol flips to the other symbol.
            local flipped = inner.value == 1 and SYMBOLS.BOTTOM or SYMBOLS.TOP
            local symbol = inner.symbol and flipped.unicode or nil
            return { { new = trees.literal(1 - inner.value, symbol), law = "negation" } }
        elseif inner.type == "not" then
            return { { new = inner.operand, law = "double negation" } }
        end
        return {}
    end

    local items, found = operands(node, node.type), {}
    for at = first or 1, last or #items do
        for _, law in ipairs(CHAIN_LAWS) do
            for _, kept in ipairs(law.apply(items, at, node.type)) do
                found[#found + 1] = { new = fold(node.type, kept), law = law.name }
            end
        end
    end
    return found
end

-- The draft of one collapse, { new, law }, at `site` of `ast`: what the law
-- made disappear and what it put in.
local function draft_collapse(ast, site, collapsed)
    return {
        tree = substitute(ast, site, collapsed.new),
        law = collapsed.law,
        consumed = gone(site, collapsed.new),
        produced = replacement_terms(site, collapsed.new),
    }
end

-- The first law that fits at a site, as its collapse. With `on_path` (the
-- nodes over the cursor) a chain is tried only with its operand under the
-- cursor as the focus; without it, with each operand in turn.
local function collapse(node, on_path)
    local focus
    if on_path and node.type ~= "not" then
        for index, item in ipairs(operands(node, node.type)) do
            if on_path[item] then
                focus = index
            end
        end
        if not focus then
            return nil
        end
    end
    return collapses(node, focus, focus)[1]
end

-- Apply one collapsing law (complement, domination, identity, idempotence,
-- absorption, reduction, or the removal of a negated constant or a double
-- negation) and say which. The nearest match wins: a law involving the
-- operand under the cursor, then one inside whatever the cursor selects,
-- then one in a chain around the cursor, then one anywhere. Without a cursor
-- in the expression only the last applies. ⊕, ⇔ and → are left as they are.
local function simplify(ast, byte)
    local positions = ast.span and {} or trees.positions(ast)
    local path = byte and path_to(ast, byte) or {}
    local on_path, target = {}, path[#path]
    for _, node in ipairs(path) do
        on_path[node] = true
    end
    local function around(site)
        return on_path[site]
    end
    local function inside(site)
        if not target then return false end
        local selected, span = target.span or positions[target], site.span or positions[site]
        return selected.start_byte <= span.start_byte and span.end_byte <= selected.end_byte
    end
    local function anywhere()
        return true
    end

    local all = sites(ast)
    local passes = {
        { within = around, focus = on_path },
        { within = inside },
        { within = around },
        { within = anywhere },
    }
    for _, pass in ipairs(passes) do
        for _, site in ipairs(all) do
            if pass.within(site) then
                local collapsed = collapse(site, pass.focus)
                if collapsed then
                    return { draft_collapse(ast, site, collapsed) }
                end
            end
        end
    end
    return {}, "No simplification applies to this expression"
end

M.simplify = operation(simplify)

-- ---------------------------------------------------------------------------
-- Moves: where a rewrite above answers for one cursor position, this lists
-- what all of them give from every position.
-- ---------------------------------------------------------------------------

-- The operand rewrites, in the order their results are listed.
local OPERAND_REWRITES = {
    xor_at,
    factor_at,
    distribute_at,
    commute_at,
    function(path, index)
        return commute_at(path, index, true)
    end,
}

-- Every rewrite the expression allows, as { law, rewritten, text }: one
-- entry per distinct result, `rewritten` its { value, change }. The laws that shrink
-- the expression come first, then De Morgan, ⊕ and ⇔ recognition, factoring,
-- distributing and, the most numerous, the swaps. The shrinking laws go
-- innermost site first, as simplify tries them, and the rest outermost
-- first; all of them left to right. A result reached twice keeps its first
-- law, and one that reads the same as the expression is left out.
function M.moves(ast)
    local found, seen = {}, { [trees.heading(ast)] = true }
    local function add(draft)
        local rewritten = completed(ast, draft)
        local text = rewritten.change.text
        if not seen[text] then
            seen[text] = true
            found[#found + 1] = { law = draft.law, rewritten = rewritten, text = text }
        end
    end

    for _, site in ipairs(sites(ast)) do
        for _, collapsed in ipairs(collapses(site)) do
            add(draft_collapse(ast, site, collapsed))
        end
    end

    local everywhere, operand_paths = paths(ast), {}
    for _, path in ipairs(everywhere) do
        local draft = de_morgan_at(ast, path[#path])
        if draft then
            add(draft)
        end
        if is_operand(path, #path) then
            operand_paths[#operand_paths + 1] = path
        end
    end

    for _, rewrite_at in ipairs(OPERAND_REWRITES) do
        for _, path in ipairs(operand_paths) do
            for _, draft in ipairs((rewrite_at(path, #path))) do
                add(draft)
            end
        end
    end
    return found
end

return M
