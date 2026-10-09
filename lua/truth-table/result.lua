-- Lua's value, error convention as a small Result pipeline. Only nil fails:
-- false and zero are valid successful values. A step that can refuse goes
-- through bind or traverse; one that cannot goes through map, so a reader
-- can tell the two apart at the call. Where a step cannot fail and there is
-- no error to carry, fp.map is the plain list map.
local M = {}

-- The value through `fn`, which may refuse (nil, err); the error untouched.
function M.bind(value, err, fn)
    if value == nil then
        return nil, err
    end
    return fn(value)
end

-- The value through `fn`, which always answers; the error untouched. The
-- same step as bind: the name says at the call whether `fn` can refuse.
M.map = M.bind

-- The value untouched; the error with `prefix` in front, so a failure deep in
-- a pipeline says where it was met ('Parse error in "A and": ...').
function M.context(value, err, prefix)
    if value == nil then
        return nil, prefix .. err
    end
    return value
end

-- fn(value, index) over every item, stopping at the first refusal; the list
-- of answers, or nil and that error.
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
