-- Editor-only preview state. The source buffer remains unchanged until apply.
local predicate = require("truth-table.predicate")
local markdown = require("truth-table.markdown")
local derivation = require("truth-table.derivation")
local rewrite = require("truth-table.rewrite")
local M = {}
local namespace = vim.api.nvim_create_namespace("truth-table.preview")
local pending, attached = {}, {}

-- Each rewrite maps a located tree and a cursor byte to a new tree. `command`
-- groups the names one user command toggles; `whole` marks a rewrite of the
-- whole expression, which needs no operand under the cursor.
local REWRITES = {
    de_morgan = {
        command = "de_morgan",
        whole = true,
        run = function(ast)
            return predicate.de_morgan(ast)
        end,
    },
    factor = { command = "factor", run = rewrite.factor },
    distribute = { command = "distribute", run = rewrite.distribute },
    commute = {
        command = "commute",
        run = function(ast, byte)
            return rewrite.commute(ast, byte, false)
        end,
    },
    commute_back = {
        command = "commute",
        run = function(ast, byte)
            return rewrite.commute(ast, byte, true)
        end,
    },
}

local function dismiss(buf)
    pending[buf] = nil
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
end

local function watch(buf)
    if attached[buf] then
        return
    end
    attached[buf] = vim.api.nvim_buf_attach(buf, false, {
        on_lines = function()
            local preview = pending[buf]
            pending[buf] = nil
            if preview then
                vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(buf) then
                        pcall(vim.api.nvim_buf_del_extmark, buf, namespace, preview.mark)
                    end
                end)
            end
        end,
        on_detach = function()
            attached[buf], pending[buf] = nil, nil
        end,
    })
end

-- A source is the expression the cursor selects plus the ways to write a
-- rewritten one back: `replace(text)` gives the edited line, and `step(text)`,
-- for expression lines only, gives the line to insert below. `offset` is the
-- cursor's byte within the expression, when it has one.

-- A heading is one expression, read from anywhere in its column. Only the
-- heading row itself puts the cursor on a byte of the expression.
local function heading_source(lines, bounds, at)
    local selected = {}
    for i = bounds.start_line, bounds.end_line do
        selected[#selected + 1] = lines[i]
    end
    local tbl, err = markdown.parse_table_lines(selected)
    if not tbl then
        return nil, err
    end
    local heading_line = lines[bounds.start_line]
    local column = math.min(markdown.column_index(lines[at.row], at.byte - 1), #tbl.headers)
    local expression = tbl.headers[column]
    local offset
    if at.row == bounds.start_line then
        local first, last = markdown.heading_cell(heading_line, column)
        -- An escaped heading does not map byte for byte (nor does it parse).
        if first and heading_line:sub(first, last) == expression then
            offset = at.byte - first + 1
        end
    end
    return {
        row = bounds.start_line,
        column = column,
        expression = expression,
        offset = offset,
        replace = function(text)
            return markdown.replace_heading(heading_line, column, text)
        end,
    }
end

local function line_source(line, at)
    if markdown.is_table_line(line) then
        return nil, "Cursor is not inside a supported truth table"
    end
    local side, err = derivation.working_side(line, at.byte)
    if not side then
        return nil, err
    end
    return {
        row = at.row,
        expression = side.text,
        offset = at.byte - side.first + 1,
        replace = function(text)
            return derivation.replace(line, side, text)
        end,
        step = function(text)
            return derivation.step(line, text, vim.fn.strdisplaywidth)
        end,
    }
end

local function resolve(buf, kind)
    local position = vim.api.nvim_win_get_cursor(0)
    local at = { row = position[1], byte = position[2] + 1 }
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local bounds = markdown.find_table(lines, at.row)
    local source, err
    if bounds then
        source, err = heading_source(lines, bounds, at)
    else
        source, err = line_source(lines[at.row], at)
    end
    if not source then
        return nil, err
    end
    local ast, parse_err = predicate.parse_located(source.expression)
    if not ast then
        return nil, parse_err
    end
    if not kind.whole and not source.offset then
        return nil, "Put the cursor on the heading row to choose an operand"
    end
    local rewritten, rewrite_err = kind.run(ast, source.offset)
    if not rewritten then
        return nil, rewrite_err
    end
    local heading = predicate.ast_to_heading(rewritten)
    local replacement, replace_err = source.replace(heading)
    if not replacement then
        return nil, replace_err
    end
    local preview = {
        row = source.row - 1,
        replacement = replacement,
        heading = heading,
        column = source.column,
        command = kind.command,
        tick = vim.api.nvim_buf_get_changedtick(buf),
    }
    if source.step then
        preview.step, preview.step_column = source.step(heading)
    end
    return preview
end

-- Running the pending preview's own command dismisses it; any other rewrite
-- replaces it.
function M.toggle(name)
    local kind = REWRITES[name]
    local buf = vim.api.nvim_get_current_buf()
    local shown = pending[buf]
    if shown then
        dismiss(buf)
        if shown.command == kind.command then
            return
        end
    end
    local preview, err = resolve(buf, kind)
    if not preview then
        vim.notify(err, vim.log.levels.WARN)
        return
    end
    watch(buf)
    local label = preview.column and (" [column " .. preview.column .. "] ⇒ ") or " ⇒ "
    preview.mark = vim.api.nvim_buf_set_extmark(buf, namespace, preview.row, 0, {
        virt_text = { { label .. preview.heading, "Comment" } }, virt_text_pos = "eol",
    })
    pending[buf] = preview
    if preview.column then
        vim.notify("Applying renames the heading; update explicit references to its old label if needed", vim.log.levels.INFO)
    end
end

-- The pending preview, provided the buffer is as it was when the preview was
-- made. Otherwise the stale state is cleared and the user is told.
local function current(buf)
    local preview = pending[buf]
    if not preview or preview.tick ~= vim.api.nvim_buf_get_changedtick(buf) then
        dismiss(buf)
        vim.notify("No current preview; run a rewrite command first", vim.log.levels.WARN)
        return nil
    end
    return preview
end

function M.apply()
    local buf = vim.api.nvim_get_current_buf()
    local preview = current(buf)
    if not preview then
        return
    end
    -- Clear state before editing so the attachment cannot invalidate a new mark.
    dismiss(buf)
    vim.api.nvim_buf_set_lines(buf, preview.row, preview.row + 1, false, { preview.replacement })
end

-- Insert the rewritten expression as the next line of a derivation and leave
-- the cursor on it, ready for the next rewrite.
function M.apply_step()
    local buf = vim.api.nvim_get_current_buf()
    local preview = current(buf)
    if not preview then
        return
    end
    if not preview.step then
        vim.notify("Steps apply to expression lines; use :TruthTableApply for a heading", vim.log.levels.WARN)
        return
    end
    dismiss(buf)
    vim.api.nvim_buf_set_lines(buf, preview.row + 1, preview.row + 1, false, { preview.step })
    vim.api.nvim_win_set_cursor(0, { preview.row + 2, preview.step_column })
end

return M
