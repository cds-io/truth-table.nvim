-- The lesson pane as styled text, when vellum.nvim is installed. Its renderer
-- turns a step's Markdown into lines wrapped to a width, plus the highlight
-- spans that style them, and tutor.lua paints both. The renderer is a module
-- vellum keeps for its own preview, with no promise that it stays as it is,
-- so what comes back is checked here and every surprise comes out as nil:
-- tutor.lua then shows the Markdown itself.
local M = {}

-- The widest column of text, as in vellum's own preview.
local MEASURE = 100

-- Whether vellum's highlight groups are defined for the current colorscheme,
-- and whether the reader has been told that vellum failed.
local themed, warned = false, false

local function vellum()
    local found, render = pcall(require, "vellum.render")
    local found_theme, theme = pcall(require, "vellum.theme")
    if found and found_theme then
        return render, theme
    end
end

local function compose(render, theme, markdown, width)
    if not themed then
        theme.apply()
        -- Rendered blocks are cached with the groups they were given.
        render.reset()
        themed = true
    end
    -- The renderer parses a buffer; this one is never shown.
    local source = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(source, 0, -1, false, markdown)
    local ok, lines, rows, margin = pcall(render.render, source, width, MEASURE)
    vim.api.nvim_buf_delete(source, { force = true })
    assert(ok, lines)

    -- vellum counts a span's columns from the text's left edge, and indents
    -- every line by `margin` to centre the text.
    local marks = {}
    for row, line in ipairs(lines) do
        assert(type(line) == "string", "a line that is not text")
        for _, span in ipairs(rows[row] or {}) do
            local from, to, group = span[1] + margin, span[2] + margin, span[3]
            assert(from >= 0 and from <= to and to <= #line and type(group) == "string", "a span outside its line")
            marks[#marks + 1] = { row = row - 1, col = from, end_col = to, group = group, priority = span[4] }
        end
    end
    return lines, marks
end

-- `markdown` (a list of lines) for a pane `width` columns wide: the lines to
-- show and the marks { row, col, end_col, group, priority } that style them,
-- rows and byte columns counted from zero. Nil when vellum is not installed,
-- and nil with one warning when it is and cannot do this.
function M.render(markdown, width)
    local render, theme = vellum()
    if not render then
        return
    end
    local ok, lines, marks = pcall(compose, render, theme, markdown, width)
    if ok then
        return lines, marks
    end
    if not warned then
        warned = true
        local message = "vellum.nvim could not render the lesson, so the pane shows its Markdown: "
        vim.notify(message .. tostring(lines), vim.log.levels.WARN)
    end
end

-- A colorscheme clears the highlight groups: define them again on the next
-- render.
function M.restyle()
    themed = false
end

return M
