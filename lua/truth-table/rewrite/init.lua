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
--
-- The rules live in the modules beside this one (path and draft are what
-- they share; operand, definition, de_morgan, laws and simplify are the
-- families; the normal forms are here, over normal.lua), and this composes
-- them: the commands under their public names, and `moves`.
local trees = require("truth-table.trees")
local normal = require("truth-table.normal")
local walk = require("truth-table.rewrite.path")
local drafting = require("truth-table.rewrite.draft")
local operand = require("truth-table.rewrite.operand")
local definition = require("truth-table.rewrite.definition")
local de_morgan = require("truth-table.rewrite.de_morgan")
local simplify = require("truth-table.rewrite.simplify")
local M = {}

local unparen, operands = trees.unparen, trees.operands
local DUAL, paths, is_operand, chain_internal = walk.DUAL, walk.paths, walk.is_operand, walk.chain_internal
local completed, operation = drafting.completed, drafting.operation
local de_morgan_at, runs = de_morgan.de_morgan_at, de_morgan.runs
local sites, collapses, draft_collapse = simplify.sites, simplify.collapses, simplify.draft_collapse
local unfold_at = definition.unfold_at

M.target = operand.target
M.commute, M.factor, M.distribute = operand.commute, operand.factor, operand.distribute
M.xor, M.unfold = definition.xor, definition.unfold
M.de_morgan = de_morgan.de_morgan
M.simplify = simplify.simplify

-- ---------------------------------------------------------------------------
-- Normal forms: the whole expression as a DNF or a CNF in one step, the
-- forms themselves from normal.lua.
-- ---------------------------------------------------------------------------

local FORMS = {
    dnf = { build = normal.dnf, law = "disjunctive normal form" },
    cnf = { build = normal.cnf, law = "conjunctive normal form" },
}

-- The draft of `ast` in the form `name`, or nil and the reason: the
-- expression is in the form already (its canonical text is the form's), or
-- the form is past the cap. The cursor plays no part.
local function form_draft(ast, name)
    local which = FORMS[name]
    local built, err = which.build(ast)
    if not built then
        return nil, err
    end
    if trees.heading(built) == trees.heading(ast) then
        return nil, "Already in " .. which.law
    end
    return { tree = built, law = which.law, consumed = { ast }, produced = { built } }
end

local function normal_form(name)
    return function(ast)
        local draft, err = form_draft(ast, name)
        if not draft then
            return {}, err
        end
        return { draft }
    end
end

M.dnf = operation(normal_form("dnf"))
M.cnf = operation(normal_form("cnf"))

-- ---------------------------------------------------------------------------
-- Moves: where a rewrite of the modules beside this one answers for one
-- cursor position, this lists what all of them give from every position.
-- ---------------------------------------------------------------------------

-- The operand rewrites, in the order their results are listed; the swaps
-- come after the normal forms.
local OPERAND_REWRITES = { definition.xor_at, operand.factor_at, operand.distribute_at }
local SWAPS = {
    operand.commute_at,
    function(path, index)
        return operand.commute_at(path, index, true)
    end,
}

-- Every rewrite the expression allows, as { law, rewritten, text }: one
-- entry per distinct result, `rewritten` its { value, change }. The laws that shrink
-- the expression come first, then De Morgan, the unfolding of →, ⊕ and ⇔, the
-- recognition of ⊕ and ⇔, factoring, distributing, the two normal forms
-- and, the most numerous, the swaps. The shrinking laws go
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
        local node = path[#path]
        if not chain_internal(path, #path) then
            local draft = de_morgan_at(ast, node)
            if draft then
                add(draft)
            elseif DUAL[unparen(node).type] then
                local items = operands(node, unparen(node).type)
                for _, first in ipairs(runs(items)) do
                    add(de_morgan_at(ast, node, first))
                end
            end
        end
        if is_operand(path, #path) then
            operand_paths[#operand_paths + 1] = path
        end
    end

    for _, path in ipairs(everywhere) do
        local draft = unfold_at(ast, path, #path)
        if draft then
            add(draft)
        end
    end

    local function operand_rewrites(list)
        for _, rewrite_at in ipairs(list) do
            for _, path in ipairs(operand_paths) do
                for _, draft in ipairs((rewrite_at(path, #path))) do
                    add(draft)
                end
            end
        end
    end
    operand_rewrites(OPERAND_REWRITES)

    for _, name in ipairs({ "dnf", "cnf" }) do
        local draft = form_draft(ast, name)
        if draft then
            add(draft)
        end
    end

    operand_rewrites(SWAPS)
    return found
end

return M
