-- A highlight mark on one line: { row, col, end_col, group, priority }, the
-- row and byte columns from zero with end_col exclusive, and the highlight
-- group it is painted in. The lit terms of a written rewrite (edit.lua), of
-- a pending preview (preview.lua) and the tutor's colour spans (tutor.lua,
-- tutor_vellum.lua) are lists of these, painted and read back here.
local M = {}

-- Paint `marks` in `namespace` of `buf`; their extmark ids, in order.
function M.paint(buf, namespace, marks)
    local ids = {}
    for i, mark in ipairs(marks) do
        ids[i] = vim.api.nvim_buf_set_extmark(buf, namespace, mark.row, mark.col, {
            end_col = mark.end_col,
            hl_group = mark.group,
            priority = mark.priority,
        })
    end
    return ids
end

-- The marks in `namespace` of `buf`, as painted.
function M.read(buf, namespace)
    local out = {}
    for _, found in ipairs(vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })) do
        local detail = found[4]
        out[#out + 1] = {
            row = found[2], col = found[3], end_col = detail.end_col,
            group = detail.hl_group, priority = detail.priority,
        }
    end
    return out
end

return M
