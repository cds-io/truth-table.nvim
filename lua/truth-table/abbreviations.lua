-- Insert-mode abbreviations for the logic symbols in truth-table.symbols.
-- Each pairs the symbol's ASCII word plus a trigger with its Unicode form,
-- so `and@` followed by a space becomes `∧`. The trigger is a non-keyword
-- character, which means the plain word never expands on its own and prose
-- like "and then" stays untouched.

local fp = require("truth-table.fp")
local SYMBOLS = require("truth-table.symbols")

local M = {}

-- The option's shape: `trigger` is the input side appended to every word,
-- `symbols` is the display side keyed by word.
M.defaults = { trigger = "@", symbols = {} }
for _, symbol in pairs(SYMBOLS) do
    M.defaults.symbols[symbol.ascii] = symbol.unicode
end

-- Ownership records retain displaced global abbreviations for restoration.
local registered = {}

function M.resolve(option)
    if option == false then
        return {}
    end
    if option ~= nil and type(option) ~= "table" then
        return nil, "abbreviations must be a table or false"
    end
    option = option or {}
    local trigger = option.trigger == nil and M.defaults.trigger or option.trigger
    if type(trigger) ~= "string" or not trigger:match("^%p$") or trigger:find("[\\|<>]") then
        return nil, "trigger must be one ASCII punctuation character other than backslash, |, <, or >"
    end
    if option.symbols ~= nil and type(option.symbols) ~= "table" then
        return nil, "symbols must be a table"
    end
    local symbols = vim.deepcopy(M.defaults.symbols)
    for word, unicode in pairs(option.symbols or {}) do
        if type(word) ~= "string" or not word:match("^[A-Za-z_][A-Za-z0-9_]*$") then
            return nil, "symbol keys must be ASCII identifiers"
        end
        if unicode ~= false and (type(unicode) ~= "string" or unicode == ""
            or unicode:find("[\r\n]") or unicode:match("^%s") or unicode:match("%s$")) then
            return nil, "symbol values must be nonempty single-line strings without surrounding whitespace, or false"
        end
        symbols[word] = unicode or nil
    end
    local resolved = {}
    for word, unicode in pairs(symbols) do
        resolved[word .. trigger] = unicode
    end
    return resolved
end

local function global_abbreviation(lhs)
    -- maparg can return a buffer-local shadow instead of the global entry.
    local found = fp.find(vim.fn.maplist(true), function(mapping)
        return mapping.buffer == 0 and mapping.lhs == lhs and mapping.mode == "i"
    end)
    return found
end

function M.register(option)
    local resolved, err = M.resolve(option)
    if not resolved then
        error("Invalid truth-table configuration: " .. err, 0)
    end
    -- Resolve and validate before touching any previously installed mappings.
    for lhs, record in pairs(registered) do
        local current = global_abbreviation(lhs)
        if current and vim.deep_equal(current, record.owned) then
            vim.cmd.iunabbrev(lhs)
            if record.previous then
                vim.fn.mapset("i", true, record.previous)
            end
        end
    end
    registered = {}
    for lhs, rhs in pairs(resolved) do
        local previous = global_abbreviation(lhs)
        vim.cmd.iabbrev({ lhs, rhs })
        registered[lhs] = { previous = previous, owned = global_abbreviation(lhs) }
    end
end

return M
