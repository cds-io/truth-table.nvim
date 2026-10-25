-- The entry's capability check. Runs inside Neovim (make test-nvim).
vim.opt.rtp:append(vim.fn.getcwd())

describe("the entry's capability check", function()
    local needs = require("cds.needs")
    local real_check = needs.check
    local real_notify = vim.notify
    local seen

    before_each(function()
        seen = {}
        vim.notify = function(msg, level)
            table.insert(seen, { msg = msg, level = level })
        end
        vim.g.loaded_truth_table = nil
    end)

    after_each(function()
        needs.check = real_check
        package.loaded["cds.needs"] = needs
        package.preload["cds.needs"] = nil
        vim.notify = real_notify
        vim.g.loaded_truth_table = true
    end)

    it("refuses to load, in words, when the cds-lua-fp present lacks a capability", function()
        needs.check = function(plugin, capabilities)
            assert.are.equal("truth-table.nvim", plugin)
            assert.are.same({ "bind", "context", "map", "traverse" }, capabilities.result)
            return "truth-table.nvim needs cds-lua-fp with fp.filter_map: the check's own words"
        end
        vim.cmd("runtime plugin/truth-table.lua")
        assert.is_nil(vim.g.loaded_truth_table)
        assert.are.same({
            {
                msg = "truth-table.nvim needs cds-lua-fp with fp.filter_map: the check's own words",
                level = vim.log.levels.ERROR,
            },
        }, seen)
    end)

    it("refuses to load when the cds-lua-fp present is too old to carry cds.needs", function()
        package.loaded["cds.needs"] = nil
        package.preload["cds.needs"] = function()
            error("module 'cds.needs' not found")
        end
        vim.cmd("runtime plugin/truth-table.lua")
        assert.is_nil(vim.g.loaded_truth_table)
        assert.are.equal(
            "truth-table.nvim needs cds-lua-fp with cds.needs: install or update cds-io/cds-lua-fp",
            seen[1].msg
        )
    end)

    it("loads once when everything declared is there", function()
        vim.cmd("runtime plugin/truth-table.lua")
        assert.is_true(vim.g.loaded_truth_table)
        assert.are.same({}, seen)
        assert.are.equal(2, vim.fn.exists(":TruthTable"))
    end)
end)
