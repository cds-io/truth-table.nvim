-- The table commands: each reads the table under the cursor, binds it
-- through the core, and writes the formatted result back, one Result
-- convention throughout. The dot-repeat of a table edit lives here too,
-- since the edits are what it replays.
local core = require("truth-table.core")
local list = require("truth-table.list")
local text = require("truth-table.text")
local result = require("cds.result")

local M = {}

-- Apply only complete successful pipelines; failures leave the buffer untouched.
local function replace_table(first, last, tbl, err, indent)
    local lines, format_err = result.bind(tbl, err, core.format)
    if not lines then
        vim.notify(format_err, vim.log.levels.WARN)
        return
    end
    vim.api.nvim_buf_set_lines(0, first, last, false, text.indented(lines, indent or ""))
end

local function get_cursor_column_index()
    local cursor = vim.api.nvim_win_get_cursor(0)
    return core.column_index(vim.api.nvim_get_current_line(), cursor[2])
end

-- The table under the cursor as a model plus its buffer bounds, or nil and an
-- error. Bounds are one-based, inclusive line numbers.
local function read_table()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    return core.table_at(lines, vim.api.nvim_win_get_cursor(0)[1])
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
        vim.go.operatorfunc = "v:lua.require'truth-table.commands.table'.operator"
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
    local lines = list.concat({ "" }, text.indented(core.format_karnaugh(analysis), bounds.indent))
    vim.api.nvim_buf_set_lines(0, bounds.end_line, bounds.end_line, false, lines)
end

M.truth_table, M.expand, M.drop_row = cmd_truth_table, cmd_expand, cmd_drop_row
M.drop_column, M.toggle, M.karnaugh = cmd_drop_column, cmd_toggle, cmd_karnaugh

return M
