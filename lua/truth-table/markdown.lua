-- Markdown codec for Boolean tables. Width measurement is an explicit dependency.
local result = require("truth-table.result")
local model = require("truth-table.table_model")
local M = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

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
    local widths = {}
    for i, h in ipairs(headers) do
        widths[i] = math.max(3, display_width(h))
    end
    for _, row in ipairs(rows) do
        for i, cell in ipairs(row) do
            widths[i] = math.max(widths[i], display_width(cell))
        end
    end

    local hdr_cells = {}
    for i, h in ipairs(headers) do
        hdr_cells[i] = " " .. M.center_pad(h, widths[i], display_width) .. " "
    end
    local heading = "|" .. table.concat(hdr_cells, "|") .. "|"

    local sep_cells = {}
    for i = 1, #headers do
        sep_cells[i] = ":" .. string.rep("-", widths[i]) .. ":"
    end
    local separator = "|" .. table.concat(sep_cells, "|") .. "|"

    local lines = { heading, separator }
    for _, row in ipairs(rows) do
        local cells = {}
        for i, cell in ipairs(row) do
            cells[i] = " " .. M.center_pad(cell, widths[i], display_width) .. " "
        end
        lines[#lines + 1] = "|" .. table.concat(cells, "|") .. "|"
    end

    return lines
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
        if ch == "\\" and (next_ch == "|" or next_ch == "\\") then
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

function M.column_index(line, byte_column)
    local count = 0
    scan(line, function(pos)
        if pos <= byte_column + 1 then
            count = count + 1
        end
    end, function() end)
    return math.max(1, count)
end

local function read_row(line)
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

-- Legacy splitting returns an empty array for invalid row syntax.
function M.split_row(line)
    return read_row(line) or {}
end

-- Parse a Markdown table into one validated semantic model.
function M.parse_table_lines(lines)
    if #lines < 2 or not M.is_separator(lines[2]) then
        return nil, "Expected a heading and separator"
    end
    local headers, err = read_row(lines[1])
    if not headers then
        return nil, err
    end
    if #M.split_row(lines[2]) ~= #headers then
        return nil, "Separator column count does not match heading"
    end
    local rows = {}
    for i = 3, #lines do
        local row, row_err = read_row(lines[i])
        if not row then
            return nil, "Line " .. i .. ": " .. row_err
        end
        rows[#rows + 1] = row
    end
    return model.normalize({ headers = headers, rows = rows })
end

function M.format(tbl, display_width)
    local normalized, err = model.normalize(tbl)
    return result.bind(normalized, err, function(valid)
        local headers = result.traverse(valid.headers, function(header)
            return (header:gsub("\\", "\\\\"):gsub("|", "\\|"))
        end)
        return format_valid(headers, model.render_rows(valid), display_width or M.display_width)
    end)
end

return M
