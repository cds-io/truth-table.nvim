-- A lesson's block strings as pane lines: a block split into lines, prose
-- reflowed to one line per paragraph for the window to wrap, and the colour
-- markers taken out of a step's text, note or template with the spans they
-- marked. page.lua lays the step out of these. Pure string handling.
local spans = require("truth-table.tutor.spans")
local M = {}

-- A block string as a list of lines, without the newlines that close it.
function M.lines(block)
    local lines = {}
    for line in ((block or ""):gsub("\n+$", "") .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    if #lines == 1 and lines[1] == "" then
        return {}
    end
    return lines
end

-- Lesson files wrap their prose at a fixed width, and the pane is whatever
-- width the reader's window has. Each paragraph and each list item (`- ` or
-- `1. `) becomes one line, for the window to wrap; fenced blocks, indented
-- commands, table rows and headings stay as written.
local function item(line)
    return line:match("^%- ") or line:match("^%d+%. ")
end

function M.reflow(lines)
    local out, fenced, open = {}, false, false
    for _, line in ipairs(lines) do
        if line:match("^%s*```") then
            fenced = not fenced
            out[#out + 1], open = line, false
        elseif fenced or line == "" or line:match("^    ") or line:match("^[|#]") then
            out[#out + 1], open = line, false
        elseif open and not item(line) then
            out[#out] = out[#out] .. " " .. line:gsub("^%s+", "")
        else
            out[#out + 1], open = line, true
        end
    end
    return out
end

-- The lines of `lines` with their markers out, and the spans found, each
-- with the `row` it was on. `allowed(row)` says whether that row may carry
-- spans; a marker that is wrong, or a span where none is allowed, is nil
-- and a message ending in the line.
local function stripped(lines, allowed)
    local out, found = {}, {}
    for row, line in ipairs(lines) do
        local clean, marked = spans.strip(line)
        if not clean then
            return nil, marked .. ": " .. line
        end
        if #marked > 0 and not allowed(row) then
            return nil, "a colour span outside a ```logic block: " .. line
        end
        out[row] = clean
        for _, span in ipairs(marked) do
            span.row = row
            found[#found + 1] = span
        end
    end
    return out, found
end

-- A step's `text` or `note` as pane lines, reflowed, with the spans of its
-- ```logic blocks.
function M.body(block)
    local lines = M.reflow(M.lines(block))
    local logic, info = {}, nil
    for row, line in ipairs(lines) do
        local fence = line:match("^%s*```%s*(%S*)")
        if fence then
            info = info == nil and fence or nil
        else
            logic[row] = info == "logic"
        end
    end
    return stripped(lines, function(row)
        return logic[row] == true
    end)
end

-- A step's `template` as the scratch pane's starting lines, with its spans.
function M.template(block)
    return stripped(M.lines(block), function()
        return true
    end)
end

return M
