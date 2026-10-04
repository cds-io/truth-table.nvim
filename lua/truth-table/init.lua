-- truth-table.nvim: generate and manipulate markdown truth tables. The pure
-- parsing/eval/format logic lives in truth-table.core; this module holds the
-- Neovim-facing pieces (buffer scanning, the user commands, keymaps) and the
-- setup() entry point.

local core = require("truth-table.core")
local result = require("truth-table.result")

local M = {}

-- Apply only complete successful pipelines; failures leave the buffer untouched.
local function replace_table(first, last, tbl, err, indent)
    local lines, format_err = result.bind(tbl, err, core.format_model)
    if not lines then
        vim.notify(format_err, vim.log.levels.WARN)
        return
    end
    if indent and indent ~= "" then
        lines = result.traverse(lines, function(line)
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
    local tbl, err = core.parse_model(selected)
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

    replace_table(first, last, core.build_model(args))
end

local function cmd_expand(opts)
    local predicates, err = core.split_expressions(opts.args, ",")
    if not predicates then
        vim.notify(err, vim.log.levels.WARN)
        return
    end

    with_table(function(tbl)
        return core.expand_model(tbl, predicates)
    end)
end

local function cmd_drop_row()
    with_table(function(tbl, start_line)
        local cur_row = vim.api.nvim_win_get_cursor(0)[1]
        if cur_row <= start_line + 1 then
            return nil, "Cannot drop heading or separator row"
        end

        local row_idx = cur_row - start_line - 1
        return core.drop_model_row(tbl, row_idx)
    end)
end

local function cmd_drop_column()
    with_table(function(tbl)
        local col_idx = math.min(get_cursor_column_index(), #tbl.headers)
        return core.drop_model_column(tbl, col_idx)
    end)
end

local function cmd_toggle()
    with_table(function(tbl)
        return core.toggle_model(tbl)
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

    vim.api.nvim_create_user_command("TruthTable", cmd_truth_table, {
        nargs = "*",
        range = true,
        desc = "Generate a truth table",
    })
    vim.api.nvim_create_user_command("TruthTableExpand", cmd_expand, {
        nargs = "+",
        desc = "Expand truth table with computed columns",
    })
    vim.api.nvim_create_user_command("TruthTableDropRow", cmd_drop_row, {
        desc = "Drop the current truth table row",
    })
    vim.api.nvim_create_user_command("TruthTableDropColumn", cmd_drop_column, {
        desc = "Drop the current truth table column",
    })
    vim.api.nvim_create_user_command("TruthTableToggle", cmd_toggle, {
        desc = "Toggle truth table between 0/1 and F/T",
    })
    vim.api.nvim_create_user_command("TruthTableKarnaugh", cmd_karnaugh, {
        desc = "Insert a Karnaugh map and minimal formula for the current column",
    })

    local preview = require("truth-table.preview")
    local function toggles(name)
        return function()
            preview.toggle(name)
        end
    end
    vim.api.nvim_create_user_command("TruthTableDeMorgan", toggles("de_morgan"), {
        desc = "Toggle a whole-expression De Morgan preview",
    })
    vim.api.nvim_create_user_command("TruthTableFactor", toggles("factor"), {
        desc = "Toggle a preview factoring the operand under the cursor out of its terms",
    })
    vim.api.nvim_create_user_command("TruthTableDistribute", toggles("distribute"), {
        desc = "Toggle a preview distributing the operand under the cursor into the group beside it",
    })
    vim.api.nvim_create_user_command("TruthTableXor", toggles("xor"), {
        desc = "Toggle a preview recognising an exclusive or (or an equivalence) in the terms under the cursor",
    })
    vim.api.nvim_create_user_command("TruthTableCommute", function(command)
        preview.toggle(command.bang and "commute_back" or "commute")
    end, {
        bang = true,
        desc = "Toggle a preview swapping the operand under the cursor with the next one (! for the previous)",
    })
    vim.api.nvim_create_user_command("TruthTableApply", preview.apply, {
        desc = "Apply the current rewrite preview in place",
    })
    vim.api.nvim_create_user_command("TruthTableDeMorganApply", preview.apply, {
        desc = "Alias of :TruthTableApply",
    })
    vim.api.nvim_create_user_command("TruthTableApplyStep", preview.apply_step, {
        desc = "Insert the current rewrite preview below as a ≡ derivation step",
    })

    vim.api.nvim_create_user_command("TruthTableTutor", function(command)
        require("truth-table.tutor").open({
            fresh = command.bang,
            lesson = command.args ~= "" and command.args or nil,
        })
    end, {
        bang = true,
        nargs = "?",
        desc = "Open the tutorial at your place (! to start over, a number to jump to that lesson)",
    })
    vim.api.nvim_create_user_command("TruthTableTutorNext", function()
        require("truth-table.tutor").step(1)
    end, {
        desc = "Go to the tutorial's next step",
    })
    vim.api.nvim_create_user_command("TruthTableTutorPrev", function()
        require("truth-table.tutor").step(-1)
    end, {
        desc = "Go to the tutorial's previous step",
    })

    local ok, wk = pcall(require, "which-key")
    if ok then
        -- selene: allow(mixed_table)
        -- which-key's spec is intentionally mixed: positional key + named group.
        wk.add({
            { "<leader>tt", group = "[T]ruth Table" },
        })
    end

    -- On a nonblank line the line is the argument, so the mapping on
    -- `A and B` builds its table in place, the same as the visual mapping on
    -- a selection. A blank line has nothing to read; prefill the command.
    vim.keymap.set("n", "<leader>ttn", function()
        if vim.api.nvim_get_current_line():match("^%s*$") then
            return ":TruthTable "
        end
        return ":.TruthTable<CR>"
    end, { expr = true, desc = "New truth table" })
    vim.keymap.set("x", "<leader>ttn", ":TruthTable<CR>", { desc = "New truth table from selection" })
    vim.keymap.set("n", "<leader>tte", ":TruthTableExpand ", { desc = "Expand truth table" })
    vim.keymap.set("n", "<leader>ttd", "<cmd>TruthTableDeMorgan<CR>", { desc = "Preview De Morgan rewrite" })
    vim.keymap.set("n", "<leader>ttf", "<cmd>TruthTableFactor<CR>", { desc = "Preview factoring out operand" })
    vim.keymap.set("n", "<leader>ttx", "<cmd>TruthTableDistribute<CR>", { desc = "Preview distributing operand" })
    vim.keymap.set("n", "<leader>tto", "<cmd>TruthTableXor<CR>", { desc = "Preview exclusive-or recognition" })
    vim.keymap.set("n", "<leader>tts", "<cmd>TruthTableCommute<CR>", { desc = "Preview swap with next operand" })
    vim.keymap.set("n", "<leader>ttS", "<cmd>TruthTableCommute!<CR>", { desc = "Preview swap with previous operand" })
    vim.keymap.set("n", "<leader>tta", "<cmd>TruthTableApply<CR>", { desc = "Apply rewrite in place" })
    vim.keymap.set("n", "<leader>ttA", "<cmd>TruthTableApplyStep<CR>", { desc = "Apply rewrite as a ≡ step" })
    vim.keymap.set("n", "<leader>ttt", "<cmd>TruthTableToggle<CR>", { desc = "Toggle 0/1 ↔ F/T" })
    vim.keymap.set("n", "<leader>ttr", "<cmd>TruthTableDropRow<CR>", { desc = "Drop truth table row" })
    vim.keymap.set("n", "<leader>ttc", "<cmd>TruthTableDropColumn<CR>", { desc = "Drop truth table column" })
    vim.keymap.set("n", "<leader>ttk", "<cmd>TruthTableKarnaugh<CR>", { desc = "Karnaugh map for column" })
    M.configured = true
end

return M
