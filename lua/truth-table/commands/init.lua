-- The user commands: each its name, what it runs, and the options the
-- command takes. The table commands are table.lua's; the rest run a
-- preview, a verdict, the menu or the tutor, each a line. `define` creates
-- them all and answers the names, which the keymaps are checked against.
local fp = require("cds.fp")
local core = require("truth-table.core")
local preview = require("truth-table.preview")
local tables = require("truth-table.commands.table")

local M = {}

local function cmd_align()
    require("truth-table.align").derivation(0, vim.api.nvim_win_get_cursor(0)[1], false)
end

local function cmd_check(command)
    require("truth-table.verdict").show(0, vim.api.nvim_win_get_cursor(0)[1], command.bang)
end

-- The expressions are the argument, split as :TruthTable splits its own,
-- or with a range and no argument the selected lines. The proof, with !,
-- goes in below the current line, or below the selection.
local function cmd_equiv(opts)
    local from_range = opts.range > 0 and opts.args == ""
    local args, below = opts.args, vim.api.nvim_win_get_cursor(0)[1]
    if from_range then
        args = core.args_from_lines(vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false))
        below = opts.line2
    end
    local exprs, err = core.split_expressions(args, "|,")
    if not exprs then
        vim.notify(err, vim.log.levels.WARN)
        return
    end
    local indent = (vim.api.nvim_buf_get_lines(0, below - 1, below, false)[1] or ""):match("^%s*")
    require("truth-table.verdict").equiv(0, exprs, below, indent, opts.bang)
end

local function cmd_commute(command)
    preview.toggle(command.bang and "commute_back" or "commute")
end

local function cmd_tutor(command)
    require("truth-table.tutor").open({
        fresh = command.bang,
        lesson = command.args ~= "" and command.args or nil,
    })
end

local function toggles(name)
    return function()
        preview.toggle(name)
    end
end

-- Each command: its name, what it runs, and the options the
-- command takes (nargs, range, bang) with its description. The tables and
-- the derivation check first, then the rewrites (the previews, the menu of them all, the two
-- ways to apply one), then the tutor.
-- stylua: ignore start
-- Packed rows: each command on a line, its long desc on a continuation.
local COMMANDS = {
    { name = "TruthTable", run = tables.truth_table, nargs = "*", range = true, desc = "Generate a truth table" },
    { name = "TruthTableExpand", run = tables.expand, nargs = "+", desc = "Expand truth table with computed columns" },
    { name = "TruthTableDropRow", run = tables.drop_row, desc = "Drop the current truth table row" },
    { name = "TruthTableDropColumn", run = tables.drop_column, desc = "Drop the current truth table column" },
    { name = "TruthTableToggle", run = tables.toggle, desc = "Toggle truth table between 0/1 and F/T" },
    { name = "TruthTableAlign", run = cmd_align, desc = "Align the derivation's justification bars in one column" },
    { name = "TruthTableVerify", run = cmd_check, bang = true,
        desc = "Verify every ≡ step of the derivation under the cursor, and show the first that fails (! inserts the proof table below)" },
    { name = "TruthTableEquiv", run = cmd_equiv, nargs = "*", range = true, bang = true,
        desc = "Are these expressions (separated by | or ,; or the selected lines) all equivalent? Name the first pair that differs (! inserts the proof table below)" },
    { name = "TruthTableKarnaugh", run = tables.karnaugh,
        desc = "Insert a Karnaugh map and minimal formula for the current column" },
    { name = "TruthTableEquivalents", run = function() require("truth-table.equivalence").toggle() end,
        desc = "Toggle the live ≡/≢ column equivalence marks, everywhere (on by default)" },
    { name = "TruthTableDeMorgan", run = toggles("de_morgan"), desc = "Toggle a whole-expression De Morgan preview" },
    { name = "TruthTableFactor", run = toggles("factor"),
        desc = "Toggle a preview factoring the operand under the cursor out of its terms" },
    { name = "TruthTableDistribute", run = toggles("distribute"),
        desc = "Toggle a preview distributing the operand under the cursor into the group beside it" },
    { name = "TruthTableXor", run = toggles("xor"),
        desc = "Toggle a preview recognising an exclusive or (or an equivalence) in the terms under the cursor" },
    { name = "TruthTableUnfold", run = toggles("unfold"),
        desc = "Toggle a preview replacing the →, ⊕ or ⇔ nearest the cursor by its definition" },
    { name = "TruthTableDNF", run = toggles("dnf"),
        desc = "Toggle a preview of the expression in disjunctive normal form (an or of and terms)" },
    { name = "TruthTableCNF", run = toggles("cnf"),
        desc = "Toggle a preview of the expression in conjunctive normal form (an and of or clauses)" },
    { name = "TruthTableSimplify", run = toggles("simplify"),
        desc = "Toggle a preview applying the collapsing law nearest the cursor (complement, identity, absorption, reduction, ...)" },
    { name = "TruthTableCommute", run = cmd_commute, bang = true,
        desc = "Toggle a preview swapping the operand under the cursor with the next one (! for the previous)" },
    { name = "TruthTableRewrites", run = require("truth-table.menu").choose,
        desc = "List every rewrite of the expression under the cursor and write the one picked as a ≡ step" },
    { name = "TruthTableApply", run = preview.apply, desc = "Apply the current rewrite preview in place" },
    { name = "TruthTableDeMorganApply", run = preview.apply, desc = "Alias of :TruthTableApply" },
    { name = "TruthTableApplyStep", run = preview.apply_step,
        desc = "Insert the current rewrite preview below as a ≡ derivation step" },
    { name = "TruthTableTutor", run = cmd_tutor, bang = true, nargs = "?",
        desc = "Open the tutorial at your place (! to start over, a number to jump to that lesson)" },
    { name = "TruthTableTutorNext", run = function() require("truth-table.tutor").step(1) end,
        desc = "Go to the tutorial's next step" },
    { name = "TruthTableTutorPrev", run = function() require("truth-table.tutor").step(-1) end,
        desc = "Go to the tutorial's previous step" },
}
-- stylua: ignore end

-- Create every command; answers the set of names defined.
function M.define()
    fp.each(COMMANDS, function(command)
        vim.api.nvim_create_user_command(command.name, command.run, {
            nargs = command.nargs,
            range = command.range,
            bang = command.bang,
            desc = command.desc,
        })
    end)
    return fp.set(COMMANDS, function(command)
        return command.name
    end)
end

return M
