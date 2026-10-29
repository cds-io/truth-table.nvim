-- The which-key popup under each prefix: only the moves legal at the
-- cursor, read fresh from the buffer on every popup, over the keymaps of
-- init.lua. Registered after which-key has loaded, for the reason below.
local core = require("truth-table.core")
local preview = require("truth-table.preview")
local keymaps = require("truth-table.keymaps")

local M = {}

local PREFIXES, KEYMAPS = keymaps.PREFIXES, keymaps.KEYMAPS

-- The contexts a leaf can wait for, read fresh at the cursor: each is one
-- pass over the buffer, cheap enough to run on every popup. An expression
-- is whatever source.at would hand the rewrites: a parseable line, or any
-- row of a table whose heading parses. `preview` is the pending preview
-- itself, so the apply labels can name its law.
local function context()
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local row = vim.api.nvim_win_get_cursor(0)[1]
    return {
        table = core.find_table(lines, row) ~= nil,
        expression = require("truth-table.source").at(buf) ~= nil,
        derivation = require("truth-table.derivation").in_derivation(lines, row),
        preview = preview.active(buf),
    }
end

-- The family's leaves whose context holds at the cursor, as which-key
-- specs: the popup's legal moves. Run from the popup, a leaf feeds the
-- keys its real mapping would, so the two paths stay one.
local function legal_leaves(family)
    local ctx = context()
    local spec = {}
    for _, map in ipairs(KEYMAPS) do
        if map.family == family and map.when and ctx[map.when] and (map.mode or "n") == "n" then
            local desc = map.desc
            if map.when == "preview" then
                desc = ("%s (%s)"):format(desc, ctx.preview.law)
            end
            local rhs = map.command and ("<cmd>" .. map.command .. "<CR>") or map.rhs
            -- selene: allow(mixed_table)
            spec[#spec + 1] = {
                map.key,
                function()
                    local keys = vim.api.nvim_replace_termcodes(rhs, true, true, true)
                    vim.api.nvim_feedkeys(keys, "n", false)
                end,
                desc = desc,
            }
        end
    end
    return spec
end

-- Add the two roots to which-key `wk`, once it has finished loading.
function M.register(wk)
    -- Each root's expand lists its family's legal moves at the cursor;
    -- the new table mapping, with a real description, merges in over
    -- the table root's.
    -- selene: allow(mixed_table)
    -- which-key's spec is intentionally mixed: positional key + named fields.
    local spec = {
        -- selene: allow(mixed_table)
        {
            PREFIXES.table,
            group = "Truth table",
            mode = "n",
            expand = function()
                return legal_leaves("table")
            end,
        },
        -- selene: allow(mixed_table)
        { PREFIXES.table, group = "Truth table", mode = "x" },
        -- selene: allow(mixed_table)
        {
            PREFIXES.rewrite,
            group = "Logic rewrite",
            mode = "n",
            expand = function()
                return legal_leaves("rewrite")
            end,
        },
    }
    -- which-key keeps the last spec a prefix was given, and it drains
    -- the queue of specs added before it loaded ahead of the ones from
    -- its own setup options. Added early, ours would lose the prefix to
    -- any group label the reader's config declares on it, and the node,
    -- childless by design (the real mappings hide behind
    -- which_key_ignore), would be pruned along with the expand. So wait
    -- for which-key to finish loading and add ours after; past ~5s add
    -- anyway, better queued than absent.
    local tries = 0
    local function register()
        tries = tries + 1
        if require("which-key.config").loaded or tries > 50 then
            wk.add(spec)
        else
            vim.defer_fn(register, 100)
        end
    end
    register()
end

return M
