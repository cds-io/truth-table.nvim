-- The table model: headings, rows of the cells 0 and 1, and the encoding
-- the Markdown spells the cells in. A table comes in through `parse`, the
-- one validator, which the Markdown codec runs on the cells it reads; a
-- table built in Lua (core.build, over generate_rows) is valid as made.
-- Every other operation takes a valid table and returns one, leaving its
-- input as it was; the result may share rows with the input, and nothing
-- here changes a row. An index argument is still checked, since it comes
-- from the cursor.
local fp = require("truth-table.fp")
local result = require("truth-table.result")
local M = {}

-- The spelling of the cells 0 and 1 under each encoding: the one place a
-- cell is spelled, read by parse, render_rows and the Karnaugh map.
M.ENCODINGS = {
    bits = { [0] = "0", [1] = "1" },
    tf = { [0] = "F", [1] = "T" },
}

-- Each spelling back to its bit and its encoding.
local READ = {}
for encoding, spelling in pairs(M.ENCODINGS) do
    for bit, text in pairs(spelling) do
        READ[text] = { bit = bit, encoding = encoding }
    end
end

-- All 2^n rows of bits, with the first variable as the high bit.
function M.generate_rows(n)
    local rows = {}
    for value = 0, 2 ^ n - 1 do
        local row = {}
        for column = 1, n do
            row[column] = math.floor(value / (2 ^ (n - column))) % 2
        end
        rows[#rows + 1] = row
    end
    return rows
end

-- The headings as they are, or nil and the first that cannot head a
-- column: one that is no text, is blank, holds a line break or surrounding
-- blanks, or repeats an earlier one. A table has at least one column.
function M.headings(headers)
    if #headers == 0 then
        return nil, "Table must have at least one column"
    end
    local seen = {}
    for _, header in ipairs(headers) do
        if type(header) ~= "string" or header:find("[\r\n]") or header:match("^%s") or header:match("%s$") then
            return nil, "Invalid column heading: " .. tostring(header)
        end
        if header == "" or seen[header] then
            return nil, "Empty or duplicate column: " .. header
        end
        seen[header] = true
    end
    return headers
end

-- The table these headings and cell texts spell: the cells read as bits,
-- and the encoding they were spelled in ("bits" for a table with no rows).
-- Nil and the reason for a heading that cannot head a column, a row of the
-- wrong length, a cell that is no Boolean, or two encodings in one table.
function M.parse(headers, rows)
    local valid, err = M.headings(headers)
    if not valid then
        return nil, err
    end
    local encoding
    local bits, row_err = result.traverse(rows, function(cells, r)
        if #cells ~= #headers then
            return nil, "Row " .. r .. ": expected " .. #headers .. " cells, got " .. #cells
        end
        return result.traverse(cells, function(cell, c)
            local read = READ[cell]
            if not read then
                return nil, "Invalid Boolean at row " .. r .. ", column " .. c .. ": " .. tostring(cell)
            end
            if encoding and encoding ~= read.encoding then
                return nil, "Mixed Boolean encodings"
            end
            encoding = read.encoding
            return read.bit
        end)
    end)
    return result.map(bits, row_err, function(valid_rows)
        return { headers = headers, rows = valid_rows, encoding = encoding or "bits" }
    end)
end

-- The rows with each cell spelled in the table's encoding.
function M.render_rows(tbl)
    local spelling = M.ENCODINGS[tbl.encoding]
    return fp.map(tbl.rows, function(row)
        return fp.map(row, function(bit)
            return spelling[bit]
        end)
    end)
end

local function without(values, index)
    return fp.filter(values, function(_, i)
        return i ~= index
    end)
end

local function valid_index(index, count)
    return type(index) == "number" and index == math.floor(index) and index >= 1 and index <= count
end

-- The table with `columns` appended, each { heading, values } with one
-- value per row, computed before they arrive here. A column whose heading
-- the table has already is skipped, so an expansion asked for twice adds
-- nothing.
function M.append_columns(tbl, columns)
    local headers, seen, appended = {}, {}, {}
    for i, header in ipairs(tbl.headers) do
        headers[i], seen[header] = header, true
    end
    for _, column in ipairs(columns) do
        if not seen[column.heading] then
            seen[column.heading] = true
            headers[#headers + 1] = column.heading
            appended[#appended + 1] = column
        end
    end
    local rows = fp.map(tbl.rows, function(row, index)
        local extended = {}
        for i, bit in ipairs(row) do
            extended[i] = bit
        end
        for _, column in ipairs(appended) do
            extended[#extended + 1] = column.values[index]
        end
        return extended
    end)
    return { headers = headers, rows = rows, encoding = tbl.encoding }
end

function M.drop_row(tbl, index)
    if not valid_index(index, #tbl.rows) then
        return nil, "Invalid data row index: " .. tostring(index)
    end
    return { headers = tbl.headers, rows = without(tbl.rows, index), encoding = tbl.encoding }
end

function M.drop_column(tbl, index)
    if not valid_index(index, #tbl.headers) then
        return nil, "Invalid column index: " .. tostring(index)
    end
    if #tbl.headers == 1 then
        return nil, "Cannot drop the only column"
    end
    return {
        headers = without(tbl.headers, index),
        rows = fp.map(tbl.rows, function(row) return without(row, index) end),
        encoding = tbl.encoding,
    }
end

function M.toggle(tbl)
    return {
        headers = tbl.headers, rows = tbl.rows,
        encoding = tbl.encoding == "tf" and "bits" or "tf",
    }
end

return M
