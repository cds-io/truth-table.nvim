-- truth-table.nvim: generate and manipulate markdown truth tables. The pure
-- table pipeline lives in truth-table.core; the user commands are
-- truth-table.commands, the keymaps and their which-key popup
-- truth-table.keymaps, and this module is the setup() entry point that
-- wires them, with the highlight groups and autocommands the plugin owns.

local core = require("truth-table.core")
local commands = require("truth-table.commands")
local keymaps = require("truth-table.keymaps")
local which_key = require("truth-table.keymaps.which_key")

local M = {}

-- The groups a rewrite is lit with, the terms it consumed and the result it
-- produced, and the ≡/≢ marks the equivalence toggle paints, as defaults
-- the reader may define over. A colorscheme clears them, so they are
-- defined again after one.
local function highlights()
    vim.api.nvim_set_hl(0, "TruthTableChanged", { default = true, link = "DiagnosticOk" })
    vim.api.nvim_set_hl(0, "TruthTableConsumed", { default = true, link = "DiagnosticWarn" })
    vim.api.nvim_set_hl(0, "TruthTableEquivalent", { default = true, link = "DiagnosticInfo" })
    vim.api.nvim_set_hl(0, "TruthTableInequivalent", { default = true, link = "Comment" })
end

-- Register commands, keymaps, insert-mode abbreviations, and (if present)
-- which-key labels. Also injects vim.fn.strdisplaywidth so column widths are
-- terminal-accurate, and states the equivalence-mark switch (on unless
-- opts.equivalence == false). Idempotent: the last call wins, including for
-- the abbreviations. Automatic loading preserves an earlier explicit setup
-- call.
function M.setup(opts)
    if opts ~= nil and type(opts) ~= "table" then
        error("truth-table setup options must be a table", 0)
    end
    opts = opts or {}
    core.display_width = vim.fn.strdisplaywidth
    require("truth-table.abbreviations").register(opts.abbreviations)
    require("truth-table.equivalence").set(opts.equivalence ~= false)
    highlights()
    local group = vim.api.nvim_create_augroup("truth_table", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })
    -- A written rewrite realigns its derivation's bars, in the same undo
    -- entry.
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "TruthTableRewrite",
        callback = function(event)
            require("truth-table.align").derivation(event.data.buf, event.data.row, true)
        end,
    })

    local defined = commands.define()
    local has_which_key, wk = pcall(require, "which-key")
    keymaps.set(defined, has_which_key)
    if has_which_key then
        which_key.register(wk)
    end
    M.configured = true
end

return M
