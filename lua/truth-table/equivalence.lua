-- Live equivalence marks for the table at the cursor: a virtual line under
-- the separator, with ≡ centred below each column whose cells match the
-- cursor column's on every row, the cursor's own among them, and ≢ below
-- the rest, so the line keeps its height while the cursor crosses columns
-- rather than popping in and out. One global switch, on by default:
-- setup({ equivalence = false }) starts it off, :TruthTableEquivalents
-- toggles it everywhere. While on, the marks follow the cursor, sit only
-- in the current buffer, and show nothing where there is no table, the
-- table is mid-edit, or it has no data rows. The buffer itself never
-- changes.
local core = require("truth-table.core")
local fp = require("truth-table.fp")
local M = {}
local namespace = vim.api.nvim_create_namespace("truth-table.equivalence")
local GROUP = "truth_table_equivalence"
local enabled = false

local function clear(buf)
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
end

-- Repaint the mark line for the table at the cursor in `buf`, the current
-- buffer when the autocmds fire. Anything short of a valid table with a
-- data row paints nothing, silently: mid-edit the table parses as
-- nothing, and that is navigation, not an error.
function M.refresh(buf)
    clear(buf)
    local cursor = vim.api.nvim_win_get_cursor(0)
    -- The cursor's own line first: the autocmds run on every move in
    -- every buffer, and most moves are nowhere near a table, so one line
    -- and one match settle those before the whole buffer is read.
    local at = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
    if not core.is_table_line(at) then
        return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local bounds = core.find_table(lines, cursor[1])
    if not bounds then
        return
    end
    local selected = {}
    for row = bounds.start_line, bounds.end_line do
        selected[#selected + 1] = lines[row]
    end
    local tbl = core.parse(selected)
    if not tbl or #tbl.rows == 0 then
        return
    end
    local column = math.min(core.column_index(lines[cursor[1]], cursor[2]), #tbl.headers)
    local members = fp.set(core.equivalent_columns(tbl, column))
    -- The separator line carries the spans the marks centre in; the mark
    -- sits on it (0-based bounds.start_line) and the line hangs below.
    local chunks, after = {}, 0
    for index, centre in ipairs(core.column_centres(lines[bounds.start_line + 1])) do
        chunks[#chunks + 1] = {
            string.rep(" ", centre - after) .. (members[index] and "≡" or "≢"),
            members[index] and "TruthTableEquivalent" or "TruthTableInequivalent",
        }
        after = centre + 1
    end
    vim.api.nvim_buf_set_extmark(buf, namespace, bounds.start_line, 0, {
        virt_lines = { chunks },
    })
end

-- Switch the marks on or off everywhere: on arms the autocmds and paints
-- at the cursor; off takes the autocmds down and every buffer's marks
-- with them. Idempotent, so setup() may state the configured value again.
function M.set(on)
    if on == enabled then
        return
    end
    enabled = on
    if on then
        local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
        vim.api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "InsertLeave", "BufEnter" }, {
            group = group,
            callback = function(event)
                M.refresh(event.buf)
            end,
        })
        -- Only the buffer the cursor is in carries marks: left behind,
        -- they would go stale as the cursor column changes elsewhere.
        vim.api.nvim_create_autocmd("BufLeave", {
            group = group,
            callback = function(event)
                clear(event.buf)
            end,
        })
        M.refresh(vim.api.nvim_get_current_buf())
    else
        vim.api.nvim_del_augroup_by_name(GROUP)
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) then
                clear(buf)
            end
        end
    end
end

function M.toggle()
    M.set(not enabled)
    vim.notify(enabled and "Equivalence marks on" or "Equivalence marks off", vim.log.levels.INFO)
end

return M
