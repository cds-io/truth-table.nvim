-- A rewrite's draft and its record. Inside rewrite/, every rule drafts what
-- it finds as { tree, law, consumed, produced }, each draft in order of
-- preference, with the reason when there are none; `completed` makes the
-- record of a draft (the tree in canonical form with its text, the consumed
-- and produced terms as nodes and as byte ranges), `operation` makes the
-- command of a rule from its drafts, and `at_cursor` aims an operand rule
-- at the cursor. Pure.
local trees = require("truth-table.trees")
local walk = require("truth-table.rewrite.path")
local fp = require("cds.fp")
local M = {}

local locate = walk.locate

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

-- The record of one rewrite, from its draft: the draft's tree in canonical
-- form with its text, the consumed terms as byte ranges in the input's
-- text, the produced ones in the result's. The produced nodes ride through
-- the canonical form by identity, outside the tree.
local function completed(ast, draft)
    local text, output, value, mapped = trees.rendered(draft.tree, draft.produced)
    local positions = ast.span and {} or trees.positions(ast)
    local input = fp.map(draft.consumed, function(node)
        local span = node.span or positions[node]
        return { span.start_byte - 1, span.end_byte }
    end)
    return {
        value = value,
        change = {
            law = draft.law,
            before = ast,
            after = value,
            text = text,
            consumed = draft.consumed,
            produced = mapped,
            consumed_ranges = input,
            produced_ranges = output,
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

-- The draft that puts `rewritten` in place of `node` in `ast` by `law`:
-- the node consumed whole and the result produced whole.
local function replacement(ast, node, rewritten, law)
    return {
        tree = substitute(ast, node, rewritten),
        law = law,
        consumed = { node },
        produced = { rewritten },
    }
end

M.at_cursor, M.completed, M.operation = at_cursor, completed, operation
M.substitute, M.replacement = substitute, replacement

return M
