-- Markdown codec for Boolean tables: a table found in a buffer's lines and
-- parsed into the model. The line codec is line.lua and the formatter
-- format.lua; this composes the two under one name and holds what spans
-- lines: discovery and the parse of a whole table.
local model = require("truth-table.table_model")
local codec = require("truth-table.markdown.line")
local format = require("truth-table.markdown.format")
local M = {}

for _, part in ipairs({ codec, format }) do
    for name, fn in pairs(part) do
        M[name] = fn
    end
end

-- Parse a Markdown table into one validated semantic model.
function M.parse_table_lines(lines)
    if #lines < 2 or not M.is_separator(lines[2]) then
        return nil, "Expected a heading and separator"
    end
    local headers, err = M.row(lines[1])
    if not headers then
        return nil, err
    end
    local separator, separator_err = M.row(lines[2])
    if not separator then
        return nil, "Line 2: " .. separator_err
    end
    if #separator ~= #headers then
        return nil, "Separator column count does not match heading"
    end
    local rows = {}
    for i = 3, #lines do
        local row, row_err = M.row(lines[i])
        if not row then
            return nil, "Line " .. i .. ": " .. row_err
        end
        rows[#rows + 1] = row
    end
    return model.parse(headers, rows)
end

-- Discovery is separate from Boolean validation: malformed data must be found
-- and reported, rather than truncated out of a replacement range.
local function table_indent(line)
    local indent = line:match("^ *")
    if #indent > 3 or line:sub(#indent + 1, #indent + 1) == "\t" then
        return nil -- Markdown indented code, not a table.
    end
    return M.is_table_line(line) and indent or nil
end

local function fence_marker(line)
    local indent, run, rest = line:match("^( *)([`~]+)(.*)$")
    if not run or #indent > 3 or #run < 3 or run:find("[^" .. run:sub(1, 1) .. "]") then
        return nil
    end
    return { character = run:sub(1, 1), length = #run, rest = rest }
end

-- Returns editor bounds and indentation, without putting locations in the model.
-- Supports top-level Markdown tables indented by zero to three spaces.
function M.find_table(lines, cursor_row)
    local row, fence = 1, nil
    while row <= #lines do
        local marker = fence_marker(lines[row])
        if fence then
            if
                marker
                and marker.character == fence.character
                and marker.length >= fence.length
                and marker.rest:match("^%s*$")
            then
                fence = nil
            end
            row = row + 1
        elseif marker and (marker.character ~= "`" or not marker.rest:find("`", 1, true)) then
            fence = marker
            row = row + 1
        else
            local indent = table_indent(lines[row])
            local next_line = lines[row + 1]
            if indent and next_line and table_indent(next_line) == indent and M.is_separator(next_line) then
                local first, last = row, row + 1
                while lines[last + 1] and table_indent(lines[last + 1]) == indent do
                    -- A second heading/separator starts another table, even
                    -- when there is no blank line between the two blocks.
                    if
                        lines[last + 2]
                        and table_indent(lines[last + 2]) == indent
                        and M.is_separator(lines[last + 2])
                    then
                        break
                    end
                    last = last + 1
                end
                if cursor_row >= first and cursor_row <= last then
                    return { start_line = first, end_line = last, indent = indent }
                end
                row = last + 1
            else
                row = row + 1
            end
        end
    end
    return nil, "Cursor is not inside a truth table"
end

return M
