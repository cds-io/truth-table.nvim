-- truth-table.nvim: generate and manipulate markdown truth tables. The pure
-- parsing/eval/format logic lives in truth-table.core; this module holds the
-- Neovim-facing pieces (buffer scanning, the user commands, keymaps) and the
-- setup() entry point.

local core = require("truth-table.core")

local M = {}

-- Locate the markdown table the cursor is inside. Returns start_row, end_row
-- (1-based, inclusive) or nil. A valid table needs at least a heading and a
-- separator row, with the separator immediately under the heading.
local function find_table()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cur_row = cursor[1]
    local total = vim.api.nvim_buf_line_count(0)

    local cur_line = vim.api.nvim_buf_get_lines(0, cur_row - 1, cur_row, false)[1]
    if not core.is_table_line(cur_line) then
        return nil
    end

    local start_row = cur_row
    for row = cur_row - 1, 1, -1 do
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        if not core.is_table_line(line) then
            break
        end
        start_row = row
    end

    local end_row = cur_row
    for row = cur_row + 1, total do
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        if not core.is_table_line(line) then
            break
        end
        end_row = row
    end

    if end_row - start_row < 1 then
        return nil
    end

    local sep_line = vim.api.nvim_buf_get_lines(0, start_row, start_row + 1, false)[1]
    if not core.is_separator(sep_line) then
        return nil
    end

    return start_row, end_row
end

local function parse_table(start_line, end_line)
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    local tbl = core.parse_table_lines(lines)
    tbl.start_line = start_line
    tbl.end_line = end_line
    return tbl
end

local function get_cursor_column_index()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local col = cursor[2]
    local line = vim.api.nvim_get_current_line()
    local count = 0
    for i = 1, col + 1 do
        if line:sub(i, i) == "|" then
            count = count + 1
        end
    end
    return math.max(1, count)
end

-- Run fn with the table under the cursor, replacing the table's lines with fn's
-- returned (headers, rows). fn may return nil to abort silently (it is expected
-- to have notified the user itself). Shared by the editing commands.
local function with_table(fn)
    local start_line, end_line = find_table()
    if not start_line then
        vim.notify("Cursor is not inside a truth table", vim.log.levels.WARN)
        return
    end

    local tbl = parse_table(start_line, end_line)
    local headers, rows = fn(tbl, start_line, end_line)
    if not headers then
        return
    end

    local lines = core.format_table(headers, rows)
    vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, lines)
end

local function cmd_truth_table(opts)
    local headers, rows = core.build_truth_table(opts.args)
    if not headers then
        -- rows holds the error message in the failure case.
        vim.notify(rows, vim.log.levels.WARN)
        return
    end

    local lines = core.format_table(headers, rows)

    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_buf_set_lines(0, cursor[1] - 1, cursor[1] - 1, false, lines)
end

local function cmd_expand(opts)
    local predicates = vim.split(opts.args, ",", { trimempty = true })
    if #predicates == 0 then
        vim.notify("Usage: :TruthTableExpand predicate1, predicate2, ...", vim.log.levels.WARN)
        return
    end

    with_table(function(tbl)
        local new_headers, new_rows = core.expand(tbl, predicates)
        if not new_headers then
            -- new_rows holds the error message in the failure case.
            vim.notify(new_rows, vim.log.levels.ERROR)
            return nil
        end
        return new_headers, new_rows
    end)
end

local function cmd_drop_row()
    with_table(function(tbl, start_line)
        local cur_row = vim.api.nvim_win_get_cursor(0)[1]
        if cur_row <= start_line + 1 then
            vim.notify("Cannot drop heading or separator row", vim.log.levels.WARN)
            return nil
        end

        local row_idx = cur_row - start_line - 1
        table.remove(tbl.rows, row_idx)
        return tbl.headers, tbl.rows
    end)
end

local function cmd_drop_column()
    with_table(function(tbl)
        if #tbl.headers <= 1 then
            vim.notify("Cannot drop the only column", vim.log.levels.WARN)
            return nil
        end

        local col_idx = get_cursor_column_index()
        if col_idx > #tbl.headers then
            col_idx = #tbl.headers
        end

        table.remove(tbl.headers, col_idx)
        for _, row in ipairs(tbl.rows) do
            table.remove(row, col_idx)
        end
        return tbl.headers, tbl.rows
    end)
end

local function cmd_toggle()
    with_table(function(tbl)
        return tbl.headers, core.toggle_cells(tbl.rows)
    end)
end

-- Register commands, keymaps, and (if present) which-key labels. Also injects
-- vim.fn.strdisplaywidth so column widths are terminal-accurate. Idempotent.
function M.setup()
    core.display_width = vim.fn.strdisplaywidth

    vim.api.nvim_create_user_command("TruthTable", cmd_truth_table, {
        nargs = "+",
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

    local ok, wk = pcall(require, "which-key")
    if ok then
        -- selene: allow(mixed_table)
        -- which-key's spec is intentionally mixed: positional key + named group.
        wk.add({
            { "<leader>tt", group = "[T]ruth Table" },
        })
    end

    vim.keymap.set("n", "<leader>ttn", ":TruthTable ", { desc = "New truth table" })
    vim.keymap.set("n", "<leader>tte", ":TruthTableExpand ", { desc = "Expand truth table" })
    vim.keymap.set("n", "<leader>ttt", "<cmd>TruthTableToggle<CR>", { desc = "Toggle 0/1 ↔ F/T" })
    vim.keymap.set("n", "<leader>ttr", "<cmd>TruthTableDropRow<CR>", { desc = "Drop truth table row" })
    vim.keymap.set("n", "<leader>ttc", "<cmd>TruthTableDropColumn<CR>", { desc = "Drop truth table column" })
end

return M
