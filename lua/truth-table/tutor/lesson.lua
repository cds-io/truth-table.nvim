-- The lesson pane drawn: the step's page, styled for the pane's width when
-- vellum.nvim is installed and as Markdown otherwise, the lesson's colour
-- spans painted as marks, the progress bar in the winbar, and the highlight
-- groups all of it uses. Draws into the session init.lua holds; the
-- session itself is changed only there.
local fp = require("cds.fp")
local page = require("truth-table.tutor.page")
local styled = require("truth-table.tutor.vellum")
local spans = require("truth-table.tutor.spans")
local marks = require("truth-table.marks")
local panes = require("truth-table.tutor.panes")
local M = {}

local dress = panes.dress
local MARKS = vim.api.nvim_create_namespace(panes.ROLE)
-- The lesson pane by what it shows. Markdown is one line per paragraph, for
-- the window to wrap at whatever width it has. Styled text arrives wrapped to
-- the window's full width, so the window gives up its gutter and leaves the
-- lines alone.
local LESSON_PANE = {
    markdown = {
        filetype = "markdown",
        options = { wrap = true, linebreak = true, breakindent = true, breakindentopt = "list:-1" },
    },
    styled = {
        filetype = "truth-table-tutor",
        options = {
            wrap = false,
            list = false,
            spell = false,
            colorcolumn = "",
            number = false,
            relativenumber = false,
            signcolumn = "no",
            foldcolumn = "0",
            statuscolumn = "",
        },
    },
}

-- The last lesson the reader has been to.
local function visited(session)
    return session.steps[session.furthest].lesson
end

-- The colour spans' and the progress bar's highlight groups, as defaults:
-- one the reader defines stands.
local function palette()
    for _, entry in ipairs(spans.PALETTE) do
        local attrs = { default = true, link = entry.link }
        if entry.underline then
            local linked = vim.api.nvim_get_hl(0, { name = entry.link, link = false })
            attrs = { default = true, fg = linked.fg, ctermfg = linked.ctermfg, underline = true }
        end
        vim.api.nvim_set_hl(0, entry.group, attrs)
    end
    for _, entry in pairs(page.STATES) do
        vim.api.nvim_set_hl(0, entry.group, { default = true, link = entry.link })
    end
end

-- A lesson's spans as marks on the lines they were found in.
local function marks_of(marked)
    return fp.map(marked, function(span)
        return {
            row = span.row - 1,
            col = span.col,
            end_col = span.end_col,
            group = span.group,
            priority = spans.PRIORITY,
        }
    end)
end

local function paint(buf, found)
    marks.paint(buf, MARKS, found)
end

-- The reader's step in the lesson pane `win`, which shows the lesson buffer:
-- styled for the width the pane has now, or as Markdown when that fails,
-- with the place and the progress bar in the pane's winbar, where scrolling
-- leaves them. The lesson's colour spans are painted either way; load()
-- checked every step renders.
-- Answers the width the text was wrapped to, or nil when it is Markdown.
local function draw(session, win)
    local at = session.steps[session.at]
    local markdown, marked = page.render(session.course, at)
    assert(markdown, marked)
    local width = vim.api.nvim_win_get_width(win)
    local lines, styled_marks = styled.render(markdown, width, marked)
    local pane = lines and LESSON_PANE.styled or LESSON_PANE.markdown

    local buf = session.lesson
    local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_clear_namespace(buf, MARKS, 0, -1)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or markdown)
    vim.bo[buf].modifiable = false
    paint(buf, lines and styled_marks or marks_of(marked))
    dress(buf, pane.filetype)
    -- Set after the buffer is in the window, and local to it. A window takes
    -- fresh options when it first shows a buffer: set any earlier, these are
    -- lost, and the scratch pane, split off this one, keeps the reader's own.
    for name, value in pairs(pane.options) do
        vim.api.nvim_set_option_value(name, value, { win = win, scope = "local" })
    end
    local progress = page.progress(session.course, at, visited(session))
    vim.api.nvim_set_option_value("winbar", progress, { win = win, scope = "local" })
    vim.api.nvim_win_call(win, function()
        vim.fn.winrestview(view)
    end)
    return lines and width
end

M.palette, M.marks_of, M.paint, M.draw = palette, marks_of, paint, draw

return M
