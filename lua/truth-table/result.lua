-- Lua's value, error convention as a small Result pipeline. Only nil fails:
-- false and zero are valid successful values. traverse stops at the first error.
local M = {}

function M.bind(value, err, fn)
    if value == nil then
        return nil, err
    end
    return fn(value)
end

function M.traverse(values, fn)
    local out = {}
    for i, value in ipairs(values) do
        local mapped, err = fn(value, i)
        if mapped == nil then
            return nil, err
        end
        out[i] = mapped
    end
    return out
end

return M
