-- map, filter, reduce, find, any, all, set and unique over lists: the
-- plugin's list vocabulary, for the pure modules in the first place, which
-- run under plain Lua 5.1 (none of these built in) and without `vim`, so
-- without vim.iter. A list is a sequence (items at 1..n, no holes), read
-- with ipairs. Map, filter and unique return fresh lists, set a fresh table,
-- reduce the final accumulator, find the item, any and all a boolean. The
-- helpers do not modify the input list. The function argument comes last,
-- so one written out over several lines reads as a block.
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

-- The first item for which test(item, index) is truthy, and its index; nil
-- when none is. The lists here hold nodes, strings and records, never
-- false, so a falsy answer means no item.
function M.find(list, test)
    for index, item in ipairs(list) do
        if test(item, index) then
            return item, index
        end
    end
end

-- Does test(item, index) hold for some item? Stops at the first.
function M.any(list, test)
    for index, item in ipairs(list) do
        if test(item, index) then
            return true
        end
    end
    return false
end

-- Does test(item, index) hold for every item? Stops at the first that
-- fails; true for an empty list.
function M.all(list, test)
    for index, item in ipairs(list) do
        if not test(item, index) then
            return false
        end
    end
    return true
end

-- The key an item is filed under: key(item, index), or the item itself
-- without a key function. A nil key is an error, naming the item, since Lua
-- would refuse the nil index without saying which item gave it.
local function key_of(name, key, item, index)
    -- Spelled out: `key and key(item, index) or item` would fall back to
    -- the item on a nil key, which is the case to refuse.
    local found = item
    if key then
        found = key(item, index)
    end
    if found == nil then
        error("fp." .. name .. ": the key function returned nil for item " .. index, 3)
    end
    return found
end

-- The items as a set: a table of each one's key to true.
function M.set(list, key)
    local out = {}
    for index, item in ipairs(list) do
        out[key_of("set", key, item, index)] = true
    end
    return out
end

-- The items whose key has not appeared before, in order: the first of each.
function M.unique(list, key)
    local seen, out = {}, {}
    for index, item in ipairs(list) do
        local found = key_of("unique", key, item, index)
        if not seen[found] then
            seen[found] = true
            out[#out + 1] = item
        end
    end
    return out
end

return M
