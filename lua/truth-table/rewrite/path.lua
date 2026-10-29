-- Where a rewrite looks: the path from a tree's root down to the node under
-- a cursor byte, the chains (maximal runs of one associative, commutative
-- operator, read flat) a node is an operand of, and the tests the rewrites
-- make on that path. Shared by every rule family under rewrite/, so it
-- holds none of the rules. Pure.
local trees = require("truth-table.trees")
local fp = require("cds.fp")
local M = {}

local unparen, operands, children = trees.unparen, trees.operands, trees.children

-- A chain is a maximal run of one of these operators, read as a flat operand
-- list. They are the associative, commutative ones, which is what makes the
-- flat reading sound; implication is neither, so it is always one operand.
local CHAIN = { ["and"] = true, ["or"] = true, xor = true, iff = true }
local DUAL = { ["and"] = "or", ["or"] = "and" }

local NO_TARGET = "Put the cursor on an operand"
M.CHAIN, M.DUAL, M.NO_TARGET = CHAIN, DUAL, NO_TARGET

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
    local member, position = fp.find(members, function(candidate)
        return candidate == path[index]
    end)
    if member then
        return { op = op, top = top, slot = slot, operands = members, index = position }
    end
end

-- The nearest ancestor on `path` above `index` that is no parenthesis.
local function enclosing(path, index)
    for above = index - 1, 1, -1 do
        if path[above].type ~= "paren" then
            return path[above]
        end
    end
end

-- Is the node at `index` inside a run of its own operator? Then it is no
-- site of its own: the run's root is.
local function chain_internal(path, index)
    local above = enclosing(path, index)
    return above ~= nil and above.type == unparen(path[index]).type and DUAL[above.type] ~= nil
end

M.path_to, M.paths, M.is_operand, M.locate = path_to, paths, is_operand, locate
M.chain_at, M.enclosing, M.chain_internal = chain_at, enclosing, chain_internal

return M
