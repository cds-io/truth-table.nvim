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

-- Compose parse -> transform -> format, using one Result convention throughout.
local function with_table(fn)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local bounds, find_err = core.find_table(lines, vim.api.nvim_win_get_cursor(0)[1])
    if not bounds then
        vim.notify(find_err, vim.log.levels.WARN)
        return
    end
    local selected = {}
    for row = bounds.start_line, bounds.end_line do
        selected[#selected + 1] = lines[row]
    end
    local tbl, err = core.parse_model(selected)
    local edited, edit_err = result.bind(tbl, err, function(valid)
        return fn(valid, bounds.start_line, bounds.end_line)
    end)
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

-- Register commands, keymaps, and (if present) which-key labels. Also injects
-- vim.fn.strdisplaywidth so column widths are terminal-accurate. Idempotent.
function M.setup()
    core.display_width = vim.fn.strdisplaywidth

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

    local preview = require("truth-table.preview")
    vim.api.nvim_create_user_command("TruthTableDeMorgan", preview.toggle, {
        desc = "Toggle a whole-expression De Morgan preview",
    })
    vim.api.nvim_create_user_command("TruthTableDeMorganApply", preview.apply, {
        desc = "Apply the current De Morgan preview",
    })

    local ok, wk = pcall(require, "which-key")
    if ok then
        -- selene: allow(mixed_table)
        -- which-key's spec is intentionally mixed: positional key + named group.
        wk.add({
            { "<leader>tt", group = "[T]ruth Table" },
        })
    end

    vim.keymap.set("n", "<leader>ttn", ":TruthTable ", { desc = "New truth table" })
    vim.keymap.set("x", "<leader>ttn", ":TruthTable<CR>", { desc = "New truth table from selection" })
    vim.keymap.set("n", "<leader>tte", ":TruthTableExpand ", { desc = "Expand truth table" })
    vim.keymap.set("n", "<leader>ttd", "<cmd>TruthTableDeMorgan<CR>", { desc = "Preview De Morgan rewrite" })
    vim.keymap.set("n", "<leader>tta", "<cmd>TruthTableDeMorganApply<CR>", { desc = "Apply De Morgan rewrite" })
    vim.keymap.set("n", "<leader>ttt", "<cmd>TruthTableToggle<CR>", { desc = "Toggle 0/1 ↔ F/T" })
    vim.keymap.set("n", "<leader>ttr", "<cmd>TruthTableDropRow<CR>", { desc = "Drop truth table row" })
    vim.keymap.set("n", "<leader>ttc", "<cmd>TruthTableDropColumn<CR>", { desc = "Drop truth table column" })
end

return M
