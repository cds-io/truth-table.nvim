-- map, filter and reduce over lists, for the pure modules: they run under
-- plain Lua 5.1, which has none of the three, and without `vim`, so without
-- vim.iter. A list is a sequence (items at 1..n, no holes), read with ipairs.
-- Each function returns a new value and leaves its list alone. The function
-- argument comes last, so one written out over several lines reads as a block.
local M = {}

-- fn(item, index) for each item, in order. A nil result is an error: it would
-- leave a hole, and ipairs would stop reading the list there.
function M.map(list, fn)
    local out = {}
    for index, item in ipairs(list) do
        local mapped = fn(item, index)
        if mapped == nil then
            error("fp.map: the function returned nil for item " .. index, 2)
        end
        out[index] = mapped
    end
    return out
end

-- The items for which keep(item, index) is true, in order.
function M.filter(list, keep)
    local out = {}
    for index, item in ipairs(list) do
        if keep(item, index) then
            out[#out + 1] = item
        end
    end
    return out
end

-- Fold the items into one value, left to right: the result of
-- fn(value, item, index) is the value the next item meets, starting from
-- `initial`, which is also what an empty list gives.
function M.reduce(list, initial, fn)
    local value = initial
    for index, item in ipairs(list) do
        value = fn(value, item, index)
    end
    return value
end

return M
