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

local function cmd_drop_row()
    with_table(function(tbl, start_line)
        local cur_row = vim.api.nvim_win_get_cursor(0)[1]
        if cur_row <= start_line + 1 then
            return nil, "Cannot drop heading or separator row"
        end

        local row_idx = cur_row - start_line - 1
        return core.drop_row(tbl, row_idx)
    end)
end

local function cmd_drop_column()
    with_table(function(tbl)
        local col_idx = math.min(get_cursor_column_index(), #tbl.headers)
        return core.drop_column(tbl, col_idx)
    end)
end

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

local PREFIX = "<leader>tt"

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
-- command takes (nargs, range, bang) with its description. The tables
-- first, then the rewrites (the previews, the menu of them all, the two
-- ways to apply one), then the tutor.
local COMMANDS = {
    { name = "TruthTable", run = cmd_truth_table, nargs = "*", range = true, desc = "Generate a truth table" },
    { name = "TruthTableExpand", run = cmd_expand, nargs = "+", desc = "Expand truth table with computed columns" },
    { name = "TruthTableDropRow", run = cmd_drop_row, desc = "Drop the current truth table row" },
    { name = "TruthTableDropColumn", run = cmd_drop_column, desc = "Drop the current truth table column" },
    { name = "TruthTableToggle", run = cmd_toggle, desc = "Toggle truth table between 0/1 and F/T" },
    { name = "TruthTableAlign", run = cmd_align, desc = "Align the derivation's justification bars in one column" },
    { name = "TruthTableKarnaugh", run = cmd_karnaugh,
        desc = "Insert a Karnaugh map and minimal formula for the current column" },
    { name = "TruthTableDeMorgan", run = toggles("de_morgan"), desc = "Toggle a whole-expression De Morgan preview" },
    { name = "TruthTableFactor", run = toggles("factor"),
        desc = "Toggle a preview factoring the operand under the cursor out of its terms" },
    { name = "TruthTableDistribute", run = toggles("distribute"),
        desc = "Toggle a preview distributing the operand under the cursor into the group beside it" },
    { name = "TruthTableXor", run = toggles("xor"),
        desc = "Toggle a preview recognising an exclusive or (or an equivalence) in the terms under the cursor" },
    { name = "TruthTableSimplify", run = toggles("simplify"),
        desc = "Toggle a preview applying the collapsing law nearest the cursor (complement, identity, absorption, reduction, ...)" },
    { name = "TruthTableCommute", run = cmd_commute, bang = true,
        desc = "Toggle a preview swapping the operand under the cursor with the next one (! for the previous)" },
    { name = "TruthTableRewrites", run = preview.choose,
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

-- The default keymaps, by family: tables, then rewrites (the previews, then
-- the menu of them all), then the two ways to apply a preview. Each names
-- the command it runs, or spells its own right-hand side where it does
-- more than run one. Each description opens with its family, so the
-- grouping shows in a key-sorted popup too; the order is the one which-key
-- is given.
local KEYMAPS = {
    { key = "n", rhs = new_table, desc = "Table: new", expr = true },
    { key = "n", rhs = ":TruthTable<CR>", desc = "Table: new from selection", mode = "x" },
    { key = "e", rhs = ":TruthTableExpand ", desc = "Table: expand with columns" },
    { key = "t", command = "TruthTableToggle", desc = "Table: toggle 0/1 ↔ F/T" },
    { key = "r", command = "TruthTableDropRow", desc = "Table: drop row" },
    { key = "c", command = "TruthTableDropColumn", desc = "Table: drop column" },
    { key = "k", command = "TruthTableKarnaugh", desc = "Table: Karnaugh map for column" },
    { key = "d", command = "TruthTableDeMorgan", desc = "Rewrite: De Morgan" },
    { key = "f", command = "TruthTableFactor", desc = "Rewrite: factor operand out" },
    { key = "x", command = "TruthTableDistribute", desc = "Rewrite: distribute operand in" },
    { key = "s", command = "TruthTableCommute", desc = "Rewrite: swap with next operand" },
    { key = "S", rhs = "<cmd>TruthTableCommute!<CR>", desc = "Rewrite: swap with previous operand" },
    { key = "o", command = "TruthTableXor", desc = "Rewrite: recognise ⊕ or ⇔" },
    { key = "z", command = "TruthTableSimplify", desc = "Rewrite: simplify at the cursor" },
    { key = "l", command = "TruthTableRewrites", desc = "Rewrite: list every rewrite and pick one" },
    { key = "a", command = "TruthTableApply", desc = "Apply: in place" },
    { key = "A", command = "TruthTableApplyStep", desc = "Apply: as a ≡ step" },
}

-- The groups a rewrite is lit with, the terms it consumed and the result it
-- produced, as defaults the reader may define over. A colorscheme clears
-- them, so they are defined again after one.
local function highlights()
    vim.api.nvim_set_hl(0, "TruthTableChanged", { default = true, link = "DiagnosticOk" })
    vim.api.nvim_set_hl(0, "TruthTableConsumed", { default = true, link = "DiagnosticWarn" })
end

-- Register commands, keymaps, insert-mode abbreviations, and (if present)
-- which-key labels. Also injects vim.fn.strdisplaywidth so column widths are
-- terminal-accurate. Idempotent: the last call wins, including for the
-- abbreviations. Automatic loading preserves an earlier explicit setup call.
function M.setup(opts)
    if opts ~= nil and type(opts) ~= "table" then
        error("truth-table setup options must be a table", 0)
    end
    opts = opts or {}
    core.display_width = vim.fn.strdisplaywidth
    require("truth-table.abbreviations").register(opts.abbreviations)
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
            nargs = command.nargs, range = command.range, bang = command.bang, desc = command.desc,
        })
        defined[command.name] = true
    end

    for _, map in ipairs(KEYMAPS) do
        local rhs = map.rhs
        if map.command then
            assert(defined[map.command], "keymap " .. map.key .. " names no command: " .. map.command)
            rhs = "<cmd>" .. map.command .. "<CR>"
        end
        vim.keymap.set(map.mode or "n", PREFIX .. map.key, rhs, { desc = map.desc, expr = map.expr })
    end

    local ok, wk = pcall(require, "which-key")
    if ok then
        -- which-key lists a popup by key unless its `sort` option includes
        -- "manual", which follows the order mappings were added in: this one.
        -- selene: allow(mixed_table)
        -- which-key's spec is intentionally mixed: positional key + named fields.
        local spec = { { PREFIX, group = "[T]ruth Table" } }
        for _, map in ipairs(KEYMAPS) do
            -- selene: allow(mixed_table)
            spec[#spec + 1] = { PREFIX .. map.key, desc = map.desc, mode = map.mode or "n" }
        end
        wk.add(spec)
    end
    M.configured = true
end

return M
