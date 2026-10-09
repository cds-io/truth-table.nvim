-- Unit tests for truth-table.karnaugh: input-column detection, minimization,
-- rendering of the map and the derived formula. Pure Lua, runs under busted.

local karnaugh = require("truth-table.karnaugh")
local predicate = require("truth-table.predicate")
local trees = require("truth-table.trees")
local model = require("truth-table.table_model")

-- A table over `names` whose last column is `fn(row bits...)`, as the plugin
-- would store it: inputs enumerated MSB-first, one output column appended.
local function table_of(names, target, fn)
    local rows = {}
    for _, bits in ipairs(model.generate_rows(#names)) do
        local row = {}
        for i, bit in ipairs(bits) do
            row[i] = bit
        end
        row[#row + 1] = fn(unpack(bits))
        rows[#rows + 1] = row
    end
    local headers = {}
    for i, name in ipairs(names) do
        headers[i] = name
    end
    headers[#headers + 1] = target
    return { headers = headers, rows = rows, encoding = "bits" }
end

-- The example from the README discussion: F = A xor B or A and C.
local function example()
    return table_of({ "A", "B", "C" }, "F", function(a, b, c)
        if (a ~= b) or (a == 1 and c == 1) then
            return 1
        end
        return 0
    end)
end

local function eval_formula(ast, names, bits)
    local ctx = {}
    for i, name in ipairs(names) do
        ctx[name] = bits[i]
    end
    return predicate.eval_ast(ast, ctx)
end

describe("karnaugh.derive", function()
    it("references stored values when input headings are expressions or reserved names", function()
        for _, heading in ipairs({ "A ∨ B", "and", "0", "rain wet", "A|B" }) do
            local tbl = table_of({ heading, "C" }, "F", function(a)
                return 1 - a
            end)
            local analysis = assert(karnaugh.derive(tbl, 3))
            assert.are.equal("¬:h1", analysis.formula)
            local parsed = assert(predicate.parse_expression(analysis.formula))
            local bound = assert(predicate.bind_columns(parsed, {}, tbl.headers))
            for _, row in ipairs(tbl.rows) do
                assert.are.equal(row[3], predicate.eval_ast(bound, row))
            end
        end
    end)

    it("minimizes literal count before breaking ties lexically", function()
        local minterms = {
            [0] = true,
            [1] = true,
            [2] = true,
            [5] = true,
            [7] = true,
            [9] = true,
            [10] = true,
            [11] = true,
            [12] = true,
            [13] = true,
        }
        local tbl = table_of({ "A", "B", "C", "D" }, "F", function(a, b, c, d)
            return minterms[a * 8 + b * 4 + c * 2 + d] and 1 or 0
        end)
        local analysis = assert(karnaugh.derive(tbl, 5))
        assert.are.equal(5, #analysis.cover)
        local literals = 0
        for _, term in ipairs(analysis.cover) do
            local _, count = term:gsub("[01]", "")
            literals = literals + count
        end
        assert.are.equal(14, literals)
        local parsed = assert(predicate.parse_expression(analysis.formula))
        for _, row in ipairs(tbl.rows) do
            assert.are.equal(row[5], eval_formula(parsed, analysis.inputs, row))
        end
    end)

    it("finds the input columns, minterms and a minimal cover", function()
        local analysis = assert(karnaugh.derive(example(), 4))
        assert.are.same({ "A", "B", "C" }, analysis.inputs)
        assert.are.equal("F", analysis.target)
        assert.are.same({ 2, 3, 4, 5, 7 }, analysis.minterms)
        assert.are.same({}, analysis.dont_cares)
        assert.are.same({ "01-", "10-", "1-1" }, analysis.cover)
    end)

    it("renders the cover as a sum of products in the predicate language", function()
        local analysis = assert(karnaugh.derive(example(), 4))
        assert.are.equal("(¬A ∧ B) ∨ (A ∧ ¬B) ∨ (A ∧ C)", analysis.formula)
        -- The formula is a predicate the plugin can parse and evaluate back.
        local parsed = assert(predicate.parse_expression(analysis.formula))
        assert.are.equal(analysis.formula, trees.heading(parsed))
    end)

    it("breaks a tie between equal covers deterministically", function()
        -- Cell 111 can pair with 101 (A ∧ C) or 011 (B ∧ C); A ∧ C sorts first.
        local analysis = assert(karnaugh.derive(example(), 4))
        assert.are.same({ "01-", "10-", "1-1", "-11" }, analysis.primes)
        assert.are.same({ "01-", "10-", "1-1" }, analysis.cover)
    end)

    it("derives constants for all-zero and all-one columns", function()
        local zero = assert(karnaugh.derive(
            table_of({ "A", "B" }, "F", function()
                return 0
            end),
            3
        ))
        assert.are.equal("0", zero.formula)
        assert.are.same({}, zero.cover)
        local one = assert(karnaugh.derive(
            table_of({ "A", "B" }, "F", function()
                return 1
            end),
            3
        ))
        assert.are.equal("1", one.formula)
        assert.are.same({ "--" }, one.cover)
    end)

    it("derives a column equal to an input as that variable", function()
        local analysis = assert(karnaugh.derive(
            table_of({ "A", "B" }, "F", function(a)
                return a
            end),
            3
        ))
        assert.are.equal("A", analysis.formula)
    end)

    it("rejects a column the columns before it do not determine", function()
        -- B is not a function of A alone: rows 1 and 2 share A = 0.
        local analysis, err = karnaugh.derive(
            table_of({ "A", "B" }, "F", function(a)
                return a
            end),
            2
        )
        assert.is_nil(analysis)
        assert.matches("disagree", err)
    end)

    it("rejects the first column, which has no inputs before it", function()
        local analysis, err = karnaugh.derive(example(), 1)
        assert.is_nil(analysis)
        assert.matches("No input columns before A", err)
    end)

    it("stops the inputs at the first column that breaks the enumeration", function()
        -- A computed column between the variables and the target is not an input.
        local tbl = table_of({ "A", "B" }, "F", function(a, b)
            return a == 1 and b == 1 and 1 or 0
        end)
        local extended = assert(model.append_columns(tbl, {
            { heading = "G", values = { 0, 1, 1, 1 } },
        }))
        local analysis = assert(karnaugh.derive(extended, 4))
        assert.are.same({ "A", "B" }, analysis.inputs)
        assert.are.equal("G", analysis.target)
        assert.are.equal("A ∨ B", analysis.formula)
    end)

    it("uses missing rows as don't-cares", function()
        local tbl = {
            headers = { "A", "B", "F" },
            rows = { { 0, 0, 0 }, { 0, 1, 1 }, { 1, 1, 1 } },
            encoding = "bits",
        }
        local analysis = assert(karnaugh.derive(tbl, 3))
        assert.are.same({ 2 }, analysis.dont_cares)
        assert.are.equal("B", analysis.formula)
    end)

    it("rejects rows that disagree about the same inputs", function()
        local tbl = {
            headers = { "A", "F" },
            rows = { { 0, 0 }, { 0, 1 } },
            encoding = "bits",
        }
        local analysis, err = karnaugh.derive(tbl, 2)
        assert.is_nil(analysis)
        assert.matches("disagree", err)
    end)

    it("rejects an invalid column index", function()
        local analysis, err = karnaugh.derive(example(), 5)
        assert.is_nil(analysis)
        assert.matches("Invalid column index", err)
    end)

    it("reproduces the column for every input on a spread of functions", function()
        local functions = {
            function(a, b, c, d)
                return (a == 1 and b == 0) or (c == d)
            end,
            function(a, b, c, d)
                return (a ~= b) and (c == 1 or d == 0)
            end,
            function(a, b, c, d)
                return (a == 1 and c == 1) or (b == 1 and d == 1) or (a == 0 and b == 0)
            end,
            function(a, b, c)
                return (a + b + c) % 2 == 1
            end,
            function(a, b, c, d, e)
                return (a == 1 and b == 1) or (c == 1 and d == 1 and e == 0) or (b == 0 and e == 1)
            end,
        }
        local widths = { 4, 4, 4, 3, 5 }
        for i, fn in ipairs(functions) do
            local names = {}
            for v = 1, widths[i] do
                names[v] = string.char(64 + v)
            end
            local tbl = table_of(names, "F", function(...)
                return fn(...) and 1 or 0
            end)
            local analysis = assert(karnaugh.derive(tbl, #names + 1))
            for _, row in ipairs(tbl.rows) do
                assert.are.equal(row[#row], eval_formula(analysis.ast, names, row), "function " .. i)
            end
        end
    end)
end)

describe("karnaugh.derive on large tables", function()
    it("finishes a random ten-variable function within the search budget", function()
        -- A fixed linear congruential generator keeps the function the same on
        -- every run without depending on math.random's implementation.
        local state = 12345
        local function next_bit()
            state = (state * 1103515245 + 12345) % 2147483648
            return math.floor(state / 65536) % 2
        end
        local names = {}
        for v = 1, 10 do
            names[v] = string.char(64 + v)
        end
        local tbl = table_of(names, "out", next_bit)
        local started = os.clock()
        local analysis = assert(karnaugh.derive(tbl, 11))
        -- An exponential exact search runs for minutes; the budget keeps this
        -- well under a second, and the margin here only guards the regression.
        assert.is_true(os.clock() - started < 10)
        for _, row in ipairs(tbl.rows) do
            assert.are.equal(row[#row], eval_formula(analysis.ast, names, row))
        end
    end)
end)

describe("karnaugh.render", function()
    it("lays out a 3-variable map with the last two variables on the columns", function()
        local analysis = assert(karnaugh.derive(example(), 4))
        assert.are.same({
            "Karnaugh map for F:",
            "",
            "|     |     |     | BC  |     |     |",
            "|:---:|:---:|:---:|:---:|:---:|:---:|",
            "|     |     | 00  | 01  | 11  | 10  |",
            "|  A  |  0  |  0  |  0  |  1  |  1  |",
            "|     |  1  |  1  |  1  |  1  |  0  |",
            "",
            "F ≡ (¬A ∧ B) ∨ (A ∧ ¬B) ∨ (A ∧ C)",
        }, karnaugh.render(analysis))
    end)

    it("lays out a 2-variable map with one variable per axis", function()
        local tbl = table_of({ "A", "B" }, "F", function(a, b)
            return a == 1 and b == 1 and 1 or 0
        end)
        local lines = assert(karnaugh.render(assert(karnaugh.derive(tbl, 3))))
        assert.are.same({
            "|     |     |  B  |     |",
            "|:---:|:---:|:---:|:---:|",
            "|     |     |  0  |  1  |",
            "|  A  |  0  |  0  |  0  |",
            "|     |  1  |  0  |  1  |",
        }, { lines[3], lines[4], lines[5], lines[6], lines[7] })
        assert.are.equal("F ≡ A ∧ B", lines[#lines])
    end)

    it("puts two variables on each axis of a 4-variable map", function()
        local tbl = table_of({ "A", "B", "C", "D" }, "F", function(a, b, c, d)
            return (a == 1 and b == 0) and 1 or (c == 1 and d == 1) and 1 or 0
        end)
        local lines = assert(karnaugh.render(assert(karnaugh.derive(tbl, 5))))
        assert.are.equal("|     |     |     | CD  |     |     |", lines[3])
        assert.are.equal("|     |     | 00  | 01  | 11  | 10  |", lines[5])
        assert.are.equal("| AB  | 00  |  0  |  0  |  1  |  0  |", lines[6])
        assert.are.equal("|     | 01  |  0  |  0  |  1  |  0  |", lines[7])
        assert.are.equal("|     | 11  |  0  |  0  |  1  |  0  |", lines[8])
        assert.are.equal("|     | 10  |  1  |  1  |  1  |  1  |", lines[9])
        assert.are.equal("F ≡ (A ∧ ¬B) ∨ (C ∧ D)", lines[#lines])
    end)

    it("marks don't-care cells with X", function()
        local tbl = {
            headers = { "A", "B", "F" },
            rows = { { 0, 0, 0 }, { 0, 1, 1 }, { 1, 1, 1 } },
            encoding = "bits",
        }
        local lines = assert(karnaugh.render(assert(karnaugh.derive(tbl, 3))))
        assert.are.equal("|     |  1  |  X  |  1  |", lines[7])
    end)

    it("keeps the table's F/T encoding in the cells", function()
        local tbl = table_of({ "A", "B" }, "F", function(a, b)
            return a == 1 and b == 1 and 1 or 0
        end)
        tbl.encoding = "tf"
        local lines = assert(karnaugh.render(assert(karnaugh.derive(tbl, 3))))
        assert.are.equal("|     |  1  |  F  |  T  |", lines[7])
    end)

    it("joins multi-character names with spaces in the axis labels", function()
        local tbl = table_of({ "p", "rain", "wet" }, "F", function(p)
            return p
        end)
        local lines = assert(karnaugh.render(assert(karnaugh.derive(tbl, 4))))
        assert.are.equal("|     |     |     | rain wet |     |     |", lines[3])
        assert.are.equal("|  p  |  0  |  0  |    0     |  0  |  0  |", lines[6])
    end)

    it("omits the map above four variables and keeps the formula", function()
        local names = { "A", "B", "C", "D", "E" }
        local tbl = table_of(names, "F", function(a)
            return a
        end)
        local lines = assert(karnaugh.render(assert(karnaugh.derive(tbl, 6))))
        assert.are.same({ "F ≡ A" }, lines)
    end)

    it("omits the map for a single variable", function()
        local tbl = { headers = { "A", "F" }, rows = { { 0, 1 }, { 1, 0 } }, encoding = "bits" }
        local lines = assert(karnaugh.render(assert(karnaugh.derive(tbl, 2))))
        assert.are.same({ "F ≡ ¬A" }, lines)
    end)
end)
