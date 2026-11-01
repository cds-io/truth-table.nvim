-- A highlight mark on one line: { row, col, end_col, group, priority }, the
-- row and byte columns from zero with end_col exclusive, and the highlight
-- group it is painted in. The lit terms of a written rewrite (edit.lua), of
-- a pending preview (preview.lua) and the tutor's colour spans (tutor.lua,
-- tutor_vellum.lua) are lists of these, painted and read back here.
local fp = require("cds.fp")
local M = {}

-- Paint `marks` in `namespace` of `buf`; their extmark ids, in order.
function M.paint(buf, namespace, marks)
    return fp.map(marks, function(mark)
        return vim.api.nvim_buf_set_extmark(buf, namespace, mark.row, mark.col, {
            end_col = mark.end_col,
            hl_group = mark.group,
            priority = mark.priority,
        })
    end)
end

-- The marks in `namespace` of `buf`, as painted.
function M.read(buf, namespace)
    return fp.map(vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true }), function(found)
        local detail = found[4]
        return {
            row = found[2],
            col = found[3],
            end_col = detail.end_col,
            group = detail.hl_group,
            priority = detail.priority,
        }
    end)
end

return M
