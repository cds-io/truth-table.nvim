-- Derivation lines: expressions separated by ≡, each side equivalent to the
-- others, then an optional justification, `| by <law>`, naming how the line
-- follows from the one above. Pure string handling. ≡ and | are outside the
-- predicate language, so no side ever contains one and a plain search finds
-- every separator and the bar.
local SYMBOLS = require("truth-table.symbols")
local M = {}

local SEPARATOR = SYMBOLS.EQUIV.unicode
local BAR = "|"
-- Columns between the wider of a step and the line above it, and the bar.
local GAP = 4

-- The part of a line that holds its sides, and the byte of the bar that ends
-- it, when the line has a justification.
local function body(line)
    local bar = line:find(BAR, 1, true)
    return bar and line:sub(1, bar - 1) or line, bar
end

-- A justification as it is written after a step, and beside a preview.
function M.justification(law)
    return BAR .. " by " .. law
end

local function separators(line)
    local found, from = {}, 1
    while true do
        local at = line:find(SEPARATOR, from, true)
        if not at then
            return found
        end
        found[#found + 1] = at
        from = at + #SEPARATOR
    end
end

-- The side the cursor byte selects: { text, first, last }, the expression
-- with surrounding blanks trimmed and the one-based bytes it occupies. The
-- separator itself, or a blank side (the padding before a leading ≡), selects
-- the side to its right; a cursor in the justification selects the last side.
function M.working_side(line, byte)
    line = body(line)
    local cuts = separators(line)
    local function side(k)
        local from = k == 1 and 1 or cuts[k - 1] + #SEPARATOR
        local content = line:sub(from, cuts[k] and cuts[k] - 1 or #line)
        local lead, text = content:match("^(%s*)(.-)%s*$")
        if text == "" then
            return nil
        end
        local first = from + #lead
        return { text = text, first = first, last = first + #text - 1 }
    end

    local selected = 1
    for k, cut in ipairs(cuts) do
        if byte >= cut then
            selected = k + 1
        end
    end
    local chosen = side(selected) or (selected <= #cuts and side(selected + 1)) or nil
    if not chosen then
        return nil, "No expression under the cursor"
    end
    return chosen
end

-- The line with one side's expression replaced by `rewritten.text`;
-- everything else is kept. A line that carries a justification gains
-- `rewritten.law` at the end of it, so it still says how the line follows
-- from the one above.
function M.replace(line, side, rewritten)
    local replaced = line:sub(1, side.first - 1) .. rewritten.text .. line:sub(side.last + 1)
    local _, bar = body(line)
    if bar and rewritten.law then
        replaced = replaced:gsub("%s+$", "") .. ", " .. rewritten.law
    end
    return replaced
end

-- The line to insert below `line` as a new step, and the zero-based byte
-- column where its expression starts. The separator sits under the line's
-- last one, measured in display columns, or at the line's indentation when
-- the line has none. `rewritten.law`, when given, follows as the step's
-- justification: its bar sits under the bar of the line above, or GAP columns
-- clear of both lines, whichever is further right.
function M.step(line, rewritten, display_width)
    local sides, bar = body(line)
    local cuts = separators(sides)
    local pad = line:match("^%s*")
    if #cuts > 0 then
        -- Measured from the start of the line: a tab's width depends on its column.
        pad = pad .. string.rep(" ", display_width(line:sub(1, cuts[#cuts] - 1)) - display_width(pad))
    end
    local prefix = pad .. SEPARATOR .. " "
    local step = prefix .. rewritten.text
    if rewritten.law then
        local width = display_width(step)
        local above = bar and display_width(sides) or display_width((sides:gsub("%s+$", ""))) + GAP
        local column = math.max(width + GAP, above)
        step = step .. string.rep(" ", column - width) .. M.justification(rewritten.law)
    end
    return step, #prefix
end

return M
