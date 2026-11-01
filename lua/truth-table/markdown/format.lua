-- Formatting a table as Markdown: the width measurement (an explicit
-- dependency, with a pure default), the centring, the escaping of a
-- heading, and the lines of a table whose cells are strings. The line
-- codec is line.lua; this only writes. Pure.
local fp = require("cds.fp")
local list = require("truth-table.list")
local model = require("truth-table.table_model")
local M = {}

-- Pure default: count UTF-8 codepoints (each as one column) by counting bytes
-- that are not continuation bytes. The Neovim layer overrides this with
-- vim.fn.strdisplaywidth for terminal-accurate widths (e.g. East Asian wide
-- characters); for the ASCII names and width-1 logic symbols this tool emits,
-- the two agree.
function M.display_width(str)
    local _, count = str:gsub("[^\128-\191]", "")
    return count
end

function M.center_pad(str, width, display_width)
    local pad = width - (display_width or M.display_width)(str)
    local left = math.floor(pad / 2)
    local right = pad - left
    return string.rep(" ", left) .. str .. string.rep(" ", right)
end

local function format_valid(headers, rows, display_width)
    local widths = fp.map(headers, function(header, i)
        return fp.reduce(rows, math.max(3, display_width(header)), function(widest, row)
            return math.max(widest, display_width(row[i]))
        end)
    end)

    local function line(cells)
        return "|" .. table.concat(cells, "|") .. "|"
    end
    -- A heading or data row: each cell centred in its column.
    local function padded(cells)
        return line(fp.map(cells, function(cell, i)
            return " " .. M.center_pad(cell, widths[i], display_width) .. " "
        end))
    end
    local separator = line(fp.map(widths, function(width)
        return ":" .. string.rep("-", width) .. ":"
    end))

    return list.concat({ padded(headers), separator }, fp.map(rows, padded))
end

-- Format arbitrary string cells (headers may be empty). The Boolean codec
-- (init.lua) validates before calling this; the Karnaugh renderer, whose cells are
-- Gray codes and axis labels, uses it directly.
function M.format_cells(headers, rows, display_width)
    return format_valid(headers, rows, display_width or M.display_width)
end

function M.escape_heading(header)
    return (header:gsub("\\", "\\\\"):gsub("|", "\\|"):gsub("`", "\\`"))
end

function M.format(tbl, display_width)
    local headers = fp.map(tbl.headers, M.escape_heading)
    return format_valid(headers, model.render_rows(tbl), display_width or M.display_width)
end

return M
