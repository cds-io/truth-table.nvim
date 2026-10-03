-- Cursor-targeted rewrites of a predicate AST: factor, distribute, commute.
-- Pure: trees in, trees out. Inputs come from predicate.parse_located, whose
-- node spans say where the cursor is; outputs are fresh trees without spans.
local predicate = require("truth-table.predicate")
local M = {}

-- A chain is a maximal run of one of these operators, read as a flat operand
-- list. They are the associative, commutative ones, which is what makes the
-- flat reading sound; implication is neither, so it is always one operand.
local CHAIN = { ["and"] = true, ["or"] = true, xor = true, iff = true }

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

return M
