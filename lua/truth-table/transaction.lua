-- A value with the ordered log of the changes that made it: Lua's value,
-- error convention (only nil fails) carrying a Writer. A rewrite returns one
-- change; bind runs the next rewrite on the value and appends its changes,
-- so a composed derivation keeps every law in order. Values and records are
-- treated as immutable by callers.
local M = {}

function M.pure(value)
    return { value = value, changes = {} }
end

function M.record(value, change)
    return { value = value, changes = { change } }
end

function M.bind(tx, err, fn)
    if tx == nil then
        return nil, err
    end
    local next_tx, next_err = fn(tx.value)
    if next_tx == nil then
        return nil, next_err
    end
    local changes = {}
    for _, change in ipairs(tx.changes) do
        changes[#changes + 1] = change
    end
    for _, change in ipairs(next_tx.changes) do
        changes[#changes + 1] = change
    end
    return { value = next_tx.value, changes = changes }
end

return M
