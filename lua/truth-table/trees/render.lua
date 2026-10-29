-- The canonical form of a tree and its text. Canonical form gives one
-- expression one text however its source grouped it; the renderer gives the
-- text, and on the way the byte ranges of nodes supplied beside the tree
-- (what a rewrite produced) and the position of every node. Pure.
local fp = require("cds.fp")
local operators = require("truth-table.operators")
local node_ = require("truth-table.trees.node")
local BINARY, SYMBOLS = operators.BINARY, operators.SYMBOLS
local M = {}

local children, fold, operands, transform = node_.children, node_.fold, node_.operands, node_.transform
local paren, negation = node_.paren, node_.negation

-- A run of ∧ or of ∨ means the same however it is grouped, and reads
-- correctly flat. ⊕ and ⇔ are associative too, but a flat run of either
-- misreads (A ⇔ B ⇔ C is true when A is true and B and C are false), so
-- their grouping stays visible, like that of →.
local FLAT = { ["and"] = true, ["or"] = true }

local function grouped(operand)
    return BINARY[operand.type] and paren(operand) or operand
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
        for _, child in ipairs(children(tree)) do
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
    local tree, err = transform(node, function(copy, original)
        local output
        if copy.type == "paren" then
            output = copy.expr
        elseif copy.type == "not" then
            output = negation(grouped_copy(copy.operand))
        elseif FLAT[copy.type] then
            output = fold(copy.type, fp.map(operands(copy, copy.type), grouped_copy))
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
        for _, child in ipairs(children(current)) do
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
    local selected = fp.set(mapped)
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

return M
