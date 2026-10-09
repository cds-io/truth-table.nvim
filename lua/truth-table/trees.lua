-- Syntax trees of the predicate language: taking one apart and putting one
-- together, copying one through a transformation, its canonical form and its
-- text. Pure: trees in, trees out, and no input tree is changed. The parser
-- that makes them is truth-table.predicate; this module never reads source.
--
-- A tree is a table with a `type`: "var" (name), "reference" (index, from
-- :hN), "column" (index, with name or variable; what binding makes of the
-- two before it), "literal" (value, and the symbol it was typed as), "paren"
-- (expr), "not" (operand), or a binary operator's name (left, right). A node
-- has no editor annotations. Provenance is supplied separately to rendered().
--
-- Every node is made by a constructor below; the parser and the rewrites
-- call them, and no other code spells a node. So the types a traversal
-- meets are the ones listed, `binary` is where a wrong operator name is
-- refused, and a tree transform() does not know is a programming error,
-- which rendered() raises on.
local fp = require("truth-table.fp")
local result = require("truth-table.result")
local operators = require("truth-table.operators")
local BINARY, SYMBOLS = operators.BINARY, operators.SYMBOLS
local M = {}

function M.var(name)
    return { type = "var", name = name }
end

function M.reference(index)
    return { type = "reference", index = index }
end

-- A column is a bound variable or reference: `name` when a reference was
-- bound to a heading, `variable` when a variable was.
function M.column(index, name, variable)
    return { type = "column", index = index, name = name, variable = variable }
end

-- `symbol` is the constant as it was typed, when it was typed.
function M.literal(value, symbol)
    return { type = "literal", value = value, symbol = symbol }
end

function M.paren(expr)
    return { type = "paren", expr = expr }
end

function M.negation(operand)
    return { type = "not", operand = operand }
end

function M.binary(op, left, right)
    assert(BINARY[op], "Unknown binary operator: " .. tostring(op))
    return { type = op, left = left, right = right }
end

function M.unparen(node)
    while node.type == "paren" do
        node = node.expr
    end
    return node
end

-- A node's children, left to right: the one under a parenthesis or a
-- negation, the two of a binary operator, none for a leaf.
function M.children(node)
    if node.type == "paren" then
        return { node.expr }
    elseif node.type == "not" then
        return { node.operand }
    elseif BINARY[node.type] then
        return { node.left, node.right }
    end
    return {}
end

local function collect(node, op, out)
    local inner = M.unparen(node)
    if inner.type == op then
        collect(inner.left, op, out)
        collect(inner.right, op, out)
    else
        out[#out + 1] = node
    end
    return out
end

-- Operands of the `op` chain rooted at `node`, left to right. Parentheses
-- around a run of the same operator are transparent; any other operand is
-- kept whole, parentheses included.
function M.operands(node, op)
    return collect(node, op, {})
end

-- Left-nested chain of `op` over `operands`, splicing in any operand that is
-- itself an `op` chain so the result reads flat.
function M.fold(op, operands)
    local flat = {}
    for _, operand in ipairs(operands) do
        collect(operand, op, flat)
    end
    local chain = flat[1]
    for i = 2, #flat do
        chain = M.binary(op, chain, flat[i])
    end
    return chain
end

-- Post-order traversal that copies every node before applying a
-- result-producing transformation. Binding, variable discovery and the
-- canonical form are all written over it; inputs stay intact.
function M.transform(node, fn)
    local copy = { type = node.type }
    if node.type == "paren" or node.type == "not" then
        local key = node.type == "paren" and "expr" or "operand"
        local child, err = M.transform(node[key], fn)
        return result.bind(child, err, function(mapped)
            copy[key] = mapped
            return fn(copy, node)
        end)
    elseif BINARY[node.type] then
        local left, err = M.transform(node.left, fn)
        return result.bind(left, err, function(mapped_left)
            local right, right_err = M.transform(node.right, fn)
            return result.bind(right, right_err, function(mapped_right)
                copy.left, copy.right = mapped_left, mapped_right
                return fn(copy, node)
            end)
        end)
    elseif node.type == "var" then
        copy.name = node.name
    elseif node.type == "reference" then
        copy.index = node.index
    elseif node.type == "literal" then
        copy.value, copy.symbol = node.value, node.symbol
    elseif node.type == "column" then
        copy.index, copy.name, copy.variable = node.index, node.name, node.variable
    else
        return nil, "Unknown AST node: " .. tostring(node.type)
    end
    return fn(copy, node)
end

-- A run of ∧ or of ∨ means the same however it is grouped, and reads
-- correctly flat. ⊕ and ⇔ are associative too, but a flat run of either
-- misreads (A ⇔ B ⇔ C is true when A is true and B and C are false), so
-- their grouping stays visible, like that of →.
local FLAT = { ["and"] = true, ["or"] = true }

local function grouped(operand)
    return BINARY[operand.type] and M.paren(operand) or operand
end

-- The canonical form of a tree: one tree, and so one text, for every way of
-- grouping and parenthesising the same expression. The source's parentheses
-- are dropped; a run of ∧ or of ∨ becomes one left-nested chain; and an
-- operand that is itself a binary expression is parenthesised, so a mix of
-- operators reads without recalling the binding order: (A ∧ B) ∨ C.
function M.canonical(node, selected)
    -- Membership belongs to this traversal, never to the syntax tree.
    local origins, mapped = {}, {}
    local function select_nodes(tree)
        origins[tree] = true
        for _, child in ipairs(M.children(tree)) do
            select_nodes(child)
        end
    end
    for _, tree in ipairs(selected or {}) do
        select_nodes(tree)
    end
    local function grouped_copy(operand)
        local group = grouped(operand)
        if mapped[operand] then
            mapped[group] = true
        end
        return group
    end
    local tree, err = M.transform(node, function(copy, original)
        local output
        if copy.type == "paren" then
            output = copy.expr
        elseif copy.type == "not" then
            output = M.negation(grouped_copy(copy.operand))
        elseif FLAT[copy.type] then
            output = M.fold(copy.type, fp.map(M.operands(copy, copy.type), grouped_copy))
        elseif BINARY[copy.type] then
            output = { type = copy.type, left = grouped_copy(copy.left), right = grouped_copy(copy.right) }
        else
            output = copy
        end
        if origins[original] then
            mapped[output] = true
        end
        return output
    end)
    if not tree then
        return nil, err
    end
    local produced = {}
    local function visit(current)
        if mapped[current] then
            produced[#produced + 1] = current
            return
        end
        for _, child in ipairs(M.children(current)) do
            visit(child)
        end
    end
    visit(tree)
    return tree, produced
end

-- The text between a binary operator's operands, and the set of every such
-- text: a gap between two lit regions that is one of these joins them.
local function glue(op)
    return " " .. SYMBOLS[op] .. " "
end
local JOINS = {}
for op in pairs(BINARY) do
    JOINS[glue(op)] = true
end

-- A renderer over one traversal's context: the text of a node that starts
-- at byte `offset` of the whole, as the tree stands, with parentheses from
-- paren nodes alone. On the way it adds the byte range of each `selected`
-- node to `regions`, and the position of every node to `positions` when
-- given a table for them.
local function renderer(selected, regions, positions)
    local function render(node, offset)
        local text
        if node.type == "paren" then
            text = "(" .. render(node.expr, offset + 1) .. ")"
        elseif node.type == "not" then
            text = SYMBOLS["not"] .. render(node.operand, offset + #SYMBOLS["not"])
        elseif BINARY[node.type] then
            local left = render(node.left, offset)
            local between = glue(node.type)
            local right = render(node.right, offset + #left + #between)
            text = left .. between .. right
        elseif node.type == "reference" then
            text = ":h" .. node.index
        elseif node.type == "column" then
            text = node.variable or ("“" .. node.name .. "”")
        elseif node.type == "var" then
            text = node.name
        else
            text = node.symbol or tostring(node.value)
        end
        if positions then
            positions[node] = { start_byte = offset + 1, end_byte = offset + #text }
        end
        if selected[node] then
            regions[#regions + 1] = { offset, offset + #text }
        end
        return text
    end
    return render
end

-- Locate a tree's nodes in its own text without mutating it or parsing it
-- again. This lets a later rewrite target a canonical result.
function M.positions(node)
    local positions = {}
    renderer({}, {}, positions)(node, 0)
    return positions
end

-- The text of a tree, with the bytes its separately supplied nodes cover as
-- zero-based half-open ranges, then the canonical tree the text was rendered
-- from and those nodes' counterparts in it. Canonical form gives one
-- expression one text however its source grouped it.
function M.rendered(node, produced)
    local tree, mapped = M.canonical(node, produced)
    assert(tree, mapped)
    local selected = {}
    for _, item in ipairs(mapped) do
        selected[item] = true
    end
    local regions = {}
    local text = renderer(selected, regions)(tree, 0)
    table.sort(regions, function(a, b)
        return a[1] < b[1] or a[1] == b[1] and a[2] > b[2]
    end)
    local merged = {}
    for _, region in ipairs(regions) do
        local previous = merged[#merged]
        local gap = previous and text:sub(previous[2] + 1, region[1])
        -- Adjacent produced operands include their joining operator. A gap
        -- containing an untouched operand stays unlit.
        if previous and (region[1] <= previous[2] or JOINS[gap]) then
            previous[2] = math.max(previous[2], region[2])
        else
            merged[#merged + 1] = { region[1], region[2] }
        end
    end
    return text, merged, tree, mapped
end

function M.heading(node)
    return (M.rendered(node))
end

-- Root-only De Morgan rewrite, returning an independent tree. No automatic
-- double-negation simplification: that is a separate refactoring operation.
-- The other operator of a De Morgan pair.
local DUAL = { ["and"] = "or", ["or"] = "and" }

-- De Morgan over the whole of `node`, in either direction, reading a run of
-- one operator as a flat list whatever its parentheses: ¬ over an ∧ or ∨
-- chain negates every operand and flips the operator; a chain whose
-- operands are all negations becomes one negation of the dual chain. The
-- result is in canonical form.
function M.de_morgan(node)
    local root = M.unparen(node)
    local rewritten
    if root.type == "not" then
        local operand = M.unparen(root.operand)
        if DUAL[operand.type] then
            rewritten = M.fold(DUAL[operand.type], fp.map(M.operands(operand, operand.type), M.negation))
        end
    elseif DUAL[root.type] then
        local inner = {}
        for _, item in ipairs(M.operands(root, root.type)) do
            local negation = M.unparen(item)
            if negation.type ~= "not" then
                inner = nil
                break
            end
            inner[#inner + 1] = negation.operand
        end
        if inner then
            rewritten = M.negation(M.fold(DUAL[root.type], inner))
        end
    end
    if not rewritten then
        return nil, "No De Morgan rewrite applies to the whole expression"
    end
    return M.canonical(rewritten)
end

return M
