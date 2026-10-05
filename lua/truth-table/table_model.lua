-- Semantic cells are 0/1; encoding belongs to the Markdown boundary.
-- All transformations return fresh arrays and use value, error results.
local fp = require("truth-table.fp")
local result = require("truth-table.result")
local M = {}
local bits = { ["0"] = 0, ["1"] = 1, F = 0, T = 1, [0] = 0, [1] = 1 }

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

-- ipairs stops at holes. Validate array shape before traversing public input.
local function dense_array(values, label)
    if type(values) ~= "table" then
        return nil, label .. " must be an array"
    end
    local count = 0
    for key in pairs(values) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return nil, label .. " must be a dense array"
        end
        count = count + 1
    end
    for index = 1, count do
        if values[index] == nil then
            return nil, label .. " must be a dense array"
        end
    end
    return values
end

function M.normalize(tbl)
    if type(tbl) ~= "table" then
        return nil, "Expected a table model"
    end
    local headers_input, header_err = dense_array(tbl.headers, "Headers")
    if not headers_input then
        return nil, header_err
    end
    local rows_input, rows_err = dense_array(tbl.rows, "Rows")
    if not rows_input then
        return nil, rows_err
    end
    if #tbl.headers == 0 then
        return nil, "Table must have at least one column"
    end
    if tbl.encoding and tbl.encoding ~= "bits" and tbl.encoding ~= "tf" then
        return nil, "Unknown Boolean encoding: " .. tostring(tbl.encoding)
    end
    local seen = {}
    local headers, err = result.traverse(tbl.headers, function(header)
        if type(header) ~= "string" or header:find("[\r\n]") or header:match("^%s") or header:match("%s$") then
            return nil, "Invalid column heading: " .. tostring(header)
        end
        if header == "" or seen[header] then
            return nil, "Empty or duplicate column: " .. header
        end
        seen[header] = true
        return header
    end)
    return result.bind(headers, err, function(valid_headers)
        local encoding
        local rows, row_err = result.traverse(tbl.rows, function(row, r)
            local dense, dense_err = dense_array(row, "Row " .. r)
            if not dense then
                return nil, dense_err
            end
            if #row ~= #valid_headers then
                return nil, "Row " .. r .. ": expected " .. #valid_headers .. " cells, got " .. #row
            end
            return result.traverse(row, function(cell, col)
                local bit = bits[cell]
                if bit == nil then
                    return nil, "Invalid Boolean at row " .. r .. ", column " .. col .. ": " .. tostring(cell)
                end
                local style = type(cell) == "number" and (tbl.encoding or "bits")
                    or ((cell == "T" or cell == "F") and "tf" or "bits")
                if (encoding and encoding ~= style) or (tbl.encoding and tbl.encoding ~= style) then
                    return nil, "Mixed Boolean encodings"
                end
                encoding = style
                return bit
            end)
        end)
        return result.bind(rows, row_err, function(valid_rows)
            return { headers = valid_headers, rows = valid_rows, encoding = encoding or tbl.encoding or "bits" }
        end)
    end)
end

function M.render_rows(tbl)
    local symbols = tbl.encoding == "tf" and { [0] = "F", [1] = "T" } or { [0] = "0", [1] = "1" }
    return result.traverse(tbl.rows, function(row)
        return result.traverse(row, function(bit)
            return symbols[bit]
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

-- Append materialized columns. Formula parsing/evaluation stays outside this
-- module; the model owns shape validation, copying, and duplicate headings.
function M.append_columns(tbl, columns)
    local normalized, err = M.normalize(tbl)
    return result.bind(normalized, err, function(valid)
        local headers, seen, appended = {}, {}, {}
        for i, header in ipairs(valid.headers) do
            headers[i], seen[header] = header, true
        end
        local dense, dense_err = dense_array(columns, "Columns")
        if not dense then
            return nil, dense_err
        end
        for _, column in ipairs(columns) do
            if type(column) ~= "table" or type(column.heading) ~= "string" then
                return nil, "Expected a column heading and values"
            end
            local values, values_err = dense_array(column.values, "Column values")
            if not values then
                return nil, values_err
            end
            if #column.values ~= #valid.rows then
                return nil, "Column row count does not match table: " .. tostring(column.heading)
            end
            if not seen[column.heading] then
                seen[column.heading] = true
                headers[#headers + 1] = column.heading
                appended[#appended + 1] = column
            end
        end
        local rows = result.traverse(valid.rows, function(row, index)
            local extended = {}
            for i, bit in ipairs(row) do
                extended[i] = bit
            end
            for _, column in ipairs(appended) do
                extended[#extended + 1] = column.values[index]
            end
            return extended
        end)
        return M.normalize({ headers = headers, rows = rows, encoding = valid.encoding })
    end)
end

function M.drop_row(tbl, index)
    local normalized, err = M.normalize(tbl)
    return result.bind(normalized, err, function(valid)
        if not valid_index(index, #valid.rows) then
            return nil, "Invalid data row index: " .. tostring(index)
        end
        return { headers = valid.headers, rows = without(valid.rows, index), encoding = valid.encoding }
    end)
end

function M.drop_column(tbl, index)
    local normalized, err = M.normalize(tbl)
    return result.bind(normalized, err, function(valid)
        if not valid_index(index, #valid.headers) then
            return nil, "Invalid column index: " .. tostring(index)
        end
        if #valid.headers == 1 then
            return nil, "Cannot drop the only column"
        end
        return {
            headers = without(valid.headers, index),
            rows = result.traverse(valid.rows, function(row) return without(row, index) end),
            encoding = valid.encoding,
        }
    end)
end

function M.toggle(tbl)
    local normalized, err = M.normalize(tbl)
    return result.bind(normalized, err, function(valid)
        return {
            headers = valid.headers, rows = valid.rows,
            encoding = valid.encoding == "tf" and "bits" or "tf",
        }
    end)
end

return M
