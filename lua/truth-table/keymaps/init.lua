-- The keymaps and their two prefixes. `set` maps them, checked against the
-- commands defined; the which-key popup that lists the legal ones at the
-- cursor is which_key.lua, over the same table.
local M = {}

-- Two prefixes, one per family: the table commands under <leader>T, the
-- rewrite workflow (the previews, verify, apply) under <leader>l for
-- logic, so the hot path stays three keys.
local PREFIXES = { table = "<leader>T", rewrite = "<leader>l" }

-- On a nonblank line the line is the argument, so the mapping on `A and B`
-- builds its table in place, the same as the visual mapping on a selection.
-- A blank line has nothing to read; prefill the command.
local function new_table()
    if vim.api.nvim_get_current_line():match("^%s*$") then
        return ":TruthTable "
    end
    return ":.TruthTable<CR>"
end

-- The default keymaps, every key one deep under its family's prefix, each
-- tagged with the context (`when`) it waits for, where a bare one is at
-- hand everywhere. m and M are the normal forms, after their minterms and
-- maxterms. Each entry names the command it runs, or spells its own
-- right-hand side where it does more than run one.
-- stylua: ignore start
local KEYMAPS = {
    { family = "table", key = "n", rhs = new_table, desc = "New table", expr = true },
    { family = "table", key = "n", rhs = ":TruthTable<CR>", desc = "New table from selection", mode = "x" },
    { family = "table", key = "e", rhs = ":TruthTableExpand ", desc = "Expand with columns", when = "table" },
    { family = "table", key = "t", command = "TruthTableToggle", desc = "Toggle 0/1 ↔ F/T", when = "table" },
    { family = "table", key = "k", command = "TruthTableKarnaugh", desc = "Karnaugh map for column", when = "table" },
    { family = "table", key = "r", command = "TruthTableDropRow", desc = "Drop row", when = "table" },
    { family = "table", key = "c", command = "TruthTableDropColumn", desc = "Drop column", when = "table" },
    { family = "table", key = "=", command = "TruthTableEquivalents", desc = "Mark equivalent columns",
        when = "table" },
    { family = "rewrite", key = "d", command = "TruthTableDeMorgan", desc = "De Morgan", when = "expression" },
    { family = "rewrite", key = "f", command = "TruthTableFactor", desc = "Factor operand out", when = "expression" },
    { family = "rewrite", key = "x", command = "TruthTableDistribute", desc = "Distribute operand in",
        when = "expression" },
    { family = "rewrite", key = "s", command = "TruthTableCommute", desc = "Swap with next operand",
        when = "expression" },
    { family = "rewrite", key = "S", rhs = "<cmd>TruthTableCommute!<CR>", desc = "Swap with previous operand",
        when = "expression" },
    { family = "rewrite", key = "o", command = "TruthTableXor", desc = "Recognise ⊕ or ⇔", when = "expression" },
    { family = "rewrite", key = "u", command = "TruthTableUnfold", desc = "Unfold →, ⊕ or ⇔ by its definition",
        when = "expression" },
    { family = "rewrite", key = "m", command = "TruthTableDNF", desc = "Disjunctive normal form",
        when = "expression" },
    { family = "rewrite", key = "M", command = "TruthTableCNF", desc = "Conjunctive normal form",
        when = "expression" },
    { family = "rewrite", key = "z", command = "TruthTableSimplify", desc = "Simplify at the cursor",
        when = "expression" },
    { family = "rewrite", key = "l", command = "TruthTableRewrites", desc = "List every rewrite and pick one",
        when = "expression" },
    { family = "rewrite", key = "v", command = "TruthTableVerify", desc = "Verify the derivation",
        when = "derivation" },
    { family = "rewrite", key = "V", rhs = "<cmd>TruthTableVerify!<CR>",
        desc = "Verify the derivation and show the proof table", when = "derivation" },
    { family = "rewrite", key = "a", command = "TruthTableApply", desc = "Apply in place", when = "preview" },
    { family = "rewrite", key = "A", command = "TruthTableApplyStep", desc = "Apply as a ≡ step", when = "preview" },
}
-- stylua: ignore end
M.PREFIXES, M.KEYMAPS = PREFIXES, KEYMAPS

-- Map every key, each to the command it names (which `defined` must hold)
-- or its own right-hand side. With which-key present, a context-gated leaf
-- hides from its tree: the popup gets it from which_key.lua while its
-- context holds, and a blind press falls through to this mapping either
-- way.
function M.set(defined, has_which_key)
    for _, map in ipairs(KEYMAPS) do
        local rhs = map.rhs
        if map.command then
            assert(defined[map.command], "keymap " .. map.key .. " names no command: " .. map.command)
            rhs = "<cmd>" .. map.command .. "<CR>"
        end
        local desc = (has_which_key and map.when) and "which_key_ignore" or map.desc
        vim.keymap.set(map.mode or "n", PREFIXES[map.family] .. map.key, rhs, { desc = desc, expr = map.expr })
    end
end

return M
