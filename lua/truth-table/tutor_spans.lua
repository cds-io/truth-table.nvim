-- Colour spans in lesson text. A lesson marks a run of bytes in a line it
-- shows with `[:colour ` ... `]`, naming one of the palette's colours: the
-- loader strips the markers and keeps the span, and the tutor paints it as an
-- extmark. A span is bytes, not syntax: `[:red ¬(B]` is as good as
-- `[:blue A]`. Inside a span, brackets pair up, so `[:blue result[1]]` ends
-- at the second `]`; a span inside a span is refused. Pure string handling:
-- no `vim`, so the lesson loader is tested under plain Lua.
local M = {}

-- Each colour's highlight group and the standard group it links to, so every
-- colorscheme has it.
M.PALETTE = {
    { colour = "blue", group = "TruthTableTutorBlue", link = "DiagnosticInfo" },
    { colour = "red", group = "TruthTableTutorRed", link = "DiagnosticError" },
    { colour = "green", group = "TruthTableTutorGreen", link = "DiagnosticOk" },
    { colour = "yellow", group = "TruthTableTutorYellow", link = "DiagnosticWarn" },
}

-- Above vellum's marks: 100, and 100 + k for a mark inside a mark.
M.PRIORITY = 200

local GROUP = {}
for _, entry in ipairs(M.PALETTE) do
    GROUP[entry.colour] = entry.group
end

-- `line` without its markers, and the spans { col, end_col, group } they
-- marked, byte columns from zero into the clean line, in order. Nil and a
-- message for a marker that is wrong, naming its byte (from one) in `line`.
-- `[:` followed by a word opens a span; a bare `[`, and any `]` outside a
-- span, are text.
function M.strip(line)
    local clean, spans = {}, {}
    local length, open, depth = 0, nil, 0
    local pos = 1
    local function keep(bytes)
        clean[#clean + 1] = bytes
        length = length + #bytes
        pos = pos + #bytes
    end
    while pos <= #line do
        local byte = line:sub(pos, pos)
        local colour = byte == "[" and line:match("^%[:(%w+)", pos)
        if colour then
            if open then
                return nil, "a span inside a span at byte " .. pos
            end
            if not GROUP[colour] then
                return nil, ('unknown colour "%s" at byte %d'):format(colour, pos)
            end
            local after = pos + 2 + #colour
            if line:sub(after, after) ~= " " or line:sub(after + 1, after + 1) == " " then
                return nil, "a colour name must be followed by one space at byte " .. pos
            end
            open, depth = { col = length, group = GROUP[colour], at = pos }, 0
            pos = after + 1
        elseif open and byte == "[" then
            depth = depth + 1
            keep(byte)
        elseif open and byte == "]" and depth > 0 then
            depth = depth - 1
            keep(byte)
        elseif open and byte == "]" then
            if open.col == length then
                return nil, "an empty span at byte " .. open.at
            end
            spans[#spans + 1] = { col = open.col, end_col = length, group = open.group }
            open = nil
            pos = pos + 1
        else
            keep(byte)
        end
    end
    if open then
        return nil, "no closing ] for the span at byte " .. open.at
    end
    return table.concat(clean), spans
end

-- The innermost of `blocks` holding Markdown row `row` (from zero).
local function block_of(blocks, row)
    local found
    for _, block in ipairs(blocks) do
        local from, count = block[1], block[2]
        if from <= row and row < from + count and (not found or count < found[2]) then
            found = block
        end
    end
    return found
end

-- Where vellum put the lines that carry spans. `spans` carry `row`, from one
-- into `markdown`; `blocks` are vellum's anchors, one per block as
-- { source_row, source_rows, rendered_row, rendered_rows }, rows from zero;
-- the marks come back with rows from zero into `lines`. A rendered line is
-- the clean line with spaces around it (vellum's margin, its code prefix,
-- its padding), which is what is searched for, inside the line's own block
-- and in order; a line that cannot be found that way (one vellum had to
-- wrap, say) gets no marks.
function M.place(spans, markdown, lines, blocks)
    local by_row, rows = {}, {}
    for _, span in ipairs(spans) do
        if not by_row[span.row] then
            by_row[span.row], rows[#rows + 1] = {}, span.row
        end
        table.insert(by_row[span.row], span)
    end
    table.sort(rows)
    local marks, last = {}, -1
    for _, row in ipairs(rows) do
        local clean = markdown[row]
        local block = clean and clean ~= "" and block_of(blocks, row - 1)
        if block then
            for rendered = math.max(block[3], last + 1), block[3] + block[4] - 1 do
                local line = lines[rendered + 1]
                local start = line and line:find(clean, 1, true)
                if start and (line:sub(1, start - 1) .. line:sub(start + #clean)):match("^ *$") then
                    for _, span in ipairs(by_row[row]) do
                        marks[#marks + 1] = {
                            row = rendered,
                            col = start - 1 + span.col,
                            end_col = start - 1 + span.end_col,
                            group = span.group,
                            priority = M.PRIORITY,
                        }
                    end
                    last = rendered
                    break
                end
            end
        end
    end
    return marks
end

return M
