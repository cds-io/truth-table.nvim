-- Editor-only preview state. The source buffer remains unchanged until apply.
local predicate = require("truth-table.predicate")
local markdown = require("truth-table.markdown")
local M = {}
local namespace = vim.api.nvim_create_namespace("truth-table.de-morgan")
local pending, attached = {}, {}

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

local function resolve(buf)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local bounds = markdown.find_table(lines, cursor[1])
    local row = cursor[1]
    local expression, column
    if bounds then
        row = bounds.start_line
        local selected = {}
        for i = row, bounds.end_line do
            selected[#selected + 1] = lines[i]
        end
        local tbl, err = markdown.parse_table_lines(selected)
        if not tbl then
            return nil, err
        end
        column = math.min(markdown.column_index(lines[cursor[1]], cursor[2]), #tbl.headers)
        expression = tbl.headers[column]
    else
        if markdown.is_table_line(lines[row]) then
            return nil, "Cursor is not inside a supported truth table"
        end
        expression = lines[row]
    end
    local heading, err = predicate.de_morgan_expression(expression)
    if not heading then
        return nil, err
    end
    local replacement
    if column then
        replacement, err = markdown.replace_heading(lines[row], column, heading)
    else
        replacement = (lines[row]:match("^%s*") or "") .. heading
    end
    if not replacement then
        return nil, err
    end
    return { row = row - 1, replacement = replacement, heading = heading, column = column,
        tick = vim.api.nvim_buf_get_changedtick(buf) }
end

function M.toggle()
    local buf = vim.api.nvim_get_current_buf()
    if pending[buf] then
        dismiss(buf)
        return
    end
    local preview, err = resolve(buf)
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

function M.apply()
    local buf = vim.api.nvim_get_current_buf()
    local preview = pending[buf]
    if not preview or preview.tick ~= vim.api.nvim_buf_get_changedtick(buf) then
        dismiss(buf)
        vim.notify("No current De Morgan preview; run :TruthTableDeMorgan first", vim.log.levels.WARN)
        return
    end
    -- Clear state before editing so the attachment cannot invalidate a new mark.
    dismiss(buf)
    vim.api.nvim_buf_set_lines(buf, preview.row, preview.row + 1, false, { preview.replacement })
end

return M
