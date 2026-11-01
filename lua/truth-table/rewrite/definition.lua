-- The definitions of →, ⊕ and ⇔, read both ways: xor recognises an
-- exclusive or (or an equivalence) spelled out as two terms of a chain, and
-- unfold replaces a connective by its definition in ∧, ∨ and ¬. Pure.
local trees = require("truth-table.trees")
local operators = require("truth-table.operators")
local walk = require("truth-table.rewrite.path")
local drafting = require("truth-table.rewrite.draft")
local terms = require("truth-table.rewrite.terms")
local M = {}

local unparen, operands, fold = trees.unparen, trees.operands, trees.fold
local DUAL, path_to, paths, chain_at = walk.DUAL, walk.path_to, walk.paths, walk.chain_at
local at_cursor, operation, substitute = drafting.at_cursor, drafting.operation, drafting.substitute
local replacement = drafting.replacement
local complement, collapse = terms.complement, terms.collapse

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
                        local items = collapse(operands(path[chain.top], chain.op), low, high, recognised)
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

-- ---------------------------------------------------------------------------
-- Unfold: a connective replaced by its definition in ∧, ∨ and ¬, the xor
-- rewrite read the other way.
-- ---------------------------------------------------------------------------

-- The draft unfolding path[index] of `ast`, or nil when it is no →, ⊕ or ⇔.
-- A connective in parentheses is taken with them, so the consumed term is
-- the parenthesised one: the node whose parent is a parenthesis waits for
-- that parent's turn.
local function unfold_at(ast, path, index)
    local node = path[index]
    if path[index - 1] and path[index - 1].type == "paren" then
        return nil
    end
    local rewritten = trees.unfold(node)
    if not rewritten then
        return nil
    end
    return replacement(ast, node, rewritten, "definition of " .. operators.SYMBOLS[unparen(node).type])
end

-- Unfold the nearest →, ⊕ or ⇔ enclosing the cursor (the node itself when
-- the cursor is on its symbol), or without a cursor inside the expression
-- the outermost one. A chain of ⊕ is nested pairs in the tree, so one step
-- unfolds one pair.
local function unfold(ast, byte)
    local path = byte and path_to(ast, byte) or {}
    for index = #path, 1, -1 do
        local draft = unfold_at(ast, path, index)
        if draft then
            return { draft }
        end
    end
    for _, whole in ipairs(paths(ast)) do
        local draft = unfold_at(ast, whole, #whole)
        if draft then
            return { draft }
        end
    end
    return {}, "No →, ⊕ or ⇔ under the cursor or in the expression"
end

M.unfold = operation(unfold)

M.xor_at, M.unfold_at = xor_at, unfold_at

return M
