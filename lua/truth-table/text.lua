-- The string helper the pure modules share: plain Lua 5.1 has no trim, and
-- each module that reads text a user typed (the :TruthTable argument, a
-- list of expressions, a Markdown row) wants one.
local M = {}

-- `s` without its leading and trailing blanks.
function M.trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

return M
