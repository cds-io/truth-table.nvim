-- Real startup: Neovim evaluates an init file and then loads plugin/ itself.
-- A spec runs inside a Neovim that has already started, so each group here
-- starts a second one with spec/startup_init.lua as its init file and reads
-- what that one reports.
-- Runs inside Neovim (make test-nvim): busted with nlua as its interpreter.

local function start(custom)
    local run = vim.system(
        { vim.v.progpath, "--headless", "-u", "spec/startup_init.lua", "-i", "NONE" },
        { text = true, env = { TRUTH_TABLE_TEST_CUSTOM = custom and "1" or "0" } }
    ):wait(30000)
    assert.are.equal(0, run.code, run.stderr)
    return vim.json.decode(run.stdout)
end

local function starts(name, custom, abbreviation)
    describe(name, function()
        local found
        setup(function()
            found = start(custom)
        end)

        it("runs the checks without an error", function()
            assert.is_nil(found.error)
        end)

        it("loads the plugin and defines its commands", function()
            assert.is_truthy(found.loaded)
            assert.are.equal(2, found.command)
        end)

        it("registers the abbreviations the init file left it with", function()
            assert.are.equal(abbreviation, found.abbreviation)
        end)

        it("builds a table and toggles it", function()
            assert.are.same({ { 0 }, { 1 } }, found.rows)
            assert.are.equal("tf", found.encoding)
        end)

        it("finds its help", function()
            assert.are.equal("help", found.help_filetype)
            assert.is_truthy(found.help_file:match("doc/truth%-table%.txt$"), found.help_file)
        end)
    end)
end

starts("startup from an init file that leaves the plugin alone", false, "∧")
starts("startup from an init file that calls setup({ abbreviations = false })", true, "")
