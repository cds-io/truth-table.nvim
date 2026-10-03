-- Derivation lines: expressions separated by ≡, each side equivalent to the
-- others. Pure string handling. ≡ is outside the predicate language, so no
-- side ever contains one and a plain search finds every separator.
local SYMBOLS = require("truth-table.symbols")
local M = {}

local SEPARATOR = SYMBOLS.EQUIV.unicode

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
-- the side to its right.
function M.working_side(line, byte)
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

-- The line with one side's expression replaced; everything else is kept.
function M.replace(line, side, text)
    return line:sub(1, side.first - 1) .. text .. line:sub(side.last + 1)
end

-- The line to insert below `line` as a new step, and the zero-based byte
-- column where its expression starts. The separator sits under the line's
-- last one, measured in display columns, or at the line's indentation when
-- the line has none.
function M.step(line, text, display_width)
    local cuts = separators(line)
    local pad = line:match("^%s*")
    if #cuts > 0 then
        pad = pad .. string.rep(" ", display_width(line:sub(#pad + 1, cuts[#cuts] - 1)))
    end
    local prefix = pad .. SEPARATOR .. " "
    return prefix .. text, #prefix
end

return M
