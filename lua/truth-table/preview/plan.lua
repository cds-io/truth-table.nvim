-- The plan of a preview: the rewrites by name, the one of them resolved at
-- the cursor into the write it would make, and the text the preview shows
-- at the end of its line. Holds no state, so the pending preview itself,
-- init.lua, stays the one small module with any.
local derivation = require("truth-table.derivation")
local rewrite = require("truth-table.rewrite")
local source = require("truth-table.source")
local write = require("truth-table.write")
local M = {}

-- Each rewrite maps a located tree and a cursor byte to a new tree and the
-- name of the law that justifies it. `whole` marks a rewrite that also
-- works without a cursor in the expression, on the whole of it. `opposite` names the rewrite a
-- reader is likely to have meant when this one refuses, with the words that
-- point to it.
local REWRITES = {
    de_morgan = { whole = true, run = rewrite.de_morgan },
    simplify = { whole = true, run = rewrite.simplify },
    factor = {
        run = rewrite.factor,
        opposite = { name = "distribute", hint = "to move it into the group beside it, use :TruthTableDistribute" },
    },
    distribute = {
        run = rewrite.distribute,
        opposite = { name = "factor", hint = "to pull it out of the terms that share it, use :TruthTableFactor" },
    },
    xor = {
        run = rewrite.xor,
        opposite = { name = "unfold", hint = "to replace a connective by its definition, use :TruthTableUnfold" },
    },
    unfold = {
        whole = true,
        run = rewrite.unfold,
        opposite = { name = "xor", hint = "to recognise ⊕ or ⇔ in the terms, use :TruthTableXor" },
    },
    dnf = { whole = true, run = rewrite.dnf },
    cnf = { whole = true, run = rewrite.cnf },
    commute = {
        run = function(ast, byte)
            return rewrite.commute(ast, byte, false)
        end,
    },
    commute_back = {
        run = function(ast, byte)
            return rewrite.commute(ast, byte, true)
        end,
    },
}

-- The preview of `kind` at the cursor in `buf`: the plan of the write; or
-- nil and the reason.
function M.resolve(buf, name)
    local kind = REWRITES[name]
    local selected, ast = source.at(buf)
    if not selected then
        return nil, ast
    end
    if not kind.whole and not selected.offset then
        return nil, "Put the cursor on the heading row to choose an operand"
    end
    -- A rewrite carries its law and both sides of the change.
    local rewritten, reason = kind.run(ast, selected.offset)
    if not rewritten then
        -- Factor and Distribute are one law used from either side, and easy
        -- to reach for the wrong way round: say so when the other applies.
        local opposite = kind.opposite
        if opposite and REWRITES[opposite.name].run(ast, selected.offset) then
            return nil, reason .. "; " .. opposite.hint
        end
        return nil, reason
    end
    local preview, err = write.prepare(buf, selected, write.rendered(rewritten))
    if not preview then
        return nil, err
    end
    return preview
end

-- The preview's text at the end of its line: the heading with what the
-- rewrite produced lit, and its law as a justification, in the comment
-- colour otherwise.
function M.chunks(preview)
    local label = preview.column and (" [column " .. preview.column .. "] ⇒ ") or " ⇒ "
    local tail = "  " .. derivation.justification(preview.law)
    if #preview.changed == 0 then
        return { { label .. preview.heading .. tail, "Comment" } }
    end
    local out = {}
    local cursor, prefix = 0, label
    for _, region in ipairs(preview.changed) do
        out[#out + 1] = { prefix .. preview.heading:sub(cursor + 1, region[1]), "Comment" }
        out[#out + 1] = { preview.heading:sub(region[1] + 1, region[2]), write.CHANGED_GROUP }
        cursor, prefix = region[2], ""
    end
    out[#out + 1] = { preview.heading:sub(cursor + 1) .. tail, "Comment" }
    return out
end

return M
