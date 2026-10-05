-- Insert-mode abbreviations: defaults from the plugin entry point, then every
-- shape of the setup({ abbreviations = ... }) option. Each setup call must
-- leave exactly its own set registered, whatever the call before it did, so
-- the cases run in order and each starts from the call it names.
-- Runs inside Neovim (make test-nvim): busted with nlua as its interpreter.
vim.opt.rtp:append(vim.fn.getcwd())
package.preload["which-key"] = function() error("which-key intentionally absent") end
vim.cmd("runtime plugin/truth-table.lua")
-- Keeps "-- INSERT --" out of the report when a case types.
vim.o.showmode = false

local tt = require("truth-table")
local symbols = require("truth-table.symbols")
local defaults = require("truth-table.abbreviations").defaults

local function abbrev(lhs)
    return vim.fn.maparg(lhs, "i", true)
end

describe("abbreviation defaults", function()
    it("pair each constant's ascii word plus @ with its unicode symbol", function()
        assert.are.equal("@", defaults.trigger)
        for _, key in ipairs({ "NOT", "AND", "OR", "XOR", "IMPLIES", "IFF", "FORALL", "EXISTS", "TOP", "BOTTOM", "EQUIV" }) do
            assert.are.equal(symbols[key].unicode, defaults.symbols[symbols[key].ascii], key)
        end
    end)

    it("are all registered by the plugin entry point, with the shared rendering for implies and iff", function()
        for word, symbol in pairs(defaults.symbols) do
            assert.are.equal(symbol, abbrev(word .. "@"), word)
        end
        assert.are.equal("⇔", abbrev("iff@"))
        assert.are.equal("→", abbrev("implies@"))
        assert.are.equal("≡", abbrev("equiv@"))
    end)
end)

describe("setup({ abbreviations = ... })", function()
    it("registers none for false, undoing the earlier call", function()
        tt.setup({ abbreviations = false })
        for word in pairs(defaults.symbols) do
            assert.are.equal("", abbrev(word .. "@"), word)
        end
    end)

    it("brings the defaults back on a later bare setup", function()
        tt.setup({ abbreviations = false })
        tt.setup()
        assert.are.equal("∧", abbrev("and@"))
    end)

    it("merges symbols over the defaults: override one, drop one, add one", function()
        tt.setup({ abbreviations = { symbols = { implies = "⇒", forall = false, top = "⊤" } } })
        assert.are.equal("⇒", abbrev("implies@"))
        assert.are.equal("", abbrev("forall@"))
        assert.are.equal("⊤", abbrev("top@"))
        assert.are.equal("∧", abbrev("and@"))
    end)

    it("changes the input side of every word with trigger, and drops the old lhs", function()
        tt.setup({ abbreviations = { symbols = { top = "⊤" } } })
        tt.setup({ abbreviations = { trigger = ";" } })
        assert.are.equal("∧", abbrev("and;"))
        assert.are.equal("", abbrev("and@"))
        assert.are.equal("", abbrev("top;"))
    end)

    it("reverts to the defaults, even past an abbreviation the user removed by hand", function()
        tt.setup({ abbreviations = { symbols = { top = "⊤" } } })
        vim.cmd("iunabbrev and@")
        tt.setup()
        assert.are.equal("∧", abbrev("and@"))
        assert.are.equal("", abbrev("top@"))
        assert.are.equal("→", abbrev("implies@"))
    end)

    it("fails on an invalid setting before deleting or registering anything", function()
        tt.setup()
        local before = vim.fn.maplist(true)
        for _, option in ipairs({
            true, { trigger = " x" }, { trigger = "" }, { trigger = "xx" }, { trigger = "|" },
            { symbols = true }, { symbols = { ["bad key"] = "X" } },
            { symbols = { and_word = 1 } }, { symbols = { and_word = "" } },
            { symbols = { and_word = "X\nY" } },
        }) do
            local ok, err = pcall(tt.setup, { abbreviations = option })
            assert.is_false(ok, vim.inspect(option))
            assert.is_truthy(err:find("Invalid truth-table configuration", 1, true), err)
            assert.are.same(before, vim.fn.maplist(true))
        end
        assert.are.equal("", abbrev("and"))
        assert.are.equal("", abbrev("bad"))
    end)
end)

describe("abbreviation ownership", function()
    it("restores a user's earlier mapping with its original options", function()
        tt.setup({ abbreviations = false })
        vim.cmd("inoreabbrev <silent> and@ ORIGINAL")
        local original = vim.fn.maparg("and@", "i", true, true)
        tt.setup()
        assert.are.equal("∧", abbrev("and@"))
        tt.setup({ abbreviations = false })
        local restored = vim.fn.maparg("and@", "i", true, true)
        assert.are.equal("ORIGINAL", restored.rhs)
        assert.are.equal(original.noremap, restored.noremap)
        assert.are.equal(original.silent, restored.silent)
        vim.cmd("iunabbrev and@")
    end)

    it("keeps a replacement the user made after setup when the plugin's are disabled", function()
        tt.setup()
        vim.cmd("iabbrev and@ USER_REPLACEMENT")
        tt.setup({ abbreviations = false })
        assert.are.equal("USER_REPLACEMENT", abbrev("and@"))
        vim.cmd("iunabbrev and@")
    end)

    it("tracks the global abbreviation under a buffer-local shadow", function()
        vim.cmd("iabbrev and@ GLOBAL")
        vim.cmd("iabbrev <buffer> and@ LOCAL")
        tt.setup()
        assert.are.equal("LOCAL", abbrev("and@"))
        tt.setup({ abbreviations = false })
        assert.are.equal("LOCAL", abbrev("and@"))
        vim.cmd("iunabbrev <buffer> and@")
        assert.are.equal("GLOBAL", abbrev("and@"))
        vim.cmd("iunabbrev and@")
    end)
end)

describe("abbreviation expansion", function()
    it("keeps a literal pipe on the right-hand side as text", function()
        tt.setup({ abbreviations = { symbols = { and_word = "A|B" } } })
        assert.are.equal("A|B", abbrev("and_word@"))
    end)

    it("expands a default while typing", function()
        tt.setup()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("iand@<C-]> <Esc>", true, false, true), "xt", false)
        assert.are.equal("∧ ", vim.api.nvim_get_current_line())
    end)
end)
