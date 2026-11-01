-- The string helpers the pure modules share: plain Lua 5.1 has no trim, and
-- each module that reads text a user typed (the :TruthTable argument, a
-- list of expressions, a Markdown row) wants one; the lines a command
-- writes below a table or a derivation take that block's indentation.
local fp = require("cds.fp")
local M = {}

-- `s` without its leading and trailing blanks.
function M.trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- `s` without its trailing blanks.
function M.rtrim(s)
    return (s:gsub("%s+$", ""))
end

-- `lines` with `indent` before each one that has text; a blank line stays
-- blank.
function M.indented(lines, indent)
    return fp.map(lines, function(line)
        return line == "" and "" or indent .. line
    end)
end

return M
