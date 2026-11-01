-- Simplify: one collapsing law (those of laws.lua, or the removal of a
-- negated constant or a double negation) applied at a site, where a site
-- is every ¬ and the root of every ∧ or ∨ chain. The command takes the
-- nearest match from the cursor outward; `sites`, `collapses` and
-- `draft_collapse` are what `moves` calls at every site. Pure.
local trees = require("truth-table.trees")
local SYMBOLS = require("truth-table.symbols")
local walk = require("truth-table.rewrite.path")
local drafting = require("truth-table.rewrite.draft")
local laws = require("truth-table.rewrite.laws")
local fp = require("cds.fp")
local M = {}

local unparen, operands, fold = trees.unparen, trees.operands, trees.fold
local DUAL, path_to = walk.DUAL, walk.path_to
local operation, substitute = drafting.operation, drafting.substitute
local CHAIN_LAWS = laws.LAWS

-- The operands of `site` that a collapsing law made disappear: those its
-- result `new` does not keep (the laws keep an operand by identity). A site
-- that is no chain, a negation, goes whole.
local function gone(site, new)
    if site.type ~= "and" and site.type ~= "or" then
        return { site }
    end
    local kept = fp.set(operands(new, site.type))
    local out = fp.filter(operands(site, site.type), function(item)
        return not kept[item]
    end)
    return #out > 0 and out or { site }
end

-- A collapsing law may put a term in while leaving the other operands as
-- they were (a ∨ ¬a ∨ b becomes 1 ∨ b): what it produced is that term. One
-- that only removes terms produced what remains at the site.
local function replacement_terms(site, new)
    if not DUAL[site.type] then
        return { new }
    end
    local original = fp.set(operands(site, site.type))
    local introduced = fp.filter(operands(new, site.type), function(item)
        return not original[item]
    end)
    return #introduced > 0 and introduced or { new }
end

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
        -- The path crosses one operand of a chain at most.
        local _, index = fp.find(operands(node, node.type), function(item)
            return on_path[item]
        end)
        if not index then
            return nil
        end
        focus = index
    end
    return collapses(node, focus, focus)[1]
end

-- Apply one collapsing law (complement, domination, identity, idempotence,
-- absorption, reduction, consensus, or the removal of a negated constant or
-- a double negation) and say which. The nearest match wins: a law involving the
-- operand under the cursor, then one inside whatever the cursor selects,
-- then one in a chain around the cursor, then one anywhere. Without a cursor
-- in the expression only the last applies. ⊕, ⇔ and → are left as they are.
local function simplify(ast, byte)
    local positions = ast.span and {} or trees.positions(ast)
    local path = byte and path_to(ast, byte) or {}
    local on_path, target = fp.set(path), path[#path]
    local function around(site)
        return on_path[site]
    end
    local function inside(site)
        if not target then
            return false
        end
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

M.sites, M.collapses, M.draft_collapse = sites, collapses, draft_collapse

return M
