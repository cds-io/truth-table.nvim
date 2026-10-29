-- One Markdown table line: whether it is a row or a separator, its cells
-- with escaped pipes and backslashes read, the column at a byte, the bytes
-- of a heading cell, the display column each cell centres on, and one
-- heading replaced in place. One scanner owns the escapes for all of them.
-- Pure.
local result = require("cds.result")
local model = require("truth-table.table_model")
local format = require("truth-table.markdown.format")
local trim = require("truth-table.text").trim
local M = {}

function M.is_table_line(line)
    return line:match("^%s*|.*|%s*$") ~= nil
end

function M.is_separator(line)
    local inner = line:match("^%s*|(.+)|%s*$")
    if not inner then
        return false
    end
    for cell in (inner .. "|"):gmatch("(.-)%|") do
        if not cell:match("^%s*:?%-+:?%s*$") then
            return false
        end
    end
    return true
end

-- One scanner owns escaped pipes for both cell parsing and cursor lookup.
local function scan(line, on_pipe, on_character)
    local pos = 1
    while pos <= #line do
        local ch, next_ch = line:sub(pos, pos), line:sub(pos + 1, pos + 1)
        if ch == "\\" and (next_ch == "|" or next_ch == "\\" or next_ch == "`") then
            on_character(next_ch)
            pos = pos + 2
        else
            if ch == "|" then
                on_pipe(pos)
            else
                on_character(ch)
            end
            pos = pos + 1
        end
    end
end

-- The byte of every unescaped pipe in `line`.
local function pipes(line)
    local found = {}
    scan(line, function(pos)
        found[#found + 1] = pos
    end, function() end)
    return found
end

function M.column_index(line, byte_column)
    local count = 0
    for _, pos in ipairs(pipes(line)) do
        if pos <= byte_column + 1 then
            count = count + 1
        end
    end
    return math.max(1, count)
end

-- The cells of one Markdown table row, trimmed, with escaped pipes and
-- backslashes read; nil and the reason for a line that is no row.
function M.row(line)
    if type(line) ~= "string" then
        return nil, "Expected a Markdown table row"
    end
    local source = trim(line)
    if source:sub(1, 1) ~= "|" then
        return nil, "Expected a leading pipe"
    end
    local cells, current, last_pipe = {}, {}, nil
    -- Scan the real closing delimiter rather than appending a synthetic one:
    -- an escaped closing pipe must never silently discard the last cell.
    scan(source:sub(2), function(pos)
        cells[#cells + 1] = trim(table.concat(current))
        current = {}
        last_pipe = pos + 1
    end, function(ch)
        current[#current + 1] = ch
    end)
    if last_pipe ~= #source then
        return nil, "Expected an unescaped closing pipe"
    end
    return cells
end

-- One-based, inclusive bytes of a heading cell's content, surrounding blanks
-- excluded. Nil for a blank cell or a column the line does not have.
function M.heading_cell(line, index)
    local at = pipes(line)
    if not at[index + 1] then
        return nil
    end
    local lead, content = line:sub(at[index] + 1, at[index + 1] - 1):match("^(%s*)(.-)%s*$")
    if content == "" then
        return nil
    end
    local first = at[index] + 1 + #lead
    return first, first + #content - 1
end

-- The display column where each cell of `line` centres a one-wide value:
-- the centre of the span between the cell's pipes, the same arithmetic
-- the formatter pads with, so a mark at it lands under the column's 0s
-- and 1s. One entry per cell, from zero.
function M.column_centres(line, display_width)
    local width = display_width or format.display_width
    local at = pipes(line)
    local centres = {}
    for index = 1, #at - 1 do
        local start = width(line:sub(1, at[index]))
        local cell = width(line:sub(at[index] + 1, at[index + 1] - 1))
        centres[index] = start + math.floor(math.max(cell - 1, 0) / 2)
    end
    return centres
end

-- Replace one header cell without rewriting separators or stored data rows.
function M.replace_heading(line, index, heading)
    local headers, err = M.row(line)
    if not headers then
        return nil, err
    end
    if not headers[index] then
        return nil, "Invalid column index"
    end
    headers[index] = heading
    local valid, validation_err = model.headings(headers)
    return result.map(valid, validation_err, function()
        local at = pipes(line)
        return line:sub(1, at[index]) .. " " .. format.escape_heading(heading) .. " " .. line:sub(at[index + 1])
    end)
end

return M
