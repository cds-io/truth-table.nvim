-- Markdown codec for Boolean tables. Width measurement is an explicit dependency.
local fp = require("truth-table.fp")
local result = require("truth-table.result")
local model = require("truth-table.table_model")
local trim = require("truth-table.text").trim
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
    local widths = fp.map(headers, function(header)
        return math.max(3, display_width(header))
    end)
    for _, row in ipairs(rows) do
        for i, cell in ipairs(row) do
            widths[i] = math.max(widths[i], display_width(cell))
        end
    end

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

    local lines = { padded(headers), separator }
    for _, row in ipairs(rows) do
        lines[#lines + 1] = padded(row)
    end
    return lines
end

-- Format arbitrary string cells (headers may be empty). The Boolean codec
-- below validates before calling this; the Karnaugh renderer, whose cells are
-- Gray codes and axis labels, uses it directly.
function M.format_cells(headers, rows, display_width)
    return format_valid(headers, rows, display_width or M.display_width)
end

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
            if marker and marker.character == fence.character and marker.length >= fence.length
                and marker.rest:match("^%s*$") then
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
                    if lines[last + 2] and table_indent(lines[last + 2]) == indent
                        and M.is_separator(lines[last + 2]) then
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

function M.escape_heading(header)
    return (header:gsub("\\", "\\\\"):gsub("|", "\\|"):gsub("`", "\\`"))
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
        return line:sub(1, at[index]) .. " " .. M.escape_heading(heading) .. " " .. line:sub(at[index + 1])
    end)
end

function M.format(tbl, display_width)
    local headers = fp.map(tbl.headers, M.escape_heading)
    return format_valid(headers, model.render_rows(tbl), display_width or M.display_width)
end

return M
