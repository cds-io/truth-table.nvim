-- truth-table.nvim: generate and manipulate markdown truth tables. The pure
-- table pipeline lives in truth-table.core; this module holds the
-- Neovim-facing pieces (buffer scanning, the user commands, keymaps) and the
-- setup() entry point.

local core = require("truth-table.core")
local result = require("truth-table.result")
local fp = require("truth-table.fp")
local preview = require("truth-table.preview")

local M = {}

-- Apply only complete successful pipelines; failures leave the buffer untouched.
local function replace_table(first, last, tbl, err, indent)
    local lines, format_err = result.bind(tbl, err, core.format)
    if not lines then
        vim.notify(format_err, vim.log.levels.WARN)
        return
    end
    if indent and indent ~= "" then
        lines = fp.map(lines, function(line)
            return indent .. line
        end)
    end
    vim.api.nvim_buf_set_lines(0, first, last, false, lines)
end

local function get_cursor_column_index()
    local cursor = vim.api.nvim_win_get_cursor(0)
    return core.column_index(vim.api.nvim_get_current_line(), cursor[2])
end

-- The table under the cursor as a model plus its buffer bounds, or nil and an
-- error. Bounds are one-based, inclusive line numbers.
local function read_table()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local bounds, find_err = core.find_table(lines, vim.api.nvim_win_get_cursor(0)[1])
    if not bounds then
        return nil, find_err
    end
    local selected = {}
    for row = bounds.start_line, bounds.end_line do
        selected[#selected + 1] = lines[row]
    end
    local tbl, err = core.parse(selected)
    if not tbl then
        return nil, err
    end
    return tbl, bounds
end

-- Compose parse -> transform -> format, using one Result convention throughout.
local function with_table(fn)
    local tbl, bounds = read_table()
    if not tbl then
        vim.notify(bounds, vim.log.levels.WARN)
        return
    end
    local edited, edit_err = fn(tbl, bounds.start_line, bounds.end_line)
    replace_table(bounds.start_line - 1, bounds.end_line, edited, edit_err, bounds.indent)
end

local function cmd_truth_table(opts)
    -- With a range and no argument, the selected lines are the argument, and
    -- the table takes their place. Otherwise the table is inserted at the
    -- cursor, above the current line.
    local from_range = opts.range > 0 and opts.args == ""
    local args = opts.args
    local first = vim.api.nvim_win_get_cursor(0)[1] - 1
    local last = first
    if from_range then
        first, last = opts.line1 - 1, opts.line2
        args = core.args_from_lines(vim.api.nvim_buf_get_lines(0, first, last, false))
    end

    replace_table(first, last, core.build(args))
end

local function cmd_expand(opts)
    local predicates, err = core.split_expressions(opts.args, ",")
    if not predicates then
        vim.notify(err, vim.log.levels.WARN)
        return
    end

    with_table(function(tbl)
        return core.expand(tbl, predicates)
    end)
end

-- The edit . runs again. Neovim replays only what it recorded as a
-- change, and a command run by name records nothing; an operator does.
-- So a repeatable command names itself here, sets 'operatorfunc' to the
-- dispatcher and runs g@ over one character: the edit runs at the cursor
-- now, and . reaches the dispatcher, which runs it again where the cursor
-- is then. The character is never read; the row and column come from the
-- cursor, as they do when the command is run by name.
local repeated

function M.operator()
    repeated()
end

local function repeatable(fn)
    return function()
        repeated = fn
        vim.go.operatorfunc = "v:lua.require'truth-table'.operator"
        vim.cmd("normal! g@l")
    end
end

local cmd_drop_row = repeatable(function()
    with_table(function(tbl, start_line)
        local cur_row = vim.api.nvim_win_get_cursor(0)[1]
        if cur_row <= start_line + 1 then
            return nil, "Cannot drop heading or separator row"
        end

        local row_idx = cur_row - start_line - 1
        return core.drop_row(tbl, row_idx)
    end)
end)

local cmd_drop_column = repeatable(function()
    with_table(function(tbl)
        local col_idx = math.min(get_cursor_column_index(), #tbl.headers)
        return core.drop_column(tbl, col_idx)
    end)
end)

local function cmd_toggle()
    with_table(function(tbl)
        return core.toggle(tbl)
    end)
end

-- The table stays as it is; the map and formula go below it, after one blank
-- line, at the table's indentation.
local function cmd_karnaugh()
    local tbl, bounds = read_table()
    if not tbl then
        vim.notify(bounds, vim.log.levels.WARN)
        return
    end
    local col_idx = math.min(get_cursor_column_index(), #tbl.headers)
    local analysis, err = core.derive_karnaugh(tbl, col_idx)
    if not analysis then
        vim.notify(err, vim.log.levels.WARN)
        return
    end
    local lines = { "" }
    for _, line in ipairs(core.format_karnaugh(analysis)) do
        lines[#lines + 1] = line == "" and "" or bounds.indent .. line
    end
    vim.api.nvim_buf_set_lines(0, bounds.end_line, bounds.end_line, false, lines)
end

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

-- The user commands: each its name, what it runs, and the options the
-- command takes (nargs, range, bang) with its description. The tables and
-- the derivation check first, then the rewrites (the previews, the menu of them all, the two
-- ways to apply one), then the tutor.
-- stylua: ignore start
-- Packed rows: each command on a line, its long desc on a continuation.
local COMMANDS = {
    { name = "TruthTable", run = cmd_truth_table, nargs = "*", range = true, desc = "Generate a truth table" },
    { name = "TruthTableExpand", run = cmd_expand, nargs = "+", desc = "Expand truth table with computed columns" },
    { name = "TruthTableDropRow", run = cmd_drop_row, desc = "Drop the current truth table row" },
    { name = "TruthTableDropColumn", run = cmd_drop_column, desc = "Drop the current truth table column" },
    { name = "TruthTableToggle", run = cmd_toggle, desc = "Toggle truth table between 0/1 and F/T" },
    { name = "TruthTableAlign", run = cmd_align, desc = "Align the derivation's justification bars in one column" },
    { name = "TruthTableVerify", run = cmd_check, bang = true,
        desc = "Verify every ≡ step of the derivation under the cursor, and show the first that fails (! inserts the proof table below)" },
    { name = "TruthTableEquiv", run = cmd_equiv, nargs = "*", range = true, bang = true,
        desc = "Are these expressions (separated by | or ,; or the selected lines) all equivalent? Name the first pair that differs (! inserts the proof table below)" },
    { name = "TruthTableKarnaugh", run = cmd_karnaugh,
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

-- The default keymaps, every key one deep under its family's prefix, each
-- tagged with the context (`when`) it waits for, where a bare one is at
-- hand everywhere. m and M are the normal forms, after their minterms and
-- maxterms. Each entry names the command it runs, or spells its own
-- right-hand side where it does more than run one.
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

-- The contexts a leaf can wait for, read fresh at the cursor: each is one
-- pass over the buffer, cheap enough to run on every popup. An expression
-- is whatever source.at would hand the rewrites: a parseable line, or any
-- row of a table whose heading parses. `preview` is the pending preview
-- itself, so the apply labels can name its law.
local function context()
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local row = vim.api.nvim_win_get_cursor(0)[1]
    return {
        table = core.find_table(lines, row) ~= nil,
        expression = require("truth-table.source").at(buf) ~= nil,
        derivation = require("truth-table.derivation").in_derivation(lines, row),
        preview = preview.active(buf),
    }
end

-- The family's leaves whose context holds at the cursor, as which-key
-- specs: the popup's legal moves. Run from the popup, a leaf feeds the
-- keys its real mapping would, so the two paths stay one.
local function legal_leaves(family)
    local ctx = context()
    local spec = {}
    for _, map in ipairs(KEYMAPS) do
        if map.family == family and map.when and ctx[map.when] and (map.mode or "n") == "n" then
            local desc = map.desc
            if map.when == "preview" then
                desc = ("%s (%s)"):format(desc, ctx.preview.law)
            end
            local rhs = map.command and ("<cmd>" .. map.command .. "<CR>") or map.rhs
            -- selene: allow(mixed_table)
            spec[#spec + 1] = {
                map.key,
                function()
                    local keys = vim.api.nvim_replace_termcodes(rhs, true, true, true)
                    vim.api.nvim_feedkeys(keys, "n", false)
                end,
                desc = desc,
            }
        end
    end
    return spec
end

-- The groups a rewrite is lit with, the terms it consumed and the result it
-- produced, and the ≡/≢ marks the equivalence toggle paints, as defaults
-- the reader may define over. A colorscheme clears them, so they are
-- defined again after one.
local function highlights()
    vim.api.nvim_set_hl(0, "TruthTableChanged", { default = true, link = "DiagnosticOk" })
    vim.api.nvim_set_hl(0, "TruthTableConsumed", { default = true, link = "DiagnosticWarn" })
    vim.api.nvim_set_hl(0, "TruthTableEquivalent", { default = true, link = "DiagnosticInfo" })
    vim.api.nvim_set_hl(0, "TruthTableInequivalent", { default = true, link = "Comment" })
end

-- Register commands, keymaps, insert-mode abbreviations, and (if present)
-- which-key labels. Also injects vim.fn.strdisplaywidth so column widths are
-- terminal-accurate, and states the equivalence-mark switch (on unless
-- opts.equivalence == false). Idempotent: the last call wins, including for
-- the abbreviations. Automatic loading preserves an earlier explicit setup
-- call.
function M.setup(opts)
    if opts ~= nil and type(opts) ~= "table" then
        error("truth-table setup options must be a table", 0)
    end
    opts = opts or {}
    core.display_width = vim.fn.strdisplaywidth
    require("truth-table.abbreviations").register(opts.abbreviations)
    require("truth-table.equivalence").set(opts.equivalence ~= false)
    highlights()
    local group = vim.api.nvim_create_augroup("truth_table", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })
    -- A written rewrite realigns its derivation's bars, in the same undo
    -- entry.
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "TruthTableRewrite",
        callback = function(event)
            require("truth-table.align").derivation(event.data.buf, event.data.row, true)
        end,
    })

    local defined = {}
    for _, command in ipairs(COMMANDS) do
        vim.api.nvim_create_user_command(command.name, command.run, {
            nargs = command.nargs,
            range = command.range,
            bang = command.bang,
            desc = command.desc,
        })
        defined[command.name] = true
    end

    local has_which_key, wk = pcall(require, "which-key")
    for _, map in ipairs(KEYMAPS) do
        local rhs = map.rhs
        if map.command then
            assert(defined[map.command], "keymap " .. map.key .. " names no command: " .. map.command)
            rhs = "<cmd>" .. map.command .. "<CR>"
        end
        -- A context-gated leaf hides from which-key's tree: the popup gets
        -- it from legal_leaves while its context holds, and a blind press
        -- falls through to this mapping either way.
        local desc = (has_which_key and map.when) and "which_key_ignore" or map.desc
        vim.keymap.set(map.mode or "n", PREFIXES[map.family] .. map.key, rhs, { desc = desc, expr = map.expr })
    end

    if has_which_key then
        -- Each root's expand lists its family's legal moves at the cursor;
        -- the new table mapping, with a real description, merges in over
        -- the table root's.
        -- selene: allow(mixed_table)
        -- which-key's spec is intentionally mixed: positional key + named fields.
        local spec = {
            -- selene: allow(mixed_table)
            {
                PREFIXES.table,
                group = "Truth table",
                mode = "n",
                expand = function()
                    return legal_leaves("table")
                end,
            },
            -- selene: allow(mixed_table)
            { PREFIXES.table, group = "Truth table", mode = "x" },
            -- selene: allow(mixed_table)
            {
                PREFIXES.rewrite,
                group = "Logic rewrite",
                mode = "n",
                expand = function()
                    return legal_leaves("rewrite")
                end,
            },
        }
        -- which-key keeps the last spec a prefix was given, and it drains
        -- the queue of specs added before it loaded ahead of the ones from
        -- its own setup options. Added early, ours would lose the prefix to
        -- any group label the reader's config declares on it, and the node,
        -- childless by design (the real mappings hide behind
        -- which_key_ignore), would be pruned along with the expand. So wait
        -- for which-key to finish loading and add ours after; past ~5s add
        -- anyway, better queued than absent.
        local tries = 0
        local function register()
            tries = tries + 1
            if require("which-key.config").loaded or tries > 50 then
                wk.add(spec)
            else
                vim.defer_fn(register, 100)
            end
        end
        register()
    end
    M.configured = true
end

return M
