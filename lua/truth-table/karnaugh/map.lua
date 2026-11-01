-- The Karnaugh map drawn: the cells of an analysis in textbook layout, and
-- the lines that go below the table (the map when drawable, and the
-- formula). init.lua makes the analysis; this only draws it. Pure.
local fp = require("cds.fp")
local list = require("truth-table.list")
local model = require("truth-table.table_model")
local markdown = require("truth-table.markdown")
local SYMBOLS = require("truth-table.symbols")
local M = {}

-- Reflexive Gray code: each neighbour differs in one bit, including wrapping.
local GRAY = { { "0", "1" }, { "00", "01", "11", "10" } }

local function axis_label(names)
    local long = fp.any(names, function(name)
        return #name > 1
    end)
    return table.concat(names, long and " " or "")
end

-- Textbook layout: the last two inputs run across the columns (one input for
-- a two-variable map), the rest down the rows, both in Gray order. An extra
-- heading row and leading column carry the axis labels. Maps are drawn for
-- two to four inputs; a larger map would need stacked panels.
function M.map_cells(analysis)
    local width = #analysis.inputs
    if width < 2 or width > 4 then
        return nil
    end
    local column_count = width == 2 and 1 or 2
    local row_count = width - column_count
    local row_names = list.slice(analysis.inputs, 1, row_count)
    local column_names = list.slice(analysis.inputs, row_count + 1, width)
    local row_codes, column_codes = GRAY[row_count], GRAY[column_count]
    local symbols = model.ENCODINGS[analysis.encoding]

    local headers = { "", "" }
    for i = 1, #column_codes do
        headers[2 + i] = ""
    end
    headers[2 + math.ceil(#column_codes / 2)] = axis_label(column_names)

    local rows = { { "", "" } }
    for i, code in ipairs(column_codes) do
        rows[1][2 + i] = code
    end
    for r, row_code in ipairs(row_codes) do
        local cells = { r == 1 and axis_label(row_names) or "", row_code }
        for _, column_code in ipairs(column_codes) do
            local value = analysis.values[row_code .. column_code]
            cells[#cells + 1] = value == nil and "X" or symbols[value]
        end
        rows[#rows + 1] = cells
    end
    return headers, rows
end

-- Lines to insert below the table: the map (when drawable) and the formula.
function M.render(analysis, display_width)
    local formula = analysis.target .. " " .. SYMBOLS.EQUIV.unicode .. " " .. analysis.formula
    local headers, rows = M.map_cells(analysis)
    if not headers then
        return { formula }
    end
    local title = "Karnaugh map for " .. analysis.target .. ":"
    return list.concat({ title, "" }, markdown.format_cells(headers, rows, display_width), { "", formula })
end

return M
