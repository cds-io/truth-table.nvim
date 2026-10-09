-- The lesson pane as styled text, when vellum.nvim is installed. Its renderer
-- turns a step's Markdown into lines wrapped to a width, plus the highlight
-- spans that style them, and tutor.lua paints both. The renderer is a module
-- vellum keeps for its own preview, with no promise that it stays as it is,
-- so what comes back is checked here and every surprise comes out as nil:
-- tutor.lua then shows the Markdown itself. The lesson's own colour spans
-- ride along: vellum says which rendered rows each Markdown block became,
-- and tutor_spans.lua finds the spans' lines in there.
local spans = require("truth-table.tutor_spans")
local M = {}

-- The widest column of text, as in vellum's own preview.
local MEASURE = 100

-- Whether vellum's highlight groups are defined for the current colorscheme,
-- and whether the reader has been told that vellum failed.
local themed, warned = false, false

-- vellum's renderer and theme, as one record, when it is installed.
local function vellum()
    local found, render = pcall(require, "vellum.render")
    local found_theme, theme = pcall(require, "vellum.theme")
    if found and found_theme then
        return { render = render, theme = theme }
    end
end

-- One of vellum's block anchors: four numbers placing the block's source rows
-- in `page.markdown` and its rendered rows in `page.lines`.
local function anchored(block, page)
    for i = 1, 4 do
        if type(block[i]) ~= "number" then
            return false
        end
    end
    return block[1] >= 0 and block[1] + block[2] <= #page.markdown
        and block[3] >= 0 and block[3] + block[4] <= #page.lines
end

-- `markdown` through vellum, `toolkit`, at `width`, with the lesson's spans `marked`:
-- the lines and the marks of render() below, or an error for anything that
-- comes back in a shape not expected.
local function compose(toolkit, markdown, width, marked)
    if not themed then
        toolkit.theme.apply()
        -- Rendered blocks are cached with the groups they were given.
        toolkit.render.reset()
        themed = true
    end
    -- The renderer parses a buffer; this one is never shown.
    local source = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(source, 0, -1, false, markdown)
    local ok, lines, rows, margin, blocks = pcall(toolkit.render.render, source, width, MEASURE)
    vim.api.nvim_buf_delete(source, { force = true })
    assert(ok, lines)

    -- vellum counts a span's columns from the text's left edge, and indents
    -- every line by `margin` to centre the text.
    local found = {}
    for row, line in ipairs(lines) do
        assert(type(line) == "string", "a line that is not text")
        for _, span in ipairs(rows[row] or {}) do
            local from, to, group = span[1] + margin, span[2] + margin, span[3]
            assert(from >= 0 and from <= to and to <= #line and type(group) == "string", "a span outside its line")
            found[#found + 1] = { row = row - 1, col = from, end_col = to, group = group, priority = span[4] }
        end
    end
    assert(type(blocks) == "table", "no block anchors")
    local page = { markdown = markdown, lines = lines, blocks = blocks }
    for _, block in ipairs(blocks) do
        assert(anchored(block, page), "a block anchor outside the page")
    end
    for _, mark in ipairs(spans.place(marked or {}, page)) do
        local line = lines[mark.row + 1]
        assert(mark.col >= 0 and mark.col <= mark.end_col and mark.end_col <= #line, "a colour span outside its line")
        found[#found + 1] = mark
    end
    return lines, found
end

-- `markdown` (a list of lines) for a pane `width` columns wide, with the
-- lesson's colour spans `marked` (rows into `markdown`, from one): the lines
-- to show and the marks { row, col, end_col, group, priority } that style
-- them, rows and byte columns counted from zero. Nil when vellum is not
-- installed, and nil with one warning when it is and cannot do this.
function M.render(markdown, width, marked)
    local found = vellum()
    if not found then
        return
    end
    local ok, lines, marks = pcall(compose, found, markdown, width, marked)
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

-- A session started over is told again, once, should vellum still fail.
function M.forget()
    warned = false
end

return M
