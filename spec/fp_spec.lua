local fp = require("truth-table.fp")

describe("fp.map", function()
    it("gives each item's result, in order", function()
        assert.are.same({ 2, 4, 6 }, fp.map({ 1, 2, 3 }, function(n) return n * 2 end))
    end)

    it("passes the item's index", function()
        assert.are.same({ "1:a", "2:b" }, fp.map({ "a", "b" }, function(item, index) return index .. ":" .. item end))
    end)

    it("keeps a false result as an item", function()
        assert.are.same({ false, true }, fp.map({ 1, 2 }, function(n) return n > 1 end))
    end)

    it("gives an empty list for an empty list", function()
        assert.are.same({}, fp.map({}, function() error("called") end))
    end)

    it("returns a new list and leaves its own alone", function()
        local list = { 1, 2 }
        local mapped = fp.map(list, function(n) return n end)
        assert.are_not.equal(list, mapped)
        assert.are.same({ 1, 2 }, list)
    end)

    it("refuses a nil result, which would leave a hole in the list", function()
        local ok, err = pcall(fp.map, { "a", "b", "c" }, function(item) return item ~= "b" and item or nil end)
        assert.is_false(ok)
        assert.is_truthy(err:find("fp.map: the function returned nil for item 2", 1, true), err)
    end)
end)

describe("fp.filter", function()
    it("keeps the items the test accepts, in order and without holes", function()
        local even = fp.filter({ 1, 2, 3, 4, 5, 6 }, function(n) return n % 2 == 0 end)
        assert.are.same({ 2, 4, 6 }, even)
        assert.are.equal(3, #even)
    end)

    it("passes the item's index", function()
        assert.are.same({ "a", "c" }, fp.filter({ "a", "b", "c" }, function(_, index) return index ~= 2 end))
    end)

    it("keeps an item that is false when the test accepts it", function()
        assert.are.same({ false }, fp.filter({ false, true }, function(item) return item == false end))
    end)

    it("gives an empty list when nothing passes, or nothing was given", function()
        assert.are.same({}, fp.filter({ 1, 2 }, function() return false end))
        assert.are.same({}, fp.filter({}, function() error("called") end))
    end)

    it("returns a new list and leaves its own alone", function()
        local list = { 1, 2 }
        local kept = fp.filter(list, function() return true end)
        assert.are_not.equal(list, kept)
        assert.are.same({ 1, 2 }, list)
    end)
end)

describe("fp.reduce", function()
    it("folds the items into the initial value, left to right", function()
        assert.are.equal(10, fp.reduce({ 1, 2, 3, 4 }, 0, function(sum, n) return sum + n end))
        assert.are.equal("-abc", fp.reduce({ "a", "b", "c" }, "-", function(text, item) return text .. item end))
    end)

    it("passes the item's index", function()
        assert.are.equal(3, fp.reduce({ "a", "b", "c" }, 0, function(_, _, index) return index end))
    end)

    it("gives the initial value back for an empty list", function()
        local initial = {}
        assert.are.equal(initial, fp.reduce({}, initial, function() error("called") end))
    end)

    it("builds any kind of value, a table included", function()
        local seen = fp.reduce({ "a", "b" }, {}, function(set, item)
            set[item] = true
            return set
        end)
        assert.are.same({ a = true, b = true }, seen)
    end)
end)

describe("fp", function()
    it("chains: the evens, times ten, summed", function()
        local evens = fp.filter({ 1, 2, 3, 4 }, function(n) return n % 2 == 0 end)
        local tens = fp.map(evens, function(n) return n * 10 end)
        assert.are.equal(60, fp.reduce(tens, 0, function(sum, n) return sum + n end))
    end)
end)
