-- Unit tests for truth-table.result: the value, error pipeline. Pure Lua,
-- runs under busted.
local result = require("truth-table.result")

describe("result composition", function()
    it("preserves false and zero successes and short-circuits errors", function()
        assert.is_false(result.bind(false, nil, function(value)
            return value
        end))
        assert.are.equal(
            0,
            result.bind(0, nil, function(value)
                return value
            end)
        )
        local value, err = result.bind(nil, "failure", function()
            error("must not run")
        end)
        assert.is_nil(value)
        assert.are.equal("failure", err)
        local calls = 0
        value, err = result.traverse({ 1, 2, 3 }, function(n)
            calls = calls + 1
            if n == 2 then
                return nil, "stop"
            end
            return n
        end)
        assert.is_nil(value)
        assert.are.equal("stop", err)
        assert.are.equal(2, calls)
    end)
end)

describe("result.map", function()
    it("applies the function to a value, false and zero included", function()
        assert.are.equal(
            2,
            result.map(1, nil, function(value)
                return value + 1
            end)
        )
        assert.is_true(result.map(false, nil, function(value)
            return not value
        end))
        assert.are.equal("0", result.map(0, nil, tostring))
    end)

    it("passes an error through without calling the function", function()
        local value, err = result.map(nil, "failure", function()
            error("must not run")
        end)
        assert.is_nil(value)
        assert.are.equal("failure", err)
    end)
end)

describe("result.context", function()
    it("prefixes an error with where it was met", function()
        local value, err = result.context(nil, "Expected )", 'Parse error in "(A": ')
        assert.is_nil(value)
        assert.are.equal('Parse error in "(A": Expected )', err)
    end)

    it("passes a value through untouched, false and zero included", function()
        local tbl = {}
        assert.are.equal(tbl, result.context(tbl, nil, "unused: "))
        assert.is_false(result.context(false, nil, "unused: "))
        assert.are.equal(0, result.context(0, nil, "unused: "))
    end)

    it("composes: the outer prefix goes first", function()
        local inner_value, inner_err = result.context(nil, "inner", "middle: ")
        local _, err = result.context(inner_value, inner_err, "outer: ")
        assert.are.equal("outer: middle: inner", err)
    end)
end)
