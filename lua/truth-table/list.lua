-- The list arithmetic cds.fp leaves out: a slice, two lists joined, one
-- without the item at an index, one with the item at an index replaced.
-- Each answers a fresh list over the same items; the input stays as it
-- was. Pure Lua 5.1, so the core and the rims share it; the four are
-- candidates for cds.fp, and move there as one when a second plugin wants
-- them.
local fp = require("cds.fp")
local M = {}

-- The items from `first` to `last` inclusive, as the loop `for i = first,
-- last` reads them; `last` is the end of the list when left out.
function M.slice(list, first, last)
    local out = {}
    for i = first, last or #list do
        out[#out + 1] = list[i]
    end
    return out
end

-- The items of each list in turn, as one list.
function M.concat(...)
    local out = {}
    for _, items in ipairs({ ... }) do
        for _, item in ipairs(items) do
            out[#out + 1] = item
        end
    end
    return out
end

-- The list without the item at `index`.
function M.without(list, index)
    return fp.filter(list, function(_, i)
        return i ~= index
    end)
end

-- The list with `value` in place of the item at `index`.
function M.with(list, index, value)
    return fp.map(list, function(item, i)
        return i == index and value or item
    end)
end

return M
