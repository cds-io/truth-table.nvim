-- Insert-mode abbreviations for the logic symbols in truth-table.symbols.
-- Each pairs the symbol's ASCII word plus a trigger with its Unicode form,
-- so `and@` followed by a space becomes `∧`. The trigger is a non-keyword
-- character, which means the plain word never expands on its own and prose
-- like "and then" stays untouched.

local SYMBOLS = require("truth-table.symbols")

local M = {}

-- The option's shape: `trigger` is the input side appended to every word,
-- `symbols` is the display side keyed by word.
M.defaults = { trigger = "@", symbols = {} }
for _, symbol in pairs(SYMBOLS) do
    M.defaults.symbols[symbol.ascii] = symbol.unicode
end

-- What the last register() call put in place, so the next call can take it
-- out again. plugin/truth-table.lua calls setup() before a user's own call
-- gets to pass options, so "last call wins" needs the undo.
local registered = {}

-- Resolve the setup option into the final lhs -> rhs table: nil keeps the
-- defaults, false empties them, a table merges `symbols` over the defaults
-- (false drops a word) and takes `trigger` as given.
function M.resolve(option)
    if option == false then
        return {}
    end
    option = option or {}
    local trigger = option.trigger or M.defaults.trigger
    local symbols = vim.deepcopy(M.defaults.symbols)
    for word, unicode in pairs(option.symbols or {}) do
        symbols[word] = unicode or nil
    end
    local resolved = {}
    for word, unicode in pairs(symbols) do
        resolved[word .. trigger] = unicode
    end
    return resolved
end

function M.register(option)
    for lhs in pairs(registered) do
        -- The user may have removed it by hand already (E24); that is fine.
        pcall(vim.cmd.iunabbrev, lhs)
    end
    registered = M.resolve(option)
    for lhs, rhs in pairs(registered) do
        vim.cmd.iabbrev({ lhs, rhs })
    end
end

return M
