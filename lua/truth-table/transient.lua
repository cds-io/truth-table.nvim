-- Keymaps that hold while a preview is pending. They are buffer-local, so
-- they shadow the user's own maps only while the preview shows, and a
-- buffer-local map they shadow is put back on release. The keys themselves
-- are preview.lua's.
local M = {}

-- Per buffer, the keys engaged there and the maps they shadowed; an entry's
-- presence is the engaged flag.
local saved = {}

-- Set `keys`, each { lhs, run, desc }, in normal mode in `buf`, unless keys
-- are engaged there already.
function M.engage(buf, keys)
    if saved[buf] then
        return
    end
    local shadowed = {}
    for _, key in ipairs(keys) do
        -- maparg reads the current buffer's maps, so ask in `buf`'s context.
        local existing = vim.api.nvim_buf_call(buf, function()
            return vim.fn.maparg(key.lhs, "n", false, true)
        end)
        if existing.buffer == 1 then
            shadowed[key.lhs] = existing
        end
        vim.keymap.set("n", key.lhs, key.run, { buffer = buf, desc = key.desc })
    end
    saved[buf] = { keys = keys, shadowed = shadowed }
end

-- Take the engaged keys out of `buf` and put back what they shadowed.
function M.release(buf)
    local engaged = saved[buf]
    if not engaged then
        return
    end
    saved[buf] = nil
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    for _, key in ipairs(engaged.keys) do
        pcall(vim.keymap.del, "n", key.lhs, { buffer = buf })
    end
    vim.api.nvim_buf_call(buf, function()
        for _, dict in pairs(engaged.shadowed) do
            vim.fn.mapset("n", false, dict)
        end
    end)
end

-- Drop what is held for `buf`, for a buffer that is gone.
function M.forget(buf)
    saved[buf] = nil
end

return M
