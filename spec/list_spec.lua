local list = require("truth-table.list")

describe("list.slice", function()
    it("is the items from first to last inclusive, to the end without a last", function()
        local items = { "a", "b", "c", "d" }
        assert.are.same({ "b", "c" }, list.slice(items, 2, 3))
        assert.are.same({ "c", "d" }, list.slice(items, 3))
        assert.are.same({}, list.slice(items, 3, 2))
        assert.are.same({ "a", "b", "c", "d" }, items)
    end)
end)

describe("list.concat", function()
    it("joins any number of lists in order and leaves each as it was", function()
        local a, b = { 1, 2 }, { 3 }
        assert.are.same({ 1, 2, 3, 4, 5 }, list.concat(a, b, { 4, 5 }))
        assert.are.same({ 1, 2 }, list.concat(a, {}))
        assert.are.same({}, list.concat())
        assert.are.same({ 1, 2 }, a)
        assert.are.same({ 3 }, b)
    end)
end)

describe("list.without", function()
    it("drops the item at an index and keeps the rest in order", function()
        local items = { "a", "b", "c" }
        assert.are.same({ "a", "c" }, list.without(items, 2))
        assert.are.same({ "a", "b", "c" }, list.without(items, 4))
        assert.are.same({ "a", "b", "c" }, items)
    end)
end)

describe("list.with", function()
    it("puts a value in place of the item at an index", function()
        local items = { "a", "b", "c" }
        assert.are.same({ "a", "x", "c" }, list.with(items, 2, "x"))
        assert.are.same({ "a", "b", "c" }, items)
    end)
end)
