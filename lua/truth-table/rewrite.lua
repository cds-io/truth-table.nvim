-- Cursor-targeted rewrites of a predicate AST: factor, distribute, commute,
-- exclusive-or recognition, and De Morgan.
-- Pure: trees in, trees out. Inputs come from predicate.parse_located, whose
-- node spans say where the cursor is; outputs are fresh trees without spans.
local predicate = require("truth-table.predicate")
local M = {}

-- A chain is a maximal run of one of these operators, read as a flat operand
-- list. They are the associative, commutative ones, which is what makes the
-- flat reading sound; implication is neither, so it is always one operand.
local CHAIN = { ["and"] = true, ["or"] = true, xor = true, iff = true }
local DUAL = { ["and"] = "or", ["or"] = "and" }

local NO_TARGET = "Put the cursor on an operand"

local function unparen(node)
    while node.type == "paren" do
        node = node.expr
    end
    return node
end

local function paren(node)
    return { type = "paren", expr = node }
end

-- Operands of the `op` chain rooted at `node`, left to right. Parentheses
-- around a run of the same operator are transparent; any other operand is
-- kept whole, parentheses included.
local function operands(node, op, out)
    out = out or {}
    local inner = unparen(node)
    if inner.type == op then
        operands(inner.left, op, out)
        operands(inner.right, op, out)
    else
        out[#out + 1] = node
    end
    return out
end

-- Left-nested chain over `items`, splicing in any item that is itself an
-- `op` chain so the result reads flat.
local function fold(op, items)
    local flat = {}
    for _, item in ipairs(items) do
        operands(item, op, flat)
    end
    local chain = flat[1]
    for i = 2, #flat do
        chain = { type = op, left = chain, right = flat[i] }
    end
    return chain
end

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
        return paren(substitute(node.expr, old, new))
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

-- Fresh, span-free copy of a rewritten tree. A rewrite can leave a chain
-- operator directly under the same operator on the right (new terms merging
-- into their parent chain). The parser never produces that shape, so
-- re-folding it touches only what the rewrite built; left alone, the renderer
-- would parenthesise it.
local function finish(tree)
    return predicate.transform_ast(tree, function(copy)
        if CHAIN[copy.type] and copy.right.type == copy.type then
            local items = {}
            local function collect(node)
                if node.type == copy.type then
                    collect(node.left)
                    collect(node.right)
                else
                    items[#items + 1] = node
                end
            end
            collect(copy)
            local chain = items[1]
            for i = 2, #items do
                chain = { type = copy.type, left = chain, right = items[i] }
            end
            return chain
        end
        return copy
    end)
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
    return finish(substitute(ast, path[chain.top], fold(chain.op, items)))
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
    local terms, remainders, parenthesised, position = {}, {}, false, nil
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
            parenthesised = parenthesised or term.type == "paren"
            position = position or #terms + 1
        else
            terms[#terms + 1] = term
        end
    end
    if #remainders < 2 then
        return nil, "Fewer than two terms share " .. label
    end

    local factored = { type = inner.op, left = target, right = paren(fold(outer.op, remainders)) }
    -- Beside other terms, the new one keeps the parentheses its sources had.
    if #terms > 0 and parenthesised then
        factored = paren(factored)
    end
    table.insert(terms, position, factored)
    return finish(substitute(ast, path[outer.top], fold(outer.op, terms)))
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
        items[first] = paren(fold(dual, products))
        table.remove(items, first + 1)
        return finish(substitute(ast, path[chain.top], fold(chain.op, items)))
    end

    -- The products take the chain's place. When the chain was a parenthesised
    -- term of a dual chain they merge into it, each keeping those parentheses.
    local slot, parent = path[chain.slot], path[chain.slot - 1]
    if slot.type == "paren" and parent and parent.type == dual then
        for i, product in ipairs(products) do
            products[i] = paren(product)
        end
        return finish(substitute(ast, slot, fold(dual, products)))
    end
    return finish(substitute(ast, path[chain.top], fold(dual, products)))
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
                        return finish(substitute(ast, path[chain.top], fold(chain.op, items)))
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
            -- A negation binds tightest, so parentheses around the group it
            -- replaces are dropped with it.
            local replacement_index = index
            while rewritten.type == "not" and path[replacement_index - 1]
                and path[replacement_index - 1].type == "paren" do
                replacement_index = replacement_index - 1
            end
            return finish(substitute(ast, path[replacement_index], rewritten))
        end
    end
    local rewritten = predicate.de_morgan(ast)
    if not rewritten then
        return nil, "No De Morgan rewrite applies under the cursor or to the whole expression"
    end
    return rewritten
end

return M
